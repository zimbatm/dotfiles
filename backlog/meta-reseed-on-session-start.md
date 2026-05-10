# meta: self-heal homespace identity on SessionStart, not on grind round 1

Filed 2026-05-10 after the homespace was rebuilt mid-session and the
home grind sat UNPROBEABLE for 2 rounds. Last month the same thing cost
16 rounds before a human noticed (`139c681`). The recovery path exists
but lives only in the kin-infra repo and a sibling Claude's head.

## what happened

A homespace rebuild wipes `~/.ssh/` and `~/.config/`. The home grind's
treeGuard self-heal is

```sh
[[ -f ~/.ssh/kin-bir7vyhu_ed25519 ]] || \
  { [[ -f ~/.ssh/kin-infra_ed25519 ]] && kin login claude --key ~/.ssh/kin-infra_ed25519; } || ...
```

— which depends on `~/.ssh/kin-infra_ed25519` surviving. It doesn't:
`~/.ssh` is ephemeral, only `/root/src/<repo>` is on the persistent
volume. So the self-heal fallback is wiped along with the thing it's
supposed to heal. Single point of failure.

## the actual recovery (works, 2 commands)

`kin-infra` keeps a gitignored copy of the SSH private key at
`keys/users/claude.ssh` (in the repo, on the persistent volume) and a
`keys/reseed.sh` that:

1. restores `~/.config/kin/key → keys/users/claude.key` (age identity)
2. writes `~/.config/hcloud/cli.toml` from `keys/hcloud.token`
3. `install -m 0600 keys/users/claude.ssh ~/.ssh/kin-infra_ed25519`
4. `kin login claude --key ~/.ssh/kin-infra_ed25519`
5. writes `~/.ssh/kin-infra-hosts`

— and runs it from a SessionStart hook so identity is restored before
the first prompt, not on grind round 17. After the kin-infra reseed,
`kin login claude --key ~/.ssh/kin-infra_ed25519` from `home/` writes
the home-fleet user cert to `~/.config/kin/bir7vyhu/`. Same key
(`users.claude.sshKeys` is identical in both fleets), just two cert
chains.

## how much

Two changes, ~30 lines total:

### 1. `keys/reseed.sh` + SessionStart hook

`home/` doesn't need its own copy of the SSH private key — the
kin-infra one is the same key. It needs the *sequence*:

```sh
#!/usr/bin/env bash
# keys/reseed.sh — restore homespace identity after a rebuild.
# Idempotent. Run from .claude/hooks/session-start (or grind treeGuard).
set -euo pipefail
KIN_INFRA_RESEED="${HOME}/src/kin-infra/keys/reseed.sh"
[[ -f "$KIN_INFRA_RESEED" ]] && bash "$KIN_INFRA_RESEED"   # restores ~/.ssh/kin-infra_ed25519
[[ -f ~/.ssh/kin-infra_ed25519 ]] || { echo "reseed: no kin-infra key — see ../kin-infra/keys/reseed.sh" >&2; exit 1; }
mkdir -p ~/.config/kin
[[ -L ~/.config/kin/key ]] || ln -sf "${HOME}/src/kin-infra/keys/users/claude.key" ~/.config/kin/key
nix develop -c kin login claude --key ~/.ssh/kin-infra_ed25519
```

Plus `.claude/settings.json` `hooks.SessionStart` calling it. No
private key material in this repo — it delegates to kin-infra's reseed
for the key and just does the home-fleet `kin login`.

### 2. fix the treeGuard check

`~/.ssh/kin-bir7vyhu_ed25519` is the *old* `kin login` artifact.
Current kin writes the cert at `~/.config/kin/bir7vyhu/cert.pub` and
keeps using `~/.ssh/kin-infra_ed25519` as the bare key. The treeGuard
never sees its success condition so it re-runs `kin login` every round.
Replace with:

```js
treeGuard: `[[ -f ~/.config/kin/bir7vyhu/cert.pub && -f ~/.ssh/kin-infra_ed25519 ]] || \\
  bash keys/reseed.sh >&2 || \\
  echo "treeGuard: home-fleet identity absent and reseed failed — drift will be UNPROBEABLE" >&2`,
```

— check the file `kin login` actually writes, and call the new reseed
script (which is idempotent) instead of inlining the recovery.

## falsifies

The next homespace rebuild should be a non-event: SessionStart reseed
runs, `kin status web2` works on the first try, the grind never sees
UNPROBEABLE. If a rebuild *still* loses identity, the durable copy
(`../kin-infra/keys/users/claude.ssh`) was also lost — that's a
homespace persistence regression, not a home-repo problem; cross-file
to wherever the homespace volume config lives.

## supersedes

`backlog/needs-human/meta-restore-fleet-identity.md` — the "how" half
is now documented. Delete it once this lands. The "needs-human" framing
was wrong: the credential *was* available the whole time, just not where
the treeGuard looked.
