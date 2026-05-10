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

let
  cargoLock = {
    lockFile = ./Cargo.lock;
    # One hash per unique git source (importCargoLock dedupes by commit
    # SHA, so any one crate per repo covers every sibling crate).
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

  # Two warpdotdev git deps have build.rs scripts that read assets from
  # *outside* the crate's own subdirectory. importCargoLock's git
  # vendoring extracts only the crate dir, so those assets vanish:
  #  - `warp_multi_agent_api` scans `CARGO_MANIFEST_DIR/../../` (in-repo:
  #    `apis/multi_agent/v1/`) for *.proto → "protoc: Missing input file".
  #  - `warp-workflows` walks `../specs/` (sibling of `workflows/`) for
  #    *.yaml → "IO error for operation on ../specs: No such file".
  # Re-fetch each repo at the same rev/hash as the cargoLock pin and
  # re-attach the missing assets in postPatch.
  warpProtoApis = pkgs.fetchgit {
    url = "https://github.com/warpdotdev/warp-proto-apis.git";
    rev = "78a78f21a75432bf0141e396fb318bf1694e47f0";
    hash = cargoLock.outputHashes."warp_multi_agent_api-0.0.0";
  };
  warpWorkflows = pkgs.fetchgit {
    url = "https://github.com/warpdotdev/workflows";
    rev = "793a98ddda6ef19682aed66364faebd2829f0e01";
    hash = cargoLock.outputHashes."warp-workflows-0.1.0";
  };

  # The lock file pins two crates with the same name+version from two
  # different sources — `core-graphics-types 0.2.0` (crates.io vs
  # servo/core-foundation-rs git) and `difflib 0.4.0` (crates.io vs
  # warpdotdev/difflib git). importCargoLock vendors every lock entry into
  # a flat `<name>-<version>` symlink tree, so the second source collides
  # ("Permission denied" trying to ln *into* the read-only first link).
  #
  # Cargo's `vendored-sources` directory source is keyed by name+version
  # only and all replaced sources funnel into the one directory, so only a
  # single copy can survive. Force `ln -sfn` so the *last* lock entry —
  # the git fork — wins:
  #  - `core-graphics-types` is macOS-only, never compiled here.
  #  - `difflib`: warp itself calls `SequenceMatcher::real_quick_ratio`,
  #    which only exists in the warpdotdev fork (E0599 with crates.io).
  # The crates.io consumers still expect the registry checksum in
  # `.cargo-checksum.json` ("unable to verify that <crate> is the same as
  # when the lockfile was generated"). Cargo never re-hashes the vendored
  # *files* (the `files` map is empty), it only string-compares `package`
  # against the lock — so materialise the fork content and stamp the
  # registry checksum onto it.
  #
  # Per-crate registry checksums copied verbatim from the [[package]]
  # entries in ./Cargo.lock — re-check on a Cargo.lock re-sync.
  duplicateCrateChecksums = {
    "core-graphics-types-0.2.0" = "3d44a101f213f6c4cdc1853d4b78aef6db6bdfa3468798cc1d9912f4735013eb";
    "difflib-0.4.0" = "6184e33543162437515c2e2b48714794e37845ec9851711914eec9d308f6ebe8";
  };
  cargoDeps =
    let
      base = pkgs.rustPlatform.importCargoLock cargoLock;
      orig = ''ln -s "$crate" $out/$(basename "$crate" | cut -c 34-)'';
      patched = ''ln -sfn "$crate" "$out/$(basename "$crate" | cut -c 34-)"'';
      stampOne = name: checksum: ''
        fork=$(readlink "$out/${name}")
        rm "$out/${name}"
        cp -r "$fork" "$out/${name}"
        chmod -R u+w "$out/${name}"
        printf '{"files":{},"package":"%s"}' ${lib.escapeShellArg checksum} \
          > "$out/${name}/.cargo-checksum.json"
      '';
    in
    base.overrideAttrs (old: {
      buildCommand =
        (
          assert lib.assertMsg (lib.hasInfix orig old.buildCommand)
            "openwarp: importCargoLock vendor-dir script changed; review the duplicate-crate workaround";
          builtins.replaceStrings [ orig ] [ patched ] old.buildCommand
        )
        + lib.concatStrings (lib.mapAttrsToList stampOne duplicateCrateChecksums);
    });
in

pkgs.rustPlatform.buildRustPackage rec {
  pname = "openwarp";
  version = "0-unstable-2026-05-09";

  src = pkgs.fetchFromGitHub {
    owner = "zerx-lab";
    repo = "warp";
    rev = "b5dd43c4c5f21d60fb9be10378268c22cc6d7095";
    hash = "sha256-9dV1WHoac68KLVdOl/Yl2DQysRoBA937hNcU8VYqGdo=";
  };

  inherit cargoDeps;

  postPatch = ''
    # Upstream gates `mod menu;` to macOS/Windows but ~50 unconditional
    # call sites still `use crate::menu::…` (E0432 → cascading E0282 type
    # inference failures). The module itself only depends on cross-platform
    # warpui/pathfinder helpers, so just compile it on Linux too. The cfg
    # attribute appears exactly once in app/src/lib.rs (line 48, attached
    # to `mod menu;`).
    substituteInPlace app/src/lib.rs --replace-fail \
      '#[cfg(any(target_os = "macos", target_os = "windows"))]' ""

    # Re-attach warp_multi_agent_api's protos (see warpProtoApis comment) and
    # point its build.rs at the crate dir instead of `../../` (which after
    # vendoring would walk back out of the vendor tree into $sourceRoot).
    cp ${warpProtoApis}/apis/multi_agent/v1/*.proto \
      "$cargoDepsCopy/warp_multi_agent_api-0.0.0/"
    substituteInPlace "$cargoDepsCopy/warp_multi_agent_api-0.0.0/build.rs" \
      --replace-fail \
        'manifest_dir.parent().unwrap().parent().unwrap()' \
        'manifest_dir.as_path()'

    # Re-attach warp-workflows' YAML specs (see warpWorkflows comment).
    # Its build.rs uses the literal relative path `../specs`, which from
    # the vendored crate dir resolves to a sibling of the crate inside
    # $cargoDepsCopy — drop them there rather than patching the path.
    cp -r ${warpWorkflows}/specs "$cargoDepsCopy/specs"
  '';

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
    rustPlatform.bindgenHook # alsa-sys / aws-lc-sys / libgit2-sys → bindgen → libclang
  ];

  buildInputs = with pkgs; [
    openssl
    freetype
    expat
    libgit2
    fontconfig
    gettext # gettext-sys
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
