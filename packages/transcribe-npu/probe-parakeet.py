#!/usr/bin/env python3
"""Compile probe: can OpenVINO's ONNX frontend convert parakeet-tdt-v3?

NeMo TDT graphs (encoder/decoder/joiner) are the candidate replacement for
whisper-base.en on the NPU lane (25-language auto-detect, lower published
WER). silero-vad v5 already showed the OV ONNX frontend has gaps
(OpConversionFailure on dynamic-rank Conv/ReduceMean — see
packages/wake-listen/default.nix). This probe answers the same question for
the parakeet graphs, on the CPU plugin so it runs without /dev/accel.

Verdict (OpenVINO 2026.1.0, CPU plugin, sherpa-onnx int8 export):
  encoder OK · joiner OK · decoder FAIL — no conversion rule for
  com.microsoft.DynamicQuantizeLSTM (the int8-quantized LSTM in the TDT
  prediction network, an onnxruntime contrib op). Same shape of failure as
  silero-vad v5: a graph the ORT runtime can run but the OV ONNX frontend
  can't lower. The NPU lane stays on whisper-base.en until either OV grows
  the op or we re-export the decoder fp16 (no DynamicQuantizeLSTM).

The script reports; it never gates. Exit 0 always — the verdict text is the
artifact.
"""

import argparse
import os
import sys

STAGES = ("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx")


def classify(err: Exception) -> str:
    msg = str(err)
    if "OpConversion" in msg:
        # OV's unconverted_ops_report appends a "Summary:" line ending in
        # "No conversion rule found for operations: <op>[, <op>...]".
        marker = "No conversion rule found for operations:"
        if marker in msg:
            ops = msg.split(marker, 1)[1].strip().splitlines()[0]
            return f"FAIL: OpConversionFailure on {ops}"
        return "FAIL: OpConversionFailure"
    first = msg.strip().splitlines()[0] if msg.strip() else type(err).__name__
    return f"FAIL: {first}"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model-dir", default=os.environ.get("PROBE_PARAKEET_MODEL"))
    p.add_argument("--device", default="CPU", choices=["CPU", "NPU"])
    args = p.parse_args()

    if not args.model_dir:
        print("probe-parakeet: no --model-dir and PROBE_PARAKEET_MODEL unset", file=sys.stderr)
        return 0

    import openvino as ov  # late import so --help works without the runtime

    core = ov.Core()
    for stage in STAGES:
        path = os.path.join(args.model_dir, stage)
        name = stage.split(".")[0]
        try:
            core.compile_model(path, args.device)
            verdict = "OK"
        except Exception as err:  # noqa: BLE001 — broad on purpose, we classify
            verdict = classify(err)
        print(f"parakeet-tdt-v3 {name} {args.device}: {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
