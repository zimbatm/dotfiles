{
  description = "zimbatm's machines — kin-managed";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    kin = {
      url = "git+ssh://git@github.com/assise/kin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.iets.follows = "iets";
      inputs.nix-skills.follows = "nix-skills";
    };
    iets = {
      url = "git+ssh://git@github.com/jonasc-ant/iets";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    srvos = {
      url = "github:numtide/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "llm-agents/systems";
      inputs.flake-parts.follows = "llm-agents/flake-parts";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    nix-skills = {
      url = "git+ssh://git@github.com/assise/nix-skills";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.blueprint.follows = "llm-agents/blueprint";
    };
    distro = {
      url = "github:generational-infrastructure/distro";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.llm-agents.follows = "llm-agents";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      lib = inputs.nixpkgs.lib;
      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      pkgsFor =
        system:
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      # Takes pkgs (not system) so callers can reuse an already-evaluated
      # nixpkgs instance instead of forcing a second `import nixpkgs {}`.
      treefmtFor =
        pkgs:
        inputs.treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          # iets fmt: nixfmt-rfc-style byte-parity on lib/, ~30× faster on
          # large trees. checks.fmt below is the idempotence guard.
          settings.formatter.iets-fmt = {
            command = "${inputs.iets.packages.${pkgs.stdenv.hostPlatform.system}.iets}/bin/iets";
            options = [ "fmt" ];
            includes = [ "*.nix" ];
          };
        };

      # Explicit — no auto-discovery. ADR-0006: locality over abstraction.
      # Canonical inventory of every modules/ file (entrypoints + internals) — intentionally exhaustive.
      nixosModules = {
        common = ./modules/nixos/common.nix;
        desktop = ./modules/nixos/desktop.nix;
        gnome = ./modules/nixos/gnome.nix;
        gotosocial = ./modules/nixos/gotosocial.nix;
        limine-hotfix = ./modules/nixos/limine-hotfix.nix;
        perlless = ./modules/nixos/perlless.nix;
        steam = ./modules/nixos/steam.nix;
        ubuntu-light = ./modules/nixos/ubuntu-light.nix;
        zimbatm = ./modules/nixos/zimbatm.nix;
      };
      homeModules = {
        desktop = ./modules/home/desktop;
        terminal = ./modules/home/terminal;
      };
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          call = p: pkgs.callPackage p { inherit inputs system; };
          shell-squeeze = call ./packages/shell-squeeze;
        in
        {
          inherit (kinOut.packages.${system}) devshell;
          inherit shell-squeeze;
          # Wrap kin's agentshell so grind's `nix build .#agentshell` profile-link
          # (grind-base.js:75, denylisted) picks up the squeeze shims first in PATH
          # without touching the workflow file. symlinkJoin: first path wins, so
          # shell-squeeze/bin/{git,nix,find,tree} shadow; marker propagates.
          agentshell = pkgs.symlinkJoin {
            name = "agentshell";
            paths = [
              shell-squeeze
              kinOut.packages.${system}.agentshell
            ];
            postBuild = "touch $out/bin/.shell-squeeze";
          };
          core = call ./packages/core;
          myvim = call ./packages/myvim;
          nvim = call ./packages/nvim;
          gitbutler-cli = call ./packages/gitbutler-cli;
          ptt-dictate = call ./packages/ptt-dictate;
          transcribe-npu = call ./packages/transcribe-npu;
          transcribe-cpu = call ./packages/transcribe-cpu;
          wake-listen = call ./packages/wake-listen;
          say-back = call ./packages/say-back;
          agent-eyes = call ./packages/agent-eyes;
          gsnap = call ./packages/gsnap;
          ask-local = call ./packages/ask-local;
          ask-cuda = call ./packages/ask-cuda;
          kin-opts = call ./packages/kin-opts;
          infer-queue = call ./packages/infer-queue;
          afk-bench = call ./packages/afk-bench;
          llm-router = call ./packages/llm-router;
          agent-meter = call ./packages/agent-meter;
          now-context = call ./packages/now-context;
          pty-puppet = call ./packages/pty-puppet;
          coord-panes = call ./packages/coord-panes;
          man-here = call ./packages/man-here;
          sem-grep = call ./packages/sem-grep;
          tab-tap = call ./packages/tab-tap;
          live-caption-log = call ./packages/live-caption-log;
          sel-act = call ./packages/sel-act;
          inherit (inputs.nix-skills.packages.${system}) nix-skills-commands;
        }
      );

      kinOut = inputs.kin.lib.mkFleet {
        root = ./.;
        config = import ./kin.nix;
        nixpkgsConfig.allowUnfree = true;
        specialArgs = { inherit inputs; };
        devShell.systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        devShell.extraPackages =
          pkgs:
          [
            pkgs.age-plugin-tpm
            pkgs.hcloud
            pkgs.sbctl
            pkgs.ssh-to-age
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            inputs.iets.packages.${pkgs.stdenv.hostPlatform.system}.iets
            (treefmtFor pkgs).config.build.wrapper
          ];
        devShell.extraAgentPackages = pkgs: [
          (pkgs.callPackage ./packages/agent-eyes { })
          (pkgs.callPackage ./packages/coord-panes { })
          (pkgs.callPackage ./packages/kin-opts { })
          (pkgs.callPackage ./packages/man-here { })
          (pkgs.callPackage ./packages/pty-puppet { })
        ];
      };
    in
    {
      inherit nixosModules homeModules packages;
      inherit (kinOut)
        nixosConfigurations
        kinManifest
        fleetManifest
        devShells
        ;

      formatter = forAllSystems (
        system: (treefmtFor inputs.nixpkgs.legacyPackages.${system}).config.build.wrapper
      );
      checks = forAllSystems (
        system:
        {
          fmt = (treefmtFor inputs.nixpkgs.legacyPackages.${system}).config.build.check inputs.self;
        }
        // lib.optionalAttrs (system == "x86_64-linux") (
          {
            # IFD ban (ADR-0011): iets/kin-deploy reject it; fastCheck passes
            # --no-allow-import-from-derivation so forcing these drvPaths trips
            # on any regression (hit dacd1ec: crops→tng→crane). nixConfig used
            # to set this but prompted users for trust — CLI flag is the gate.
            # seq forces instantiation (so IFD still surfaces); context is then
            # discarded so writeText doesn't input-depend on the .drv — avoids
            # the transient "path … is not valid" race under --no-build.
            no-ifd =
              let
                line =
                  n: c:
                  let
                    p = c.config.system.build.toplevel.drvPath;
                  in
                  builtins.seq p "${n} ${builtins.unsafeDiscardStringContext p}";
              in
              (pkgsFor system).writeText "no-ifd" (
                lib.concatLines (lib.mapAttrsToList line kinOut.nixosConfigurations)
              );
          }
          // lib.mapAttrs (_: c: c.config.system.build.toplevel) kinOut.nixosConfigurations
        )
      );
    };
}
