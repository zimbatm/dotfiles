# ops: deploy builders bridge — kin deploy hcloud-07 + nv1, run falsifiers

**needs-human** — `kin deploy` to running machines, both fleets.

## status

The manual key-drop is **superseded** — nv1's ssh-host key is now declared
at `kin-infra@3f9c010f` (`machines/hcloud-07/configuration.nix`), so it
survives redeploys, is auditable, and gets removed in one commit when
`../kin/backlog/feat-builders-peer-fleet-keys.md` lands `TrustedUserCAKeys`.
What's left is two deploys and the round-trip proof.

## steps

1. **Pre-flight: check the maille route.** `dc78daf` removed `relay1`;
   `kin.nix:77` peers kin-infra via `seeds = ["5.75.246.255:7850"]`. If
   that was relay1's address, the cross-fleet mesh path is gone before
   the auth question even comes up. `maille status` on nv1 should show
   kin-infra peers reachable. If not, fix `peerFleets.kin-infra.seeds`
   first.

2. `cd ../kin-infra && kin deploy hcloud-07` — picks up the authorized_keys
   change from `3f9c010f`.

3. `cd ../home && kin deploy nv1` — picks up `nix.buildMachines` from
   `builders.hcloud-07` in `kin.nix`.

4. **Falsifiers (on nv1, mesh-only):**
   ```sh
   nix store ping --store 'ssh-ng://nix-remote@fdc5:e1a6:b03f::ad72:8e88:ac84:0e54'
   nix build nixpkgs#hello --max-jobs 0
   ```
   Ping fails → transport (step 1) or auth (check `~nix-remote/.ssh/
   authorized_keys` on hcloud-07 has the assise://…/machine/nv1 key).
   Ping ok, build fails → `experimental-features = ca-derivations` on
   both sides; check `kin/services/builders.nix` consumer + builder arms.

## known wart

`builders.hcloud-07.sshKey` in `kin.nix` is hard-coded to nv1's per-machine
`/run/kin/...` path because kin's `selfEntries` patch only fires when the
attr is *absent*, not `null`. Filed
`../kin/backlog/bug-builders-remote-sshkey-null-not-patched.md`.

## not the default policy

`--max-jobs 0` forces *everything* remote — fine for the proof, wrong as a
default. The default is the next slice
(`../kin/backlog/feat-system-features-split.md`, not yet filed).

## append @ 2026-05-10: hcloud-07 deployed, auth path changed, nv1 cert not deployed

The kin-infra grind sunset-removed the manual `3f9c010f` key bridge
(`c0cc0fba0`) once `feat-builders-peer-fleet-keys` shipped. hcloud-07
is now deployed (kin-infra Claude, 2026-05-10) with the declarative
replacement: `Match User nix-remote` block has `TrustedUserCAKeys`
trusting the home fleet CA (`kin://bir7vyhu.../ca`) and
`AuthorizedPrincipalsFile` requiring `builder@bir7vyhu7hjc6ybptojyjerh2nepv6oe`.

nv1 has the matching material in `gen/`:
- `gen/identity/machine/nv1/builder-cert.pub` — cert *for the ssh-host
  key* (same fingerprint), principal `builder@bir7vyhu...`, signed by
  the home fleet CA. Exactly what hcloud-07 expects.

**But the cert isn't deployed.** `/run/kin/identity/machine/nv1/` has
`{attest.key, ssh-host, tls.key}` and no `builder-cert.pub` /
`ssh-host-cert.pub`. SSH auto-loads `<key>-cert.pub` next to the key;
without it nv1 presents the bare host key and the cert-only auth path
on hcloud-07 rejects it (the manual bare-key path is gone).

Falsifier from nv1 confirms: `nix store ping --store 'ssh-ng://nix-remote@fdc5:e1a6:b03f::ad72:8e88:ac84:0e54'`
hangs ~50s then fails (auth waterfall, no matching key).

## remaining

1. **kin gap** — `services.builders` should deploy
   `gen/identity/machine/<n>/builder-cert.pub` to
   `/run/kin/identity/machine/<n>/ssh-host-cert.pub` (or set
   `CertificateFile` in the build-dispatch SSH options). Cross-filed:
   `../kin/backlog/feat-builders-deploy-cert.md`.
2. After the kin fix lands and bumps into `home/flake.lock`,
   `kin deploy nv1` deploys the cert.
3. Re-run the falsifier:
   ```sh
   nix store ping --store 'ssh-ng://nix-remote@fdc5:e1a6:b03f::ad72:8e88:ac84:0e54'
   nix build nixpkgs#hello --max-jobs 0
   ```
4. If pass: delete this file, drop the `# Cross-fleet authz is a MANUAL
   key drop` comment from `kin.nix`. The builders bridge is live.

The hcloud-07 side is **done**. This item is now blocked on the kin
side only — re-route from `needs-human/` to the regular backlog once
the kin cross-file lands.
