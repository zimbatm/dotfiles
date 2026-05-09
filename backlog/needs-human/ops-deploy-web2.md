# web2: post-deploy runtime checks (CONVERGED gen-25; relay1 gen-16)

**What:** Walk the remaining runtime checks below on web2, then delete
this file. Deploy itself is **done** — web2 + relay1 both human-deployed
Apr-24 20:06 batch @ fcc6b68-tip and CONVERGED.

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
