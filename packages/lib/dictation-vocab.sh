# shellcheck shell=bash
# Shared decoder-biasing vocabulary helper for the dictation pipeline.
# Sourced by ptt-dictate / transcribe-cpu / transcribe-npu the same way
# fetch-model.sh is. Mines project jargon from sem-grep's existing index so
# whisper.cpp / sherpa-onnx / OpenVINO whisper get the identifiers they would
# otherwise mishear (niri, gsnap, GBNF, machine names, ...).
#
# The corpus you grep feeds the transcriber that feeds the corpus — that
# self-tightening loop is the falsification target. The WER bench is
# human-gated (needs nv1 hardware) — see backlog/needs-human/ops-dictation-
# vocab-bench.md.

# dictation_vocab [N]
#   Print up to N (default 200) bias terms, one per line. Cached per session
#   under $XDG_RUNTIME_DIR (falling back to $XDG_STATE_HOME/dictation, never
#   /tmp) and regenerated when older than 1h or empty. `sem-grep vocab` is
#   bounded with `timeout 5` so a cold model fetch in the sem-grep wrapper can
#   never stall a dictation hotkey. Falls back to a static seed list when
#   sem-grep is unavailable (relay1/web2 don't ship it) or its index is cold,
#   so callers always get something.
dictation_vocab() {
  local n="${1:-200}"
  local cache="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dictation}/dictation-vocab.txt"
  mkdir -p "$(dirname "$cache")"
  local mtime now

  if [[ -s "$cache" ]]; then
    # stat/date over find so the helper only needs coreutils (already in every
    # transcriber's runtimeInputs); findutils would be a new dep on each.
    mtime=$(stat -c %Y "$cache" 2>/dev/null) || mtime=0
    now=$(date +%s)
    if (( now - mtime < 3600 )); then
      head -n "$n" "$cache"
      return 0
    fi
  fi

  if command -v sem-grep >/dev/null 2>&1; then
    timeout -k 2 5 sem-grep vocab --lines --top "$n" 2>/dev/null > "$cache.part" || true
    if [[ -s "$cache.part" ]]; then
      mv "$cache.part" "$cache"
      head -n "$n" "$cache"
      return 0
    fi
    rm -f "$cache.part"
  fi

  # Seed list: hand-curated project nouns the ASR models reliably mangle.
  # Keeps the bias non-empty before sem-grep's first index run and on hosts
  # that don't ship it. Reading the heredoc through head directly (no pipe)
  # avoids a SIGPIPE under `set -o pipefail` when N < the seed count.
  head -n "$n" <<'SEED'
niri
gsnap
pueue
GBNF
sem-grep
ptt-dictate
ask-local
ask-cuda
agent-eyes
infer-queue
wake-listen
live-caption-log
say-back
now-context
shell-squeeze
sel-act
tab-tap
afk-bench
gitbutler
pty-puppet
man-here
nv1
relay1
web2
hcloud
nixpkgs
nixos
flake
sops
agenix
sherpa
parakeet
whisper
OpenVINO
ydotool
pipewire
treesitter
zimbatm
SEED
}
