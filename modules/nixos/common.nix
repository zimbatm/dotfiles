# Common configuration accross *all* the machines
{ inputs, lib, ... }:
{
  imports = [
    ./perlless.nix
    ./zimbatm.nix
    inputs.home-manager.nixosModules.default
    inputs.srvos.nixosModules.common
    inputs.srvos.nixosModules.mixins-nix-experimental
    inputs.srvos.nixosModules.mixins-terminfo
  ];

  # Configure Let's Encrypt
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "zimbatm@zimbatm.com";

  # Configure all the machines with Numtide caches and a fast
  # mirror for cache.nixos.org hosted at Hetzner.
  nix.settings.trusted-public-keys = [
    # cache.numtide.com
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
  nix.settings.substituters = lib.mkForce [
    # Fast mirror for cache.nixos.org
    "https://hetzner-cache.numtide.com"
    # NumTide cache
    "https://cache.numtide.com"
  ];
  nix.settings.experimental-features = lib.mkForce [
    "auto-allocate-uids"
    "ca-derivations"
    "cgroups"
    "fetch-closure"
    "recursive-nix"
    "configurable-impure-env"
    "impure-derivations"
    "blake3-hashes"
    "nix-command"
    "flakes"
  ];

  # Disallow IFDs by default. IFDs can too easily sneak in and cause trouble.
  #
  # https://nix.dev/manual/nix/2.22/language/import-from-derivation)
  nix.settings.allow-import-from-derivation = false;

  # Allow __noChroot builds.
  nix.settings.sandbox = "relaxed";

  nixpkgs.config.allowUnfree = true;

  networking.firewall.allowPing = true;

  # DNS search domain
  networking.search = [ "ntd.one" ];

  # Configure home-manager
  home-manager.extraSpecialArgs.inputs = inputs; # forward the inputs
  home-manager.useGlobalPkgs = true; # don't create another instance of nixpkgs
  home-manager.useUserPackages = true; # install user packages directly to the user's profile

  # Enable better declarative user management. https://github.com/nikstur/userborn
  services.userborn.enable = true;

  # Security issue workaround. <https://discourse.nixos.org/t/newly-announced-vulnerabilities-in-cups/52771>
  systemd.services.cups-browsed.enable = false;
}
