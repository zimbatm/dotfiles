# adopt: hybrid lexical+dense retrieval for sem-grep

## What

`qmd` (tobi/qmd) is a "mini cli search engine for your docs, knowledge
bases, meeting notes — all local, tracking current SOTA approaches."
The SOTA part is **hybrid retrieval**: BM25 lexical scoring fused with
dense embedding similarity, then rank-merged. Dense alone misses exact
identifiers; lexical alone misses paraphrase.

Our angle: `sem-grep` is already the local search engine for the assise
repos and the `live-caption-log` transcript corpus, but it's
**dense-only** — brute-force cosine over a tiny NPU embedding model.
For a personal corpus this jargon-dense, that's the wrong half to be
missing. `kin.nix`, `kin nicks`, and `kin-opts` embed nearly
identically on a small model; only a lexical index disambiguates. The
fix doesn't need qmd, tantivy, or a new flake input — sem-grep already
stores its chunks in **sqlite**, and sqlite ships **FTS5** with BM25
ranking built in.

Wire-up:

1. `packages/sem-grep` index path — alongside the existing `chunks`
   table, populate a contentless FTS5 virtual table
   (`CREATE VIRTUAL TABLE chunks_fts USING fts5(text, content='chunks',
   content_rowid='rowid')`). Identifiers should survive tokenisation:
   set `tokenize = "unicode61 remove_diacritics 2 tokenchars '._-'"` so
   `kin.nix` stays one token. Index update is incremental on the same
   nightly pass that already exists.
2. Query path — run both: top-K cosine over blobs (existing), top-K
   BM25 over `chunks_fts MATCH`. Fuse with reciprocal-rank fusion
   (`score = Σ 1/(k + rank_i)`, k≈60) — no learned weights, no
   reranker, just RRF. Return the merged top-N.
3. Add `--mode dense|lexical|hybrid` (default `hybrid`) so the bench can
   A/B all three on the same query set.

## Why

`sem-grep` is upstream of two consumers that both lean on identifier
precision: agents grepping the assise repos for option names / function
signatures, and the nightly `live-caption-log` fold (which is itself
full of dictated project terms). Dense-only retrieval is at its weakest
exactly there. Hybrid is the obvious next step and the implementation
lives entirely inside dependencies sem-grep already has — sqlite3 is
stdlib, FTS5 is compiled into nixpkgs' sqlite by default, and the index
file already exists. This is qmd's idea executed with zero new closure.

## How much

~0.5r. The FTS5 table is ~15 lines of schema + ~10 lines of incremental
sync. RRF is ~10 lines. The `--mode` flag is plumbing. The eval (a
fixed set of identifier-heavy queries with known-good answers) is
~0.2r more and can run anywhere with a built index — does NOT need nv1
hardware (FTS5 + cosine are CPU; only the embedding step touches the
NPU and that's already cached in the index).

## Falsifies

Does adding the lexical pass measurably improve top-3 recall on a fixed
identifier-heavy query set vs dense-only? Measure: a `tests/` fixture
with ~20 queries (mix of exact identifiers, paraphrase, transcript
recall), compare hit@3 across `--mode dense`, `lexical`, `hybrid`.
If dense-only already wins (small corpus, tiny model overfit), wontfix
with the recall numbers. If lexical-only wins, dense is the dead weight
— different and bigger conversation.

## Blockers

None — no flake input, no kin.nix change, no hardware. The eval fixture
needs a built sem-grep index; the index-from-repo path runs on any
machine, the index-from-transcripts path needs a `live-caption-log`
JSONL sample (can be a synthetic fixture).

## References

- qmd (tobi/qmd) — "tracking current SOTA approaches while being all
  local." https://github.com/tobi/qmd
- sqlite FTS5 + BM25 (built into nixpkgs sqlite)
- Reciprocal Rank Fusion — Cormack, Clarke, Büttcher 2009
- `packages/sem-grep` (existing dense index)
