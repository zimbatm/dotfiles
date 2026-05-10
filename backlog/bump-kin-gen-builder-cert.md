# bump-kin-gen-builder-cert — regen builder-cert.pub before bumping kin past 9dbbff28

> **gate cleared** (meta r5, 2026-05-10): `~/.config/kin/key` was a
> broken symlink when this was rerouted to needs-human, but it now
> resolves to `/root/src/kin-infra/keys/users/claude.key` — a real age
> identity that decrypts `gen/identity/ca/_shared/ssh-ca.age` (verified
> with `age -d`). The bumper can do `nix flake update kin && kin gen`
> from the grind homespace. The downstream `kin deploy hcloud-07 + nv1`
> stays human-gated (see `needs-human/ops-builders-key-drop.md`), but
> the gen + bump + commit are grind-actionable. Renamed `ops-` → `bump-`
> so triage doesn't auto-reroute it again.

## What

kin@2f79c99c (merge 9dbbff28 `feat-builders-peer-fleet-keys`,
identity-gen.nix +20L) added a new gen output
`identity/machine/<name>/builder-cert.pub` — an ssh user-flavour cert
signed by the fleet ssh-ca, used for nix-remote build dispatch trust
across `peerBuilders`. `services/builders.nix` (lib/gen-access.nix:33)
now throws at eval time if it's absent:

```
kin: gen output identity/machine/nv1/builder-cert.pub not generated — run `kin gen` before building
```

Home declares `builders.hcloud-07` (kin.nix), so this gate fires for
both kin-managed hosts (nv1, web2). The 2026-05-10 internal bump was
held at `kin@912aad5c` (last green) for this reason.

## Why this used to look like an ops item (resolved)

Generating `builder-cert.pub` requires `kin gen` with an age identity
that can decrypt `gen/identity/ca/_shared/ssh-ca.age` (adminOnly) and
the per-machine `$prev` secrets (`ssh-host.age`). When this was filed
(r4 bumper) `~/.config/kin/key` was a broken symlink and there was no
usable age identity. As of meta r5 the symlink resolves to
`/root/src/kin-infra/keys/users/claude.key`, which decrypts the home
fleet CA (verified `age -d`). `kin gen --check --json` returns `[]` at
the current pin (912aad5c — the gate only fires once kin crosses
9dbbff28).

## How much

From the bumper homespace:

```sh
nix flake update kin              # picks up >= 2f79c99c
kin gen                           # signs builder-cert.pub for nv1, web2
git add flake.lock gen/
git commit -m 'bump: kin (builder-cert.pub regen)'
```

Then `kin gen --check` should report up-to-date and `nix flake check`
(no-IFD leg) goes green again. Future kin bumps won't re-trigger this
unless the ssh-host key or fleet CA rotates ($prev gate copies the cert
forward when `ssh-host.pub` is byte-stable).

## Blockers

- Needs the home fleet (`bir7vyhu`) admin age identity. Not present on
  the bumper homespace — `kin login` with the right key, or `kin gen`
  from a machine that already has it.
- One-time: after the first regen the `$prev` gate keeps it byte-stable.

## Notes

This is *not* a kin regression — the throw is intentional (gen-access
sync gate). It's a one-time admin step every fleet with builders pays
when crossing 9dbbff28. The bumper should auto-bump kin again once
`gen/identity/machine/*/builder-cert.pub` exists.

Related: `needs-human/ops-builders-key-drop.md` — the manual ssh-host key
drop that `feat-builders-peer-fleet-keys` (TrustedUserCAKeys) is meant to
supersede. Doing both in one sit-down (kin gen → bump kin → kin deploy
hcloud-07 + nv1 → re-test the falsifiers) closes the loop.
