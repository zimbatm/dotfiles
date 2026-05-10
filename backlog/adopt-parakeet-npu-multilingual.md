# adopt: parakeet-tdt-v3 on the NPU lane — multilingual where it's cheapest

## What

**Handy** (cjpais/Handy, 21k★, Rust+Tauri, packaged in
numtide/llm-agents.nix) is converging local dictation on
**parakeet-tdt-0.6b-v3** as the recommended *non-GPU* model — citing
"CPU-optimized, excellent performance, automatic language detection"
and treating Whisper as the GPU-only fallback. That's a clear external
signal: the field has moved past whisper-base for the low-power lane.

We already run parakeet-tdt-0.6b-v3 — but only on the **CPU lane**
(`packages/transcribe-cpu`, sherpa-onnx int8). The two accelerated
lanes still run **whisper-base.en**, which is English-only:

- `ptt-dictate` → whisper-cpp/Vulkan on Arc (`ggml-base.en.bin`)
- `transcribe-npu` → OpenVINO `whisper-base.en-fp16-ov` on the Meteor
  Lake NPU

The NPU is the *cheapest* lane (lowest power, zero contention with Arc
when ask-local is resident) — exactly where you'd want to run the
default dictation model. Right now it's the *most* limited (single
language, English). Handy's signal is that parakeet-tdt-v3 (25 European
languages, auto-detect) closes that gap on commodity CPUs; the question
for nv1 is whether it also closes it on the NPU.

## Why

This is the dictation proving-ground gap that
`ops-dictation-vocab-bench.md` *doesn't* cover — that bench is about
vocabulary biasing on the *existing* models. This is about whether the
NPU lane is running the *wrong model entirely*. If a NEMO/CTC/TDT
encoder–decoder can compile under OpenVINO on the NPU, the NPU lane
gains 25-language auto-detect and (per NeMo's published WER) drops
English error rate vs whisper-base too — a strict upgrade on the most
efficient lane. If it can't compile (the same way silero-vad v5's
dynamic-rank `If` graph couldn't, see `packages/wake-listen` comments),
that's a real OpenVINO frontend boundary worth knowing — file it back
to whichever assise piece tracks NPU coverage.

## How much

Two stages, the first is dry and implementer-doable:

1. **Compile probe (no nv1 needed).** Add
   `packages/transcribe-npu/probe-parakeet.py` (~30 lines): fetch the
   sherpa-onnx parakeet-tdt-v3 ONNX (already a FOD in
   `transcribe-cpu`), `openvino.Core().compile_model(..., "NPU")` for
   encoder/decoder/joiner. Catch `OpConversionFailure`. Emit a one-line
   verdict. Run it with `device="CPU"` in CI (same frontend, different
   plugin) so the conversion question gets answered without hardware.
   Reuse the FOD from `transcribe-cpu` — **no flake.lock change, no
   new download.**

2. **WER bench (needs nv1, ops-* follow-up).** If the probe compiles
   clean on CPU plugin, file the `ops-` follow-up: run
   `tests/bench-dictate.sh` with the NPU plugin against the same WAVs
   the vocab bench will use, both whisper-base.en and parakeet-tdt-v3.
   Compare WER and RTF. Decide which model the NPU lane should default
   to.

Stage 1 is small and falsifiable on its own. Don't do stage 2 from an
agent (real machine, real NPU).

## Falsifies

- Does the OpenVINO ONNX frontend even convert a NeMo TDT graph?
  Stage 1's compile probe answers this in CI, no nv1.
- Is the NPU's int8 path competitive with sherpa-onnx int8 on a P-core?
  Stage 2's RTF column answers this. If the NPU is slower (small TDT
  decoder may be latency-bound, not throughput-bound), the NPU lane
  should stay on whisper for dictation and parakeet stays cpu-only —
  also a clean answer.
- Does Jonas actually dictate non-English? `live-caption-log` already
  records transcripts; grep the log for the whisper.cpp `[lang]`
  marker. If it's 100% `en`, the multilingual gain is theoretical and
  the WER delta is the only thing that matters — re-frame stage 2.
