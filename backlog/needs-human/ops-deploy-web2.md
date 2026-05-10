# web2: deploy + runtime checks (STALE again — carries 2 since gen-26 @ 87a370f)

**What:** `kin deploy web2` (carries 2: kin builder-cert regen +
iets bump), then walk the remaining runtime checks below, then delete
this file. Last human deploy: gen-26 May-9 ~20:44 + reboot ~21:06,
CONVERGED at 87a370f for ~1 day before bumps re-staled it. Drifted
gen-25 (Apr-24 → May-9, carries reached 13) is history; relay1 retired.

**Blockers:** Human-gated. Non-root probe (kin-bir7vyhu) covers
service-level; the unchecked items below need root SSH or at-the-host
verification, refused by harness for META.

## Status (drift @ 87a370f, 2026-05-10)

```
web2:  have kjiq55xlnipwssavflkz9isq3zhxwpgq…549bd84 (gen-26, May-9)
       want kjiq55xlnipwssavflkz9isq3zhxwpgq…549bd84 (87a370f)
       carries 0 — CONVERGED
nv1:   not-on-mesh                                  want mmr7zsqbsx…549bd84
```

13 carries flushed in one deploy. Dry-build web2 0/0/0 (already in
local store). nv1 dry-build 486/1245/4.3G (was 542/1279/4.4G —
fetches landed). Externals all <7d (nixpkgs 5.1d, hm 1.8d, srvos
3.2d, nixos-hw 3.0d, nix-index-db 1.8d, nixvim 4.7d).

## Runtime checks — web2 (5/8 PASS via drift spot-check @ gen-26, 2 remain, 1 fixed)

| check | status | command |
|---|---|---|
| peer-fleet /48 route | **PASS** | `ip -6 route show dev kinq0 \| grep fdc5:e1a6:b03f::/48` present |
| CA derivations | **PASS** | `nix config show \| grep ca-derivations` enabled |
| cache.assise substituter | **PASS** | `nix config show \| grep substituters` lists cache.assise.systems |
| peer-kin-infra trust | **PASS** | `@cert-authority` 1 entry in `/etc/ssh/ssh_known_hosts` |
| ietsd rollout-stage-1 | **PASS** | ietsd ACTIVE, `/nix/var/iets/daemon-socket/socket` present (`services.ietsd.on=[web2]` live) |
| pin-nixpkgs dropped | unverified | `nix registry list \| grep nixpkgs` and `echo $NIX_PATH` resolve to system pin |
| attest identity | unverified | `ls /run/kin/identity/attest.*` exists (non-root) |
| acme-order-renew | **FIXED** | post-deploy May-9 21:05 + May-10 07:02 both `status=0/SUCCESS`; cert valid to 2026-07-07. `ops-web2-acme-renew.md` deleted. |

Failed units: 1 (`restic-backups-gotosocial.service` — survived gen-26
deploy + reboot; sshpass auth to rsync.net rejected before SFTP
negotiates. Tracked in `ops-web2-restic-rsyncnet.md`, not config drift.)

relay1: retired @ dc78daf (2026-05-09).

---

## drift append-log

(drift-checker appends new `### drift @ <rev>` sections below; META
re-compacts into the table above when this section exceeds 3 entries)

<!-- compacted @ c93309d (META r3, 2026-05-10): folded 12 entries
(e960caf..87a370f, the Apr-24 gen-25 → May-9 gen-26 drift cycle:
carries grew 1→13 across f5bd72e, 778e7b8, dde1472, 1cb22af, a73c579,
9def97e, cce49ee, 80a9212, 6753fd8; web2 reconverged @ 87a370f;
acme-order-renew fixed; restic-gotosacial split out to
ops-web2-restic-rsyncnet.md; relay1 retired @ dc78daf). Prior
restructure @ b236e97 (META r1, 2026-04-24). -->

### drift @ 5d4d6b3 (2026-05-10)

```
have: /nix/store/kjiq55xlnipwssavflkz9isq3zhxwpgq-…549bd84   (gen-26, May-9)
want: /nix/store/q433p0x76a4nxqqvqf48izzf9lbx17ld-…549bd84   (was kjiq55xl @ 5e01750)
carries: 1 — STALE again (1 day after gen-26 reconverge)
```

