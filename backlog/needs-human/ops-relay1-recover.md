# ops: relay1 not running NixOS — Hetzner recovery needed

**needs-human** — Hetzner Cloud console + reinstall/recover. drift can
only probe; the recovery path is the same one walked Apr-26.

## What

relay1 (95.216.188.155) answers TCP/22 with
`SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.13` and a **raw ed25519 host
key** (not a kin-CA-signed cert). The host is **not booted into NixOS
gen-16** — it is in Hetzner rescue mode or has been reinstalled. As a
result:

- `kin status relay1` → unreachable (kin-bir7vyhu cert rejected:
  `Permission denied (publickey,password)`).
- `kin status nv1` → not-on-mesh (nv1's mesh ProxyJump goes through
  `root@95.216.188.155`, dead now).
- The maille relay role for the fleet is down.

ICMP works (114ms RTT), so the IP is live — just the wrong OS.

## Why this happened (most likely)

relay1's deployed gen-16 (`xmb9mkd4…`) still has **limine 11.4.0**,
which has the limlz BIOS decompressor bug that bricked relay1 on the
Apr-26 deploy attempt (see `ops-deploy-web2.md`, "deploy attempt @
fc1c14d"). That recovery used Hetzner rescue + chroot bootloader
reinstall and got it booting again — but the on-disk bootloader was
never replaced with 11.4.1. The fix (`modules/nixos/limine-hotfix.nix`,
landed 2844219) was committed but never deployed because the deploy was
rolled back. So **any reboot of relay1 since Apr-26** (Hetzner host
maintenance, kernel panic, manual reboot) would re-hit the same boot
failure → land in rescue.

Last known good: drift @ 8231b3d (2026-04-26) saw relay1 running gen-16,
0 failed units. uptime had reset that day from the rescue. Sometime
between then and 2026-05-09 it went down.

## How to recover

1. Hetzner Cloud console → check whether 95.216.188.155 is the same
   server (server ID matches relay1) or the IP got reassigned.
2. If rescue mode: same recipe as Apr-26 — mount `/dev/sda*`, chroot,
   `nixos-enter --root /mnt -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot`
   to reinstall the bootloader from gen-16, reboot. **This still leaves
   limine 11.4.0 on disk** — the host will brick again on next reboot
   unless step 3 follows immediately.
3. Once SSH-reachable, `kin deploy relay1` from origin/main (carries
   the limine-hotfix → 11.4.1, no longer brickable on BIOS boot).
   Confirm `gen/identity/ca/_shared/known_hosts` SSH path survives per
   `../kin/docs/howto/lockout-recovery.md` first.
4. If the disk is gone / reinstalled: full `kin install relay1`
   (nixos-anywhere or equivalent).

## How much

15–60 min depending on whether step 2 or step 4. Blocks: nv1 mesh
reachability, fleet relay, ops-deploy-nv1.

## Blockers

Hetzner Cloud account access. drift cannot auth (no cert-signed host
key, no rescue root password).

## drift append-log

### drift @ 23975b3 (2026-05-09)

First detection. ICMP up, SSH banner Ubuntu 8.9p1, raw host key
`AAAAC3NzaC1lZDI1NTE5AAAAIJD2h2Q299AeBB23AO/DuQcAiLpuuZ+kdTRpDDPfLXUW`
(record this — if it changes again the box was touched). web2 (same
fleet, same IP block) still up 31d → not a network-wide Hetzner event.

### drift @ a73c579 (2026-05-09)

**State change: now FULLY DOWN.** ICMP 100% loss (was 114ms RTT),
TCP/22 connection-timeout (was Ubuntu OpenSSH 8.9p1 banner). The host
that answered as Ubuntu rescue at the 23975b3 probe is now not
reachable at all from this homespace. web2 (same Hetzner Helsinki) is
up 31d8h, so not a region-wide outage — relay1 went from rescue-mode to
powered-off / reinstalling / network-detached. Step 1 (Hetzner console
existence check) is now load-bearing before anything else.

want unchanged: `8gk4aiq0…549bd84` (eval @ a73c579, dry-build
80/18/145.5M passes). nv1 still not-on-mesh transitively (proxy through
this dead IP).

### drift @ 9def97e (2026-05-09)

Still **FULLY DOWN** — re-probed: ICMP 2/2 packets lost (100%), TCP/22
connection-timeout. No change from a73c579. web2 (same Hetzner
Helsinki, 89.167.46.118) up 31d8h. want unchanged `8gk4aiq0…549bd84`
(re-evaled @ 9def97e — none of the 6 commits since a73c579 moved
relay1's closure). Dry-build 80/18/145.5M unchanged.
