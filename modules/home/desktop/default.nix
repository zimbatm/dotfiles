{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  llm = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  self' = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
  # nixpkgs buildGoModule puts GOPROXY in the go-modules FOD's impureEnvVars
  # (so corp proxies work). On the ant build host GOPROXY points at an authed
  # artifactory the FOD has no creds for → 401. Pin the public proxy and drop
  # GOPROXY from impureEnvVars (impure wins over explicit drv env in Nix).
  # Verified pkgs.crush@0.55.0 still hits this; upstream fix would be nixpkgs
  # buildGoModule defaulting env.GOPROXY in the FOD.
  crush =
    let
      goModules = pkgs.crush.goModules.overrideAttrs (old: {
        GOPROXY = "https://proxy.golang.org,direct";
        impureEnvVars = pkgs.lib.remove "GOPROXY" old.impureEnvVars;
      });
    in
    pkgs.crush.overrideAttrs (_: {
      inherit goModules;
    });

  # Electron's safeStorage backend autodetect keys off XDG_CURRENT_DESKTOP,
  # which is "niri" on this host — not in Electron's known-DE list, so it
  # falls back to basic_text and Signal aborts on backend mismatch. Force
  # gnome-libsecret; gnome-keyring-daemon owns org.freedesktop.secrets here.
  signal-desktop = pkgs.symlinkJoin {
    name = "signal-desktop-libsecret";
    paths = [ pkgs.signal-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/signal-desktop \
        --add-flags "--password-store=gnome-libsecret"
    '';
  };
in
{
  imports = [
    ../terminal
    ./activitywatch.nix
    ./afk-bench.nix
    ./live-caption.nix
    ./sem-grep.nix
  ];

  programs.firefox.enable = true;
  # pin legacy path; XDG migration would need manual ~/.mozilla move on nv1
  programs.firefox.configPath = ".mozilla/firefox";

  # tab-tap native-messaging manifest: lets the (unsigned, local) extension at
  # ${tab-tap}/share/tab-tap/extension reach its host. Load the extension via
  # about:debugging → Load Temporary Add-on for now; if it survives the
  # falsification (two verbs suffice) it graduates to a policies.json install.
  home.file.".mozilla/native-messaging-hosts/tab_tap.json".text = builtins.toJSON {
    name = "tab_tap";
    description = "tab-tap socket relay";
    path = "${self'.tab-tap}/libexec/tab-tap-host";
    type = "stdio";
    allowed_extensions = [ "tab-tap@home" ];
  };

  programs.foot = {
    enable = true;
    server.enable = true;
    settings.main.font = "monospace:size=16";
  };

  programs.ghostty = {
    enable = true;

    settings = {
      # theme = "catppuccin-mocha";
      font-size = 16;
    };
  };

  # GNOME custom keybinds. The custom-keybindings list is the *registry* —
  # hm activation REPLACES it, so every bind we want must be listed here
  # (manual binds via Settings get de-registered on switch otherwise).
  dconf.settings = {
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ptt-dictate/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ptt-dictate-intent/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/sel-act-tighten/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/sel-act-ask/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/terminal" = {
      name = "Terminal";
      command = "foot";
      binding = "<Super>Return";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ptt-dictate" = {
      name = "Push-to-talk dictate";
      command = "ptt-dictate";
      binding = "<Super>d";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ptt-dictate-intent" = {
      name = "Push-to-talk intent dispatch";
      command = "ptt-dictate --intent";
      binding = "<Super><Shift>d";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/sel-act-tighten" = {
      name = "Selection: tighten via ask-local";
      command = "sel-act tighten";
      binding = "<Super>e";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/sel-act-ask" = {
      name = "Selection: free-form prompt via ask-local";
      command = "sel-act ask";
      binding = "<Super><Shift>e";
    };
  };

  # Grant non-interactive xdg-desktop-portal Screenshot to host (unsandboxed)
  # apps — app_id "" — so gsnap can capture without a prompt. GNOME 41+ locks
  # org.gnome.Shell.Screenshot to allowlisted senders, so the portal is the only
  # CLI path; the portal in turn refuses interactive:false until this row exists
  # in PermissionStore. Idempotent; tolerates no-session-bus (initial install).
  home.activation.grantScreenshotPortal = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.glib}/bin/gdbus call --session \
      --dest org.freedesktop.impl.portal.PermissionStore \
      --object-path /org/freedesktop/impl/portal/PermissionStore \
      --method org.freedesktop.impl.portal.PermissionStore.SetPermission \
      screenshot true screenshot "" '["yes"]' 2>/dev/null || true
  '';

  # Dispatch table for `ptt-dictate --intent`. Each [section] is an intent name
  # the GBNF-constrained classifier (ask-local --grammar) may emit; `exec` runs
  # via bash -c with {arg} substituted shell-quoted. `fallthrough = true` types
  # the raw utterance via ydotool (the pre-intent path). Unmatched → fallthrough.
  # Targets are existing skill CLIs already on PATH (agent-eyes, ask-local,
  # say-back, now-context) — zero new closure.
  xdg.configFile."voice-intent/intents.toml".text = ''
    [screenshot]
    exec = "peek"

    [ask]
    exec = "ask-local {arg} | say-back"

    [context]
    exec = "now-context --clip"

    [type]
    fallthrough = true
  '';

  # Transform table for `sel-act <verb>`. Same [section].prompt shape as the
  # ptt-dictate intent table above so the two grow together; ask-local sees
  # "<prompt>\n\n---\n<selection>". `sel-act ask` bypasses this (zenity entry).
  xdg.configFile."sel-act/prompts.toml".text = ''
    [tighten]
    prompt = "Rewrite the text below to be tighter and clearer. Keep meaning, tone, and formatting. Output only the rewritten text."

    [translate]
    prompt = "Translate the text below to English. Output only the translation."

    [explain]
    prompt = "Explain the text below in 2-3 plain sentences. Output only the explanation."

    [shellify]
    prompt = "Produce a single POSIX shell command that does what the text below describes. Output only the command, no fences."
  '';

  home.packages = with pkgs; [
    # Graphical
    brave
    element-desktop
    joplin-desktop
    signal-desktop
    slack
    telegram-desktop

    # KDE stuff
    kdePackages.filelight
    kdePackages.okular

    # SSH shortcuts
    self'.core

    # AI
    self'.ptt-dictate
    self'.wake-listen
    self'.say-back
    self'.ask-local
    self'.llm-router
    self'.agent-eyes
    self'.gsnap
    self'.web-eyes
    self'.now-context
    self'.pty-puppet
    self'.tab-tap
    self'.sel-act
    codex
    crush
    opencode
    llm.pi
    inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Always-on VAD gate on the NPU. ConditionPathExists keeps it inert until
  # the accel node is live (gated on needs-human/ops-deploy-nv1).
  systemd.user.services.wake-listen = {
    Unit = {
      Description = "NPU-resident VAD gate for ptt-dictate";
      ConditionPathExists = "/dev/accel/accel0";
      After = [ "pipewire.service" ];
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      ExecStart = "${self'.wake-listen}/bin/wake-listen";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
