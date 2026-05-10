#!/usr/bin/env bash
# keys/reseed.sh — restore home-fleet (bir7vyhu) identity after a homespace rebuild.
#
# A rebuild wipes ~/.ssh and ~/.config but leaves /root/src/<repo> on the
# persistent volume. The durable copy of the SSH key lives in kin-infra
# (keys/users/claude.ssh, gitignored) and its keys/reseed.sh restores it to
# ~/.ssh/kin-infra_ed25519. We delegate to that, then run `kin login` from
# *this* repo to mint the home-fleet cert chain under ~/.config/kin/bir7vyhu/.
#
# Idempotent. Run from a SessionStart hook or the grind treeGuard.
# No private key material lives in this repo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

KIN_INFRA="${HOME}/src/kin-infra"
KIN_INFRA_RESEED="${KIN_INFRA}/keys/reseed.sh"

if [[ ! -f "$KIN_INFRA_RESEED" ]]; then
  echo "reseed: ${KIN_INFRA_RESEED} not found — kin-infra not checked out, cannot restore identity" >&2
  exit 1
fi

# Delegates: restores ~/.ssh/kin-infra_ed25519, ~/.config/kin/key, hcloud token,
# kin-infra fleet cert. See ../kin-infra/keys/reseed.sh for the full sequence.
bash "$KIN_INFRA_RESEED"

if [[ ! -f "${HOME}/.ssh/kin-infra_ed25519" ]]; then
  echo "reseed: ~/.ssh/kin-infra_ed25519 still absent after kin-infra reseed — see ${KIN_INFRA_RESEED}" >&2
  exit 1
fi

# Age identity (kin set / decrypt). kin-infra's reseed already symlinks this,
# but be defensive in case it's run standalone or the layout drifts.
mkdir -p "${HOME}/.config/kin"
if [[ ! -e "${HOME}/.config/kin/key" ]]; then
  ln -sf "${KIN_INFRA}/keys/users/claude.key" "${HOME}/.config/kin/key"
fi

# Mint the home-fleet (bir7vyhu) user cert chain. Same SSH key as kin-infra
# (users.claude.sshKeys is identical in both fleets) — just a second cert.
# Writes ~/.config/kin/bir7vyhu/{cert.pub,ssh-config,...}.
nix develop -c kin login claude --key "${HOME}/.ssh/kin-infra_ed25519"
