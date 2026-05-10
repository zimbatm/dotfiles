# meta: restore home-fleet kin identity in the homespace

**needs-human** — credential drop into the agent's homespace.

## What

The grind homespace has **no kin identity at all**: neither
`~/.ssh/kin-bir7vyhu_ed25519` (the home-fleet identity) nor
`~/.ssh/kin-infra_ed25519` (the self-heal fallback the meta wrapper uses
to `kin login claude --key`). `kin keys` reports `<no identity>`.

## Why

Drift @ `f3a50b4` reports **ALL 3 hosts UNPROBEABLE** for this reason —
not a host fault, just missing credentials. Until restored, every drift
round is a no-op: it can eval/dry-build but cannot compare deployed-vs-
declared, so the "carries N commits" counts are projections, not
measurements. The drift specialist's whole job degrades to a flake.lock
age check.

## How much

A human runs (from a machine that already has the identity):

```sh
scp ~/.ssh/kin-bir7vyhu_ed25519 <homespace>:~/.ssh/
# or, if reissuing:
kin login claude   # interactive, on the homespace
```

Then verify: `kin keys` should show the bir7vyhu identity, and the next
drift round should probe at least web2 (always-on).

## Falsifies

Next drift commit after the key drop should read `web2 PROBEABLE` (or
similar) instead of `UNPROBEABLE`. If it still can't reach web2 with the
key present, that's a real network/firewall regression — split into a
separate `bug-*`.

Delete this file once the key is restored and a drift round confirms
probe.
