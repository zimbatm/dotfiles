# feat: dogfood lockring as nv1's ssh-agent — one week, one rollback line

## What

Declare `services.lockring = { on = ["nv1"]; sshAgent = true; };` in
`home/kin.nix`, dry-run the Cedar policy against the real ssh callers,
flip `$SSH_AUTH_SOCK` to lockring's socket, run one week of normal use.

This is a **falsification test**, not a deploy. lockring is pre-alpha;
19 rounds of adversarial review found the bugs the model could imagine,
the dogfood finds the ones it can't.

## Procedure (in order — do not skip the dry-run)

1. `home/kin.nix`: add `services.lockring = { on = ["nv1"]; sshAgent = true; };`
   (default `policyFile` from the kin wrapper = lockring's
   `examples/policy.cedar`). `kin gen`, `kin deploy nv1`.
2. **Policy dry-run before flipping.** For every ssh caller actually
   used on nv1 — terminal `ssh`, `git push` over ssh, `kin deploy`,
   `iroh-ssh` — run:
   `lockring policy check --as-caller <path-to-binary> --purpose ssh_auth`.
   Anything that returns `Deny` is a policy bug. Fix the policy in
   `home/` (or upstream in lockring's example) before going live.
3. Flip: `export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/lockring/ssh-agent.sock"`
   in the shell init (the exact path comes from the lockring module —
   verify against `modules/nixos/lockring.nix`).
4. Keep the escape hatches visible:
   - YubiKey directly via `ssh -i` works regardless.
   - `gpg-agent` fallback unchanged.
   - Reverting is one line: unset/restore `$SSH_AUTH_SOCK`.
5. Run a week. `lockring audit tail` should be readable; `lockring audit
   verify` should exit 0.

## Why

Track L (`meta/next.md`). lockring just shipped its deploy artifact;
it's never carried a real key. nv1's ssh-agent is the smallest real
workload that exercises the whole path (caller ID → Cedar policy →
sign → audit) under daily load with a one-line rollback.

Strategic side effect: resolves T21 (lockring vs tng-broker) toward
"compose, don't replace" — lockring on the host doing UDS+`SO_PEERCRED`
is what tng-broker structurally can't do over `AF_VSOCK`.

## How much

Small. One `kin.nix` line + a checklist run. Deploy is the gating
human action. The week of use is calendar time, not effort.

## Blockers

- ~~Hard gate: `../kin/backlog/feat-services-lockring.md` (the kin
  wrapper). File this only after that ships.~~
  **CLEARED r10** — kin pin `fb13c282` (this round's bump) includes
  `services/lockring.nix` (`d21658e7`).
- ~~New gate: home needs `inputs.lockring` + mkFleet `extraInputs` wiring
  before `services.lockring` can be declared (kin module throws on
  build otherwise). Lock-touching ⇒ split out to
  `backlog/bump-lockring-input.md` (filed r10).~~
  **CLEARED r11** — `bump-lockring-input` landed: `inputs.lockring`
  (pin `f999b8da`), `mkFleet { extraInputs = { inherit (inputs) lockring; }; }`,
  `services.lockring = { on = ["nv1"]; sshAgent = true; };`. Both hosts
  eval + dry-build. Only the deploy + week-of-use stay here.
- Human-gated: `kin deploy nv1` and the env-var flip need Jonas. After
  the wrapper lands, retag this `ops-` or move to `needs-human/`.

## Falsifies

Seven days of normal ssh on nv1 with `$SSH_AUTH_SOCK` → lockring.

**Pass:** `lockring audit verify` exits 0 (chain intact); every `Sign`
row in `lockring audit tail` maps to an ssh Jonas ran; zero unexpected
`Deny`; zero panics. lockring graduates from pre-alpha for *this*
surface.

**Fail:** any locked-out moment, any unexplained audit row, any panic.
File `../lockring/backlog/{sec,bug}-*.md` with the real-world repro.
**Either result is a finding.**

Do not let this borrow confidence forward: passing L2 does **not**
unlock L3 (system-scope / sops-nix replacement) by itself — that's a
kin-side ADR-shaped decision, taken on the L2 evidence, not on momentum.
