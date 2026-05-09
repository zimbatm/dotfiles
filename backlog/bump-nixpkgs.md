# bump: nixpkgs (16d stale, nixos-unstable)

## What

```sh
nix flake update nixpkgs
kin gen --check && nix flake check  # gate: all 3 hosts eval+dry-build
```

## Why

drift @ 23975b3 (2026-05-09): `flake.lock` nixpkgs lastModified=1776877367
(2026-04-22, rev 0726a0ec) — **16d** vs 7d threshold. Follows
`nixos-unstable`; upstream HEAD `549bd84d` (ls-remote verified MOVED).
All 3 host toplevels currently pin `26.05.20260422.0726a0e`.

After nixpkgs lands, the other externals are also stale — ALL upstream
MOVED (ls-remote verified at 23975b3), pick oldest-first per
`.claude/commands/grind.md`:

| input | locked | age | upstream HEAD |
|---|---|---|---|
| srvos | 7ae6f096 | 15d | 6f237ae1 |
| nixos-hardware | 2096f3f4 | 15d | 3bcaa367 |
| nix-index-database | b8eb7ace | 13d | dd2d0e3f |
| home-manager | c55c498c | 12d | fdb2ccba |
| nixvim | d404af65 | 12d | 7986a276 |

## How much

One round per input; `nix flake update <input>` + eval gate. nixpkgs is
the heaviest (rebuilds most of nv1's 4.9 GiB closure). 13-day grind gap
let all 6 cross threshold at once — bumper backlog should clear in ~6
rounds.

## Blockers

None for the bump itself. **Do not deploy** — that's human-gated, and
relay1 is currently unreachable (`ops-relay1-recover.md`).
