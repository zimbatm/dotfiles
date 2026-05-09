# simplify: drop stale VFIO comments left after 7bdd14f

## What

Two comment lines still describe the RTX 4060 as VFIO-reserved, but
`7bdd14f nv1: drop CROPS vfio passthrough, enable NVIDIA driver for CUDA`
removed `modules/nixos/vfio-host.nix` and switched nv1 to PRIME offload
for CUDA. The accurate description already exists at
`machines/nv1/configuration.nix:26-29`.

- `machines/nv1/configuration.nix:12`
  `# GPU: Intel Arc for display, NVIDIA reserved for VFIO passthrough`
  → delete the line (line 11's hardware id is still accurate; the GPU
  topology is documented correctly 14 lines down).
- `packages/sel-act/default.nix:29`
  `# ... or revisit the vfio-reserved 4060.`
  → reword to `# ... or revisit the 4060 dGPU (PRIME offload).`

## Why

The nv1 imports block is the first thing read when building a mental model
of that host's GPU setup; "reserved for VFIO passthrough" is now the
opposite of reality. Leaving stale comments is exactly the kind of drift
the simplifier exists to catch.

## How much

2 lines changed across 2 files. Comment-only; no eval/build delta.
Gate: `nix flake check` passes (trivially).

## Blockers

None.
