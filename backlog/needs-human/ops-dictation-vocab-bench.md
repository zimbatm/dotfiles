# ops: WER bench for dictation vocabulary biasing

**needs-human** — needs nv1 hardware (microphone, NPU, Arc iGPU) and a
human to record reference WAVs.

## What

`adopt-dictation-vocab-biasing` landed the wiring: `sem-grep vocab` mines
project identifiers from the existing `refs` table, `dictation_vocab`
caches them under `$XDG_RUNTIME_DIR`, and all three transcribers now bias
on them — `ptt-dictate` via whisper.cpp `--prompt`, `transcribe-npu` via
the OpenVINO whisper `<|startofprev|>` prefix, `transcribe-cpu` via
sherpa-onnx `--hotwords-file` (gated on `bpe.vocab` shipping with the
parakeet tarball).

What landed is **plumbing, not proof**. Whisper's `--prompt` is a soft
n-gram bias and is documented to *hurt* when the prompt is too long or
mismatched. Parakeet's hotwords are a hard lattice rescore and can
overcorrect (rewrite real words into nearby jargon). Whether the bias
helps, hurts, or is a wash is exactly what the bench has to answer.

## How

1. Record ~20 short jargon-dense WAVs on nv1 (the dictation mic, real
   acoustic conditions). Cover the seed list and the top of `sem-grep
   vocab --top 30`: kin, assise, iets, maille, niri, gsnap, pueue, GBNF,
   sem-grep, ptt-dictate, ask-local, infer-queue, nv1, relay1, web2,
   nixpkgs, sops, agenix, parakeet, OpenVINO, ydotool, pipewire,
   tree-sitter, foot, zimbatm, plus a few sentences of plain English as
   a control.
2. Hand-transcribe references; write `tests/dictation-vocab.txt`
   (one `wav-path<TAB>reference` per line).
3. For each lane, transcribe the set twice — biased and unbiased — and
   compute WER and *identifier* WER (errors on the jargon tokens only):
   ```sh
   for f in tests/dictation/*.wav; do
     transcribe-npu "$f"                            # biased (default)
     TRANSCRIBE_NPU_PROMPT="" transcribe-npu "$f"   # unbiased
     transcribe-cpu "$f"                            # biased (default)
     TRANSCRIBE_CPU_HOTWORDS=0 transcribe-cpu "$f"  # unbiased
     # ptt-dictate's arc lane: re-run whisper-cli with/without --prompt
   done
   ```
4. Sweep `TRANSCRIBE_CPU_HOTWORDS_SCORE` (0.5, 1.0, 1.5, 2.0, 3.0) and
   the `dictation_vocab` cap on the biased runs.
5. Verify `bpe.vocab` actually ships in the parakeet FOD — if not, the
   transcribe-cpu lane is inert by design (see the gate in default.nix)
   and the bench should note that the cpu lane has no biasing path
   without a model swap.

## Done when

`packages/sem-grep/bench-vocab.txt` (mirroring `bench-refs.txt`) records
per-lane biased-vs-unbiased WER + identifier WER with the prompt cap and
hotword score that won. If unbiased ties or wins on identifier WER for
all three lanes, move `adopt-dictation-vocab-biasing.md` to `wontfix/`
with the numbers and revert the bias defaults to off.

## Falsifies

Does decoder biasing measurably reduce identifier WER vs the unbiased
baseline on a jargon test set, without raising plain-English WER? The
adopt item filed the hypothesis; this bench answers it.
