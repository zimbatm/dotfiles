{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  self' = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Off by default — capturing the sink monitor turns *all* desktop audio into
  # text on disk. Policy 2026-04-14 (396d2de): enable per-host with explicit
  # retentionDays; `live-caption off` for per-session pause.
  options.home.live-caption = {
    enable = lib.mkEnableOption "live-caption-log: monitor-source → NPU transcript → jsonl + sem-grep";
    retentionDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Delete caption jsonl older than this many days during the nightly reindex.";
    };
  };

  config = lib.mkIf config.home.live-caption.enable {
    home.packages = [
      self'.live-caption-log
      (pkgs.writeShellApplication {
        name = "live-caption";
        text = ''
          case "''${1:-status}" in
            on)     systemctl --user start live-caption-log ;;
            off)    systemctl --user stop live-caption-log ;;
            status) systemctl --user status live-caption-log --no-pager ;;
            tail)   tail -f "''${XDG_STATE_HOME:-$HOME/.local/state}/live-caption/$(date +%F).jsonl" ;;
            *)      echo "usage: live-caption {on|off|status|tail}  (off is per-session; edit config for persistent)" >&2; exit 2 ;;
          esac
        '';
      })
    ];

    systemd.user.services.live-caption-log = {
      Unit = {
        Description = "System audio → NPU transcript → jsonl";
        ConditionPathExists = "/dev/accel/accel0";
        After = [
          "pipewire.service"
          "pueued.service"
        ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${self'.live-caption-log}/bin/live-caption-log";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Nightly: fold yesterday's caption jsonl into the sem-grep corpus so
    # `sem-grep "what did the standup say about X"` works against local audio
    # history. Index is incremental on content-hash; default repo set is
    # duplicated here so the caption dir appends rather than replaces.
    systemd.user.services.live-caption-reindex = {
      Unit.Description = "sem-grep reindex with caption logs";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "live-caption-reindex" ''
          set -eu
          state="''${XDG_STATE_HOME:-$HOME/.local/state}/live-caption"
          [ -d "$state" ] || exit 0
          find "$state" -name '*.jsonl' -mtime +${toString config.home.live-caption.retentionDays} -delete
          export SEM_GREP_REPOS="''${SEM_GREP_REPOS:-$HOME/src/home:$HOME/src/meta}:$state"
          exec ${self'.sem-grep}/bin/sem-grep index
        ''}";
      };
    };
    systemd.user.timers.live-caption-reindex = {
      Unit.Description = "Nightly sem-grep reindex of caption logs";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
