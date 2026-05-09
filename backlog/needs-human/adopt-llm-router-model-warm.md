# adopt: llm-router model-warm — bench the swap latency on nv1

## Status

Code landed (`grind/adopt-llm-router-model-warm`). **Remaining work needs nv1
hardware (Arc iGPU + the local GGUFs in `$XDG_DATA_HOME/llama`). DO NOT run
from an agent.**

What landed:

- `packages/llm-router/llm-router.py` — model-keyed lifecycle manager. Backend
  registry `model -> {port, pid, last_used}` mirrored to
  `$XDG_STATE_HOME/llm-router/backends.json`; on a local-routed request whose
  `model` resolves to a GGUF under `$XDG_DATA_HOME/llama` and has no live
  backend, spawns `ask-local --serve --model <path> --port <next-free>`, polls
  `/health`, then proxies. Idle reaper thread (`LLM_ROUTER_IDLE_S`, default
  300s) SIGTERMs untouched backends; hard cap `LLM_ROUTER_MAX_RESIDENT`
  (default 1) evicts LRU before spawn. Each `decisions.jsonl` line gains
  `{spawn, evict, reuse}`; reaper appends standalone `{"event": "evict"}`
  lines. Requests whose `model` does not resolve locally still hit the legacy
  `LLM_ROUTER_LOCAL` (`:8088`) backend unchanged.
- `packages/ask-local/default.nix` — `--serve [--model M] [--port N]`. Bare
  names resolve under `$XDG_DATA_HOME/llama`, mirroring the auto-fetch path.
- `packages/ask-local/bench-model-swap.sh` — alternates two model targets ×N
  through the router, records first-token TTFB per swap and one
  `intel_gpu_top -J` sample, prints post-swap p95 + PASS/WATCH/FAIL verdict.

### Remaining (human, on nv1, after `kin deploy nv1`)

1. Make sure the embed model exists locally (the bench defaults to
   `Phi-3-mini-4k-instruct-Q4_K_M` ↔ `bge-small-en-v1.5-q8_0`; pick a real
   pair from `ls $XDG_DATA_HOME/llama/*.gguf` and pass them as `$2 $3`).
2. `LLM_ROUTER_MAX_RESIDENT=1 llm-router &` then
   `packages/ask-local/bench-model-swap.sh 20`.
3. Re-run with `LLM_ROUTER_MAX_RESIDENT=2` to test coexistence — watch for
   OOM / ptt-dictate stutter while the bench runs.
4. Decide per the falsification spec:
   - **PASS** (post-swap p95 ≤ 5s 3.8B / ≤ 1s embed, no OOM at 2): flip
     `--agent` and `sem-grep embed` onto distinct models, file the diff-gate
     small-model follow-up.
   - **FAIL** (post-swap p95 > 10s or pressure stutter): keep `MAX_RESIDENT=1`,
     document the constraint in `llm-router.py`'s header, and the
     structured-CoT "mirror into ask-local" question gets a hard no.
5. Update or delete this file accordingly.

## Why this is needs-human

The whole item is a falsification of a hardware question (Meteor Lake shared
iGPU memory swap cost). The code is ready but the verdict needs a real Arc and
real models. See `backlog/adopt-llm-router-model-warm.md` history for the full
PASS/FAIL spec (deleted on landing — this carries the gist).
