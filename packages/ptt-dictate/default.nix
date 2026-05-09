{ pkgs, ... }:
let
  whisper = pkgs.whisper-cpp.override { vulkanSupport = true; };
  transcribe-npu = pkgs.callPackage ../transcribe-npu { };
  transcribe-cpu = pkgs.callPackage ../transcribe-cpu { };
  ask-local = pkgs.callPackage ../ask-local { };
in
pkgs.writeShellApplication {
  name = "ptt-dictate";
  runtimeInputs = [
    whisper
    transcribe-npu
    transcribe-cpu
    ask-local
    pkgs.pipewire
    pkgs.ydotool
    pkgs.coreutils
    pkgs.curl
    pkgs.jq
    pkgs.yq-go
    pkgs.pueue
  ];
  text = ''
    # Toggle push-to-talk: first call starts recording, second call stops and
    # types the transcription via ydotool. Bind to a single hotkey.
    #   ptt-dictate            → record/stop, type transcript
    #   ptt-dictate --intent   → record/stop, classify via ask-local --grammar
    #                            against $XDG_CONFIG_HOME/voice-intent/intents.toml,
    #                            dispatch matched intent or fall through to type
    STATE="''${XDG_RUNTIME_DIR:-/tmp}/ptt-dictate"
    MODEL="''${PTT_DICTATE_MODEL:-''${XDG_DATA_HOME:-$HOME/.local/share}/whisper/ggml-base.en.bin}"
    mkdir -p "$STATE"

    intent=0; backend=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --intent)    intent=1; shift ;;
      --backend=*) backend="''${1#*=}"; shift ;;
      *) break ;;
    esac; done

    if [[ -f "$STATE/pid" ]] && kill -0 "$(cat "$STATE/pid")" 2>/dev/null; then
      kill "$(cat "$STATE/pid")"
      exit 0
    fi

    # shellcheck source=/dev/null
    . ${../lib/fetch-model.sh}
    # shellcheck source=/dev/null
    . ${../lib/dictation-vocab.sh}
    fetch_model "$MODEL" \
      https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

    REC="$STATE/rec.wav"
    pw-record --rate 16000 --channels 1 "$REC" &
    echo $! > "$STATE/pid"

    # Decoder biasing: feed project jargon as the whisper.cpp initial prompt.
    # --prompt is a soft n-gram bias (it conditions the decoder, doesn't
    # constrain it) and over-long prompts steal context from the audio and
    # *hurt* — cap ~600 chars (~150 BPE tokens, well under whisper's 224-token
    # prompt half of the 448-token decoder window). Computed here so the cold
    # cache path overlaps with the user speaking instead of delaying recording
    # start; warm cache is a stat+head. transcribe-{npu,cpu} pull the same
    # cached list themselves so the npu/cpu lanes are biased too.
    VOCAB_PROMPT=$(dictation_vocab 200 | tr '\n' ' ')
    VOCAB_PROMPT="''${VOCAB_PROMPT:0:600}"

    wait || true
    rm -f "$STATE/pid"

    # --backend=auto: pick the infer-queue lane (arc|npu|cpu) with the fewest
    # running+queued tasks so dictation routes around whatever ask-local /
    # sem-grep / agent-eyes currently has resident. Opt-in this round; default
    # stays NPU-then-vulkan until tests/bench-dictate.sh proves the cpu lane
    # wins under load (≥200 ms p95, see backlog/adopt-parakeet-cpu-lane.md).
    if [[ "$backend" == auto ]]; then
      backend=$(pueue status --json 2>/dev/null | jq -r '
        .tasks | map(select(.status|objects|has("Running") or has("Queued")) | .group)
        | reduce .[] as $g ({arc:0,npu:0,cpu:0}; .[$g] += 1)
        | to_entries | min_by(.value) | .key' 2>/dev/null) || backend=""
    fi
    case "$backend" in
      npu) TEXT=$(transcribe-npu "$REC" 2>/dev/null) ;;
      cpu) TEXT=$(transcribe-cpu "$REC" 2>/dev/null) ;;
      arc) TEXT=$(whisper-cli -m "$MODEL" -f "$REC" --no-timestamps --no-prints \
                    --prompt "$VOCAB_PROMPT" 2>/dev/null) ;;
      *)
        # Default: prefer the Meteor Lake NPU when present — frees the Arc iGPU
        # for ask-local. Fall back to whisper-cpp/vulkan if the accel node is
        # absent or the NPU run fails.
        if [[ -e /dev/accel/accel0 ]] && TEXT=$(transcribe-npu "$REC" 2>/dev/null); then
          :
        else
          TEXT=$(whisper-cli -m "$MODEL" -f "$REC" --no-timestamps --no-prints \
                   --prompt "$VOCAB_PROMPT" 2>/dev/null)
        fi ;;
    esac
    TEXT=$(printf %s "$TEXT" | tr -d '\n' | sed 's/^ *//;s/ *$//')
    [[ -n "$TEXT" ]] || exit 0

    if [[ $intent -eq 0 ]]; then
      exec ydotool type -- "$TEXT"
    fi

    # --intent: GBNF-constrained classify → dispatch. Every failure path
    # degrades to the pre-intent behaviour (type the raw utterance).
    CFG="''${XDG_CONFIG_HOME:-$HOME/.config}/voice-intent/intents.toml"
    INTENTS=$(yq -p toml -o json "$CFG" 2>/dev/null) || INTENTS=""
    [[ -n "$INTENTS" ]] || exec ydotool type -- "$TEXT"

    # Grammar: force {"type":"<one-of-intents|text>","arg":"<no-ctrl-no-quote>"}.
    # Regenerated per call so user edits to intents.toml take effect immediately.
    alts=$(jq -r 'keys + ["text"] | unique | map("\"" + . + "\"") | join(" | ")' <<<"$INTENTS")
    GRAMMAR="$STATE/intent.gbnf"
    {
      printf '%s\n' 'root   ::= "{\"type\":\"" intent "\",\"arg\":\"" arg "\"}"'
      printf 'intent ::= %s\n' "$alts"
      printf '%s\n' 'arg    ::= [^"\\\x7f\x00-\x1f]*'
    } >"$GRAMMAR"

    names=$(jq -r 'keys | join(", ")' <<<"$INTENTS")
    t0=$(date +%s%3N)
    OUT=$(ask-local --grammar "$GRAMMAR" \
      "Classify the voice command into one of: $names. Use 'text' if none fit. Put any free-text argument in arg.
    Command: $TEXT
    JSON:" 2>/dev/null | head -c 512) || OUT=""
    t1=$(date +%s%3N)

    INTENT=$(jq -r '.type // "text"' 2>/dev/null <<<"$OUT" || echo text)
    ARG=$(jq -r '.arg // ""' 2>/dev/null <<<"$OUT" || true)

    LOG="''${XDG_STATE_HOME:-$HOME/.local/state}/voice-intent"
    mkdir -p "$LOG"
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg u "$TEXT" --arg i "$INTENT" \
      --argjson ms "$((t1 - t0))" '{ts:$ts, utterance:$u, intent:$i, latency_ms:$ms}' \
      >>"$LOG/decisions.jsonl"

    EXEC=$(jq -r --arg i "$INTENT" '.[$i].exec // empty' <<<"$INTENTS")
    if [[ -n "$EXEC" ]]; then
      # Intent targets (peek, say-back, now-context, ...) resolve from the
      # caller's PATH — writeShellApplication prepends runtimeInputs, so the
      # session profile is still visible.
      ARG_Q=$(printf %q "$ARG")
      exec bash -c "''${EXEC//\{arg\}/$ARG_Q}" </dev/null
    fi
    # text, fallthrough=true, or unmapped → type the raw utterance
    exec ydotool type -- "$TEXT"
  '';
}
