# feat: feature-split build policy — nv1 builds small, dispatches heavy

## what

Exclude `big-parallel`, `nixos-test`, `benchmark` from nv1's
`nix.settings.system-features` so derivations carrying
`requiredSystemFeatures = ["big-parallel"]` (and friends) are *forced* onto a
remote builder. kin-infra builders advertise those features; nv1 won't.

This is the policy half of "some, not all." Stock `nix.buildMachines` is
overflow-only — dispatches when local is saturated or a feature is missing,
never to load-balance. `--max-jobs 0` forces *everything* remote, which is
wrong on a laptop. The feature gate is the declarative, per-derivation answer:
heavy drvs go out, normal drvs stay, no flags. The tags carry forward unchanged
into the eventual pull/work-steal model — the policy survives the transport
swap.

## how-much

One line of per-machine settings in `kin.nix` (or a NixOS module override
scoped to nv1). Check the current default first
(`nix config show system-features` on nv1 — typically
`benchmark big-parallel kvm nixos-test` plus the platform tuple) and remove
only the heavy ones; keep `kvm` and the platform.

## blockers

`feat-builders-kin-infra.md` — with no remote builder declared, excluding
`big-parallel` makes those drvs **unbuildable**, not dispatched. Land the
builders entry first or in the same change.

## falsifies

`nix build` on nv1 of a closure containing one `big-parallel` drv and one
normal drv, with **no** `--max-jobs` / `--builders` flags → the heavy drv
appears in hcloud-07's `nix log`, the normal one in nv1's. Conversely, with the
builder removed, the same build fails with "a build with required system
features … is not available" rather than building the heavy drv locally —
proves the exclusion is enforced, not advisory.
