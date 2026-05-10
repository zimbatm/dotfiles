# adopt: shell-squeeze TOON emit — encode the JSON shims, not just cap them

## What

Add a structured-output filter to `packages/shell-squeeze`: when a shim
detects `--json` in the wrapped command's args (or pipes from `jq`),
re-encode the JSON output as **TOON** (Token-Oriented Object Notation)
before it reaches the agent. ~40-line Python encoder shipped inside the
shell-squeeze closure (`pkgs.python3` is already in agentshell — zero
new inputs, zero flake.lock delta). Encoder handles the two shapes that
matter:

- arrays of homogeneous objects → `key[N]{f1,f2}: \n  v1,v2\n  ...`
  (~30-50 % token cut on tabular data per the spec's own numbers)
- nested objects → key-folded paths (smaller win, ~10 %)
- anything else → pass through unchanged (the encoder must be a strict
  no-op outside the two shapes, never a lossy approximation)

A trailing `[shell-squeeze: TOON-encoded — append --raw or
SHELL_SQUEEZE=0 for plain JSON]` hint keeps the escape hatch visible,
matching the existing `_capl` pattern.

## Why (seed → our angle)

Seed: **`toon-format/toon-rust`** (in numtide/llm-agents.nix since
2026-04). Spec-compliant Rust crate + CLI for TOON v3.0 — a format
designed specifically to cut LLM-prompt token spend on structured data.

Prior scout (356c258) noted toon as "format-only, fold into
shell-squeeze if bench passes" but never filed the bench plan. This is
the bench plan.

Our angle: shell-squeeze today does *line-capping and flag-defaulting* —
it stops `git log` and `find` from flooding context. It does nothing
about *encoding density*. The grind subagents run `nix eval --json`,
`kin opts ... --json`, and `jq` pipelines constantly; that output is
JSON, which is the format TOON was designed to replace. Adding the
encoding layer is the orthogonal second axis on the same problem.

Also original: don't vendor toon-rust (190 KB Rust crate, needs
cargoHash + buildRustPackage, heavyweight for an unproven win). Write
the 80 % case — homogeneous arrays + key-folding — in Python that
shell-squeeze already closes over. If the bench passes and the Python
encoder turns out to be the bottleneck, *then* vendor the crate.

## How much

~0.3 round.
- `packages/shell-squeeze/toon-emit.py` (~40 lines: `json.load` →
  shape-detect → encode-or-passthrough)
- Extend the `nix`, `kin`, `jq` shims (or add them) to pipe through
  `toon-emit.py` when `--json` is in args
- Bench harness: `agent-meter` already records per-round token counts
  in `refs/notes/tokens`; record 5 rounds with TOON, 5 without

## Falsifies

Median per-round token delta on the JSON-emitting shim subset over 5
grind rounds:

- **≥ 10 % drop with zero round-trip-decode failures** → keep, and
  consider upstreaming the pattern into kin's agentshell wrap.
- **< 10 %** → wontfix with the measured number. The TOON spec's
  headline savings come from large homogeneous arrays; if the grind's
  actual `nix eval`/`kin opts` output is dominated by deeply nested
  one-off objects, TOON gains evaporate. That's a real result worth
  recording — it tells the next scout that token compression for this
  workload lives in line-capping, not encoding.
- **Any decode failure** (a downstream tool tries to `jq` the TOON
  output and chokes) → immediate revert. The shim must be transparent
  to anything that explicitly asks for JSON; if shape-detection can't
  guarantee that, the whole approach is wrong.

## Notes

The `toon` CLI from llm-agents.nix could be used as a *reference
oracle* in the test (encode same input both ways, diff token counts) —
but only via `nix run github:numtide/llm-agents.nix#toon` as a one-off
in a bench script, never as a flake input (denylist).

## Status: implemented — bench-watch (needs-human)

Landed on `grind/adopt-shell-squeeze-toon-emit` (base `3603dcd`):

- `packages/shell-squeeze/toon-emit.py` — stdlib-only encoder, two
  shapes + strict pass-through; quotes scalars containing `,:\n"{}[]`;
  refuses to "win" if the TOON form is not strictly smaller than the
  input (guards against flat/noisy shapes that fold worse than JSON).
- `packages/shell-squeeze/default.nix` — `_toon` helper in the prelude;
  `nix --json` (eval and friends), new `kin` and `jq` shims pipe through
  it. Guarded by `[ -p /dev/stdout ]`: when stdout is a pipe (i.e.
  `nix eval --json | jq ...`), the shim execs the real binary unwrapped
  so downstream JSON consumers never see TOON. Verified the agent
  capture context presents fd 1 as a regular file, not a FIFO, so the
  encode still fires for the leaf-call case that matters.
- Hint emitted to stderr only when the encoder actually rewrote.

### Bench plan (needs-human / next 10 rounds)

`agent-meter` already records per-round token counts under
`refs/notes/tokens`. After this branch merges and `nv1`/`web2` redeploy
agentshell:

1. Let the next 5 grind rounds run with the TOON shims live (default).
2. Run 5 more with `SHELL_SQUEEZE=0` exported in the round wrapper (or
   the `agentshell` env) to disable the encode while keeping line caps.
3. Compare `med_billable` across the two windows on roles that touch
   `nix eval --json` / `kin opts --json` / `jq` (drift, bumper, scout):
   - ≥ 10 % drop, zero decode failures in round logs → keep + file
     `../kin/backlog/adopt-agentshell-toon.md` to upstream.
   - < 10 % → revert shims, move this file to `wontfix/` with the
     measured number.
   - any `jq: error ... is not valid JSON` traced to a shim → immediate
     revert (the `[ -p /dev/stdout ]` guard failed somewhere).

Until then this stays in `needs-human/` so triage doesn't re-pick it.
