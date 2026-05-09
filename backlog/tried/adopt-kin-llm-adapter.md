# tried: adopt-kin-llm-adapter

**Outcome:** abandoned — scope violation (denylist hit)

**What happened:** grind worktree implementation touched `flake.lock`. The
item itself declares "Requires `flake.lock` bump to a kin rev ≥ 3012f7da —
the builtin doesn't exist at the current pin." Switching `kin.nix` to
`services.llm-adapter` therefore can't land without a lock change, and the
denylist forbids lock changes outside an explicit bumper round.

**File that tripped it:** `flake.lock`

**Resolution:** branch `grind/adopt-kin-llm-adapter` deleted, worktree
removed. Original item restored from origin/main and rerouted to
`backlog/needs-human/adopt-kin-llm-adapter.md`.

**Why needs-human:** triage skips subdirs, so this won't be auto-picked
again. A human reviews and either:
- applies the denylisted change directly (bump the kin input to ≥ 3012f7da
  in a reviewed commit; the kin.nix switch + `git rm
  services/llm-nvidia-adapter.nix` + secret re-key can follow in a normal
  grind round), or
- re-scopes so the lock bump is decoupled (e.g. file/await a `bump-kin`
  bumper item to land the pin first, then move this back to `backlog/` as
  a pure kin.nix edit with no lock delta), or
- deletes it.

**Don't retry as-is:** the builtin is absent at the current kin pin, so any
attempt to use `services.llm-adapter` either fails eval or forces a lock
bump. Land the kin pin first.
