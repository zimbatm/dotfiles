# bump: nixos-hardware (15d stale, oldest external)

## What

```sh
nix flake update nixos-hardware
nix flake check  # gate: all 3 hosts eval + dry-build
```

## Why

Locked `2096f3f411ce` (2026-04-23, 15d). Upstream HEAD `3bcaa367d4c5` —
moved (ls-remote, drift @ dde1472). Only nv1 imports `nixos-hardware`
profiles; relay1/web2 should be eval-identical. Watch for the limine
12.x landing in nixpkgs interacting with `modules/nixos/limine-hotfix.nix`
(11.4.1 pin) — the hotfix module already carries its own removal trigger,
but a hardware-profile bump can shift bootloader defaults.

## Externals freshness table (drift @ dde1472, 2026-05-09)

Bumper: oldest-first, one per round. nixpkgs already fresh post-a06dd70.
`bump-kin.md` (functional, unblocks adopt-kin-llm-adapter) outranks
freshness bumps per nixpkgs > kin > iets priority — take that first.

| input | locked | age | upstream HEAD | moved? |
|---|---|---|---|---|
| nixos-hardware | `2096f3f411ce` | 15d | `3bcaa367d4c5` | yes — **this file** |
| srvos | `7ae6f096b2ff` | 14d | `6f237ae1c8f0` | yes |
| home-manager | `c55c498c9aa2` | 12d | `fdb2ccba9d5e` | yes |
| nix-index-database | `b8eb7acee0f7` | 12d | `dd2d0e3f6ba0` | yes |
| nixvim | `d404af65e951` | 12d | `7986a276960b` | yes |
| nixpkgs | `549bd84d6279` | 3d | — | fresh (a06dd70) |

## How much

One `nix flake update <input>` + `nix flake check`. Small.
