# sec: harden three grind-authored packages (small, ≤5 lines each)

Filed 2026-05-10 from automated security review of recent grind merges.
None of these are exploitable in deployment context (loopback-only,
single-user desktop, no privilege boundary), but each is a strict
≤5-line improvement and clearing them stops the same review re-firing
every round.

## 1. `packages/llm-router/llm-router.py` — `resolve_local_model()` accepts arbitrary paths

Current: returns any path containing `os.sep` or ending `.gguf` verbatim
if it exists on disk. The path is passed to a subprocess
(`ask-local --serve --model <path>`), not echoed back, so no info leak —
but the HTTP `model` field shouldn't carry the same trust as a CLI flag.

Fix: basename the HTTP-supplied name, `os.path.realpath` the candidate,
verify it's under `os.path.realpath(MODEL_DIR)` before returning. Keep
absolute-path acceptance for *CLI* callers if there are any (grep —
the docstring claims parity with `ask-local --model`). Don't break the
documented bare-name lookup under `$XDG_DATA_HOME/llama`.

## 2. `packages/lib/dictation-vocab.sh` — `/tmp` cache fallback

Current: `cache="${XDG_RUNTIME_DIR:-/tmp}/dictation-vocab.txt"`. On nv1
`XDG_RUNTIME_DIR` is always set (systemd-logind), so the `/tmp` branch
never fires in practice. But `>"$cache.part"` follows pre-placed symlinks
and `/tmp` is shared.

Fix: fall back to `${XDG_STATE_HOME:-$HOME/.local/state}/dictation`
instead of `/tmp`. One line. The cache is per-user state, not a runtime
temp file — `XDG_STATE_HOME` is the right home for it anyway.

## 3. `packages/sem-grep/bench-vs-ck.sh` — unpinned `nix run github:…`

Current: `nix run github:numtide/llm-agents.nix#ck` fetches floating
HEAD. Beyond the supply-chain angle (low — own org), this means the
recall@5 numbers compare `sem-grep` against whatever `ck` is at runtime,
not the `ck` actually pinned in `flake.lock`. Bench results aren't
reproducible or comparable across runs.

Fix: resolve the locked rev and pin the ref:

```sh
ck_rev=$(nix eval --raw --impure --expr \
  '(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.llm-agents.locked.rev')
nix run "github:numtide/llm-agents.nix?rev=${ck_rev}#ck" -- ...
```

Or, if the bench can assume a devshell, add `ck` to the sem-grep
package's `runtimeInputs` from `inputs.llm-agents.packages` so it's the
locked binary on PATH.

## How much

3 files, ~15 changed lines total. No closure delta beyond the package
hashes. Gate: nv1 + web2 eval + dry-build (only nv1's closure moves).

## Falsifies

If a future review re-flags the same patterns after this lands, the
review heuristic is broader than the fix — file the *new* finding, don't
re-tighten beyond what these address.
