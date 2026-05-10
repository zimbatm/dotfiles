# relay1: first install + deploy (re-created @ 74ed8ef, 2026-05-10)

**What:** `kin install relay1` (or `kin deploy relay1` if hcloud
seeded it), then verify mesh relay function and delete this file.

**Why:** relay1 was retired @ `dc78daf` (2026-05-09) and re-created
@ `74ed8ef` as a fresh cpx22 in `hel1` (hcloud server id 130258147,
public IP `37.27.251.231`). Fresh identity (`kin gen` ran, attest
key + ssh-host + tls all regenerated). It is now the fleet's
declared `services.mesh.relay` and `nv1.proxyJump` target — until
it is installed and on the mesh, both of those are pointing at a
host that isn't running the declared closure.

**Blockers:** Human-gated (CLAUDE.md). `kin install` is destructive
(partitions the disk). Needs the hcloud token (set @ a495b1d) and
direct SSH to the public IP for the initial bootstrap.

## Status (drift @ af167fd, 2026-05-10, ~16:50 UTC)

```
relay1: have <UNPROBEABLE — likely not installed yet>
        want dikz2p8m1574axnljwzr5j5awa8sb3fi…549bd84
build:  ✓ eval ok; dry-build 92 drvs (smallest closure of the three —
        no common.nix, no HM, deliberately minimal per
        machines/relay1/configuration.nix comment)
```

Direct `ssh root@37.27.251.231` rejected (publickey) from homespace
— consistent with both "fresh hcloud image waiting for `kin
install`" and "homespace has no fleet identity". Cannot
disambiguate without a fleet key. Either way, first deploy is
human-gated.

## Runtime checks (after install + deploy)

| check | command |
|---|---|
| mesh relay reachable | from nv1/web2: `ip -6 route show dev kinq0` includes relay1's ULA |
| proxyJump works | from a fleet machine: `kin ssh nv1` routes via relay1 |
| iroh relay serving | `journalctl -u maille-relay --since -5m` shows accept loop, no bind errors |
| assise cache trusted | `nix config show \| grep substituters` lists cache.assise.systems |
| sudo nopasswd | `sudo -n true` exits 0 for wheel |
| identity provisioned | `ls /run/kin/identity/attest.*` exists |

## Order matters

Install relay1 **before** redeploying nv1/web2: the
`services.mesh.relay = [ "relay1" ]` line in `kin.nix` lands on
every host's mesh config. Deploying nv1/web2 first leaves them
dialing a relay address that isn't accepting yet (iroh falls back to
direct/derp, but the telemetry will flap and `kin status` will
report the relay as unreachable).

## drift append-log

(drift-checker appends new `### drift @ <rev>` sections below;
META re-compacts when this exceeds 3 entries)
