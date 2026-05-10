# web2: post-deploy runtime checks (CONVERGED gen-26 @ 87a370f, May-10)

**What:** Walk the remaining runtime checks below on web2, then delete
this file. Deploy itself is **done** — web2 human-deployed gen-26
May-9 ~20:44 + reboot ~21:06, CONVERGED at 87a370f. Drifted gen-25
(Apr-24 → May-9, carries reached 13) is history; relay1 retired.

**Blockers:** Human-gated. Non-root probe (kin-bir7vyhu) covers
service-level (0 failed units verified by drift); the unchecked items
below need root SSH or at-the-host verification, refused by harness for
META.

## Status (drift @ fcc6b68, 2026-04-24)

```
web2:   have c27fxv31… == want c27fxv31…  (gen-25, 2026-04-24 20:06)  0 failed units
relay1: have xmb9mkd4… == want xmb9mkd4…  (gen-16, 2026-04-24 20:06)  0 failed units
```

Both carried 0 since deploy; 778e7b8 was the last closure-affecting
commit. Dry-build web2 158/76/285.5M, relay1 71/9/140.7M. acme-degraded
cleared from failed-state by redeploy (last-run pre-deploy still
status=1; next timer tells — see ops-web2-acme-renew.md).

## Runtime checks — web2 (3/8 PASS via drift spot-check, 5 remain)

| check | status | command |
|---|---|---|
| peer-fleet /48 route | **PASS** | `ip -6 route show dev kinq0 \| grep fdc5:e1a6:b03f::/48` present |
| CA derivations | **PASS** | `nix config show \| grep ca-derivations` enabled |
| cache.assise substituter | **PASS** | `nix config show \| grep substituters` lists cache.assise.systems |
| peer-kin-infra trust | unverified | `grep '@cert-authority' /etc/ssh/ssh_known_hosts` includes kin-infra CA; `maille config show \| jq .peer_fleets` lists kin-infra |
| pin-nixpkgs dropped | unverified | `nix registry list \| grep nixpkgs` and `echo $NIX_PATH` resolve to system pin |
| attest identity | unverified | `ls /run/kin/identity/attest.*` exists |
| restic-gotosocial | unverified | `systemctl status restic-backups-gotosocial.{service,timer}` active |
| acme-order-renew | next-timer | see ops-web2-acme-renew.md |

relay1: /48 route PASS + 0 failed units (drift @ fcc6b68); same 5
remain unverified (root SSH denied to META) but 0-failed-units covers
service-level.

---

## drift append-log

(drift-checker appends new `### drift @ <rev>` sections below; META
re-compacts into the table above when this section exceeds 3 entries)

<!-- restructured @ b236e97 (META r1, 2026-04-24): web2 CONVERGED gen-25 — header "redeploy (drifted)" stale, folded carries-8 table + fcc6b68 append into 3-PASS/5-remain checks table. relay1 history retained: split from ops-deploy-relay1-web2.md @ META r1 2026-04-24, converged gen-15 @ xzzh4496 Apr-24 10:29, gen-16 Apr-24 20:06. -->

### drift @ e960caf (2026-04-26)

**DRIFTED again** — declared moved forward (f5bd72e flake update); both
still on Apr-24 gen. Reconcile: `kin deploy web2 relay1`.

```
web2:   have c27fxv31… (gen-25)  want 9ngq03fj…-26.05.20260422.0726a0e   carries 1
relay1: have xmb9mkd4… (gen-16)  want 01g8xx8p…-26.05.20260422.0726a0e   carries 1
```

Dry-build: web2 143/75/165.2M (was 158/76/285.5M), relay1 50/1/0.4K (was
71/9/140.7M — cache.assise has it). Bisect fcc6b68..e960caf: f5bd72e
(nixpkgs b12141e→0726a0e + 8 internal/ext bumps) is the only
closure-affecting commit for both — c37cecc vim-utils overlay is
nv1-only, verified NEUTRAL (relay1 01g8xx8p, web2 9ngq03fj identical at
both f5bd72e and e960caf).

Spot-check (re-probed): web2 /48 route PRESENT + ca-derivations enabled
+ cache.assise in substituters (3/8 hold). relay1 /48 route PRESENT + 0
failed. **web2 1 failed unit**: acme-order-renew-gts.zimbatm.com fired
Apr-26 02:26 post-deploy and FAILED again — see ops-web2-acme-renew.md
(redeploy did NOT fix it).

