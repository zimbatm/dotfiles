# adopt: AFK bench lane — run the stuck local-inference benches when nv1 is idle

## What

A user systemd timer + small wrapper (`packages/afk-bench/`) that
drains nv1's queue of "needs hardware, needs a human" benches
opportunistically when the machine is unattended.

Logic, every ~30 min:

1. `now-context | jq .afk` — if `false`, exit 0. Jonas is at the
   keyboard; the Arc/NPU are his.
2. Check `infer-queue status` — if any `arc`/`npu` lane job is running
   or queued, exit 0. Don't pile benches on top of real work.
3. Pick the *oldest-stale* bench from a small manifest
   (`packages/afk-bench/benches.json`, one line per script: path, lane,
   max-wall, last-run). Candidates already in-tree:
   - `packages/ask-local/bench.sh` (arc)
   - `packages/ask-local/bench-diff-gate.sh` (arc)
   - `packages/ask-local/bench-agent.jsonl` runner (arc)
   - `packages/ask-cuda/bench-structured-cot.sh` (cuda, dGPU — only if
     vfio not bound)
   - `packages/sem-grep/bench-refs.txt` runner (npu)
   - `tests/bench-dictate.sh` (cpu/npu/arc; the `parakeet-cpu-lane`
     follow-up)
4. Submit it via `infer-queue add --lane <lane>` with a `timeout` wrap
   (kill at `max-wall`, default 10 min — benches should be bounded).
5. Append the result line to
   `$XDG_STATE_HOME/afk-bench/results.jsonl` (`{ts, bench, wall,
   verdict, raw_path}`) and update `last-run` in the manifest.
6. **Stop early on un-AFK**: a `now-context` poll inside the wrapper,
   every 60s, sends `infer-queue` a kill if `.afk` flips to `false`
   mid-bench. Yielding the device is the whole point.

No daemon. No new package input. The pieces already exist:
`now-context` for AFK, `infer-queue` for device-tagged queueing with
1-slot accelerator lanes, and the benches themselves were each landed
by a prior grind round and then parked behind "needs nv1 hardware".

## Why

Seed: `gnhf` (kunchenguid/gnhf, new in `llm-agents.nix`) — a
"Ralph/autoresearch-style orchestrator that keeps coding agents running
while you sleep." Same family as `gastown`, `auto-claude`, `ralph-tui`:
orchestrate *cloud* agents through the night.

Our angle: nv1 doesn't have an idle-cloud-agent problem (grind already
runs unattended on a separate box). It has an **idle-hardware** problem.
Five benches have landed in `packages/` over the last ~10 grind rounds
and every one of them is parked in `needs-human/` with the same gate:
"needs nv1 hardware, DO NOT run from an agent." The hardware sits in a
backpack 16 h/day and on a desk asleep the other 8. The benches are
the falsification harness for the LLM-future testbed — they decide
which of `parakeet-cpu-lane`, `structured-cot`, `diff-gate`,
`sem-grep refs`, `model-warm` actually earn their place — and right now
they accumulate without ever producing the numbers that would let us
delete or promote anything. `gnhf`'s insight (idle wall-clock is the
cheapest compute there is) applies; the workload doesn't.

This is also the better split of the two "needs human" sub-gates that
keep getting conflated: *measuring* needs the hardware, *interpreting*
needs Jonas. AFK-bench unblocks the first without pretending to do the
second — `results.jsonl` accumulates and the human reads it on their
schedule, instead of the human having to be present for the run.

## How much

~0.4r. `writeShellApplication` ~70L + `benches.json` manifest +
`systemd.user.timers.afk-bench` + `.services.afk-bench` in
`modules/home/desktop/` (or a new `modules/home/afk-bench.nix` —
simplifier's call). One `flake.nix` module-list entry if it's a new
file. Zero new inputs, zero new pkgs.

## Falsifies

Two things, in order:

1. **Are unattended Arc/NPU bench numbers stable enough to compare?**
   The `needs-human` framing has assumed yes. `bench.sh`-style scripts
   measure wall-clock and tok/s; an AFK desktop has DPMS off, P-state
   governor in powersave, no foreground compositor pressure. Run the
   same bench 3× across 3 AFK windows. If σ/μ of wall-clock > 20%, the
   AFK window isn't a controlled bench environment and the items stay
   needs-human (this lane becomes "smoke-test only, not a number
   source"). If ≤ 20%, the lane is a real measurement instrument.
2. **Does the early-stop actually yield?** Synthetic test: submit a
   600s bench, simulate un-AFK (`aw-client heartbeat`), confirm
   `infer-queue` kills the job within 90s and `ptt-dictate` latency is
   unaffected. If it doesn't yield cleanly, the lane is a daily-driver
   regression and gets reverted — the testbed serving the user, not the
   other way round, is a hard constraint.

## Blockers

Like everything in this family: the *code* lands in a grind round
(pure `packages/` + `modules/home/`, eval+dry-build gated). The
*activation* and the σ/μ check need `kin deploy nv1`, which is
human-gated. File the activation step into `needs-human/` after merge,
same pattern as `ops-gsnap-baseline.md`. Note one ordering dependency:
this should land *after* `adopt-llm-router-model-warm` if both are
picked up, so the benches it queues exercise the model-swap path
rather than racing a stale single-model `:8088`.
