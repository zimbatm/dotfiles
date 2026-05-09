# zimbatm's home

Jonas's personal machines, deployed with [`../kin`](../kin) over the [`../maille`](../maille) mesh. This is the **primary assise dogfood** — the falsification test for the whole stack: if an assise piece can't run here, it's not real. See [`../meta`](../meta) for the project context; [`../kin-infra`](../kin-infra) is the second dogfood (org infra).

## Machines

| machine | host | tags | notes |
|---|---|---|---|
| `nv1` | `fd0c:3964:8cda::…:deae` (mesh ULA) | desktop | NAT'd; reachable via maille only |
| `web2` | 89.167.46.118 | server | hetzner-cloud; runs gotosocial |

All kin-managed machines are on the `ztm` identity domain. The maille mesh is
on but has no own relay (relay1 retired 2026-05); mesh reachability comes from
the kin-infra peer-fleet path.

## Layout

```
kin.nix              # the fleet declaration — users, machines, services, gen
machines/<name>/     # per-host NixOS config (hardware, machine-local)
modules/nixos/       # shared NixOS modules (common, desktop, server, …)
modules/home/        # home-manager modules
gen/                 # generated: identity certs, mesh, manifest.lock — `kin gen` rewrites this
keys/                # age recipients for machines and users
```

The flake is explicit (no auto-discovery) per ADR-0006 — every module and host is listed in `flake.nix`.

## Deploy

```sh
kin gen          # regenerate gen/ from kin.nix
kin deploy <machine>
```

**Deploy is human-gated.** These are real machines (one's a desktop). The `/grind` loop and CI commit changes but never apply them — `kin deploy` is run by a person after reviewing the diff and confirming SSH access stays intact.

Check before deploying: `nix build .#nixosConfigurations.<machine>.config.system.build.toplevel --dry-run`.
