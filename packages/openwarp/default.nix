# OpenWarp — community fork of Warp that opens the AI layer to any
# OpenAI-compatible provider. Pinned to a commit (upstream has no
# releases yet); bump rev + hash + Cargo.lock together.
#
# Cargo.lock is vendored next to this file so importCargoLock can read
# it at eval time without IFD (reading "${src}/Cargo.lock" would force
# realising the source fetcher under --no-allow-import-from-derivation).
# Re-sync after a rev bump:
#   cp $(nix-prefetch-git https://github.com/zerx-lab/warp <rev> | jq -r .path)/Cargo.lock .
{ pkgs, lib, ... }:

pkgs.rustPlatform.buildRustPackage rec {
  pname = "openwarp";
  version = "0-unstable-2026-05-09";

  src = pkgs.fetchFromGitHub {
    owner = "zerx-lab";
    repo = "warp";
    rev = "b5dd43c4c5f21d60fb9be10378268c22cc6d7095";
    hash = "sha256-9dV1WHoac68KLVdOl/Yl2DQysRoBA937hNcU8VYqGdo=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    # One hash per unique git source (importCargoLock dedupes by commit
    # SHA, so any one crate per repo carries the hash for its siblings).
    outputHashes = {
      "command-corrections-0.0.0" = "sha256-dV7UzRxIF5K9TH0lOTONMVhTcEO0VmquWf4AB/k4hA0=";
      "core-foundation-0.10.1" = "sha256-CfGnJgsyUjR0uWfXMOGDjVMkDcjzAD/EwXr6L5FdgqU=";
      "cosmic-text-0.12.0" = "sha256-xuUTf6qdbGryKLLmjl4kP0X8u7SMk9WWFq32GibxC2U=";
      "dagre_rust-0.0.5" = "sha256-vnO+6hqdxxlXnhN1DHRVn2k+sdqYxnzN0Igu2oSjskc=";
      "difflib-0.4.0" = "sha256-nN54WUgZagDvmdo2hYwaeGsWOXuIwOLNrlnvPxuKhKU=";
      "dpi-0.1.1" = "sha256-6fyP7+qp1AklfUFWDuJqvChHaU/nj/4Xyc+SGE/ligs=";
      "dwrote-0.11.5" = "sha256-2XeWdLMuVmaBfG9AcNYyVJX1QUXxBvjc9mlGl8szxl0=";
      "email_address-0.2.3" = "sha256-OZUExG8rbBgPlGMGlWR72dSsnyYxNOsIgHQ1tAoX5f4=";
      "file-id-0.2.2" = "sha256-qpkWIt2be1FXa0Ua9IkKeFNnoW70m3bhJ9wXRNzqi6I=";
      "font-kit-0.12.0" = "sha256-exECbZ7eQv+WdpXu4gEfSeryChqTlyQrHSQEN/0yKrY=";
      "objc-0.2.7" = "sha256-+Fqo8+HX5Dz5VZMRZinpqzPqB71FX7UHxEbxArdfNVI=";
      "pathfinder_simd-0.5.4" = "sha256-EYaGJLCgEkCtTaIPgIAhRo8m9p6ncUYYeYFgl6oQQ1Q=";
      "rmcp-0.10.0" = "sha256-sAa4RZsnmnYKKnoCHOxwOGDJuBJJeXrEqbXE6MsxTwg=";
      "session-sharing-protocol-0.0.0" = "sha256-9gQAoUaJ8c7Fi5c2khOdGq1eZWXcCXlU5I4jcotH6YM=";
      "tikv-jemalloc-sys-0.6.1+5.3.0-1-g0d7a26e9b6faa4ea33601ee605b5d86b68ff7790" =
        "sha256-SaTS9bT3OCD9r1SzFHvu4CEYYL7sGxpU2DbQi26zRbQ=";
      "tink-core-0.3.0" = "sha256-lsyF98CYikT9V7KCCf/+iHdJ4QjdxXUJ+bWOBv7gzmg=";
      "uneval-0.2.3" = "sha256-UPMOQaCQAkgrrbiUXudcps8zS/2j0ex0pi2aWcaNt6s=";
      "utf8parse-0.2.1" = "sha256-kaM0tEdpzGkpDOXvywXd8cy5M+sgWZBXHWFYSCLlJ3k=";
      "warp-command-signatures-0.0.0" = "sha256-mpOc8xxdqLh/Zjp6/eIvYuuQn7yzLNTIXV8lI1mU48c=";
      "warp-workflows-0.1.0" = "sha256-ICgkxlUUIfyhr0agZEk3KtGHX0uNRlRCKtz0iF2jd7o=";
      "warp_multi_agent_api-0.0.0" = "sha256-8bB/tCLIzRCofMK1rYCe8bizUr1U4A6f6uVeckJJKI4=";
      "yaml-rust-0.4.5" = "sha256-C7CXEw4rTnkZlXWCAyMOJ4BIelapB1AQ3HCzsnr0rcI=";
    };
  };

  # OSS channel only: `warp-oss` is auto-selected when `warp-channel-config`
  # isn't on PATH (script/run + app/build.rs::generate_channel_config_if_needed).
  # No `release_bundle` feature → build.rs skips channel-config embedding and
  # the Sentry/macOS branches; on Linux it only emits cargo:rustc-cfg lines.
  cargoBuildFlags = [
    "-p"
    "warp"
    "--bin"
    "warp-oss"
    "--features"
    "gui"
  ];
  doCheck = false;

  nativeBuildInputs = with pkgs; [
    pkg-config
    cmake
    protobuf
    jq
    brotli
    perl # openssl-sys vendored build, in case OPENSSL_NO_VENDOR is ignored by a transitive dep
  ];

  buildInputs = with pkgs; [
    openssl
    freetype
    expat
    libgit2
    fontconfig
    alsa-lib # voice_input is pulled in by the `gui` feature
    libxkbcommon
    wayland
    libGL
    vulkan-loader
    libxcb
    libx11
    libxi
    libxcursor
  ];

  env = {
    OPENSSL_NO_VENDOR = "1";
    # Skip protoc download attempts in any prost-build/tonic-build crates.
    PROTOC = "${pkgs.protobuf}/bin/protoc";
  };

  meta = {
    description = "OpenWarp terminal (warp-oss) — community fork with pluggable OpenAI-compatible AI backends";
    homepage = "https://github.com/zerx-lab/warp";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "warp-oss";
  };
}
