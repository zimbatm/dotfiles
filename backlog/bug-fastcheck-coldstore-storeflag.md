# bug-fastcheck-coldstore-storeflag — cold-store leg passes a bare path to `--store`

## What

`.claude/grind.config.js` fastCheck leg 3 (cold-store, fires only when
flake.lock is in `origin/main..HEAD`) does:

```sh
iets eval --no-warn --store "$(mktemp -d /tmp/cold-XXXX)" -E "..." -A ...
```

`iets eval --store` takes a store *URI*
(`null:// | local:// | auto | daemon | pending:// | unix:// | tcp:// | ssh-ng://`),
not a bare path. The bare path errors on every iets we have:

- iets@4d7f54b7 (origin/main lock):
  `error: --store /tmp/cold-XXXX: daemon protocol error: unknown store URI` → exit 1
- iets@2e2f827c (post-bump): `iets eval: --store: unrecognized store '/tmp/cold-XXXX'` → exit 2
  (iets@fbcd45d0d4 added a CLI-boundary pre-flight; same outcome, nicer error)

So the cold-store leg has been failing since it was added (dcf394ad,
2026-04-24). The "fastCheck 3-leg green" notes in prior bump commits are
wrong about leg 3 — either the merge gate's `origin/main..HEAD` diff was
empty (leg skipped, falsely reported as green), or the failure was
swallowed.

## Why

The leg's purpose (per the inline comment) is a fresh-store eval so that
freshly-introduced lock-node paths surface as "not realised" instead of
being masked by the warm `~/.cache/iets` and `/nix/store`. That's
**`--store-dir`**, not `--store`. The author conflated the two flags.

## How much

One-line change in `.claude/grind.config.js` fastCheck:

```diff
- --store "$(mktemp -d /tmp/cold-XXXX)"
+ --store-dir "$(mktemp -d /tmp/cold-XXXX)"
```

Then verify `iets eval --no-warn --store-dir /tmp/cold-test -E '1+1'`
exits 0 and `iets eval --no-warn --store-dir /tmp/cold-test -E
'(import <nixpkgs> {}).hello.outPath'` does what the comment claims it
does. If `--store-dir` alone doesn't trigger fresh-store IFD detection
(it may only rewrite output-path prefixes, not gate realisation), the
intent might need `--store local:// --store-dir $tmp` or `--store
pending://` — verify the leg actually catches an unrealised-path eval
before declaring it fixed.

## Blockers

None — single-file `.claude/` change, no host eval surface. Suits a
simplifier or implementer round.

## Notes

Discovered while re-running the cold-store leg for the 2026-05-10
internal bump (iets 4d7f54b7→2e2f827c). The leg fires conditionally on
`git diff --name-only origin/main..HEAD | grep -qx flake.lock` so it's
only exercised at merge-gate time. The bump itself is green on legs 1+2
(flake-check no-ifd + iets warm 2-host).
