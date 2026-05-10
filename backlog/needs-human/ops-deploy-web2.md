# web2: deploy + runtime checks (STALE — carries 1 since gen-27 @ bd8ef65)

**What:** `kin deploy web2` (carries 1: lockring landing 7f043af —
gen/manifest.lock + gen/_policy regen; lockring service is nv1-only
but the gen/ side touches all hosts), then walk the remaining runtime
checks below, then delete this file. Last human deploy: gen-27
May-10 ~12:13 + reboot, flushed the 3 carries from gen-26 within a
day. Carries grew back to 1 immediately (7f043af landed before the
deploy was probed).

**Blockers:** Human-gated. Non-root probe (kin-bir7vyhu) covers
service-level; the unchecked items below need root SSH or at-the-host
verification, refused by harness for META.

## Status (drift @ 4868b89, 2026-05-10)

```
web2:  have f06q7cg89xb9srxc1plsw6kngs0m8cjv…549bd84 (gen-27, May-10 ~12:13, rebooted)
       want b1vki8smbl8jjmcssx6lw8lhpn0nf1ly…549bd84 (unchanged @ d9ac7f1, 7f043af lockring gen/)
       carries 1 — STALE, no new movers
nv1:   have mmr7zsqbsx…549bd84 (= 87a370f, gen-26)  want pdbl6y1n…549bd84 (carries 7) — UNREACHABLE this round
```

3 carries flushed in the gen-27 deploy. Dry-build web2 0/0/0 (already
in local store). nv1 dry-build 30 drvs / 0 fetch. nv1 went off the
mesh ~13:00 UTC (web2 jump path 100% loss — desktop off/asleep, see
`ops-deploy-nv1.md`). Externals all <7d.

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

### drift @ bd8ef65 (2026-05-10)

```
have: /nix/store/kjiq55xlnipwssavflkz9isq3zhxwpgq-…549bd84   (gen-26, May-9)
want: /nix/store/f06q7cg89xb9srxc1plsw6kngs0m8cjv-…549bd84   (was zm1v54mn @ 38ccdcf)
carries: 3 — STALE
```

Closure mover: **d8a49c0** (kin `4db2186d→fb13c282`, iets
`751471a8→42fa90c1`). web2's closure delta is exactly the kin/iets
bump fan-out: `iets-0.1.0`, `kin-attest-publish`, `nix.conf`,
`unit-{ietsd,iets-attest-log,nix-daemon,dbus-broker}.service`,
`X-Restart-Triggers-{ietsd,nix-daemon,dbus-broker}` and the etc/
system-units/system-path cascade — 18 paths swap, closure size holds
at 701. **db007f8** (home-manager `fdb2ccba→2f419037`) is
web2-closure-neutral — no HM-managed users on web2's tag-set.
**4df1c0c** (packages harden — `llm-router.py`,
`lib/dictation-vocab.sh`, `sem-grep/bench-vs-ck.sh`) is web2-neutral
too — those packages reach only the desktop/terminal HM modules, not
the server profile. Carries grow 2→3 (`5decc79` iets + `e22951a`
kin builder-cert + `d8a49c0` kin/iets re-bump).

Dry-build PASS: web2 0 drvs to build (toplevel `f06q7cg89` already in
local store). `kin status` health: degraded — uptime 0d14h50m,
mem 2.8G/3.7G (74%), disk 13.3G/36.8G (36%), no needs_reboot,
`restic-backups-gotosocial.service` still failing (tracked in
`ops-web2-restic-rsyncnet.md`, not config drift). Not rebooted since
gen-26 deploy May-9 ~21:06.

Externals all <7d (nixpkgs 5d, hm 0d, srvos 3d, nixos-hw 3d,
nix-index-db 0d, nixvim 4d) — no bump-* to file.

Reconcile: unchanged from `### drift @ 3603dcd` — `kin deploy web2`
after the lockout-recovery check (the kin builder-cert carry from
e22951a is still in this delta; confirm fleet CA signing key hasn't
rotated underneath the deployed cert).

### drift @ d9ac7f1 (2026-05-10) — gen-27 DEPLOYED + REBOOTED, 1 new carry

```
have:   /nix/store/f06q7cg89xb9srxc1plsw6kngs0m8cjv-…549bd84   (gen-27, May-10 ~12:13)
booted: /nix/store/f06q7cg89xb9srxc1plsw6kngs0m8cjv-…549bd84   (have == booted == current — clean)
want:   /nix/store/b1vki8smbl8jjmcssx6lw8lhpn0nf1ly-…549bd84   (was f06q7cg89 @ bd8ef65)
carries: 1 — STALE
build:  ✓ dry-build 0 drvs / 0 fetch
```

