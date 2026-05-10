# ops: ietsd coexist soak on nv1 — alt-socket round-trip on a desktop

**needs-human** — runs a build against the desktop's daemon socket; can't
verify visually-degraded local dev without someone at the keyboard.

## what

`services.ietsd.on` was widened to `["web2" "nv1"]` after the web2
alt-socket round-trip passed (2026-05-10, `ops-ietsd-soak-web2.md`).
Same falsifier on the other surface: a desktop with home-manager,
`nix shell`/direnv churn, and a much spikier build pattern than the
always-on server.

## why

web2 is the safe-by-design canary — server, no interactive use, the
worst case is "one cron build went weird." nv1 is the opposite: it's
where a coexist-mode panic interrupts real work. The web2 pass proves
the protocol works on the simplest workload; the nv1 soak proves it
doesn't degrade the daily-driver. Different bars, same falsifier.

## steps (on nv1, after `kin deploy nv1`)

1. Confirm the alt socket exists and ietsd is up:
   ```sh
   systemctl is-active ietsd.service ietsd.socket
   ls -la /nix/var/iets/daemon-socket/socket
   ```

2. Round-trip + diff against the stock daemon:
   ```sh
   ALT="unix:///nix/var/iets/daemon-socket/socket"
   diff <(NIX_REMOTE="$ALT" nix-build '<nixpkgs>' -A hello --no-out-link) \
        <(nix-build '<nixpkgs>' -A hello --no-out-link)
   ```
   Empty diff = pass.

3. Soak with `NIX_REMOTE=$ALT` for a normal session — direnv reload, a
   `nix develop`, a `nix build` of something non-trivial (the home
   flake's devshell is a good target). Note any latency delta or build
   weirdness.

4. `journalctl -u ietsd | grep -iE 'panic|error'` should be empty.

## falsifies

- Pass: step 2 diff empty, step 3 unremarkable, step 4 clean. **Then:**
  the home fleet matches kin-infra at stage-1 across all
  interactive+server surfaces. File `ops-ietsd-stage2-takeover.md` only
  if/when there's appetite for `takeover = true` on a canary — that's a
  much higher bar (panic recovery, watchdog, fallback-to-cppnix story).
- Fail at step 2: cross-file `../iets/backlog/bug-ietsd-coexist-nv1-<symptom>.md`.
- Fail at step 3: same, with the workload + latency numbers.
- Fail at step 4: `../iets/backlog/bug-ietsd-panic-<symptom>.md` with the
  journal excerpt.

## not the takeover gate

Same caveat as web2: passing this means coexist mode is safe on a
desktop. It does **not** mean `takeover = true`. Don't conflate.

## append @ 2026-05-10: round-trip verified over SSH, soak still pending

Steps 1-2-4 verified from the homespace via SSH:
- ietsd.service + ietsd.socket active
- `nix-build '<nixpkgs>' -A hello` via `unix:///nix/var/iets/daemon-socket/socket`
  == stock daemon: `/nix/store/3pcn0adm…-hello-2.12.3` IDENTICAL
- journal clean (no panics/errors)

**Step 3 (the soak) still needs a human at the desk** — `NIX_REMOTE=$ALT`
for a normal session, watching for latency/weirdness on direnv reload,
`nix develop`, and a non-trivial build. That's a quality judgment about
the daily-driver, not a protocol check.
