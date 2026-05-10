let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuiDoBOxgyer8vGcfAIbE6TC4n4jo8lhG9l01iJ0bZz"
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIOH4yGDIDHCOFfNeXuvYwNoSVtAPOznAHfxSTSze8tMnAAAABHNzaDo= zimbatm@p1"
  ];
in
{
  users.zimbatm = {
    admin = true;
    inherit sshKeys;
    uid = 1000;
    groups = [
      "audio"
      "docker"
      "input"
      "libvirtd"
      "networkmanager"
      "video"
    ];
  };
  users.zimbatm-yk = {
    recipientOnly = true;
  }; # YubiKey age recipient (no unix account)
  users.migration-test = {
    admin = true;
    uid = 1001;
  }; # still load-bearing for kin/userborn migration test (Jonas 2026-04-11)
  users.claude = {
    admin = true;
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJeTgAfmrKax1TAMTiv/D8IImSRfnELGamSJvDqfQt21 claude@kin-infra"
    ];
  };

  machines = {
    nv1 = {
      host = "fd0c:3964:8cda::6e42:b995:2026:deae";
      tags = [ "desktop" ];
      profile = "none";
      stateVersion = "23.05";
    };
    web2 = {
      host = "89.167.46.118";
      tags = [ "server" ];
      profile = "hetzner-cloud";
      stateVersion = "26.05";
    };
  };

  services.identity = {
    domain = "ztm";
    on = [ "all" ];
    # ADR-0011 reciprocal: trust kin-infra's CA so its leaves verify here.
    # CA = ../kin-infra/gen/identity/ca/_shared/tls-ca.crt (URI-SAN
    # assise://dwqfzbq5zxrlhfhcub6fsaeb4zitwfxa/ca), committed at
    # keys/peers/kin-infra-ca.crt so `kin gen` needs no sibling read.
    peers.kin-infra.tlsCaCert = builtins.readFile ./keys/peers/kin-infra-ca.crt;
    # kin-infra's gen/_fleet/_shared/ula-prefix → maille [fleet.<id>].net so
    # kinq0 gets a /48 route to peer-fleet ULAs (feat-mesh-peer-fleets-tun;
    # ADR-0021 cedar curl-pair leg-2 datapath).
    peers.kin-infra.net = "fdc5:e1a6:b03f";
  };
  services.mesh.on = [ "all" ];
  # No own relay since relay1 was decommissioned (2026-05-09; iroh underused).
  # Mesh stays on for the kin-infra peer-fleet path → hcloud-07 builder ULA.
  # Reachability half of identity.peers.kin-infra (kin@a8d56b76, maille@eaefaae).
  # hcloud-01 is kin-infra's ingress host; port 7850 is the kin default.
  services.mesh.peerFleets.kin-infra.seeds = [ "5.75.246.255:7850" ];

  # ADR-0009 remote-tier builder — push-bridge proof to kin-infra hcloud-07
  # (ccx33, 8 vCPU/32G) over the maille mesh ULA. Reachability is
  # services.mesh.peerFleets.kin-infra above; the route exists, dispatch
  # over it didn't until this block. Cross-fleet authz is a MANUAL key drop
  # on hcloud-07 for now (nv1's ssh-host.pub → nix-remote authorizedKeys);
  # declarative path is ../kin/backlog/feat-builders-peer-fleet-keys.md.
  # sshKey is nv1's per-machine /run/kin secret path — only nv1 dispatches;
  # web2 also gets this nix.buildMachines entry but never reaches for it.
  builders.hcloud-07 = {
    host = "fdc5:e1a6:b03f::ad72:8e88:ac84:0e54";
    systems = [
      {
        system = "x86_64-linux";
        features = [
          "benchmark"
          "big-parallel"
          "ca-derivations"
          "kvm"
          "nixos-test"
        ];
        speedFactor = 2;
      }
    ];
    maxJobs = 8;
    sshKey = "/run/kin/identity/machine/nv1/ssh-host";
  };

  services.attest.on = [ "web2" ];
  services.attest.keyName = "attest.ztm-1";

  # ietsd rollout stage-1 (kin docs/howto/rollout-ietsd.md): coexist on
  # one canary. takeover=false → alt socket /nix/var/iets/daemon-socket/
  # alongside nix-daemon; opt in per-shell with NIX_REMOTE=unix://… to
  # soak. kin-infra is at stage-2 (3 builders coexist, kin-infra@kin.nix:245);
  # web2 starts here as the always-on box. Widen to nv1 once a routine
  # `nix-build -A hello` via the alt socket round-trips clean.
  services.ietsd = {
    on = [ "web2" ];
    takeover = false;
  };

  # NVIDIA NIM is OpenAI-shaped; the kin builtin LiteLLM adapter republishes it
  # as Anthropic-shaped for kin/Claude consumers. pendingOn keeps the unit
  # inert until a human rotates+sets the API key with:
  #   kin set llm-adapter/api-key/_shared/key
  services.llm-adapter = {
    on = [ "nv1" ];
    backend = "openai";
    apiBase = "https://integrate.api.nvidia.com/v1";
    upstreamModel = "minimaxai/minimax-m2.7";
    model = "claude-nvidia";
    apiKeySecret = true;
    pendingOn = "llm-adapter/api-key/_shared/key";
  };

  # Track L dogfood: lockring as nv1's per-user secrets daemon with the
  # opt-in ssh-agent ingress (LOCKRING_SSH_AUTH_SOCK=1). kin does NOT
  # flip $SSH_AUTH_SOCK — that and the week-of-use procedure stay in
  # backlog/needs-human/feat-lockring-ssh-agent.md. Default policyFile
  # = lockring's crates/lockring-core/examples/policy.cedar.
  services.lockring = {
    on = [ "nv1" ];
    sshAgent = true;
  };

  gen.gotosocial-restic = {
    for = [ "web2" ];
    perMachine = false;
    files.password.random.bytes = 32;
  };
  gen.gotosocial-rsyncnet = {
    for = [ "web2" ];
    perMachine = false;
    files.password.secret = true;
  };
}
