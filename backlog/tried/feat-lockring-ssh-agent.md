# tried: feat-lockring-ssh-agent

**Outcome:** abandoned — scope violation (denylist hit)

**What happened:** grind worktree implementation touched `flake.lock`. The
item depends on a kin-side `services.lockring` wrapper that doesn't exist
at the current pin (the item itself lists
`../kin/backlog/feat-services-lockring.md` as a hard gate), so any attempt
to declare `services.lockring` in `kin.nix` either fails eval or forces a
kin input bump. The denylist forbids lock changes outside an explicit
bumper round.

**File that tripped it:** `flake.lock`

**Resolution:** branch `grind/feat-lockring-ssh-agent` deleted, worktree
removed. Original item restored from origin/main and rerouted to
`backlog/needs-human/feat-lockring-ssh-agent.md`.

**Why needs-human:** triage skips subdirs, so this won't be auto-picked
again. A human reviews and either:
- applies the denylisted change directly (bump the kin input to a rev that
  ships `services.lockring` in a reviewed commit; the `kin.nix` line +
  policy dry-run + `$SSH_AUTH_SOCK` flip can follow in a normal grind
  round — though deploy and the env flip are themselves human-gated), or
- re-scopes so the lock bump is decoupled (await the kin wrapper landing
  and a `bump-kin` bumper round to pin past it, then move this back to
  `backlog/` as a pure `kin.nix` edit with no lock delta), or
- deletes it.

**Don't retry as-is:** the kin wrapper is absent at the current pin. Land
`../kin/backlog/feat-services-lockring.md` and bump the pin first.
