---
name: sem-grep
description: Semantic grep over the five assise repos (~/src/{home,kin,iets,maille,meta}) via a local embedding index on the NPU. Reach for this BEFORE Grep when the query is fuzzy or conceptual ("where do we set the worker ssh CA", "what handles wake-word debounce") and you don't have the exact literal.
---

`sem-grep "<natural-language query>"` prints ranked `score  path:line`
hits (top 10) against a chunked index of every git-tracked text file in
the five repos. Default is **hybrid retrieval**: dense cosine
(bge-small-en on the Meteor Lake NPU) and lexical BM25 (sqlite FTS5)
fused with reciprocal-rank fusion. Dense catches paraphrase
("agentshell devshell wiring"); lexical catches exact identifiers
(`kin.nix`, `wheelNeedsPassword`) that a 384-dim model conflates.
No network, no paid API.

```sh
sem-grep "where is the agentshell devshell wired"
sem-grep -n 20 "openvino model directory layout"
sem-grep --mode dense   "..."   # cosine only (the original path)
sem-grep --mode lexical "..."   # BM25 only — exact identifiers, no NPU
sem-grep --mode hybrid  "..."   # RRF-fused (default)
sem-grep index    # refresh; incremental on git blob-sha — run after pulls
```

Use it when you'd otherwise Grep for a *concept* without knowing the
token. For a known literal `rg 'wheelNeedsPassword'` is still faster and
exact, but `sem-grep --mode lexical` gets close without an embed pass.
sem-grep is for the "I know it's in here somewhere" case across all
five repos at once. If top hits look wrong the index may be stale; run
`sem-grep index`.

## hist — semantic shell-history recall

`sem-grep hist "<what the command did>"` (alias `hist-sem`) ranks past
shell commands by intent, not literal match — for when you remember
*what it did* but not *what it was called*. The bash PROMPT_COMMAND hook
in `modules/home/terminal` appends `(ts,cwd,cmd,exit)` to
`$XDG_STATE_HOME/hist-sem/log.jsonl`; first query lazily batch-embeds
new rows into the same sqlite DB (`hist` table) with the same bge-small
encoder.

```sh
hist-sem "the ffmpeg line that fixed the audio drift"
hist-sem -n 20 "nix eval that showed closure size"
hist-sem --pick 2 "that rsync to relay1"   # bare cmd → stdout, for eval/$()
```

State lives at `$XDG_STATE_HOME/sem-grep/`: `index.db` is the chunk→vec
store (chunks + chunks_fts + sigs + refs + hist tables), `evals.jsonl`
logs every file query (with its `--mode`) so the dense/lexical/hybrid
recall test has real traffic to score. `SEM_GREP_DEVICE=CPU` to bypass
the NPU.