web2 was deployed to gen-27 (`f06q7cg89` — the want from `### drift @
bd8ef65`) and **rebooted** at ~May-10 12:13. The 3 carries from gen-26
(5decc79 iets, e22951a builder-cert, d8a49c0 kin/iets) flushed in one
deploy. Uptime 16 min at probe.

Closure mover since bd8ef65: **7f043af** (`grind/bump-lockring-input`
merge). web2 does *not* import the lockring nixosModule
(`services.lockring.on = ["nv1"]` — `kin-opts` confirms web2 has no
`services.lockring.enable` option), but the merge regenerates
`gen/_policy/_shared/export.cedar` (+3 lines) and `gen/manifest.lock`
(rev bump), both of which land in every host's `/etc` cascade. `flake.nix`
`extraInputs` is eval-only; `flake.lock`'s new `lockring` node is a
narHash dependency of the `self` flake input. Net: web2 toplevel moves
on the gen/ side only — small delta, 0 new drvs.

**Failed unit caveat:** `kin status web2` shows `FAILED -` and
`systemctl is-failed restic-backups-gotosocial.service` reports
`inactive` — but that's a **reboot artifact, not a fix**. The service
last fired at 12:00 UTC (still
`Fatal: unable to open repository at sftp:zh6422@zh6422.rsync.net…
unexpected EOF`), web2 rebooted at ~12:13, the systemd FAILED state
reset, and the next timer fire is 13:00 UTC. `ops-web2-restic-rsyncnet.md`
stays open — the gen-27 deploy did not change `gotosocial.nix` or the
secret. Re-check after 13:00 UTC before closing.

Externals all <7d (nixpkgs 4d, hm 0d, srvos 2d, nixos-hw 2d,
nix-index-db 0d, nixvim 4d) — no bump-* to file. gen/ up to date
(`kin gen --check` passes).

Reconcile: `kin deploy web2`. Then re-walk the unverified runtime
checks (pin-nixpkgs, attest identity); re-check restic at 13:00+.

### drift @ 4868b89 (2026-05-10) — carries hold at 1, restic false-clean CONFIRMED

```
have:   /nix/store/f06q7cg89xb9srxc1plsw6kngs0m8cjv-…549bd84   (gen-27, May-10 ~12:13)
booted: /nix/store/f06q7cg89xb9srxc1plsw6kngs0m8cjv-…549bd84   (have == booted == current — clean)
want:   /nix/store/b1vki8smbl8jjmcssx6lw8lhpn0nf1ly-…549bd84   (unchanged @ d9ac7f1)
carries: 1 — STALE, no new web2 movers
build:  ✓ dry-build 0 drvs / 0 fetch
```

No web2-closure delta since d9ac7f1. The 4 source commits since then
are nv1-only or eval-only: `41e6f41`/`ed6da85` (web-eyes — desktop HM
module + flake package output, no server tag), `e395d16`/`4bb028a`
(parakeet probe — `transcribe-{cpu,npu}` reach only the desktop HM
profile), `a14716b` (`kin.nix` `gen.hcloud-api-token` — operator-side,
no `for`, `kin gen --check` shows only the unset reminder),
`fa65957` (`shell-squeeze` — agentshell devShell only). Carries hold
at 1 (`7f043af` lockring gen/ regen).

**restic false-clean CONFIRMED**: the `### drift @ d9ac7f1` caveat
("FAILED-flag reset by reboot is a reboot artifact, not a fix —
re-check after 13:00 UTC") fires. The 13:00 timer cycle ran and
failed the same way — `Fatal: unable to open repository at
sftp:zh6422@zh6422.rsync.net:gotosocial: … unexpected EOF`.
`kin status web2` now shows `✗` again. `ops-web2-restic-rsyncnet.md`
stays open; `gen-27` deploy did not change `gotosocial.nix` or the
rsync.net secret leg.

Health: uptime 0d0h44m (post-reboot), mem 2.9G/3.7G (76%) +836K
swap, disk 9.6G/36.8G (26%), 1 failed unit
(`restic-backups-gotosocial.service`).

Externals all <7d (nixpkgs 5d, hm 0d, srvos 3d, nixos-hw 3d,
nix-index-db 0d, nixvim 4d) — no bump-* to file. gen/ up to date.

Reconcile: `kin deploy web2`. Then re-walk the unverified runtime
checks (pin-nixpkgs, attest identity).
