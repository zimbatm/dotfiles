# bump: srvos (15.5d stale, oldest external)

## What

```sh
nix flake update srvos
nix flake check  # gate: all 3 hosts eval + dry-build
```

## Why

Locked `7ae6f096b2ff` (2026-04-24, 15.5d). Upstream HEAD `6f237ae1c8f0`
— moved (ls-remote, drift @ 1cb22af). srvos provides the server hardening
profiles for relay1 + web2 (`srvos.nixosModules.server`,
`srvos.nixosModules.hardware-hetzner-cloud`). nv1 does not import srvos
— should be eval-identical. Watch for `services.openssh` /
`networking.firewall` defaults shifting under us; the kin mesh
(`kinq0`) and the kin-CA-signed host certs depend on the SSH config not
regressing.

## Externals freshness table (drift @ 1cb22af, 2026-05-09)

Bumper: oldest-first, one per round. nixpkgs (4.5d) and nixos-hardware
(2.3d) both fresh post-r4. No `bump-kin` outstanding (consumed @
1b86152 / r4). Next-oldest external is srvos.

| input | locked | age | upstream HEAD | moved? |
|---|---|---|---|---|
| srvos | `7ae6f096b2ff` | 15.5d | `6f237ae1c8f0` | yes — **this file** |
| nix-index-database | `b8eb7acee0f7` | 13.4d | `dd2d0e3f6ba0` | yes |
| home-manager | `c55c498c9aa2` | 13.0d | `fdb2ccba9d5e` | yes |
| nixvim | `d404af65e951` | 13.0d | `7986a276960b` | yes |
| nixpkgs | `549bd84d6279` | 4.5d | — | fresh (a06dd70) |
| nixos-hardware | `3bcaa367d4c5` | 2.3d | — | fresh (2dad55f) |

## How much

One `nix flake update srvos` + `nix flake check`. Small. relay1/web2
closures move (deploy reminder); nv1 should stay eval-identical —
verify.
