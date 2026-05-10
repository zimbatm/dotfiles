export const meta = {
  name: 'home-grind',
  description: 'Dogfood-repo grind: drift-check, simplify, bump inputs, scout external tooling; gate = all hosts eval+build',
  whenToUse: 'When the user wants autonomous progress on the home fleet config',
  phases: [
    { title: 'Triage', detail: 'pick items; drift-check first if stale' },
    { title: 'Work', detail: 'implementers + 1 rotating specialist' },
    { title: 'Merge', detail: 'serialized; eval + dry-build all hosts' },
    { title: 'Meta', detail: 'audit; deploy-reminder if hosts changed' },
  ],
}

const HOSTS = ['nv1', 'web2']

const CONFIG = {
  name: 'home',
  implementers: 2,
  archCadence: 6,
  // drift is the work-generator (declared-vs-deployed); weight it 3× so
  // backlog refills faster than implementers drain (meta-roster p51).
  rotation: ['drift', 'simplifier', 'drift', 'bumper', 'drift', 'scout'],
  // Self-heal fleet identity. users.claude is enrolled with the soft key
  // ~/.ssh/kin-infra_ed25519 (kin.nix:28) — no hardware key needed. Homespace
  // state loss drops kin-bir7vyhu_* ~monthly; 16 rounds sat UNPROBEABLE on a
  // false hardware-key gate before this was found.
  treeGuard: `[[ -f ~/.ssh/kin-bir7vyhu_ed25519 ]] || \\
  { [[ -f ~/.ssh/kin-infra_ed25519 ]] && kin login claude --key ~/.ssh/kin-infra_ed25519 >&2; } || \\
  echo "treeGuard: home-fleet identity absent, self-heal key missing — drift will be UNPROBEABLE" >&2`,
  // checks.x86_64-linux = {fmt, nv1, web2}; --no-build = eval-only (dry-build parity).
  // ~21s vs ~23s for the old per-host loop — single process shares the nixpkgs import.
  // iets step: `kin deploy` evals via iets which bans IFD (ADR-0011 → IETS-0025); plain
  // nix allows it, so flake check alone green-lights changes that break deploy
  // (hit 2026-04-13: cp.run-crops → crane mkDummySrc). iets is in devShell.extraPackages,
  // not agentshell PATH — hence `nix develop -c`. Multi -A shares one root parse.
  // ~/.cache/iets cleared before each call: the attr-cache is NOT keyed on
  // flake.lock and returns stale outPaths across bumps (observed r4 @22bbd1c;
  // cross-filed ../iets/backlog/bug-attrcache-stale-flake-shim.md). Every run
  // is cold-cache (~+42s). Correctness > speed here.
  // outPath (not drvPath): bumper reports these hashes in commit msgs for drift's
  // per-commit closure bisect, which compares outPath. Since kin@053a8092 the
  // flake-shim synthesises lastModifiedDate/shortRev, so iets-via-flake-shim
  // outPaths match `nix eval .#…outPath` — both paths are deploy-authoritative.
  // Entrypoint: kin@8b24bfd5 evaluator.py bootstraps from flake.lock so fleets
  // needn't ship a default.nix; here we mirror that by resolving the locked kin
  // source via getFlake (cheap — input fetch only, no outputs eval) and feeding
  // its lib/flake-shim.nix to `iets eval -E`. Keeps --no-warn/multi-A that
  // `iets-compat iets-flake eval` lacks.
  // No cold-store leg. dcf394ad added one (`--store "$(mktemp -d)"`) to catch
  // warm-store-masked unrealised paths (IETS-0033 fileset.toSource, IFD/0025)
  // on flake.lock-touching rounds, but it never ran: `--store` takes a URI
  // (null:// | local:// | …), not a path — exit 2 on every iets we've shipped.
  // The intended flag is `--store-dir <path>`, and a fresh dir *does* gate
  // realisation (readFile (path {…}) → IETS-0025). It also empties the FOD
  // short-circuit the flake-shim bootstrap depends on: every locked input
  // becomes "not in store-dir" → fetchTarball → 404 on private kin/iets repos.
  // No `--store`/`--store-dir`/`--allowed-path` combo gets past that without
  // also re-warming the store, so the leg can't both be cold and resolve the
  // shim — dropped rather than left perma-red on bump rounds. Coverage today:
  // leg 2's default null:// store already throws IETS-0025/0033 for any path
  // not present in /nix/store; the residual gap (path *is* in /nix/store from
  // a prior local build but won't be on the deploy target) only `kin deploy`
  // itself can probe.
  fastCheck:
    'nix flake check --no-build --no-allow-import-from-derivation && ' +
    'KIN=$(nix eval --raw --impure --expr \'(builtins.getFlake (toString ./.)).inputs.kin.outPath\') && ' +
    'rm -rf ~/.cache/iets && nix develop -c iets eval --no-warn -E "import $KIN/lib/flake-shim.nix ./." ' +
    HOSTS.map(h => `-A nixosConfigurations.${h}.config.system.build.toplevel.outPath`).join(' '),

  triageExtra: () => `
   **kin.nix is the spine** — at most 1 pick per round that touches it.
   ops-* items (deploy, kin set) are human-in-the-loop; mark "needs-human"
   instead of picking.
   **\`backlog/bump-*\` is the flake.lock-write prefix** — any item whose
   how-much needs \`nix flake lock\` (new input, \`inputs.*.follows\`, drop
   input) must be filed/renamed \`bump-*\` or it hits the merge denylist.
   Don't route lock-touching work to a non-bump slot.`,

  mergeGate: () => ({
    needsGate: true,
    cmd: CONFIG.fastCheck,
    instructions: `All ${HOSTS.length} hosts must eval and dry-build clean. If a host
fails, the change broke that machine's config — abandon, don't partially merge.`,
  }),

  metaExtra: () => `
If any \`machines/\` or \`kin.nix\` was touched this round, remind: changes
are committed but NOT deployed. \`kin deploy <machine>\` to actually
apply (with the deploy-safety check from feedback_deploy_safety.md).`,

  specialists: {
    drift: ctx => `${ctx.BASE_SETUP}
You are the DRIFT-CHECKER. Compare what's declared vs what's deployed.

**Skip-guard (run FIRST):**
\`LAST=$(git log -1 --format=%H --grep='^drift @' origin/main)\`; if set and
\`git diff --name-only $LAST..origin/main -- '*.nix' kin.nix gen/ flake.lock\`
is empty, commit \`drift @ <sha>: skip — zero .nix-delta since $LAST\` and
return immediately — nothing to re-inspect.

For each host in ${HOSTS.join(' ')}: \`kin status <host>\` (or
\`ssh <host> readlink /run/current-system\` vs the local toplevel).
File backlog/drift-<host>.md for any mismatch with the diff and a
proposed reconciliation (usually: just deploy, but flag if deployed
state has something declared doesn't).

Also check: are external flake.lock inputs (nixpkgs, home-manager, srvos,
nixos-hardware, nix-index-database, nixvim) >7 days stale? File
backlog/bump-*. Internal inputs (kin/iets/nix-skills/llm-agents) are the
bumper's job every round — don't flag those here.
${ctx.MAIN_GUARD}`,

    simplifier: ctx => `${ctx.BASE_SETUP}
You are the SIMPLIFIER. This is a 38-line kin.nix + ~1500 LoC total —
keep it that way.

**Skip-guard (run FIRST):**
\`LAST=$(git log -1 --format=%H --grep='^simplifier @' origin/main)\`; if set and
\`git diff --name-only $LAST..origin/main -- '*.nix' kin.nix gen/\`
is empty, commit \`simplifier @ <sha>: skip — zero .nix-delta since $LAST\` and
return immediately — nothing to re-sweep.

- modules/ files not imported by any host → delete
- commented-out config (zerotier, tailscale leftovers) → delete
- inputs in flake.nix not referenced → drop + relock
- per-host config that's identical across hosts → lift to common.nix
${ctx.MAIN_GUARD}`,

    bumper: ctx => `${ctx.BASE_SETUP}
You are the BUMPER. You own flake.lock — version bumps, new inputs,
\`inputs.*.follows\` dedupe, dropped inputs. Anything that must run
\`nix flake lock\` is your remit (the merge gate denies flake.lock
writes from any non-\`bump-*\` pick). Three phases.

**Phase 1 — internal inputs (every round, all together):**
\`nix flake update kin iets nix-skills llm-agents\`, then fastCheck.
Green → commit \`bump: internal (kin/iets/nix-skills/llm-agents)\`.
Red → \`git checkout flake.lock\` and cross-file the regression to the
offending sibling's backlog/ (../kin, ../iets, ../nix-skills) per the
CLAUDE.md cross-dispatch recipe — add+commit+push+verify in that repo.

**Phase 2 — external inputs (one per round, oldest-first):**
Pick the single oldest-locked input from {nixpkgs, home-manager, srvos,
nixos-hardware, nix-index-database, nixvim}. \`nix flake update <it>\`,
then fastCheck. Green → commit \`bump: <input>\`. Red → investigate
(changelog, error) and either fix or file backlog/bump-<input>-blocked.md
with the reason, then \`git checkout flake.lock\`.

**Phase 3 — lock-adjacent backlog (at most one per round):**
\`ls backlog/bump-*.md\` for items beyond plain version bumps — adding a
new input, \`inputs.*.follows\` dedupe, dropping an unused input. Pick
one, apply the flake.nix change, \`nix flake lock\`, fastCheck, commit
\`bump: <slug>\`, \`git rm\` the backlog file. Red → revert and annotate
the item with the failure. Skip if none or if Phase 1/2 already went red.
${ctx.MAIN_GUARD}`,

    scout: ctx => `${ctx.BASE_SETUP}
You are the SCOUT. Survey the outside world for LLM/agent tooling worth
trying on nv1 (the LLM-future testbed) and file backlog/adopt-* sketches.

Sources (curl via Bash; no WebSearch tool here):
- \`curl -sL https://raw.githubusercontent.com/Mic92/dotfiles/main/home-manager/modules/ai.nix\`
- \`curl -sL https://raw.githubusercontent.com/nix-community/awesome-nix/master/README.md | grep -iA1 'llm\\|whisper\\|voice\\|agent'\`
- \`gh search prs --repo nixos/nixpkgs --label '6.topic: AI/ML' --merged --limit 20 --json title,url 2>/dev/null\`

For each promising find: file \`backlog/adopt-<slug>.md\` (what / why /
how-much / falsifies). Frame as "X does Y; here's our angle on the same
problem" — Jonas wants original work, not verbatim copies. Skip anything
already in backlog/, tried/, or wontfix/. Max 2 filings per round.
${ctx.MAIN_GUARD}`,
  },
}
