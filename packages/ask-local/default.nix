{ pkgs, ... }:
let
  # vulkanSupport for the Arc iGPU. LLAMA_BUILD_EXAMPLES gets us llama-lookup
  # (prompt-lookup n-gram speculative decoding); nixpkgs disables examples by
  # default and llama-cli at b8667 gates -lcd/--spec-type to {LOOKUP,SERVER}
  # only, so the one-shot lookup path needs the separate binary.
  llama = (pkgs.llama-cpp.override { vulkanSupport = true; }).overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DLLAMA_BUILD_EXAMPLES=ON" ];
  });
in
pkgs.writeShellApplication {
  name = "ask-local";
  runtimeInputs = [
    llama
    pkgs.coreutils
    pkgs.curl
    pkgs.python3
  ];
  text = ''
    # One-shot offline LLM on the Intel Arc iGPU (vulkan). Mirrors ptt-dictate:
    # model lives under XDG_DATA_HOME, auto-fetched on first run.
    #   ask-local "<prompt>"                  → llama-cli, prints completion to stdout
    #   ask-local --grammar <gbnf> "<prompt>" → constrained decoding (used by
    #                                           ptt-dictate --intent for JSON-only output)
    #   ask-local --fast [...] "<prompt>"     → llama-lookup: prompt-lookup n-gram
    #                                           speculative decoding, no draft model.
    #                                           Dynamic n-gram cache persists under
    #                                           XDG_CACHE_HOME so repeated prompt
    #                                           templates (intent classify) compound.
    #                                           NB: llama-lookup echoes the prompt on
    #                                           stdout (--no-display-prompt is gated to
    #                                           CLI/COMPLETION upstream); callers must
    #                                           strip. See bench.sh for the 4-case
    #                                           grammar×lookup tok/s matrix.
    #   ask-local --serve [--model M] [--port N]
    #                                         → llama-server on 127.0.0.1:N (default 8088,
    #                                           OpenAI-compat) with n-gram lookup decoding
    #                                           always on. --model overrides $ASK_LOCAL_MODEL;
    #                                           bare names resolve under $XDG_DATA_HOME/llama.
    #                                           llm-router uses these to spawn one backend per
    #                                           resident model and reap idle ones.
    #   ask-local --agent "<goal>"            → bounded ReAct loop: GBNF-forced JSON tool
    #                                           calls over packages/ CLIs (tools.json),
    #                                           ≤4 turns. See bench-agent.jsonl.
    #   ask-local --diff-gate                 → reads a git diff on stdin, GBNF-forced
    #                                           {"risk":"low|high","why":"…"} triage,
    #                                           prints why, exit 0=low 1=high. Gates
    #                                           pre-commit + llm-router /review. See
    #                                           bench-diff-gate.sh for the label harness.
    # shellcheck source=/dev/null
    . ${../lib/fetch-model.sh}
    MODEL="''${ASK_LOCAL_MODEL:-''${XDG_DATA_HOME:-$HOME/.local/share}/llama/Phi-3-mini-4k-instruct-Q4_K_M.gguf}"
    fetch_model "$MODEL" \
      https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf

    CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/ask-local"
    mkdir -p "$CACHE"

    case "''${1:-}" in
      --agent)
        shift
        export ASK_LOCAL_BIN="$0"
        export ASK_LOCAL_TOOLS="''${ASK_LOCAL_TOOLS:-${./tools.json}}"
        exec python3 ${./agent.py} "$@" ;;
      --diff-gate)
        export ASK_LOCAL_BIN="$0"
        export ASK_LOCAL_DIFF_GATE_GBNF="''${ASK_LOCAL_DIFF_GATE_GBNF:-${./diff-gate.gbnf}}"
        exec python3 ${./agent.py} --diff-gate ;;
    esac

    if [[ "''${1:-}" == "--serve" ]]; then
      shift
      PORT="''${ASK_LOCAL_PORT:-8088}"
      while true; do
        case "''${1:-}" in
          --model)
            [[ $# -ge 2 ]] || { echo "ask-local: --model needs a name or path" >&2; exit 2; }
            MODEL="$2"
            [[ "$MODEL" == */* ]] || MODEL="''${XDG_DATA_HOME:-$HOME/.local/share}/llama/$MODEL"
            [[ "$MODEL" == *.gguf ]] || MODEL="$MODEL.gguf"
            shift 2 ;;
          --port)
            [[ $# -ge 2 ]] || { echo "ask-local: --port needs a number" >&2; exit 2; }
            PORT="$2"; shift 2 ;;
          *) break ;;
        esac
      done
      [[ -f "$MODEL" ]] || { echo "ask-local: no such model: $MODEL" >&2; exit 1; }
      # Server exposes prompt-lookup cleanly (no echo issue); enable unconditionally.
      exec llama-server -m "$MODEL" -ngl 99 --host 127.0.0.1 --port "$PORT" \
        -lcd "$CACHE/lookup.ngram" --spec-type ngram-cache --draft-max 16
    fi

    fast=''${ASK_LOCAL_LOOKUP:-0}
    extra=()
    while true; do
      case "''${1:-}" in
        --fast) fast=1; shift ;;
        --grammar)
          [[ $# -ge 2 ]] || { echo "ask-local: --grammar needs a file" >&2; exit 2; }
          extra+=(--grammar-file "$2" -n 128); shift 2 ;;
        *) break ;;
      esac
    done

    # --grammar does NOT auto-enable --fast yet: llama-lookup has no
    # --no-display-prompt, so the echoed prompt would break ptt-dictate's jq
    # parse. Flip after bench.sh confirms grammar×lookup ≫ grammar-alone on Arc
    # vulkan AND a strip is in place (or upstream gates the flag to LOOKUP).
    if [[ $fast -eq 1 ]]; then
      exec llama-lookup -m "$MODEL" -ngl 99 "''${extra[@]}" \
        -lcd "$CACHE/lookup.ngram" --draft-max 16 --color off -p "$*" 2>/dev/null
    fi

    exec llama-cli -m "$MODEL" -ngl 99 "''${extra[@]}" -p "$*" --no-display-prompt 2>/dev/null
  '';
}
