# Drop limine-hotfix module — removal trigger fired

## What

`modules/nixos/limine-hotfix.nix` pins `boot.loader.limine.package` to a
manually-fetched 11.4.1 tarball. Its own header reads:

> Hotfix for limine 11.4.0's legacy BIOS limlz integrity failures on
> Hetzner Cloud. Remove once nixos-unstable carries limine >= 11.4.1.

That condition is now met. After `4b5ca4e` (nixpkgs `0726a0ec → 549bd84d`,
2026-04-22 → 2026-05-05):

```
$ nix eval --raw .#nixosConfigurations.web2.pkgs.limine.version
12.1.0
```

The module is no longer a forward-fix — it's an active **downgrade**
(12.1.0 → 11.4.1) and an `overrideAttrs` with a 12.x derivation body
applied to an 11.x source tarball, which only keeps building by luck.

## Change

Three deletions, no additions:

1. `rm modules/nixos/limine-hotfix.nix`
2. `flake.nix:94` — drop `limine-hotfix = ./modules/nixos/limine-hotfix.nix;`
   from `nixosModules` (keeps the ADR-0006 inventory exhaustive: 9 → 8
   files, 9 → 8 entries).
3. `machines/web2/configuration.nix:6` and
   `machines/relay1/configuration.nix:4` — drop the
   `inputs.self.nixosModules.limine-hotfix` import.

## How much

−12 LoC module, −3 import/inventory lines, −1 `fetchurl` derivation.

## Gate

Standard 3-host eval + dry-build. **Closure moves on web2 and relay1**
(bootloader binary changes 11.4.1 → 12.1.0).

## Deploy caution — read before applying

This touches the bootloader on both Hetzner VMs. It is *not* an inert
cleanup:

- **web2** is the always-on box. Limine 12.x has a different on-disk
  layout than 11.x; `limine-deploy` on switch will rewrite the BIOS boot
  sectors. Have the Hetzner console open and a snapshot taken before
  `kin deploy web2`. Verify with a controlled reboot, not by waiting for
  the next unplanned one.
- **relay1** is currently FULLY DOWN (ICMP+TCP/22 dead per drift r7) and
  will need a Hetzner-console rebuild anyway — apply there after recovery.
- Don't fold this into the cumulative DEPLOY REMINDER pile. Land it as
  its own commit so the deploy diff is one bootloader change, reviewable
  in isolation.

## Blockers

None for the repo edit. Deploy is human-gated as always — flagged here
because a bootloader swap deserves a snapshot and a watched reboot, not a
fire-and-forget `kin deploy`.
