# bug: shell-squeeze `kin` shim orphans itself in the agentshell

## What's broken

`packages/shell-squeeze/default.nix` shims `kin` (added 1bf6327, TOON
re-encode axis). The shim prelude strips every PATH dir carrying a
`.shell-squeeze` marker before resolving `command -v kin`:

```sh
PATH="$(IFS=:; o=; for d in $PATH; do [ -e "$d/.shell-squeeze" ] || o="${o:+$o:}$d"; done; printf %s "$o")"
real=$(command -v kin) || { echo "shell-squeeze: kin: not found in PATH" >&2; exit 127; }
```

For `git`/`nix`/`jq`/`find`/`tree` this is fine — there's always a
backing binary elsewhere on PATH. For `kin` there isn't: the *only*
`kin` is `kinOut.packages.<sys>.agentshell`'s `bin/kin`, and the
`flake.nix` `agentshell = symlinkJoin { paths = [ shell-squeeze
kinOut...agentshell ]; ... }` shadows it with the shim (first path
wins). After the shim strips its own dir, `kin` is gone.

Reproduce in a fresh `_base` worktree (no system kin):

```
$ nix build .#agentshell --out-link .claude/profile
$ PATH=".claude/profile/bin:$PATH" kin --version
shell-squeeze: kin: not found in PATH
```

`SHELL_SQUEEZE=0` does **not** bypass it — the bypass `exec "$real"`
is gated on `$real` already being resolved.

## Why it slipped the bench gate

The bench falsifier (`needs-human/adopt-shell-squeeze-toon-emit.md`)
watches for *decode* failures (`jq: error ... is not valid JSON`).
This is an exit-127 *resolution* failure — the shim never reaches the
TOON path. It's silent in any environment that has a second `kin` on
PATH (devshell, deployed nv1), which is everywhere the bench was run.
The grind `_base` worktree on a homespace has no other `kin`.

## How much

~0.1 round. Pick one:

1. **Drop `kin` from the shim list** (simplest, smallest). kin's
   `--json` output (`kin opts`, `kin status`) is tiny compared to
   `nix eval --json` — the TOON win there is marginal and not worth
   breaking the agentshell entrypoint. Update the
   `flake.nix` agentshell comment (currently says `git,nix,find,tree`,
   already stale — also omits `jq`).
2. **Wire the source explicitly.** Have the agentshell `symlinkJoin`
   in `flake.nix` link kin's `bin/kin` to `bin/.kin-real` and have
   the `kin` shim resolve that before falling back to PATH. Keeps the
   TOON re-encode for the bench but adds coupling between
   shell-squeeze (a self-contained package) and the flake's wrap.

(1) is the simplifier's pick; the TOON bench can re-add a hardened
`kin` shim if the `nix`/`jq` wins justify it. Either way the
flake.nix:127 comment listing the shadowed binaries needs updating —
it's drifted from the actual `shell-squeeze` contents twice now.

## Falsifies

After the fix:
```
$ rm -rf .claude/profile && nix build .#agentshell --out-link .claude/profile
$ env -i PATH=".claude/profile/bin:/run/current-system/sw/bin" kin --version
```
must print a version string, not `not found in PATH`.
