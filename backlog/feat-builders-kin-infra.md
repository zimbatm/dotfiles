# feat: dispatch builds from nv1 to kin-infra over the mesh (bridge proof)

## what

Add a `builders.hcloud-07` entry to `kin.nix` (kin remote tier, top-level
`builders.<n>` per `spec/model.nix`) pointing at kin-infra's hcloud-07 (ccx33,
8 vCPU / 32G, `ca-derivations` + `big-parallel`) over its maille ULA. For the
round-trip proof, drop nv1's machine ssh-host pubkey into hcloud-07's
`nix-remote` `authorizedKeys` by hand and pass that key as `sshKey`.

This is the **push bridge** — it proves the mesh route exists and the builder
accepts work. The declarative cross-fleet key path (no manual drop) is
`../kin/backlog/feat-builders-peer-fleet-keys.md`; the eventual pull/work-steal
shape replaces this entirely (track B3, not yet filed).

## why

nv1 is the dogfood for ADR-0009 graduated builds. Today `nix build` on nv1
builds everything locally — the laptop never uses the network. The mesh route
already exists (`services.mesh.peerFleets.kin-infra.seeds`,
`identity.peers.kin-infra` in `kin.nix:70-77`); build dispatch over it doesn't.
If the dogfood laptop can't reach a fleet builder, nothing past it will.

## how-much

Small. ~10 lines in `kin.nix` plus one ops command on hcloud-07. Needs:
- hcloud-07's maille ULA (from kin-infra's gen tree or `maille status`)
- confirmation hcloud-07 actually has `nix-remote` configured (kin-infra's
  `services/builders.nix` peer arm, or `services.ietsd.on` with a `nix-remote`
  user). If not, file a kin-infra config slice first.

## blockers

- Cross-fleet authz is the manual key for now. **Don't bake the key into a gen
  tree** — it's throwaway, removed by the kin slice.
- The `--max-jobs 0` falsifier forces *everything* remote — fine for the proof,
  wrong as a default. The default policy is the next slice
  (`feat-system-features-split.md`).

## falsifies

On nv1, mesh-only (no public IP):
1. `nix store ping --store 'ssh-ng://nix-remote@<hcloud-07-ula>'` succeeds.
2. `nix build nixpkgs#hello --max-jobs 0` builds on hcloud-07 (in hcloud-07's
   `nix log`, not nv1's).

Ping fails → key drop or `nix-remote` config wrong on hcloud-07.
Ping ok, build fails → protocol/feature mismatch — check
`experimental-features = ca-derivations` on both sides
(`kin/services/builders.nix` consumer + builder arms).
