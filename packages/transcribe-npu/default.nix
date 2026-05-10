{ pkgs, ... }:
let
  py = pkgs.python3.withPackages (ps: [
    ps.openvino
    ps.transformers
    ps.soundfile
    ps.numpy
    ps.huggingface-hub
  ]);
  whisper-base-en-ov = pkgs.fetchgit {
    url = "https://huggingface.co/OpenVINO/whisper-base.en-fp16-ov";
    rev = "50b74f57c2339aaf6cd2bfae1e7a0a437d73faff";
    fetchLFS = true;
    hash = "sha256-iA220hJxoBLNJMQFucCGLygJgtCIlLftMqINFpaeOnQ=";
  };
  # Same FOD transcribe-cpu uses for sherpa-onnx. probe-parakeet asks the
  # *other* question: does the OpenVINO ONNX frontend convert these graphs?
  parakeet = import ../lib/parakeet-tdt-v3.nix pkgs;

  # Diagnostic, not a user command — answers whether the NPU lane could run
  # parakeet-tdt-v3 instead of whisper-base.en. CPU plugin shares the ONNX
  # frontend with NPU, so a clean compile here means the conversion question
  # is settled and only the on-device WER/RTF bench remains (ops-* follow-up).
  # Mirrors the silero-vad v5 probe that found OpConversionFailure
  # (packages/wake-listen/default.nix). Reports, never gates: exit 0 always.
  probe-parakeet = pkgs.writeShellApplication {
    name = "probe-parakeet";
    runtimeInputs = [ py ];
    text = ''
      exec python3 ${./probe-parakeet.py} --model-dir ${parakeet} --device "''${1:-CPU}"
    '';
  };

  transcribe-npu = pkgs.writeShellApplication {
    name = "transcribe-npu";
    runtimeInputs = [
      py
      pkgs.coreutils
    ];
    text = ''
      # Whisper on the Meteor Lake NPU via OpenVINO runtime. Frees the Arc iGPU
      # for ask-local so dictation + local-LLM run concurrently. ptt-dictate
      # prefers this path when /dev/accel/accel0 exists; also the first real
      # workload for `infer-queue add --lane npu -- transcribe-npu <wav>`.
      #   transcribe-npu <wav>   → prints transcript to stdout
      # Model: OpenVINO/whisper-base.en-fp16-ov, shipped as a FOD in the closure.
      MODEL="''${TRANSCRIBE_NPU_MODEL:-${whisper-base-en-ov}}"
      DEVICE="''${TRANSCRIBE_NPU_DEVICE:-NPU}"
      export TRANSFORMERS_OFFLINE=1 HF_HUB_OFFLINE=1

      [[ -f "$MODEL/openvino_encoder_model.xml" ]] || { echo "transcribe-npu: model not found: $MODEL" >&2; exit 1; }

      # Decoder biasing: project jargon as a whisper initial prompt, threaded
      # via env so callers (ptt-dictate, infer-queue) can override or disable
      # (TRANSCRIBE_NPU_PROMPT="" → no bias). Same cached list as the other lanes.
      # shellcheck source=/dev/null
      . ${../lib/dictation-vocab.sh}
      if [[ -z "''${TRANSCRIBE_NPU_PROMPT+set}" ]]; then
        TRANSCRIBE_NPU_PROMPT=$(dictation_vocab 200 | tr '\n' ' ')
        TRANSCRIBE_NPU_PROMPT="''${TRANSCRIBE_NPU_PROMPT:0:600}"
      fi
      export TRANSCRIBE_NPU_PROMPT

      exec python3 - "$MODEL" "$DEVICE" "''${1:-/dev/stdin}" <<'PY'
      import os, sys, numpy as np, soundfile as sf, openvino as ov
      from transformers import WhisperProcessor

      model_dir, device, wav = sys.argv[1], sys.argv[2], sys.argv[3]
      audio, _ = sf.read(wav, dtype="float32")
      if audio.ndim > 1: audio = audio.mean(axis=1)

      proc = WhisperProcessor.from_pretrained(model_dir)
      feat = proc(audio, sampling_rate=16000, return_tensors="np").input_features

      core = ov.Core()
      enc = core.compile_model(f"{model_dir}/openvino_encoder_model.xml", device)
      dec = core.compile_model(f"{model_dir}/openvino_decoder_model.xml", device)
      hidden = enc({enc.inputs[0].any_name: feat})[enc.outputs[0]]

      tok = proc.tokenizer
      sot, nots = (tok.convert_tokens_to_ids(t)
                   for t in ("<|startoftranscript|>", "<|notimestamps|>"))
      eos = tok.eos_token_id
      # Whisper initial-prompt biasing: <|startofprev|> + prompt tokens +
      # <|startoftranscript|>. Soft n-gram conditioning, same mechanism as
      # whisper.cpp --prompt. Capped to 96 tokens — the decoder here re-runs
      # the full sequence each step (no KV cache on this OV path) so a long
      # prefix is paid 224x. The 448-token decoder ctx allows up to 224 but
      # 96 keeps the latency hit ~1.4x while still covering ~80 jargon terms.
      ids = []
      prompt = os.environ.get("TRANSCRIBE_NPU_PROMPT", "").strip()
      if prompt:
          sop = tok.convert_tokens_to_ids("<|startofprev|>")
          unk = getattr(tok, "unk_token_id", None)
          if sop is not None and sop != unk:
              ids = [sop] + tok.encode(" " + prompt, add_special_tokens=False)[-96:]
      ids += [sot, nots]
      start = len(ids)  # decode the transcript only, not the prompt prefix
      for _ in range(min(224, 448 - len(ids))):
          inp = {}
          for port in dec.inputs:
              n = port.any_name
              if "input_ids" in n: inp[n] = np.array([ids], dtype=np.int64)
              elif "hidden" in n:  inp[n] = hidden
              elif "mask" in n:    inp[n] = np.ones((1, len(ids)), dtype=np.int64)
          nxt = int(dec(inp)[dec.outputs[0]][0, -1].argmax())
          ids.append(nxt)
          if nxt == eos: break
      print(tok.decode(ids[start:], skip_special_tokens=True).strip())
      PY
    '';
  };
in
pkgs.symlinkJoin {
  name = "transcribe-npu";
  paths = [
    transcribe-npu
    probe-parakeet
  ];
}