Closure mover: **5decc79** (iets `4d7f54b7→751471a8` + llm-agents
`c7419130→7f0cb51f`). web2 runs `ietsd` (rollout-stage-1 PASS above), so
the iets bump moves the server toplevel. Note: the r4 bumper meta
(5d4d6b3) said "web2 unchanged (no nix-index-db in server closure)" —
that justification is correct for `5b3e8e1` only; it overlooked that
`5decc79` *does* touch web2 via ietsd. Drift confirms the eval delta.

Dry-build PASS: web2 21 drvs to build, no fetch listed (substituted).
`kin status` health: degraded — `restic-backups-gotosocial.service`
still failing (tracked in `ops-web2-restic-rsyncnet.md`, not config
drift). Uptime 0d13h — not rebooted since gen-26 deploy May-9 ~21:06.

Reconcile: `kin deploy web2`. Then re-walk the unverified runtime
checks above (pin-nixpkgs, attest identity).

### drift @ 3603dcd (2026-05-10)

```
have: /nix/store/kjiq55xlnipwssavflkz9isq3zhxwpgq-…549bd84   (gen-26, May-9)
want: /nix/store/zm1v54mngycdxrwl07w8cq4i9nsasj6z-…549bd84   (was q433p0x7 @ 5d4d6b3)
carries: 2 — STALE
```

Closure mover: **e22951a** (kin `912aad5c→4db2186d`, builder-cert
regen — `gen/identity/machine/web2/builder-cert.pub`,
`gen/identity/user-{claude,zimbatm}/_shared/cert-{1,2}.pub`,
`gen/ssh/_shared/config`). The new cert and the regenerated
`/etc/ssh/ssh_known_hosts` land in the web2 toplevel. Stacked on the
prior carry (5decc79: iets `4d7f54b7→751471a8` touches ietsd).

Dry-build PASS: web2 0 drvs to build (toplevel `zm1v54mn` already in
local store). `kin status` health: degraded — uptime 0d13h40m,
mem 2.8G/3.7G (75%), `restic-backups-gotosocial.service` still
failing (tracked in `ops-web2-restic-rsyncnet.md`, not config drift).

Externals all <7d (nixpkgs 5d, hm 1d, srvos 3d, nixos-hw 3d,
nix-index-db 0d, nixvim 4d) — no bump-* to file.

Reconcile: `kin deploy web2` (after lockout-recovery check — the
builder-cert regen rotates `/etc/ssh/ssh_known_hosts` and the
`@cert-authority` entry; confirm the fleet CA signing key hasn't
rotated underneath the deployed cert before applying). Then re-walk
the unverified runtime checks above (pin-nixpkgs, attest identity).

### drift @ 38ccdcf (2026-05-10)

```
have: /nix/store/kjiq55xlnipwssavflkz9isq3zhxwpgq-…549bd84   (gen-26, May-9)
want: /nix/store/zm1v54mngycdxrwl07w8cq4i9nsasj6z-…549bd84   (unchanged @ 3603dcd)
carries: 2 — STALE, no new movers
```

No web2-closure delta since 3603dcd. The two `.nix` commits since
0639edd (last drift) are nv1-only / agentshell-only: `459f04b`
(`machines/nv1/configuration.nix` gemma pin) and `1bf6327`
(`packages/shell-squeeze/default.nix`, reaches only the `agentshell`
flake output). Carries hold at 2 (`5decc79` iets bump + `e22951a`
kin builder-cert regen).

Dry-build PASS: web2 0 drvs to build (toplevel `zm1v54mn` already in
local store). `kin status` health: degraded — uptime 0d14h14m,
`restic-backups-gotosocial.service` still failing every hourly cycle
(`server unexpectedly closed connection: unexpected EOF` — tracked in
`ops-web2-restic-rsyncnet.md`, not config drift). Not rebooted since
gen-26 deploy May-9 ~21:06.

Externals all <7d (nixpkgs 5.3d, hm 1.9d, srvos 3.4d, nixos-hw 3.1d,
nix-index-db 0.2d, nixvim 4.9d) — no bump-* to file.

Reconcile: unchanged from `### drift @ 3603dcd`.
