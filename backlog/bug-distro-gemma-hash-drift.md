# bug: distro gemma-4-E2B FOD hash drift breaks nv1 toplevel build

## What

`nix build .#nixosConfigurations.nv1.config.system.build.toplevel` fails:

```
error: hash mismatch in fixed-output derivation
       '/nix/store/s7dg1njs6kw8q3qp54lqn03ssi2p0mc0-gemma-4-E2B-it-Q4_K_M.gguf.drv':
  specified: sha256-rABp68zTmSXYNvJKiMDwyFjSBXjCmyGrfO3OZu5XaEU=
       got:  sha256-k3i8RxcQIp7xZXCbYuNL+2IjFCDdr21ynnJzBbW4Zy0=
```

This blocks `kin deploy nv1`. **It is NOT caught by the grind gate**
(eval + `nix build --dry-run` both pass — FOD output hashes are only
verified at build time when curl actually fetches the bytes).

## Why

`distro` flake input (`generational-infrastructure/distro` @ 385a9fe9)
pins the model in `modules/nixos/llama-swap.nix:35-37`:

```nix
gemma4-e2b-gguf = pkgs.fetchurl {
  url = "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf";
  hash = "sha256-rABp68zTmSXYNvJKiMDwyFjSBXjCmyGrfO3OZu5XaEU=";
};
```

The URL targets `resolve/main` — a **mutable** Hugging Face ref.
unsloth re-uploaded the GGUF (e.g. a re-quantization) and the bytes
under that URL changed. Confirmed: a 3.0 GB file with the new flat
sha256 (`sha256-k3i8RxcQIp7xZXCbYuNL+2IjFCDdr21ynnJzBbW4Zy0=`) is
already in the homespace store at
`/nix/store/jakmd1zznwjkynvsbw5x5s87f4cb90zf-gemma-4-E2B-it-Q4_K_M.gguf`.
This is not a transient network or substituter problem.

Reaches the toplevel via `services.opencrow-local.enable = true`
(`machines/nv1/configuration.nix:49`) → distro `opencrow.nix` →
distro `llama-swap.nix` → fetchurl → `config.yaml` →
`unit-llama-swap.service` → `system-units` → `etc` → toplevel.

## How much

Small. Two viable fixes, in preference order:

1. **Bump `distro`** if/when upstream fixes the hash or — better —
   pins the URL to an immutable HF revision
   (`resolve/<commit-sha>/…` instead of `resolve/main/…`):
   `nix flake update distro`. Zero local code. This is the real fix
   and the only one that prevents recurrence; the same drift will
   re-bite anyone consuming `distro` until the URL is pinned.
   No `../distro` sibling repo here to cross-file to — open a GitHub
   issue on `generational-infrastructure/distro` with the
   specified/got hashes and the suggested immutable-rev URL.

2. **Local override** (unblock-now, while waiting for upstream): add
   a small `pkgs.fetchurl`-shaped overlay or use
   `nixpkgs.overlays` / `disabledModules`+local module to replace
   `gemma4-e2b-gguf` with the new hash. Keep it next to the
   `services.opencrow-local` block in `machines/nv1/configuration.nix`
   with a `# FIXME(distro): drop once upstream pins HF rev` comment so
   it doesn't outlive the upstream fix.

## Blockers

None for the local override — fully grind-actionable. Verify with
`nix build --no-link .#nixosConfigurations.nv1.config.system.build.toplevel`
(NOT `--dry-run`; the dry-run is a false green here). Deploy stays
human-gated regardless (`ops-deploy-nv1.md`, nv1 not-on-mesh).

## Found

drift @ 3603dcd, 2026-05-10. See `needs-human/ops-deploy-nv1.md`
"drift @ 3603dcd" section for the full chain.
