# web2: post-deploy runtime checks (CONVERGED gen-26 @ 87a370f, May-10)

**What:** Walk the remaining runtime checks below on web2, then delete
this file. Deploy itself is **done** — web2 human-deployed gen-26
May-9 ~20:44 + reboot ~21:06, CONVERGED at 87a370f. Drifted gen-25
(Apr-24 → May-9, carries reached 13) is history; relay1 retired.

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
