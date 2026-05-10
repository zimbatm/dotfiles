# CLAUDE.md: stale "all 3 kin-managed hosts" gate description

## What

`CLAUDE.md:49` (the `/grind` section) still says:

> Gate: all 3 kin-managed hosts eval + dry-build.

The fleet is 2 hosts since `dc78daf` removed `relay1`
(2026-05-09; `kin.nix` `machines = { nv1 web2 }`,
`README.md` machine table already updated to 2 rows,
`.claude/commands/grind.md:8` already says "every host").
CLAUDE.md is the only repo doc still carrying the hardcoded `3`.

## Why

CLAUDE.md is the agent-facing spine doc — every grind specialist
reads it. A stale host count here is the same class of leftover as
the post-VFIO comments swept in `simplify-stale-vfio-comments.md`:
mechanically harmless (the gate scripts don't parse this sentence)
but actively misinforms the reader about fleet shape.

## How much

1 word. Replace `all 3 kin-managed hosts` with `all kin-managed hosts`
— drop the count entirely so the line never goes stale on the next
add/remove. Matches `.claude/commands/grind.md:8` ("every host")
which already takes the count-free form.

## Gate

Doc-only — no eval/build impact. `git grep -n '3 kin-managed'` should
return nothing after.

## Blockers

None. CLAUDE.md is also a "spine" file per its own conventions —
fold into a round that's already touching it, or do as a standalone
1-line commit; either is fine.