### drift @ 671f35b (2026-04-26)

**No-change re-probe** — declared UNCHANGED (66b1cfa nixvim+overlay-drop
verified NEUTRAL: relay1 01g8xx8p, web2 9ngq03fj eval-identical at
e960caf and 671f35b; 79eb0ac default.nix not in closure). Deployed
unchanged, still carries 1 (f5bd72e). Reconcile unchanged: `kin deploy
web2 relay1`.

```
web2:   have c27fxv31… (gen-25)  want 9ngq03fj…   carries 1   degraded (acme-order-renew)
relay1: have xmb9mkd4… (gen-16)  want 01g8xx8p…   carries 1   running (0 failed)
```

Dry-build: web2 143/75/165.2M (identical), relay1 50/0/0 (was 50/1/0.4K
— last fetch landed locally). Uptime web2 18d8h, relay1 18d6h. acme
timer next-fire Apr-27 02:26 not yet reached.

### drift @ e3c1cea (2026-04-26)

**DRIFTED again** — declared moved (94dd7b4 internal bump); both still
on Apr-24 gen, **carries 1→2**. Reconcile unchanged: `kin deploy web2
relay1`.

```
web2:   have c27fxv31… (gen-25)  want y6amiis8…   carries 2   degraded (acme-order-renew)
relay1: have xmb9mkd4… (gen-16)  want 8mfqxwb0…   carries 2   running (0 failed)
```

Dry-build: web2 143/75/165.2M (identical), relay1 53/1/0.4K (was 50/0 —
+3 drv from kin bump, 1 new fetch). Bisect 671f35b..e3c1cea: 94dd7b4
(kin 65eccea0→0bfa6d35 + iets/nix-skills/llm-agents + gen regen) is the
only closure-affecting commit for both — 22bbd1c hm bump verified
NEUTRAL (relay1 8mfqxwb0, web2 y6amiis8 eval-identical at 94dd7b4 and
e3c1cea; servers have no home-manager). Uptime web2 18d9h, relay1 18d7h
(no reboot). acme last-fire Apr-26 02:26 (same failure already known
from e960caf, no new fire), next-fire Apr-27 02:26 ~8h away.

### deploy attempt @ fc1c14d (2026-04-26, human-instructed)

**FAILED then ROLLED BACK** — `kin deploy relay1 web2` hit
switchInhibitor (dbus→broker), retried `--action boot` + reboot per
upstream guidance. relay1 went dark ~25min: limine 11.4.0 limlz BIOS
decompressor bug (upstream-fixed 11.4.1, see
backlog/bug-limine-11.4.0-bios-boot.md). Recovered via Hetzner rescue +
gen-16 chroot bootloader reinstall. web2 boot rolled back to gen-25
before reboot. **Both back on Apr-24 gens, carries-2 unchanged.**
relay1 uptime reset; web2 18d13h unchanged. **Deploy BLOCKED on
bug-limine-11.4.0-bios-boot.**

### drift @ 23975b3 (2026-05-09)

**DRIFTED, deploy UNBLOCKED for web2; relay1 DOWN (non-NixOS).** First
drift round in 13 days. Limine hotfix (`modules/nixos/limine-hotfix.nix`
→ 11.4.1) landed at 2844219 — the BIOS-brick blocker is cleared. web2
declared moved 3 more steps; **carries 2→5**. relay1 is no longer
running NixOS (Hetzner rescue / reinstalled — see
`ops-relay1-recover.md`). Reconcile: `kin deploy web2`, then recover
relay1 (`ops-relay1-recover.md`) before `kin deploy relay1`.

```
web2:   have c27fxv31… (gen-25, Apr-24)  want vnpjyvr1…   carries 5   degraded (acme)  31d6h
relay1: have ???      (Ubuntu OpenSSH 8.9p1, raw host key — not NixOS)   want psah9s86…
```

Bisect 872a798..23975b3 for web2, 3 new closure-affecting commits (on
top of f5bd72e + 94dd7b4 carried from e3c1cea):

| commit | toplevel | what | scope |
|---|---|---|---|
| 1f0c8c4 | y6amiis8→zqd3917b | `services.ietsd` stage-1 coexist on web2 (alt-socket, takeover=false) | web2 |
| 2844219 | zqd3917b→1b1z88kr | limine pinned 11.4.1 (`modules/nixos/limine-hotfix.nix`) | relay1 + web2 |
| 2313ae2 | 1b1z88kr→vnpjyvr1 | NVIDIA NIM adapter (nv1 service) — **fleet-wide** via `gen/_policy/_shared/export.cedar` + `gen/manifest.lock` | all |

