# bump: home-manager (13.0d stale)

**What:** `nix flake update home-manager`. Currently `c55c498c`
(2026-04-26 15:44 UTC, 13.0d), upstream tip `fdb2ccba`
(nix-community/home-manager master, ls-remote 2026-05-09).

**Why:** >7d stale per drift policy. Tied second-oldest external (with
nixvim) as of `drift @ a73c579`.

**How much:** home-manager moves nv1's user closure broadly (terminal +
desktop hm modules). relay1/web2 import hm too via `gen.*` user blocks —
expect all 3 to move. Re-check `firefox.configPath` legacy pin
(`a94817f`, `modules/home/desktop`) survives — last hm bump (`22bbd1c`)
introduced the warning this pin silences; if upstream removed the
deprecation it can be dropped.

**Blockers:** none. Standard bumper round. Run after
`bump-nix-index-database` if doing oldest-first; same priority class
otherwise.
