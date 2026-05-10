# adopt: ck head-to-head bench — is the NPU embedder load-bearing?

## What

Bench `ck` (BeaconBay/ck — Rust hybrid BM25+semantic grep, ships its
own small ONNX embedder, no GPU/NPU) against `sem-grep` on the
existing 20-query bench (`packages/sem-grep/bench-refs.txt` /
`bench-log.txt`), three legs:

1. `sem-grep` body+sig dense (bge-small on NPU) — the current default
2. `sem-grep` lexical-only (FTS path, no embed, already exists per
   `sem-grep.py:163`) — the floor
3. `ck --hybrid` (BM25 + its bundled CPU ONNX embedder) — the
   challenger

Score recall@5 on the same labelled corpus (`~/src/{home,kin,iets,
maille,meta}`). One bench script (`packages/sem-grep/bench-vs-ck.sh`),
~40 lines. Run `ck` via `nix run github:numtide/llm-agents.nix#ck` —
one-off, no flake input, no flake.lock delta.

## Why (seed → our angle)

Seed: **`ck`** (BeaconBay, in numtide/llm-agents.nix). "Local first
semantic and hybrid BM25 grep / search tool for use by AI and humans."
Pure Rust, no accelerator, runs anywhere.

Prior scout (356c258) skipped ck as "sem-grep covers local-RAG." That
dismissal was about *capability* — ck doesn't add a verb sem-grep lacks.
This filing is about *cost*: sem-grep's dense path drags `openvino +
transformers + numpy` (~1 GB of closure per `default.nix:3` "subset of
transcribe-npu's closure") and a 280 MB rerank IR into the home
build. The whole point of the home repo is falsification under
daily-driver load — and "do we need the NPU embedder" is exactly the
kind of premise that should have a number behind it instead of an
assumption. ck is the cheapest available off-the-shelf falsifier:
someone already built the no-accel version and tuned it for AI agents.

Our angle: not "adopt ck." We keep sem-grep regardless — its `runs`,
`hist`, `refs` tables are bespoke and ck has nothing comparable. The
question is whether the *body-search dense leg specifically* earns its
weight. Three outcomes:

- ck's CPU embedder matches bge-small/NPU on recall → the dense leg's
  value is the embedding *quality*, not the NPU residency. File a
  simplifier item: swap sem-grep's body embedder to a fastembed-style
  CPU ONNX and drop the OpenVINO body-leg dependency. (NPU stays for
  `runs`/`hist` if those benches hold, and for transcribe-npu/
  wake-listen which have their own justification.)
- ck loses to sem-grep dense but matches sem-grep lexical → the dense
  leg isn't earning its keep over FTS; same simplification applies but
  more aggressively (drop dense body search entirely).
- sem-grep dense clearly wins both → the NPU embedder is load-bearing.
  Record the margin in `bench-log.txt` so the next "why is the home
  closure 1 GB bigger than expected" investigation has an answer.

## How much

~0.3 round to write the bench script (extend `bench-refs.txt` legs).
Bench *run* needs nv1 hardware (the NPU device + the fetched bge-small
IR) → goes to `needs-human/` after the script lands, paired with
`ops-deploy-nv1`.

## Falsifies

Recall@5 on the 20-query labelled set:

- **ck-hybrid ≥ sem-grep-dense − 0.05** → file
  `simplify-sem-grep-body-embedder.md` (swap to CPU ONNX, drop
  OpenVINO from sem-grep's body leg; measure closure delta).
- **sem-grep-dense > ck-hybrid + 0.10 AND sem-grep-dense >
  sem-grep-lexical + 0.10** → keep as-is, record margin, mark this
  question answered.
- **sem-grep-dense ≈ sem-grep-lexical** → drop the body dense leg
  entirely; the FTS path is sufficient for the grind's query shape.

## Notes

This is intentionally *not* a vendor-ck item. If the bench says ck
wins, the follow-up is "make sem-grep's embedder lighter," not
"replace sem-grep" — sem-grep's NPU co-residency story (Silero VAD +
embed + rerank as 1st/2nd/3rd tenants) is its own thread and shouldn't
be collapsed into a body-search bake-off.

## Status (2026-05-10) — script landed, needs nv1 to run

`packages/sem-grep/bench-vs-ck.sh` is in. Three legs (dense/lexical/ck-hybrid)
over `bench-refs.txt`, file-level recall@5, prints the falsification thresholds.
Fails loudly if `/dev/accel/accel0` or the bge-small IR is absent — by design,
this cannot run in the grind worktree. Pair with `ops-deploy-nv1`:

```sh
packages/sem-grep/bench-vs-ck.sh | tee -a packages/sem-grep/bench-log.txt
```

Then file the follow-up the threshold table picks (or close this if dense
clearly earns its keep).
