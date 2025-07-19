{
  description = "zimbatm's dotfiles";

  inputs = {
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
    blueprint.url = "github:numtide/blueprint";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
    lanzaboote.url = "github:nix-community/lanzaboote";
    mkdocs-numtide.inputs.nixpkgs.follows = "nixpkgs";
    mkdocs-numtide.url = "github:numtide/mkdocs-numtide";
    nix-ai-tools.inputs.blueprint.follows = "blueprint";
    nix-ai-tools.inputs.nixpkgs.follows = "nixpkgs";
    nix-ai-tools.inputs.treefmt-nix.follows = "treefmt-nix";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:Mic92/nix-index-database";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # Trick renovate into working: "github:NixOS/nixpkgs/nixpkgs-unstable"
    # see https://github.com/renovatebot/renovate/issues/29721
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    srvos = {
      url = "github:numtide/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/x86_64-linux";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs:
    inputs.blueprint {
      inherit inputs;
      nixpkgs.config.allowUnfree = true;
    };
}
