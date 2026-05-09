# bump: nix-index-database (13.5d stale, weekly index regen)

**What:** `nix flake update nix-index-database`. Currently `b8eb7ace`
(2026-04-26 05:27 UTC, 13.5d), upstream tip `dd2d0e3f` (Mic92/nix-index-database
main, ls-remote 2026-05-09).

**Why:** Weekly comma/nix-locate index regen. >7d stale per drift policy.
Oldest external in the lock as of `drift @ a73c579` (after srvos landed
ea03541).

**How much:** Data-only — the flake's nixos/hm module surface is stable.
Expect closure delta on every host that imports
`nix-index-database.hmModules.nix-index` (nv1 via
`modules/home/terminal`); relay1/web2 likely neutral. Verify with
`nix eval` per host before/after; gate = 3/3 eval + dry-build.

**Blockers:** none. Standard bumper round.