NEUTRAL for web2 (eval-identical at neighbours): 7bdd14f, 052a455,
7790634 (vfio/deepfilter/ask-cuda — nv1-only); aa07e81, 35b6f06,
e9785c7 (deepfilter-pw1.6 / llm-router — nv1-only, on parallel branches
that merged after 2844219); 3a81166, 3541c2a, 23975b3 (deepfilter
removal / gsnap heredoc / distro input — verified vnpjyvr1 unchanged).

Dry-build web2 161/57/149.9M (was 143/75/165.2M @ e3c1cea), relay1
69/4/2.7M, nv1 563/1286/4.9G — **3/3 dry-build pass**.

acme-order-renew-gts.zimbatm.com fired Sat 2026-05-09 02:26:06,
`ExecMainStatus=1` — **still failing, 13 days running**. Daily fire,
daily fail, zero network bytes. Cert pressure increasing — see
`ops-web2-acme-renew.md`. The `kin deploy web2` (gen with limine fix +
ietsd) is the next thing to try since the root cause was never journaled.

Externals stale (filed `bump-nixpkgs.md`): nixpkgs 16d, srvos 15d,
nixos-hardware 15d, nix-index-database 13d, home-manager 12d, nixvim
12d — all upstream MOVED (ls-remote verified).

### drift @ dde1472 (2026-05-09, same day as 23975b3 entry)

**carries 5→6.** Single closure-affecting commit since 23975b3:
a06dd70 (merge of 4b5ca4e) `nix flake update nixpkgs` 0726a0ec→549bd84d
(2026-04-22→2026-05-05, flake.lock only). Want vnpjyvr1→cqs9rgp0
(`26.05.20260418.b12141e` → `26.05.20260505.549bd84`). Have unchanged
c27fxv31 (gen-25, Apr-24). NEUTRAL: 1c08114 (packages/ask-cuda
--structured-think — not in any host closure, verified `grep -rn
ask-cuda machines/ modules/ kin.nix gen/` empty).

```
web2:   have c27fxv31… (gen-25, Apr-24)  want cqs9rgp0…   carries 6   degraded (acme)  31d6h
relay1: have ???      (Ubuntu, not NixOS)                 want 712jwrfb…
```

acme-order-renew last fire Sat May-9 02:26:06 ExecMainStatus=1, next
Sun May-10 02:26 — same fire as 23975b3 entry, no NEW data. Dry-build
3/3: web2 175/67/291.9M, relay1 87/17/145.5M, nv1 591/1387/5.0G.
Reconcile unchanged: `kin deploy web2`, then recover relay1
(`ops-relay1-recover.md`).

### drift @ 1cb22af (2026-05-09, third drift round same day)

**carries 6→9.** r4 landed 3 closure-affecting commits for web2 on top
of dde1472. Have unchanged c27fxv31 (gen-25, Apr-24, `26.05.20260418.b121…`)
— uptime 31d7h, still degraded (acme + restic-backups-gotosocial).
Want 4xr21l3q→7562f0v1 (`26.05.20260505.549bd84` unchanged label,
closure moves under it). Reconcile unchanged: `kin deploy web2`, then
recover relay1 (`ops-relay1-recover.md`).

> Correction to prev entry: dde1472 want is `4xr21l3q…549bd84`
> (re-evaled fresh `git+file://?rev=dde1472`). Prev recorded
> `cqs9rgp0…` which does not reproduce — likely transcription error;
> 23975b3's `vnpjyvr1…0726a0e` does reproduce, carries-6 count holds.

Bisect 54b44f6..1cb22af, first-parent eval at each merge boundary:

| commit | toplevel | what | scope |
|---|---|---|---|
| 1b86152 | 4xr21l3q→8l4ay4513 | bump kin 0bfa6d35→303dcb2e (ecdc26f, flake.lock) | all |
| a1a5da4 | 8l4ay4513→l25z8f6x | bump internal kin/iets/nix-skills/llm-agents (flake.lock + gen regen) | all |
| 14e353b | l25z8f6x→7562f0v1 | adopt `services.llm-adapter` builtin, drop local module (ffb9aeb: kin.nix, gen/_policy/_shared/export.cedar, gen/manifest.lock, flake.nix -1 module) | all |

