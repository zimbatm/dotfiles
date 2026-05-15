{ inputs, pkgs, ... }:
{
  users.users.zimbatm = {
    description = "Jonas Chevalier";
    isNormalUser = true;
    uid = 1000;
    group = "users";
    packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.myvim ];
    shell = "/run/current-system/sw/bin/bash";
  };
}
