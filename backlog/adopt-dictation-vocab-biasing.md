# adopt: vocabulary biasing for the dictation pipeline

## What

Handy (cjpais/Handy, ~21k stars) ships a hand-maintained **dictionary** —
a static substitution table users curate so the transcriber stops
mangling their proper nouns. That's a post-hoc fixup.

Our angle: **steer the decoder before it commits**, and **mine the
vocabulary instead of curating it**. All three transcription paths on
nv1 already accept biasing hints — none currently get any:

- `ptt-dictate` arc/fallback path → `whisper-cli` (whisper.cpp) supports
  `--prompt "<vocab list>"` as initial-context biasing.
- `transcribe-npu` → OpenVINO whisper pipeline accepts
  `initial_prompt` / decoder context tokens.
- `transcribe-cpu` → sherpa-onnx Parakeet supports `--hotwords-file` +
  `--hotwords-score` (contextual biasing built into the TDT decoder).

The biasing source is already on disk: `sem-grep` indexes every
git-tracked identifier across `~/src/{home,kin,iets,maille,meta}` plus
the `live-caption-log` corpus. A `sem-grep vocab` verb (or a 20-line
sqlite query against its existing index) yields the project's
high-frequency terms — `kin.nix`, `maille`, `iets`, `gsnap`, `niri`,
`pueue`, `GBNF`, machine names, package names — sorted by recency and
document frequency.

Wire-up:

1. `packages/sem-grep` — add a `vocab [--top N] [--json|--lines]` verb
   that emits the top-N identifiers from the current index. Cheap query;
   no new deps.
2. `packages/lib/dictation-vocab.sh` — shared helper that calls
   `sem-grep vocab --lines`, falls back to a static seed list if the
   index is cold, caches the result in `$XDG_RUNTIME_DIR` for the
   session.
3. Thread the result into each transcriber:
   `ptt-dictate` adds `--prompt "$(dictation-vocab)"`;
   `transcribe-cpu` writes it to a temp `--hotwords-file`;
   `transcribe-npu` passes it through to the OpenVINO pipeline.

## Why

The home repo's dictation pipeline is jargon-dense — `kin`, `assise`,
`iets`, `maille`, `niri`, package names, Nix idioms — exactly the
vocabulary stock Whisper/Parakeet won't know. Handy's answer is "make
the user maintain a dictionary." That's the wrong layer: it can only fix
what it can pattern-match after the model already chose the wrong
tokens. Decoder biasing fixes it where it's cheap, and `sem-grep`
already does the curation work nightly. This is the kind of
self-tightening loop nv1 exists to test: the corpus you grep feeds the
transcriber that feeds the corpus.

## How much

~0.5–0.7r. Step 1 is a small SQL verb on an existing tool. Step 2 is a
shell helper. Step 3 is three flag additions. No new flake inputs, no
new model downloads, no kin.nix change. The bench (a fixed set of
jargon-heavy WAVs + WER comparison with/without biasing) is ~0.3r more
and needs nv1 hardware → file as `ops-` once the code lands.

## Falsifies

Does decoder biasing measurably reduce identifier WER vs the unbiased
baseline on a fixed jargon test set? Whisper's `--prompt` is known to be
a soft bias (it biases the n-gram prior, not a hard constraint) and can
hurt if the prompt is too long. Parakeet's hotwords are stronger but the
TDT decoder may overcorrect. The bench answers both. If the unbiased
baseline already gets the vocab right (e.g. these terms appear in the
training data more than expected), wontfix and note the WER numbers.

## Blockers

None on the code side — pure `packages/` change. The bench needs nv1
hardware (NPU + Arc); that part is `ops-` and human-gated.

## References

- Handy (cjpais/Handy) — "the most forkable STT app"; dictionary feature
  is the inspiration. https://github.com/cjpais/Handy
- whisper.cpp `--prompt` flag (initial-prompt biasing)
- sherpa-onnx contextual biasing (`--hotwords-file`)
- `packages/sem-grep` (existing index source)