NEUTRAL for web2: 40d6053 (e4db263 nv1 vfio-comment drop —
machines/nv1 + packages/sel-act, not in web2 closure; eval at 1b86152
and a1a5da4 brackets the only delta to a1a5da4); 5101bc3 (backlog only);
2dad55f (eceb5e4 nixos-hardware bump — eval-identical 7562f0v1 at
14e353b and 2dad55f, servers do not import nixos-hardware); 1cb22af
(meta backlog only).

```
web2:   have c27fxv31… (gen-25, Apr-24)  want 7562f0v1…549bd84   carries 9   degraded   31d7h
relay1: have ???      (Ubuntu, not NixOS)                        want 8gk4aiq0…549bd84
nv1:    not-on-mesh                                              want h31nl66w…549bd84
```

Failed units on web2 now **2** (was 1):
`acme-order-renew-gts.zimbatm.com.service` (chronic, see
`ops-web2-acme-renew.md`) + **NEW** `restic-backups-gotosocial.service`
— first time restic appears in `kin status` failed column. Cannot pull
journal (root SSH denied to drift); add to the runtime-checks table
above when re-probing post-deploy.

Dry-build 3/3: web2 168/68/291.9M (was 175/67), relay1 80/18/145.5M
(was 87/17), nv1 589/1387/5.0G (was 591/1387). All gates pass.

Externals stale ≥7d (filed `bump-srvos.md`, oldest @ 15.5d): srvos
15.5d, nix-index-database 13.4d, home-manager 13.0d, nixvim 13.0d —
all upstream MOVED (ls-remote verified). nixpkgs 4.5d, nixos-hardware
2.3d both fresh post-r4.

### drift @ a73c579 (2026-05-09)

**carries 9→10.** One closure-affecting commit landed since 1cb22af:
bfbaf59 (`flake.lock: bump srvos 7ae6f09 → 6f237ae`, merged ea03541) —
srvos imported by both relay1 and web2 (`modules/nixos/common.nix`),
moved both servers' want; nv1 also moved (srvos in shared closure).
NEUTRAL: 6153e49, cb0b310, a73c579 (backlog only).

```
web2:   have c27fxv31… (gen-25, Apr-24)  want 5x19wq23…549bd84   carries 10  degraded   31d8h
relay1: have ???      (Ubuntu, not NixOS)                        want 8gk4aiq0…549bd84
nv1:    not-on-mesh                                              want h31nl66w…549bd84
```

Failed units on web2 still **2** (unchanged from 1cb22af): `acme-order-renew-gts.zimbatm.com.service`
last fire Sat May-9 02:26:06 ExecMainStatus=1, IP 0B in/out, CPU 44ms — same
early-exit signature, next Sun May-10 02:26 (see `ops-web2-acme-renew.md`);
`restic-backups-gotosocial.service` last fire Sat May-9 16:00:08
**ExecStartPre=1/FAILURE**, IP 8.4K in/out — pre-start is the failure
point with network traffic, so the SFTP leg to rsync.net was reached
(`gen.gotosocial-rsyncnet`, `modules/nixos/gotosocial.nix:23-29`):
likely repo-not-init, host-key, or `kin set` cred mismatch; hourly
timer next 17:00. Cannot pull journal (root SSH denied to drift).

Booted-system check: `/run/booted-system` →
`zmk2wdqzx19jpg8n6jwwhgjqmaqggs9d…26.05.20260405.68d8aa3` ≠
`/run/current-system` → `c27fxv31…26.05.20260418.b121…` — gen-25 was
switch-only (no reboot since gen ≤24). Carries-10 deploy is also a
kernel/initrd skip; consider scheduling a reboot.

Dry-build 3/3: web2 164/68/291.9M (was 168/68), relay1 80/18/145.5M
(unchanged), nv1 587/1385/5.0G (was 589/1387). All gates pass.

Externals stale ≥7d (3): nix-index-database 13.5d (b8eb7ace, upstream
dd2d0e3f), home-manager 13.0d (c55c498c, upstream fdb2ccba), nixvim
13.0d (d404af65, upstream 7986a276) — all upstream MOVED (ls-remote
verified). srvos 2d nixos-hardware 2d nixpkgs 4d fresh post-r6. Filed
`bump-nix-index-database.md`, `bump-home-manager.md`, `bump-nixvim.md`.

### drift @ 9def97e (2026-05-09)

