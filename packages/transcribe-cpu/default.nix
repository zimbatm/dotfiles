{ pkgs, ... }:
let
  # NVIDIA NeMo parakeet-tdt-0.6b-v3, pre-converted to ONNX by sherpa-onnx
  # upstream and shipped as a release tarball (encoder/decoder/joiner int8 +
  # tokens). ~670 MB unpacked — large, but FOD-pinned like transcribe-npu's
  # whisper IR so the cpu lane is reproducible offline.
  parakeet = pkgs.fetchzip {
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2";
    hash = "sha256-3zMIAaTYBJZB8rXgaxHZdgBqBbrrLLN7USLH+JNTaDY=";
  };
in
pkgs.writeShellApplication {
  name = "transcribe-cpu";
  runtimeInputs = [
    pkgs.sherpa-onnx
    pkgs.coreutils
    pkgs.jq
  ];
  text = ''
    # Parakeet TDT on plain CPU via sherpa-onnx (onnxruntime). Third dictation
    # backend after whisper-cpp/vulkan and whisper-openvino/npu — fills the
    # otherwise-empty `cpu` lane in infer-queue so dictation can route around
    # Arc/NPU contention when ask-local or sem-grep are resident. NeMo claims
    # faster-than-realtime on a single P-core; tests/bench-dictate.sh measures
    # whether that holds on Meteor Lake under load.
    #   transcribe-cpu <wav>   → prints transcript to stdout
    MODEL="''${TRANSCRIBE_CPU_MODEL:-${parakeet}}"
    THREADS="''${TRANSCRIBE_CPU_THREADS:-2}"

    [[ -f "$MODEL/encoder.int8.onnx" ]] || { echo "transcribe-cpu: model not found: $MODEL" >&2; exit 1; }

    # Decoder biasing: project jargon as sherpa-onnx hotwords (contextual
    # biasing built into the TDT transducer decoder — a hard lattice rescore,
    # stronger than whisper's soft --prompt). sherpa-onnx needs the model's
    # bpe.vocab to encode hotword text into BPE pieces, and hotwords only take
    # effect under modified_beam_search; without bpe.vocab the flag would error
    # so the whole bias is gated on its presence and inert otherwise. Score is
    # a tunable: higher = stronger pull, risk of overcorrection — the WER bench
    # (backlog/needs-human/ops-dictation-vocab-bench.md) decides where it lands.
    # TRANSCRIBE_CPU_HOTWORDS=0 disables for an A/B run.
    # shellcheck source=/dev/null
    . ${../lib/dictation-vocab.sh}
    HOTWORD_ARGS=()
    if [[ -f "$MODEL/bpe.vocab" && "''${TRANSCRIBE_CPU_HOTWORDS:-1}" != 0 ]]; then
      HW="''${XDG_RUNTIME_DIR:-/tmp}/transcribe-cpu-hotwords.$$"
      dictation_vocab 200 > "$HW" || true
      if [[ -s "$HW" ]]; then
        trap 'rm -f "$HW"' EXIT
        HOTWORD_ARGS=(
          --bpe-vocab="$MODEL/bpe.vocab"
          --decoding-method=modified_beam_search
          --hotwords-file="$HW"
          --hotwords-score="''${TRANSCRIBE_CPU_HOTWORDS_SCORE:-1.5}"
        )
      else
        rm -f "$HW"
      fi
    fi

    WAV="''${1:-/dev/stdin}"
    sherpa-onnx-offline \
      --encoder="$MODEL/encoder.int8.onnx" \
      --decoder="$MODEL/decoder.int8.onnx" \
      --joiner="$MODEL/joiner.int8.onnx" \
      --tokens="$MODEL/tokens.txt" \
      --model-type=nemo_transducer \
      --num-threads="$THREADS" \
      "''${HOTWORD_ARGS[@]}" \
      "$WAV" 2>/dev/null \
    | jq -r 'select(type=="object" and has("text")) | .text' \
    | sed 's/^ *//;s/ *$//'
  '';
}
