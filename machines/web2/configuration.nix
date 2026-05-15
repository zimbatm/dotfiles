{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.common
    inputs.self.nixosModules.gotosocial
    inputs.srvos.nixosModules.mixins-nginx
  ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.sudo.wheelNeedsPassword = false;
}
