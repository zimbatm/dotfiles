# ops: activate afk-bench on nv1 + check unattended bench stability

**needs-human** — `kin deploy nv1` is human-gated; the σ/μ check needs an
unlocked graphical session and the Arc/NPU nodes.

## What

After the next `kin deploy nv1` pulls in `afk-bench`:

1. Confirm the timer armed:

   ```sh
   systemctl --user list-timers afk-bench
   journalctl --user -u afk-bench -n 50
   ```

   The service is gated on `ConditionPathExists=/dev/accel/accel0` and on
   `now-context` reporting `.afk == true`, so the first useful run is the
   first time the desktop actually goes idle.

2. Stability check (the falsification gate from
   `backlog/adopt-afk-bench-lane.md`): let the timer run the same bench
   3× across 3 separate AFK windows, then compute σ/μ of `wall_s`:

   ```sh
   jq -s 'group_by(.bench)
          | map({bench:.[0].bench, n:length,
                 mu:(map(.wall_s)|add/length),
                 sigma:((map(.wall_s) as $w | ($w|add/length) as $m
                        | ($w|map((.-$m)*(.-$m))|add/length)|sqrt))})
          | map(.cv = (if .mu>0 then .sigma/.mu else null end))' \
     ~/.local/state/afk-bench/results.jsonl
   ```

   - `cv ≤ 0.20` → AFK windows are a usable measurement instrument.
     Promote: the parked benches in `needs-human/` that only need
     hardware (not interpretation) can move to "drained by afk-bench."
   - `cv > 0.20` → an unattended desktop with DPMS off + powersave
     governor is not a controlled bench environment. Downgrade afk-bench
     to smoke-test-only (still useful: catches "bench is broken", not
     "bench got slower"). Note this in the manifest header.

3. Yield check: with a bench running, sit down (un-AFK). Within ~90s the
   `afk-bench` service should `pueue kill` the task and exit; confirm
   `ptt-dictate` latency was unaffected. If it didn't yield, the lane is
   a daily-driver regression — revert.

## Done when

`results.jsonl` has ≥3 entries per arc-lane bench, the σ/μ verdict is
recorded back in `backlog/adopt-afk-bench-lane.md` (or its tried/ entry),
and the yield check passed.