**carries 10 holds — want UNCHANGED.** 4 closure-affecting commits
landed since a73c579 (a1a615b home-manager c55c498c→fdb2ccba, 318976e
nix-index-database b8eb7ace→dd2d0e3f, a3f8a1c afk-bench, 74d901a
llm-router) — re-evaled web2 toplevel at 9def97e: still
`5x19wq235j8dk6cn6gk9d1zgfnpqd2rh…549bd84`, identical to a73c579.
All 4 commits are nv1-only at the closure level: home-manager + nix-index-database
upstream moved no module web2 imports (`terminal` → `desktop` → nv1),
afk-bench/llm-router are `modules/home/desktop` + `packages/`. relay1
also unchanged (`8gk4aiq0…549bd84`). Only nv1 moved
(`h31nl66w` → `rsb8r0kg…549bd84`). NEUTRAL for web2: all 6 commits
since a73c579.

```
web2:   have c27fxv31… (gen-25, Apr-24)  want 5x19wq23…549bd84   carries 10  degraded   31d8h
relay1: FULLY DOWN (ICMP+TCP/22 dead)                            want 8gk4aiq0…549bd84
nv1:    not-on-mesh                                              want rsb8r0kg…549bd84
```

Failed units on web2 still **2**: `acme-order-renew-gts.zimbatm.com.service`
last fire Sat May-9 02:26:06 ExecMainStatus=1, next Sun May-10 02:26
(unchanged from a73c579 entry — same fire);
`restic-backups-gotosocial.service` last fire Sat May-9 17:00:02
Result=exit-code (one more hourly cycle since a73c579's 16:00:08 entry,
ExecStartPre still the failure point), next 18:00. Booted-system still
`zmk2wdqzx…20260405` ≠ current `c27fxv31…20260418` — no reboot.

Dry-build 3/3: web2 161/43/262.5M (was 164/68/291.9M — some deps
populated by intervening evals), relay1 80/18/145.5M (unchanged), nv1
565/1343/5.0G (was 587/1385). All gates pass.

Externals: only nixvim still stale at 13d (`bump-nixvim.md` already
filed @ a73c579, still actionable). home-manager 1d / nix-index-database
1d (both consumed @ r8). nixpkgs 4d, srvos 2d, nixos-hardware 2d fresh.
No new bump-* filed.

### drift @ cce49ee (2026-05-09, r10 follow-up)

**carries 10→13.** Three closure-affecting commits landed since 9def97e
on the web2 path. Have unchanged c27fxv31 (gen-25, Apr-24,
`26.05.20260418.b121…`) — uptime 31d9h, still degraded (acme + restic).
Want 5x19wq23→msim209r (`26.05.20260505.549bd84` label unchanged,
closure moves under it). Reconcile unchanged: `kin deploy web2`, then
recover relay1 (`ops-relay1-recover.md`).

Bisect 9def97e..cce49ee, first-parent eval at each merge boundary:

| commit | toplevel | what | scope |
|---|---|---|---|
| 0837c94 | 5x19wq23→fyvwhww1 | drop limine-hotfix (7dadd8c: rm `modules/nixos/limine-hotfix.nix`, web2/relay1 drop import; pkgs.limine 11.4.1-pin → 12.1.0) | relay1 + web2 |
| ad3ea1a | fyvwhww1→5v010f83 | bump internal kin/iets/nix-skills/llm-agents (flake.lock; iets in web2 closure via gotosocial+ietsd, NOT in relay1 — relay1 unchanged at this rev) | nv1 + web2 |
| a2759f9 | 5v010f83→msim209r | declare `builders.hcloud-07` (9bdf0a7: kin.nix, `gen/_policy/_shared/export.cedar` adds `Service::"builders"` permit, `gen/manifest.lock`) | all |

NEUTRAL for web2: 03bb206 (80ed9fb nixvim d404af65→7986a276 —
flake.lock only; `packages/nvim` is not in any host toplevel,
eval-identical fyvwhww1 at 0837c94 and 03bb206); 68b781a, 07c2219,
1ec97e3, 5f2e510, cce49ee (backlog only).

```
web2:   have c27fxv31… (gen-25, Apr-24)  want msim209r…549bd84   carries 13  degraded   31d9h
relay1: FULLY DOWN (ICMP 100% loss, TCP/22 timeout)              want dxirzajg…549bd84
nv1:    not-on-mesh                                              want 53s3xn5k…549bd84
```

