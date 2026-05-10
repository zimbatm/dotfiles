# adopt: openwarp (zerx-lab/warp openWarp branch) — `packages/openwarp`

## what

Package the OpenWarp terminal — a community fork of Warp that opens the
AI layer to any OpenAI-compatible provider — at
`github:zerx-lab/warp#openWarp` (commit b5dd43c at sketch time). Ship as
`packages/openwarp/default.nix`, single binary `warp-oss` (the OSS
channel — automatically selected when `warp-channel-config` isn't on
PATH, see `script/run`).

**Scope this round (minimum viable):**

- `cargo build --release -p warp --bin warp-oss --features gui`
- No AppImage / .deb / .rpm bundle; just the bare binary in `$out/bin`.
- No website/wasm bundle — `crates/serve-wasm` and the bun-driven
  `website/` are excluded from default-members and not needed for the
  terminal binary itself.
- No `prepare_bundled_resources` step. If the binary fails at runtime
  for missing embedded assets, expand scope from there — don't
  pre-emptively port `script/prepare_bundled_resources`.
- Telemetry/Sentry features off; channel config absent (falls back to
  `oss` channel automatically).

**Out of scope this round:** AppImage bundling (linuxdeploy), Sentry
upload, `gcloud` integration tests, internal channel binaries
(`stable`/`dev`/`preview`), website static site, Docker images, voice
input crate (`alsa` is a runtime dep but voice_input is its own
optional surface).

## why

OpenWarp is a real on-host need (zimbatm asked to package it directly)
and aligns with the dogfood mandate: a terminal that pipes through
local-only OpenAI-compatible providers (Ollama, llama-swap on nv1) is
exactly the kind of tool the assise stack wants to validate. nv1 has
the GPU + iGPU split and the local LLM serving infra already
(opencrow-local, llama-swap), so it's a natural fit.

A scout sketch here also seeds the `bun + wasm-bindgen + brotli`
asset-pipeline pattern, which is broadly useful for future Rust+web
hybrid adoptions.

## how-much

Big. Realistically a 2–4 round adopt before it deploys cleanly.

**Build deps (Linux):** `pkg-config cmake protobuf openssl freetype
expat libgit2 fontconfig alsa-lib jq brotli` — most via
`nativeBuildInputs`/`buildInputs`, `protobuf` for `protoc`.

**Runtime deps:** `fontconfig freetype zlib libxkbcommon libxcb libX11
libXi libXcursor libwayland libegl mesa vulkan-loader` — wired into
`runtimeDependencies` or wrapped via `wrapGAppsHook` /
`addAutoPatchelfSearchPath`.

**Toolchain:** `rust-toolchain.toml` pins `1.92.0` — use `fenix` or
`rust-overlay` to get an exact match; the repo's existing inputs don't
have either yet, so this likely needs a **flake input addition** —
that's a denylist hit during a normal grind round and will need to be
landed by hand (cf. `tried/adopt-niri-session.md` precedent).

**Cargo deps:** Use `rustPlatform.importCargoLock { lockFile =
./Cargo.lock; }` — the workspace `Cargo.lock` is checked in.
`outputHashes` will likely be needed for any git-sourced deps; do a
first eval and capture the hashes from the error.

**Patching:**

- `script/install_channel_config` is gcloud-gated and silently skipped
  when gcloud auth is missing — should already work in a sandbox, but
  verify or stub it out.
- `app/build.rs` likely bundles assets — read it before assuming the
  build is hermetic. If it shells out to `script/*`, those scripts
  need patching or the bundling bypassed.
- Disable `default-features` on workspace members that pull in
  cloud/firebase/computer_use surfaces if they break sandboxed builds.

**First eval will fail** — almost certainly on missing system libs
(easy fix), `outputHashes` for git deps (capture from error), or a
build.rs that shells out to a `script/*` (patch or feature-flag off).

## blockers

- **Flake input addition required** (fenix/rust-overlay) for exact
  1.92.0 toolchain. Denylisted in normal grind rounds — must be
  pre-seeded by hand or this stays in `needs-human/` indefinitely.
- Upstream is "early development, no release" — version pin will drift;
  fix to a specific commit, accept manual bumps.
- License is dual AGPL-3.0 / MIT (workspace declares AGPL-3.0-only).
  AGPL is fine for personal use on nv1; flag if any redistribution
  channel surfaces later.

