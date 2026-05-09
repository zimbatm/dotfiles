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
