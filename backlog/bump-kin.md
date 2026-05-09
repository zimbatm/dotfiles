# bump: kin (functional — unblocks adopt-kin-llm-adapter)

## What

```sh
nix flake update kin
kin gen && kin gen --check && nix flake check  # gate: all 3 hosts eval+dry-build
```

`kin gen` will likely regenerate `gen/` (ssh certs, manifest.lock) — commit
the regen alongside the lock bump.

## Why

Pin `0bfa6d35` (lastModified 2026-04-25, 14d, ~445 commits behind). Not
age-driven (kin is internal, not on the externals 7d threshold) —
**functional**: kin@`3012f7da` ships `services.llm-adapter` as a builtin,
which `backlog/needs-human/adopt-kin-llm-adapter.md` needs to drop our
local `services/llm-nvidia-adapter.nix` copy.

That item was rerouted to needs-human/ at 671466a as a scope violation
(implementer touched `flake.lock` outside a bumper round). Once this bump
lands, the adopt item's only remaining blocker is the `kin set` re-key +
deploy verify (genuinely human) — a future triage can move it back to
`backlog/` with the lock blocker stripped.

Also picks up whatever else moved in 445c — bumper should skim
`git -C ../kin log --oneline 0bfa6d35..origin/main | head -30` for breaking
changes before the eval gate.

## How much

`nix flake update kin` + `kin gen` regen + eval gate. Internal input —
small rebuild surface vs nixpkgs.

## Blockers

None for the bump. Sequence after `bump-nixpkgs.md` if both are pending
(priority `nixpkgs > kin > iets` per grind.md). **Do not deploy.**
