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

### drift @ a246abf (2026-05-10, ~20:10 UTC) — INSTALLED + AT WANT

```
have:   /nix/store/dikz2p8m1574axnljwzr5j5awa8sb3fi-…549bd84   (gen-1, May-10 ~15:31 UTC)
booted: /nix/store/dikz2p8m1574axnljwzr5j5awa8sb3fi-…549bd84   (have == booted == current — clean)
want:   /nix/store/dikz2p8m1574axnljwzr5j5awa8sb3fi-…549bd84   (unchanged @ af167fd; fa37f2c/a246abf are web2-gen-only)
carries: 0
build:  ✓ eval ok; dry-build PASS (298 drvs across all 3 hosts, cold homespace store)
probe:  ✓ kin status relay1 → ✓ running, 0 stale, 0 unhealthy. Uptime 4h36m.
```

relay1 was installed at ~15:31 UTC and is running the declared
toplevel exactly. `kin status` reports it healthy: load 0.0/2,
mem 1.8G/3.7G (48%), disk 1.1G used / 70G avail (`kin status` 93%
column is *available*, not used — `df -h /` = 2% used). 0 failed
units. `kin-mesh.service` running (maille — QUIC TUN mesh); relay
function lives there, **no separate `maille-relay` unit** — the
runtime-check table above lists `journalctl -u maille-relay`, that's
the wrong unit name; use `journalctl -u kin-mesh`.

Mesh routes present on relay1's `kinq0`: `fd0c:3964:8cda::/48`
(home fleet) + `fdc5:e1a6:b03f::/48` (kin-infra peer-fleet).

**Runtime-check status:**

| check | status |
|---|---|
| mesh relay reachable | **partial** — web2's `kinq0` has the /48; relay1's specific ULA not individually checked |
| proxyJump works | **✗ NOT YET** — `kin ssh nv1` (proxyJump=relay1) times out. nv1 is running gen-26 (`mmr7zsqbsx`), which predates `mesh.relay=[relay1]` and the relay1 re-create — nv1's mesh doesn't know relay1's identity/route. Expected until nv1 redeploy. |
| iroh relay serving | **unverified** — unit is `kin-mesh.service`, not `maille-relay`; running, journal not yet inspected |
| assise cache trusted | **unverified** (non-root probe didn't `nix config show`) |
| sudo nopasswd | **unverified** |
| identity provisioned | **unverified** |

**Do not delete this file yet** — keep until the proxyJump leg is
verified working post nv1 redeploy. The "Order matters" note above
played out exactly: relay1 came up first; web2 redeployed next
(gen-28, see `ops-deploy-web2.md`); nv1 still on gen-26 and won't
route via relay1 until its own deploy. relay1 itself is fully
reconciled — nothing left to do *on relay1*.
