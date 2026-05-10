# feat: enable ietsd LAN-peer discovery (B0 falsifier setup)

Filed by meta dispatcher, 2026-05-10. Track B0 (`../meta/next.md`).

## what

`kin.nix` currently runs `ietsd` only on web2, stage-1 canary
(`takeover = false`, alt socket, soak-gated before widening — comment at
`kin.nix:100`). It does not set `services.ietsd.discoverLan`. The B0
falsifier needs two `ietsd` instances on the same LAN segment that can
discover each other over `_iets_castore._tcp` mDNS.

The home slice:

1. Pass the existing stage-1 soak gate: confirm a routine
   `nix-build -A hello` via web2's alt socket round-trips clean, then
   widen `services.ietsd.on` to include `nv1` (per the comment in
   `kin.nix`).
2. Set `services.ietsd.discoverLan = true` on the LAN-segment machines.
   This is per-machine, not global — `discoverLan` opens 5353/udp; only
   set it where machines actually share a link (kin's option doc is
   explicit that cloud boxes shouldn't speak mDNS).
3. ~~Identify the **second** machine that shares nv1's LAN segment.~~
   **Done — finding (grind, 2026-05-10): there is no LAN peer.** web2
   is a Hetzner cloud box (`machines/web2/configuration.nix:16`, "IPv4
   via DHCP, IPv6 via hetzner-ipv6.service"); nv1 is a desktop. They
   are not co-located and never share a link-local segment. Recorded
   in `../meta/next.md` Track B0. Per the kin option doc warning, do
   **not** set `discoverLan` on web2 — cloud boxes shouldn't speak mDNS.
4. `kin deploy` both, run the B0 falsifier (below).

## why

ADR-0009's first tier (peer substitution) has all code-gates landed
upstream — iets@b5e3c549ef (LAN-first prepend), iets@cdec56782c
(`substitute_rev2` in production fetch path), kin@bc1fed10
(`services.ietsd.discoverLan`). home is the dogfood; the falsifier
hasn't run because no home machine declares any of it. If the dogfood
laptop doesn't fetch from LAN peers, nothing past it will.

## how-much

S for the config edit (one `discoverLan = true` line per LAN machine,
one widen of `on`). Deploy + falsifier run is human-gated — same shape
as `needs-human/ops-builders-key-drop.md`.

## blockers

- **iets-side advertise gap.** `ietsd --discover-mdns` is browse-only:
  it finds `castored` peers but does not announce itself
  (`kin/services/ietsd.nix:60` comment). Two `ietsd`-only machines
  cannot discover each other today. Filed
  `../iets/backlog/feat-ietsd-advertise-mdns.md`. Until that lands (or
  the design answer is "co-locate `castored`"), this item can declare
  the config but the falsifier is **not runnable**.
- **No LAN peer in the home fleet (grind finding, 2026-05-10).** The
  fleet is nv1 (desktop) + web2 (Hetzner cloud,
  `machines/web2/configuration.nix:16`). They do not share a LAN
  segment, and web2 must not speak mDNS (kin option doc). The B0
  falsifier needs a second physical machine on nv1's link — that
  machine does not exist. Blocked on **hardware**, not config. Do not
  fake it with a VM/container peer (loopback mDNS proves nothing about
  the real LAN-fallthrough path the falsifier measures). Recorded in
  `../meta/next.md` Track B0.
- **Pinned kin lacks `services.ietsd.discoverLan` (grind finding,
  2026-05-10).** `flake.lock` pins kin@912aad5c (2026-05-09 17:56Z);
  `discoverLan` landed kin@bc1fed10 (2026-05-10 03:27Z), which is
  **not an ancestor** of the pin (`git merge-base --is-ancestor`
  fails). Even the no-op config declaration cannot be written until a
  bump-kin to ≥ bc1fed10 lands here. That bump is the bumper
  specialist's call (one input per round, oldest-first), not this
  item's.
- Stage-1 soak gate (`kin.nix:100` comment): widen to nv1 only after
  web2's alt-socket soak round-trips clean.
- Human-gated: `kin deploy nv1` + `kin deploy <peer>` + falsifier run.
  Move to `needs-human/` once the config edit is in.

## status (grind, 2026-05-10)

Moved to `needs-human/`. Every remaining blocker is outside grind's
reach: the LAN-peer gap needs a hardware decision (add a second
machine on nv1's LAN, or accept B0 is unfalsifiable on this fleet),
the advertise gap is upstream iets work, the kin pin is the bumper's
queue, and the deploy + falsifier run is human-gated. Nothing left
for an autonomous round to do here.

## falsifies

B0 falsifier from `../meta/next.md` Track B:

> Two machines on the same LAN segment, both running ietsd; machine A
> `nix build`s a CA path; machine B `nix build`s the same closure →
> `ietsd substitute-proxy` log on B shows the path fetched from A's
> `_iets_castore._tcp`-discovered address, not from any configured
> substituter or the internet. Disconnect A → B falls through to the
> next tier in <100ms.

Pass: both clauses observed. Fail (config): `discoverLan` is on but
neither machine appears in the other's discovered-peer list — that's the
advertise gap, not a home bug. Fail (substitution): peer is discovered
but the NAR comes from the internet anyway — that's an iets fetch-path
bug, file there. Either failure is a finding, not a no-op.
