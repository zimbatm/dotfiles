# ops: ietsd coexist soak on web2 — run the alt-socket round-trip falsifier

**needs-human** — runs a build against a live machine's daemon socket.

## what

`kin.nix:103-105` says: *"web2 starts here as the always-on box. Widen to
nv1 once a routine `nix-build -A hello` via the alt socket round-trips
clean."* That gate has been a comment, not a backlog item, since the
ietsd-coexist deploy. Run it.

## why

`services.ietsd.on = ["web2"]` with `takeover = false` has been deployed
for weeks. Coexist mode is the safe-by-design tier: ietsd listens on its
own socket, stock `nix-daemon` is untouched, the blast radius of a
failure is "one opt-in build went weird." The falsifier proves ietsd
answers the worker protocol correctly against a real store on a real
machine — protocol 1.39, drvPath byte-exact, FramedSource — the things
the README claims that the cross-test matrix verifies in CI but the
dogfood has never confirmed.

This is the **only gate** between the current state and `services.ietsd.on
= ["web2" "nv1"]`, which is itself the only gate between the current state
and Track B B0 (LAN substitution from nv1).

## steps (on web2)

1. Find the alt socket: `systemctl show ietsd -p Listen` or check
   `services.ietsd` module output for the socket path. Default per
   `iets.nixosModules.ietsd` is a non-default path so it doesn't shadow
   `/nix/var/nix/daemon-socket/socket` in coexist mode.

2. Round-trip a build:
   ```sh
   NIX_REMOTE="unix://<alt-socket-path>" nix-build '<nixpkgs>' -A hello --no-out-link
   ```

3. Verify the output is byte-identical to a stock-daemon build:
   ```sh
   diff <(NIX_REMOTE="unix://<alt-socket-path>" nix-build '<nixpkgs>' -A hello --no-out-link) \
        <(nix-build '<nixpkgs>' -A hello --no-out-link)
   ```
   Both should print the same `/nix/store/...` path (substitution; CA
   means same input → same path regardless of which daemon answered).

4. Check nothing fell over: `systemctl status ietsd`, `journalctl -u
   ietsd --since '10 minutes ago' | grep -iE 'panic|error|warn' || echo clean`.

## falsifies

- Pass: step 2 produces a `/nix/store/...` path; step 3 diff is empty;
  step 4 shows no panics. **Then:** widen `services.ietsd.on` to include
  nv1 (`takeover = false`), `kin deploy nv1`, file the same soak for nv1.
- Fail at step 2: protocol mismatch or build error → `../iets/backlog/
  bug-ietsd-coexist-<symptom>.md` (self-contained: socket path, NIX_REMOTE
  string, error output, `iets --version`).
- Fail at step 3: divergence is a serious finding — ietsd produced a
  different path for the same drv → `../iets/backlog/bug-ietsd-drvpath-
  divergence.md` with both paths and `nix derivation show` for each.
- Fail at step 4: panic in coexist mode → `../iets/backlog/bug-ietsd-
  panic-<symptom>.md` with the journal excerpt.

## not the takeover gate

Passing this means ietsd is safe to *run* on nv1 in coexist mode. It does
**not** mean ietsd is ready to *replace* the stock daemon (`takeover =
true`). Takeover is a separate gate with a separate falsifier (weeks of
real workload, panic-recovery story, watchdog) and a separate backlog
item. Don't conflate them — coexist is low-risk by design and conflating
the bars is how nv1 never gets ietsd at all.
