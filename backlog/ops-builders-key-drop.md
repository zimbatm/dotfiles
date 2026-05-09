# ops: drop nv1's ssh-host.pub on hcloud-07 nix-remote, then run the falsifiers

**needs-human** — touches a running kin-infra machine and runs commands on nv1.

## what

`builders.hcloud-07` is now declared in `kin.nix` (ADR-0009 remote tier,
push-bridge proof). The `nix.buildMachines` entry lands on nv1 after the next
`kin deploy nv1`. What's left is the manual cross-fleet authz half and the
round-trip falsifiers — both human steps.

## key drop (on hcloud-07)

Append nv1's machine ssh-host pubkey to `nix-remote`'s `authorizedKeys` on
hcloud-07. The key is `gen/identity/machine/nv1/ssh-host.pub`:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE37f4+I6Yml/OhA62ror89NWNjhHebmbRxv6/o4nFAY assise://bir7vyhu7hjc6ybptojyjerh2nepv6oe/machine/nv1
```

```sh
# from a host with kin-infra deploy access (hcloud-07 = 46.224.164.167)
ssh root@hcloud-07 'mkdir -p ~nix-remote/.ssh && cat >> ~nix-remote/.ssh/authorized_keys' \
  < gen/identity/machine/nv1/ssh-host.pub
```

**Don't bake this into kin-infra's gen tree** — it's throwaway, removed once
`../kin/backlog/feat-builders-peer-fleet-keys.md` lands the declarative path.

## falsifiers (on nv1, mesh-only — no public IP)

After `kin deploy nv1` and the key drop:

1. `nix store ping --store 'ssh-ng://nix-remote@fdc5:e1a6:b03f::ad72:8e88:ac84:0e54'`
   succeeds.
2. `nix build nixpkgs#hello --max-jobs 0` builds on hcloud-07
   (check hcloud-07's `nix log`, not nv1's).

Ping fails → key drop or `nix-remote` config wrong on hcloud-07.
Ping ok, build fails → protocol/feature mismatch — check
`experimental-features = ca-derivations` on both sides
(`kin/services/builders.nix` consumer + builder arms).

## known wart

`builders.hcloud-07.sshKey` in `kin.nix` is hard-coded to nv1's per-machine
`/run/kin/...` path because kin's `selfEntries` patch only fires when the attr
is *absent*, not when it's `null` — `mkEntry` always sets it for remote-tier
entries. Filed `../kin/backlog/bug-builders-remote-sshkey-null-not-patched.md`.
Once that lands, drop the `sshKey` line and each dispatcher gets its own key.

## not the default policy

`--max-jobs 0` forces *everything* remote — fine for the proof, wrong as a
default. The default policy is the next slice
(`feat-system-features-split.md`, not yet filed).
