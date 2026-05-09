{
  pkgs,
  inputs,
  ...
}:
let
  self' = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Opportunistic bench drain: every ~30 min, if Jonas is AFK and the
  # arc/npu lanes are idle, run the oldest-stale local-inference bench
  # from packages/afk-bench/benches.json through infer-queue with a hard
  # timeout. Yields the device within 60s of un-AFK. Results accumulate in
  # $XDG_STATE_HOME/afk-bench/results.jsonl for human interpretation.
  #
  # Sits next to the LLM tooling it drains (ask-local, ask-cuda, sem-grep,
  # ptt-dictate). Falsification step (σ/μ ≤ 20% across 3 AFK windows) is
  # human-gated post-deploy — see backlog/needs-human.

  home.packages = [ self'.afk-bench ];

  systemd.user.services.afk-bench = {
    Unit = {
      Description = "Drain one stale local-inference bench while AFK";
      # Same gate as the rest of the accel stack — inert until the NPU node
      # exists, i.e. inert everywhere but a deployed nv1.
      ConditionPathExists = "/dev/accel/accel0";
      After = [
        "pueued.service"
        "aw-server.service"
      ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${self'.afk-bench}/bin/afk-bench";
      # Bench wall clock is bounded inside the wrapper (default 600s) plus
      # poll slack; cap the unit so a wedged pueue can't hold it forever.
      TimeoutStartSec = "20min";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.afk-bench = {
    Unit.Description = "Periodic AFK bench drain";
    Timer = {
      # Re-arm relative to the last finish, not the wall clock — keeps a
      # steady cadence regardless of how long a bench ran or got yielded.
      OnBootSec = "10min";
      OnUnitInactiveSec = "30min";
      RandomizedDelaySec = "2min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
