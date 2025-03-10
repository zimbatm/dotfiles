# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration-extra.nix
    ./hardware-configuration.nix
    inputs.self.nixosModules.desktop
    inputs.self.nixosModules.gnome
    inputs.self.nixosModules.nix-remote-builders
    inputs.sops-nix.nixosModules.default
    inputs.srvos.nixosModules.mixins-systemd-boot
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;

  sops.defaultSopsFile = ./secrets.yaml;

  boot.initrd.systemd.enable = true;

  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.nvidia-container-toolkit.enable = true;
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.nvidiaSettings = true;
  hardware.nvidia.open = true;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.production;
  services.xserver.videoDrivers = [ "nvidia" ];

  networking.hostName = "no1"; # Define your hostname.
  networking.networkmanager.enable = true;

  nix.nixPath = [ "nixpkgs=${toString pkgs.path}" ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  services.xserver.wacom.enable = true;
  # services.xserver.upscaleDefaultCursor = lib.mkForce false;

  # 
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.cnijfilter2 ];
  services.avahi.enable = true;
  services.avahi.nssmdns4 = true;
  services.avahi.openFirewall = true;

  home-manager.users.zimbatm = {
    imports = [ inputs.self.homeModules.desktop ];
    config.home.stateVersion = "22.11";
  };

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "19.09"; # Did you read the comment?

  # Set your time zone.
  time.timeZone = "Europe/Paris";

  virtualisation.docker.storageDriver = "btrfs";
  virtualisation.docker.package = pkgs.docker_25;
  #virtualisation.libvirtd.enable = true;
}
