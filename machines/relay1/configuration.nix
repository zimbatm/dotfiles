{ ... }:
{
  # Public-IP node — natural maille relay once QNT lands. Minimal for now.
  security.sudo.wheelNeedsPassword = false;

  # relay1 doesn't import common.nix (deliberately minimal — no hm/srvos),
  # so the assise federation cache is duplicated here. Same wontfix-dup
  # precedent as wheelNeedsPassword above; lift to a kin base module if a
  # third standalone host appears.
  nix.settings.substituters = [ "https://cache.assise.systems" ];
  nix.settings.trusted-public-keys = [
    "cache.assise.systems-1:6AhZgZEbIMKqsRdgT+P0M+poXohJbiGD/MHrnfZF19U="
  ];
}