Failed units on web2 still **2**:
`acme-order-renew-gts.zimbatm.com.service` last fire Sat May-9 02:26:06
ExecMainStatus=1 (same fire as 9def97e entry, no new data, next Sun
May-10 02:26 — see `ops-web2-acme-renew.md`);
`restic-backups-gotosocial.service` last fire Sat May-9 18:00:08
Result=exit-code, ExecStartPre status=1 (one more hourly cycle since
9def97e's 17:00:02; pre-start ran 18:00:06→18:00:08, 2s — still
SFTP/repo-init failure point), next 19:00. Booted-system still
`zmk2wdqzx…20260405` ≠ current `c27fxv31…20260418` — no reboot, gen-25
was switch-only.

Dry-build 3/3 PASS (exit 0). Externals all <7d (nixpkgs 4d,
home-manager 1d, srvos 2d, nixos-hardware 2d, nix-index-database 1d,
nixvim 4d post-r9 bump) — no new bump-* filed.

**a2759f9 surprise:** `gen/_policy/_shared/export.cedar` is shared
fleet policy; the new `Service::"builders"` permit moved every host's
toplevel even though `nix.buildMachines` only lands on nv1. Carries
count for web2/relay1 ticks up on a builder declared for a different
host — expected under shared-policy regen, but worth knowing the deploy
scope when reading the meta DEPLOY REMINDER (which only said "kin
deploy nv1").

### drift @ 80a9212 (2026-05-09, r13)

**carries 13 holds — want UNCHANGED.** One closure-affecting commit
since cce49ee (d62288d): `5a218c6` (merged `2f23dfe`)
`machines/nv1/configuration.nix` narrows `nix.settings.system-features`
to `kvm uid-range recursive-nix` (drop big-parallel/nixos-test/benchmark
so heavy drvs dispatch to hcloud-07). **nv1-only** — re-evaled web2 at
80a9212 → `msim209r…549bd84` identical to cce49ee; relay1
`dxirzajg…549bd84` identical. Have unchanged c27fxv31 (gen-25, Apr-24,
`26.05.20260418.b121…`) — uptime 31d10h, still degraded.

```
web2:   have c27fxv31… (gen-25, Apr-24)  want msim209r…549bd84   carries 13  degraded   31d10h
relay1: FULLY DOWN (ICMP 100% loss, TCP/22 timeout)              want dxirzajg…549bd84
nv1:    not-on-mesh                                              want isgj6yg9…549bd84  (was 53s3xn5k)
```

Failed units on web2 still **2**:
`acme-order-renew-gts.zimbatm.com.service` last fire Sat May-9 02:26:06
ExecMainStatus=1 (same fire as cce49ee entry, no new data, next Sun
May-10 02:26 — see `ops-web2-acme-renew.md`);
`restic-backups-gotosocial.service` last fire Sat May-9 19:00:06
Result=exit-code (one more hourly cycle since cce49ee's 18:00:08;
ExecMainStatus=0 — main never starts, still pre-start failure), next
20:00. Booted-system still `zmk2wdqzx…20260405` ≠ current
`c27fxv31…20260418` — no reboot, gen-25 was switch-only.

Dry-build 3/3 PASS: web2 141/32/118.0M (was 161/57/149.9M @ cce49ee —
intervening evals populated more deps), relay1 56/4/0.8K (was
69/4/2.7M), nv1 555/1331/4.8G (was 563/1286/4.9G). Externals all <7d
(nixpkgs 4.6d, hm 1.2d, srvos 2.7d, nixos-hw 2.4d, nix-index-db 1.3d,
nixvim 4.2d) — no new bump-* filed. Reconcile unchanged: `kin deploy
web2`, then recover relay1 (`ops-relay1-recover.md`).

### drift @ 6753fd8 (2026-05-09, r15)

**carries 13 holds — want UNCHANGED.** Two closure-affecting commits
since 80a9212 (38be12c): `b2d179c` (dictation vocab biasing) and
`f94448e` (sem-grep hybrid retrieval) — both touch
`packages/{ptt-dictate,sem-grep,transcribe-cpu,transcribe-npu}` pulled
only via `modules/home/desktop` (nv1). Re-evaled web2 at 6753fd8 →
`msim209r…549bd84` identical to 80a9212; relay1 `dxirzajg…549bd84`
identical. Have unchanged c27fxv31 (gen-25, Apr-24,
`26.05.20260418.b121…`) — uptime 31d10h, still degraded, booted
`zmk2wdqzx…20260405` ≠ current (no reboot since gen<=24).

```
web2:   have c27fxv31… (gen-25, Apr-24)  want msim209r…549bd84   carries 13  degraded   31d10h
relay1: FULLY DOWN (ICMP 100% loss, TCP/22 timeout)              want dxirzajg…549bd84
nv1:    not-on-mesh                                              want mbw1f3pr…549bd84  (was isgj6yg9)
```

Failed units on web2 still **2**:
`acme-order-renew-gts.zimbatm.com.service` last fire Sat May-9 02:26:06
status=1 (same fire as 80a9212 entry, 17h ago, next Sun May-10 02:26 —
see `ops-web2-acme-renew.md`); `restic-backups-gotosocial.service`
last fire Sat May-9 19:00:08 ExecStartPre=1 (one more hourly cycle since
80a9212's 19:00:06; main never starts), next 20:00.

Dry-build 3/3 PASS: web2 141/32/118.0M (unchanged @ 80a9212), relay1
56/4/0.8K (unchanged), nv1 542/1279/4.4G (was 555/1331/4.8G — fetches
landed). Externals all <7d (nixpkgs 4.7d, hm 1.3d, srvos 2.7d, nixos-hw
2.5d, nix-index-db 1.3d, nixvim 4.2d) — no new bump-* filed. Reconcile
unchanged: `kin deploy web2`, then recover relay1
(`ops-relay1-recover.md`).

## append @ relay1 retired (2026-05-09)

relay1 decommissioned (Jonas; iroh underused) — removed from `kin.nix`,
`machines/`, `gen/`, `keys/`. The "recover relay1" half of the
reconcile is moot; `ops-relay1-recover.md` deleted. Reconcile is now
just `kin deploy web2`. relay1 history above retained for the record.

### drift @ 87a370f (2026-05-10) — web2 RECONVERGED gen-26

**web2 deployed and rebooted.** Human-deployed gen-26 May-9 ~20:44
(profile linked 20:44, `system→26-link` flipped 20:59, host rebooted
~21:06 per `up 11:07` at 08:13 probe). Booted system == current system
== want at origin/main HEAD (87a370f, last 2 commits backlog-only):

```
web2:  have kjiq55xlnipwssavflkz9isq3zhxwpgq…549bd84 (gen-26, May-9)
       want kjiq55xlnipwssavflkz9isq3zhxwpgq…549bd84 (87a370f)
       carries 0 — CONVERGED
nv1:   not-on-mesh                                  want mmr7zsqbsx…549bd84
```

13 carries flushed in one deploy. Dry-build web2 0/0/0 (already in
local store). nv1 dry-build 486 drvs / 1245 fetch / 4.3 GiB (was
542/1279/4.4G — fetches landed).

Failed units **2 → 1**:

- `acme-order-renew-gts.zimbatm.com.service` — **FIXED.** Fired
  post-deploy May-9 21:05 and May-10 07:02, both `status=0/SUCCESS`;
  cert valid until 2026-07-07. Root cause never confirmed (deploy +
  reboot cleared whatever broke pre-start), but the falsifier passed.
  `ops-web2-acme-renew.md` DELETED this round.
- `restic-backups-gotosocial.service` — **still failing**, hourly,
  every cycle in journal window. Survived gen-26 deploy + reboot, so
  it's not a config-staleness issue. Pre-start dies on
  `Fatal: unable to open repository at sftp:zh6422@zh6422.rsync.net:gotosocial:
  unable to start the sftp session, error: error receiving version
  packet from server: server unexpectedly closed connection: unexpected
  EOF` — sshpass auth to rsync.net is being rejected (server closes
  before SFTP negotiates). Filed `ops-web2-restic-rsyncnet.md`.

Spot-checks (re-probed @ gen-26): /48 route PASS, ca-derivations PASS,
cache.assise PASS, `@cert-authority` 1 entry, **ietsd ACTIVE +
`/nix/var/iets/daemon-socket/socket` present** (rollout-stage-1 from
`services.ietsd.on=[web2]` is live — first probe since the option
landed). attest identity unverified (non-root).

Externals all <7d (nixpkgs 5.1d, hm 1.8d, srvos 3.2d, nixos-hw 3.0d,
nix-index-db 1.8d, nixvim 4.7d) — no new bump-* filed.

Reconcile remaining: `kin deploy nv1` (mesh access required).
