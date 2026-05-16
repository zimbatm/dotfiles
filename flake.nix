{
  description = "zimbatm's local packages and home modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
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
    distro = {
      url = "github:generational-infrastructure/distro";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.llm-agents.follows = "llm-agents";
    };
    voxtype = {
      follows = "distro/voxtype";
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
      treefmtFor =
        pkgs:
        inputs.treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          settings.formatter.nixfmt = {
            command = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
            includes = [ "*.nix" ];
          };
        };
      nixosModules = {
        common = ./modules/nixos/common.nix;
        desktop = ./modules/nixos/desktop.nix;
        gnome = ./modules/nixos/gnome.nix;
        perlless = ./modules/nixos/perlless.nix;
        steam = ./modules/nixos/steam.nix;
        ubuntu-light = ./modules/nixos/ubuntu-light.nix;
        zimbatm = ./modules/nixos/zimbatm.nix;
      };
      homeModules = {
        desktop = ./modules/home/desktop;
        terminal = ./modules/home/terminal;
      };
      nixosConfigurations = {
        nv1 = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./machines/nv1/configuration.nix
            {
              nixpkgs.config.allowUnfree = true;
            }
          ];
        };
      };
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          call = p: pkgs.callPackage p { inherit inputs system; };
        in
        {
          shell-squeeze = call ./packages/shell-squeeze;
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
          infer-queue = call ./packages/infer-queue;
          afk-bench = call ./packages/afk-bench;
          llm-router = call ./packages/llm-router;
          now-context = call ./packages/now-context;
          pty-puppet = call ./packages/pty-puppet;
          man-here = call ./packages/man-here;
          sem-grep = call ./packages/sem-grep;
          tab-tap = call ./packages/tab-tap;
          live-caption-log = call ./packages/live-caption-log;
          sel-act = call ./packages/sel-act;
          web-eyes = call ./packages/web-eyes;
        }
      );
    in
    {
      inherit nixosModules homeModules nixosConfigurations packages;

      formatter = forAllSystems (
        system: (treefmtFor inputs.nixpkgs.legacyPackages.${system}).config.build.wrapper
      );
      checks = forAllSystems (
        system: {
          fmt = (treefmtFor inputs.nixpkgs.legacyPackages.${system}).config.build.check inputs.self;
        }
      );
    };
}
