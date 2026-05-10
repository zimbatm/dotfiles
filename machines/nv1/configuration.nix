{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    # NovaCustom V5xTNC: Intel Meteor Lake-H + NVIDIA RTX 4060 Max-Q
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-ssd
    inputs.self.nixosModules.desktop
    inputs.self.nixosModules.gnome
    inputs.distro.nixosModules.niri
    inputs.distro.nixosModules.noctalia-bar
    inputs.self.nixosModules.steam
    inputs.srvos.nixosModules.mixins-systemd-boot
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Hybrid graphics: Intel Arc (Meteor Lake iGPU) drives the display; NVIDIA
  # RTX 4060 Max-Q is the compute dGPU (CUDA / llama.cpp). Apps stay on Intel
  # by default and opt into the dGPU via the `nvidia-offload` wrapper from
  # prime.offload.enableOffloadCmd.
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    intel-compute-runtime
    intel-media-driver
  ];

  # Meteor Lake NPU (Intel AI Boost) — exploration: OpenVINO Whisper offload off the iGPU.
  # nixos module wires intel-npu-driver.firmware (intel/vpu/vpu_37xx_v1.bin) + libze_intel_npu.so
  # into /run/opengl-driver, plus level-zero loader & npu validation tools in PATH.
  # Kernel 6.18 ships ivpu (CONFIG_DRM_ACCEL_IVPU=m); load explicitly for first-boot enumeration.
  # Verify post-deploy: `ls /dev/accel/` and `vpu-umd-test` / openvino Core().available_devices.
  hardware.cpu.intel.npu.enable = true;
  boot.kernelModules = [ "ivpu" ];

  # uinput access for ptt-dictate (ydotool type)
  programs.ydotool.enable = true;

  # opencrow-chat panel in noctalia bar (Mod+N toggles); llama-swap
  # serves the local LLM the chat talks to. opencrow runs in a NixOS
  # container so override perlless's enableContainers=false default.
  services.opencrow-local = {
    enable = true;
    noctaliaPlugin = true;
  };
  boot.enableContainers = true;

  # FIXME(distro): drop once upstream pins HF rev (resolve/<sha> not resolve/main) — upstream issue, not ours to vendor.
  # distro@a80828ae pins both GGUFs via the mutable `resolve/main` HF ref using
  # *eval-time* `builtins.fetchurl`. unsloth re-uploaded gemma so the hash
  # drifted (rABp68... -> k3i8Rx...). A `lib.mkForce` on `.cmd` alone (the
  # previous fix, 459f04b) does NOT prevent the eval failure: the module
  # system's def-collection (`lib/modules.nix:1247` `isAttrs d.value`) forces
  # *every* definition's value to WHNF to check for `_type`, and forcing a
  # string with `${gemma4-e2b-gguf}` interpolation forces the builtins.fetchurl.
  # Replacing the whole `settings.models` attr at mkForce priority means the
  # module system never accesses distro's per-model entries, so the let
  # bindings stay un-forced. Side-effect benefit: `pkgs.fetchurl` (build-time
  # FOD) instead of `builtins.fetchurl` (eval-time / IFD-shaped) for both
  # models — this is what distro should be doing anyway.
  services.llama-swap.settings.models =
    let
      gemma4-e2b-gguf = pkgs.fetchurl {
        url = "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf";
        hash = "sha256-k3i8RxcQIp7xZXCbYuNL+2IjFCDdr21ynnJzBbW4Zy0=";
      };
      qwen25-05b-gguf = pkgs.fetchurl {
        url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf";
        hash = "sha256-dKTajJ/bzRW9H20B1iFBDTHG/ACYb162h4JOe5PXqds=";
      };
      llama-server = lib.getExe' config.services.llama-swap.llama-server-package "llama-server";
      # mirror distro's modelArgs so modelExtraArgs still composes
      modelArgs =
        id:
        lib.optionalString (config.services.llama-swap.modelExtraArgs ? ${id})
          " ${config.services.llama-swap.modelExtraArgs.${id}}";
    in
    lib.mkForce {
      "qwen2.5:0.5b".cmd =
        "${llama-server} -m ${qwen25-05b-gguf} --port \${PORT}" + modelArgs "qwen2.5:0.5b";
      "gemma4:e2b".cmd = "${llama-server} -m ${gemma4-e2b-gguf} --port \${PORT}" + modelArgs "gemma4:e2b";
    };

  # NVIDIA RTX 4060 Max-Q (Ada / AD107M) for CUDA compute. Open kernel
  # modules — supported on Ada from the 555 series; production (595.58.03)
  # ships the matching userspace and pairs with cudaPackages_13. Display
  # stays on the Intel Arc iGPU; offload via `nvidia-offload <cmd>`.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.production;
    open = true;
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = false;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 8;

  environment.systemPackages = [
    # For debugging and troubleshooting Secure Boot.
    pkgs.sbctl

    # NPU exploration — OpenVINO runtime (built with ENABLE_INTEL_NPU) + python bindings.
    pkgs.openvino
    (pkgs.python3.withPackages (p: [ p.openvino ]))

    pkgs.perf
    pkgs.pam_u2f # provides pamu2fcfg for enrolling the YubiKey
  ];

  # Debugging tools
  programs.bcc.enable = true;
  programs.sysdig.enable = true;

  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.trusted-users = [ "zimbatm" ];

  # Build policy: nv1 builds small, dispatches heavy. Strip big-parallel /
  # nixos-test / benchmark from local system-features so derivations carrying
  # requiredSystemFeatures for those are forced onto the hcloud-07 remote
  # builder (kin.nix builders.hcloud-07 advertises them). Keep kvm/uid-range/
  # recursive-nix — hardware/daemon capabilities, not load classes. mkForce
  # because the nixpkgs config/nix.nix module and the srvos nix-experimental
  # mixin both set system-features at default priority — a plain assignment
  # would merge with theirs, not replace.
  nix.settings.system-features = lib.mkForce [
    "kvm"
    "uid-range"
    "recursive-nix"
  ];

  # sudo/login/unlock via YubiKey touch (FIDO2). Enroll: pamu2fcfg > ~/.config/Yubico/u2f_keys
  security.pam.u2f = {
    enable = true;
    settings.cue = true;
  };
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.gdm-password.u2fAuth = true;
  security.pam.services.login.u2fAuth = true;
  security.pam.services.polkit-1.u2fAuth = true;

  time.timeZone = "Europe/Zurich";

  # Configure the home-manager profile
  home-manager.users.zimbatm = {
    imports = [ inputs.self.homeModules.desktop ];
    config.home.stateVersion = "22.11";
    config.home.live-caption.enable = false;
    config.home.packages = [
      inputs.iets.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.infer-queue
    ];
    config.services.pueue.enable = false;
  };

  # Auto-tune power management settings
  powerManagement.powertop.enable = true;
}
