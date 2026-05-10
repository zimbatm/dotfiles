# ops-kin-gen-builder-cert — regen builder-cert.pub before bumping kin past 9dbbff28

> **needs-human** (rerouted 2026-05-10): generating
> `gen/identity/machine/{nv1,web2}/builder-cert.pub` requires `kin gen`
> with the home fleet admin age identity (decrypts
> `gen/identity/ca/_shared/ssh-ca.age` + per-machine `ssh-host.age`).
> That identity is not on the grind homespace — `~/.config/kin/key` is a
> broken symlink and `bir7vyhu.key` is a TLS client key, not age.
> `kin gen --check --json` confirms `identity/machine/{nv1,web2}` held on
> `$prev`. No grind implementer can satisfy this. **Pair with
> `ops-builders-key-drop.md` (this directory) for one human sit-down** —
> kin gen → bump kin → kin deploy hcloud-07 + nv1 → re-test falsifiers.

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

## Why this is an ops item

Generating `builder-cert.pub` requires `kin gen` with an age identity
that can decrypt `gen/identity/ca/_shared/ssh-ca.age` (adminOnly) and
the per-machine `$prev` secrets (`ssh-host.age`). The bumper homespace
does not have the home fleet's claude age identity:

- `~/.config/kin/key` is a broken symlink → a removed kin-infra worktree
  (`/root/src/kin-infra-grind/bug-runner-ssh-host-blocks-stub/keys/users/claude.key`).
- `~/.config/kin/bir7vyhu.key` is a PEM TLS client key (kin login), not
  an age identity.
- `keys/users/` has only `claude.pub` — the private age key isn't in the
  repo (correct, it's a secret).

`kin gen --check --json` from the bumper:
```json
[{"id":"identity/machine/nv1","state":"held","why":"$prev"},
 {"id":"identity/machine/web2","state":"held","why":"$prev"}, ...]
```

## How much

A human with the home fleet age identity:

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