## verify

- Eval: `nix build .#openwarp --dry-run` clean across all 3
  kin-managed hosts (only nv1 needs the binary, but the package should
  at least eval everywhere).
- Build: `nix build .#openwarp -L --log-format bar-with-logs` produces
  `result/bin/warp-oss`.
- Smoke: `result/bin/warp-oss --help` exits 0 (don't try to launch the
  GUI in a headless sandbox).

## next-step if picked

1. Read `app/build.rs` — establish whether the build is hermetic or
   shells out. That decision dominates the rest of the work.
2. If shells out to `script/*` for asset bundling, identify the
   minimal subset and either port to nix or feature-flag-off.
3. Stand up the derivation against a first eval; iterate on system
   libs + `outputHashes` errors.

## round-1 findings

Stood up `packages/openwarp/default.nix` and wired `openwarp = call
./packages/openwarp;` in `flake.nix`. Not in any host closure — the
3-host eval+dry-build gate is unchanged.

**Reached:**

- **`app/build.rs` read (next-step #1) — hermetic on Linux.** Sentry,
  DockTilePlugin, and `script/macos/update_sentry_cocoa` are all
  macOS-only. The Windows/wasm branches don't fire.
  `generate_channel_config_if_needed` short-circuits unless
  `release_bundle` is enabled (it isn't; we build `--features gui`
  only). On `x86_64-unknown-linux-gnu` `add_features` just emits
  `cargo:rustc-cfg` lines — no `script/*` shell-out, no patch needed.
- **Source pinned + hashed.** `fetchFromGitHub` at
  `b5dd43c4c5f21d60fb9be10378268c22cc6d7095`,
  `sha256-9dV1WHoac68KLVdOl/Yl2DQysRoBA937hNcU8VYqGdo=`. No submodules.
- **Cargo.lock vendored locally** (`packages/openwarp/Cargo.lock`,
  ~400 KB). `cargoLock.lockFile = "${src}/Cargo.lock"` would be IFD —
  the no-IFD gate (`nix flake check --no-allow-import-from-derivation`,
  ADR-0011) rejects it. Re-sync on rev bump (see header comment).
- **`outputHashes` captured.** 22 unique git sources in the lock file
  (warpdotdev forks of cosmic-text/font-kit/winit/vte/notify/etc., plus
  servo/core-foundation-rs). Prefetched all 22 with `nix-prefetch-git`;
  importCargoLock dedupes by commit SHA so one hash per repo covers
  every sibling crate.
- **Toolchain: nixpkgs `rustPlatform` as-is.** Upstream pins 1.92.0;
  nixpkgs ships 1.94.x. No fenix/rust-overlay (denylisted lock-write).
  No incompatibility surfaced at eval.
- **Eval + dry-run clean.** `nix eval .#openwarp.drvPath`,
  `nix build .#openwarp --dry-run`, and the full
  `nix flake check --no-build --no-allow-import-from-derivation` all
  pass. iets eval of `nv1` and `web2` toplevels unchanged (only 2
  kin-managed hosts at present).

**Not yet reached:**

- The actual `nix build .#openwarp` did not finish inside the round
  budget. The build was started (per-crate vendor unpacking + the
  `warp` workspace compile, ~1500 crates); it had not failed at time
  of commit. Round 2 should re-run `nix build .#openwarp -L` and chase
  whatever the first compile error is.

**Risks for round 2** (likely first failures, in rough order):

- `clang-sys`/bindgen-driven crates may need
  `rustPlatform.bindgenHook` (`LIBCLANG_PATH`).
- `gettext-sys`, `ort-sys`, `openh264-sys2`, `cfasttext-sys` are in the
  lock file. If they're in the `--features gui` graph they'll need
  `gettext`, ONNX runtime (`ORT_LIB_LOCATION`), `nasm`, and possibly
  vendored fasttext respectively. They may all be feature-gated off —
  cargo only builds the active dependency graph, not the lock file.
- `aws-lc-sys` builds with cmake; covered.
- Any link errors against `wayland`/`xkbcommon`/`vulkan` →
  `runtimeDependencies` / `wrapProgram` with `LD_LIBRARY_PATH`.
- Embedded assets (`rust-embed`) may need the `bun`/`brotli` website
  pipeline; the item already scopes that out — fail loud, expand only
  if the binary panics at startup.
