# adopt: llm-router model-warm — model-keyed spawn/reap for `ask-local --serve`

## What

Teach `llm-router` (`packages/llm-router/llm-router.py`) to be a model
*lifecycle* manager, not just a request-shape proxy.

Today the local leg is one fixed backend: `ask-local --serve` runs a
single `llama-server` on `:8088` with whichever model `$ASK_LOCAL_MODEL`
named at launch. `llm-router` (`:8090`) routes by request *shape* (short,
no-tools, ≤4k ctx → local) but forwards the OpenAI `model` field
opaquely. There is no way for two callers to want two different local
models — `sem-grep` needing the embed model and `ask-local --agent`
needing the 3.8B in the same window means manual restart, and the
structured-CoT model from `bench-structured-cot.sh` can't coexist with
either.

Add to `llm-router.py`:

- A backend registry `model → {port, pid, last_used}` (in-memory dict;
  state file under `$XDG_STATE_HOME/llm-router/backends.json` for
  visibility).
- On a local-routed request whose `model` field has no live backend,
  spawn `ask-local --serve --model <name> --port <next-free>`, wait for
  `/health`, then proxy. If the request names a model with a live
  backend, proxy directly.
- An idle reaper: a model unused for `LLM_ROUTER_IDLE_S` (default 300s)
  gets `SIGTERM` and its port freed. Reaping is the part that matters
  on Arc — shared iGPU memory means a stale resident model is
  contention against `transcribe-npu`/`agent-eyes`, not free.
- A hard cap `LLM_ROUTER_MAX_RESIDENT` (default 1, opt-up to 2) so the
  proxy can never thrash the iGPU into swap. Above cap, evict LRU
  before spawn.
- `decisions.jsonl` already logs route choices — extend each line with
  `{spawn, evict, reuse}` so `agent-meter` can plot model-residency
  churn next to its existing Arc/NPU occupancy gauge.

Needs a small `ask-local --serve --model <name> --port <n>` extension
(`packages/ask-local/default.nix:66-70` currently hardcodes `:8088` and
reads only the env var). One arg-parse case-arm, ~5 lines.

## Why

Seed: `llama-swap` (mostlygeek/llama-swap) — bumped 199→204→211 in
nixpkgs over the last two weeks (2026-04-23, 2026-05-05), so it's the
actively-maintained tool in this niche. It is an OpenAI-compat reverse
proxy that spawns/swaps `llama-server` processes keyed on the request's
`model` field, with idle TTLs and a YAML model registry.

Our angle: don't bolt a third proxy in front of `:8090`. nv1 already
has the proxy seam (`llm-router`), the spawnable backend (`ask-local
--serve`), the model auto-fetch (`adopt-model-autofetch` / 4f0f9ba),
and the contention awareness (`infer-queue` lanes). What's missing is
the ~80 lines that connect them: the registry + spawn-on-miss + idle
reap. `llama-swap` is also llama.cpp-only; folding the logic into
`llm-router` keeps the door open for an OpenVINO/NPU backend later
(same `model →` map, different launcher), which a verbatim adoption
would close.

This is also the structural answer to a question several backlog items
keep circling: structured-CoT wants its own model
(`needs-human/adopt-structured-cot-grammar.md` step 4 — "mirror into
ask-local?"), `diff-gate` wants a fast small model, `--agent` wants the
3.8B, and `sem-grep` wants `bge-small`. None of them can be a *default*
while there's exactly one resident-model slot. Model-warm is the piece
that lets nv1's local-LLM future be plural.

## How much

~0.4r. ~80L into `llm-router.py` (registry + reaper thread + spawn) +
~5L `ask-local` arg-parse + a `bench-model-swap.sh` (alternate
3.8B↔embed requests ×20, record first-token latency post-swap and
RSS/iGPU mem via `intel_gpu_top -J` for 1 sample/swap).
Zero new flake inputs, zero new pkgs (`llama-swap` itself is *not*
added — that's the point).

## Falsifies

The Arc iGPU question: is on-demand model swap usable on Meteor Lake
shared memory, or does the load latency make `MAX_RESIDENT=1` the only
sane default (= local-multi-model is dead, route everything-but-the-3.8B
to cloud)? `bench-model-swap.sh` decides:

- **PASS** (model-warm earns its place): post-swap first-token p95
  ≤ 5s for the 3.8B, ≤ 1s for `bge-small`, no OOM at `MAX_RESIDENT=2`.
  → flip `--agent` and `sem-grep embed` onto distinct models, file the
  diff-gate small-model follow-up.
- **FAIL** (swap is the cost, not residency): post-swap p95 > 10s or
  iGPU mem pressure causes ptt-dictate stutter. → keep `MAX_RESIDENT=1`,
  document it as a hardware constraint in `llm-router.py`'s header, and
  the structured-CoT "mirror into ask-local" question gets a hard no.

Either result is information; the bench is the falsification.

## Blockers

Bench needs nv1 hardware (Arc iGPU + the local models in `$XDG_DATA_HOME`).
The `llm-router.py` + `ask-local` edits and `bench-model-swap.sh` are
grind-safe (pure pkg edits, no flake.lock, no kin.nix). Land the code +
bench in a grind round, then route the *measurement* step to needs-human
the same way structured-CoT did.
