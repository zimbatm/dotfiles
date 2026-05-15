{ pkgs, ... }:
# Terse-by-default PATH shims for the noisiest grind-subagent commands.
# Each shim falls through to the next-in-PATH binary on any explicit
# output-shaping flag, so deliberate calls are unchanged. Prepended only
# via the .#agentshell wrap (flake.nix) — interactive zsh on nv1 never
# sees these.
#
# Dispatch: every shim-bearing bin/ dir carries a `.shell-squeeze` marker.
# The prelude rebuilds PATH without marked dirs, so (a) the shim resolves
# the real binary via plain lookup regardless of symlinkJoin / out-link
# layering, and (b) any *downstream* wrapper that itself walks PATH
# (homespace's /root/code/config/remote/bin/nix is one) can't loop back
# into us. No hardcoded store paths — respects whatever git/nix the env
# actually provides.
#
# Two axes:
#   1. line/byte capping  — git log, find, tree, raw nix eval (volume)
#   2. TOON re-encoding   — nix --json, jq                 (density)
# Axis 2 ships `toon-emit.py` (stdlib python3, already in agentshell's
# closure). Strict pass-through outside two safe shapes; only fires when
# stdout is *not* a pipe so `nix eval --json | jq` style cascades keep
# real JSON, and only when SHELL_SQUEEZE!=0 like everything else.
#
# Bench: refs/notes/tokens 5-round comparison vs the pre-shim baseline
# recorded in the adopting commit. ≥15% drop in any non-META role's
# med_billable with zero truncation-attributable gate failures → upstream
# the pattern to a dedicated agentshell wrapper. Otherwise revert
# (shims are theatre).
# TOON axis has its own 5-round window (see backlog item).
let
  toonEmit = ./toon-emit.py;
  prelude = name: ''
    PATH="$(IFS=:; o=; for d in $PATH; do [ -e "$d/.shell-squeeze" ] || o="''${o:+$o:}$d"; done; printf %s "$o")"
    real=$(command -v ${name}) || { echo "shell-squeeze: ${name}: not found in PATH" >&2; exit 127; }
    [ "''${SHELL_SQUEEZE-1}" = 0 ] && exec "$real" "$@"
    _has() {
      local pat="$1" a; shift
      for a in "$@"; do case "$a" in $pat) return 0;; esac; done
      return 1
    }
    _capl() {
      ${pkgs.gawk}/bin/awk -v n="$1" -v h="$2" \
        'NR<=n; END{if(NR>n) printf "[shell-squeeze: +%d lines elided — %s, or SHELL_SQUEEZE=0 to bypass]\n", NR-n, h >"/dev/stderr"}'
    }
    # TOON re-encode — only when stdout is not a pipe (a downstream tool
    # that explicitly asked for JSON must keep getting JSON). The encoder
    # is itself a strict pass-through outside its two shapes and prints
    # the escape-hatch hint to stderr only when it actually rewrote.
    _toon() {
      if [ -p /dev/stdout ]; then exec "$real" "$@"; fi
      "$real" "$@" | ${pkgs.python3}/bin/python3 ${toonEmit}
      exit "''${PIPESTATUS[0]}"
    }
  '';
  shim = name: body: pkgs.writeShellScriptBin name (prelude name + body);

  git = shim "git" ''
    pre=()
    while [ $# -gt 0 ]; do
      case "$1" in
        -C|-c|--git-dir|--work-tree|--namespace|--config-env)
          pre+=("$1" "$2"); shift 2 ;;
        --git-dir=*|--work-tree=*|--namespace=*|--config-env=*|--exec-path=*|\
        -p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--no-optional-locks|\
        --literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-advice)
          pre+=("$1"); shift ;;
        *) break ;;
      esac
    done
    if [ "''${1-}" = log ]; then
      shift
      if ! { _has '-p' "$@" || _has '-u' "$@" || _has '--patch*' "$@" \
          || _has '--stat*' "$@" || _has '--numstat' "$@" || _has '--shortstat' "$@" \
          || _has '--oneline' "$@" || _has '--pretty*' "$@" || _has '--format*' "$@" \
          || _has '-n*' "$@" || _has '--max-count*' "$@" || _has '-[0-9]*' "$@"; }; then
        exec "$real" "''${pre[@]}" log --oneline -n 40 "$@"
      fi
      exec "$real" "''${pre[@]}" log "$@"
    fi
    exec "$real" "''${pre[@]}" "$@"
  '';

  nix = shim "nix" ''
    if [ "''${1-}" = eval ] && ! { _has '--json' "$@" || _has '--raw' "$@"; }; then
      "$real" "$@" | {
        ${pkgs.coreutils}/bin/head -c 4096
        rest=$(${pkgs.coreutils}/bin/wc -c)
        [ "$rest" -gt 0 ] && printf '\n[shell-squeeze: +%s bytes elided — add --json/--raw, or SHELL_SQUEEZE=0 to bypass]\n' "$rest" >&2
      }
      exit "''${PIPESTATUS[0]}"
    fi
    if _has '--json' "$@" && ! _has '--raw' "$@"; then _toon "$@"; fi
    exec "$real" "$@"
  '';

  jq = shim "jq" ''
    # -r/-j/-a leave JSON; --arg/--rawfile/etc. are inputs, not output shape.
    if ! { _has '-r' "$@" || _has '--raw-output' "$@" || _has '-j' "$@" \
        || _has '--join-output' "$@" || _has '-a' "$@" || _has '--ascii-output' "$@"; }; then
      _toon "$@"
    fi
    exec "$real" "$@"
  '';

  find = shim "find" ''
    # Actions with side effects or explicit depth → never interpose.
    if _has '-maxdepth' "$@" || _has '-mindepth' "$@" \
       || _has '-exec' "$@" || _has '-execdir' "$@" || _has '-ok' "$@" || _has '-okdir' "$@" \
       || _has '-delete' "$@" || _has '-fprint*' "$@" || _has '-fls' "$@"; then
      exec "$real" "$@"
    fi
    pre=(); paths=()
    while [ $# -gt 0 ]; do
      case "$1" in -H|-L|-P|-O?|-D) pre+=("$1"); shift ;; -D*) pre+=("$1"); shift ;; *) break ;; esac
    done
    while [ $# -gt 0 ]; do
      case "$1" in -*|'('|')'|'!'|,) break ;; *) paths+=("$1"); shift ;; esac
    done
    "$real" "''${pre[@]}" "''${paths[@]}" -maxdepth 4 "$@" | _capl 200 'add explicit -maxdepth N'
    exit "''${PIPESTATUS[0]}"
  '';

  tree = shim "tree" ''
    _has '-L' "$@" && exec "$real" "$@"
    exec "$real" -L 3 "$@"
  '';
in
pkgs.symlinkJoin {
  name = "shell-squeeze";
  paths = [
    git
    nix
    jq
    find
    tree
  ];
  postBuild = "touch $out/bin/.shell-squeeze";
}
