{ pkgs, ... }:
let
  ask-local = pkgs.callPackage ../ask-local { };
in
pkgs.writeShellApplication {
  name = "sel-act";
  runtimeInputs = [
    ask-local
    pkgs.wl-clipboard
    pkgs.ydotool
    pkgs.zenity
    pkgs.yq-go
    pkgs.jq
    pkgs.coreutils
    pkgs.libnotify
  ];
  text = ''
    # Text dual of ptt-dictate: grab the wayland primary selection (or
    # clipboard on --clip), run a named transform from
    # $XDG_CONFIG_HOME/sel-act/prompts.toml through ask-local, then
    # wl-copy the result (or `ydotool type` it back on --replace).
    #
    #   sel-act <verb> [--clip] [--replace]
    #   sel-act ask    [--clip] [--replace]   → prompt from `zenity --entry`
    #
    # Same [section].prompt TOML shape as ptt-dictate's intent table so
    # the two grow together. Falsifies: Phi-3-mini on the Arc iGPU is
    # fast enough (<2s/paragraph) for *interactive* text edits — if not,
    # route through llm-router or revisit the 4060 dGPU (PRIME offload).
    CFG="''${XDG_CONFIG_HOME:-$HOME/.config}/sel-act/prompts.toml"

    src=--primary replace=0 verb=""
    for a in "$@"; do
      case "$a" in
        --clip) src= ;;
        --replace) replace=1 ;;
        -*) echo "sel-act: unknown flag $a" >&2; exit 2 ;;
        *) verb="$a" ;;
      esac
    done
    [[ -n "$verb" ]] || { echo "usage: sel-act <verb|ask> [--clip] [--replace]" >&2; exit 2; }

    # shellcheck disable=SC2086  # $src is intentionally empty-or-one-flag
    SEL=$(wl-paste --no-newline $src 2>/dev/null || true)
    [[ -n "$SEL" ]] || { notify-send -t 2000 "sel-act" "no selection"; exit 0; }

    if [[ "$verb" == ask ]]; then
      PROMPT=$(zenity --entry --title "sel-act" --text "Prompt for selection:") || exit 0
    else
      PROMPT=$(yq -p toml -o json "$CFG" 2>/dev/null \
        | jq -r --arg v "$verb" '.[$v].prompt // empty' 2>/dev/null) || PROMPT=""
      [[ -n "$PROMPT" ]] || { notify-send -t 3000 "sel-act" "no [$verb] in $CFG"; exit 1; }
    fi

    OUT=$(ask-local "$(printf '%s\n\n---\n%s' "$PROMPT" "$SEL")")
    [[ -n "$OUT" ]] || exit 0

    if [[ $replace -eq 1 ]]; then
      printf %s "$OUT" | ydotool type --file -
    else
      printf %s "$OUT" | wl-copy
      notify-send -t 2000 "sel-act $verb" "→ clipboard"
    fi
  '';
}
