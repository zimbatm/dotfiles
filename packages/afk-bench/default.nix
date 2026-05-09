{ pkgs, ... }:
let
  infer-queue = pkgs.callPackage ../infer-queue { };
  now-context = pkgs.callPackage ../now-context { };
  seed = ./benches.json;
in
pkgs.writeShellApplication {
  name = "afk-bench";
  runtimeInputs = [
    pkgs.jq
    pkgs.coreutils
    pkgs.pueue # for `pueue kill <id>` — infer-queue exposes no kill verb yet
    infer-queue
    now-context
  ];
  text = ''
    # Opportunistic local-inference bench drain. nv1's accelerator benches are
    # all parked behind "needs nv1 hardware, DO NOT run from an agent" — but
    # the hardware idles ~16 h/day. This drain runs from a 30-min user timer:
    # if Jonas is AFK and no real arc/npu work is queued, submit the
    # oldest-stale bench from the seed manifest (./benches.json) into
    # infer-queue with a hard timeout, append the verdict to results.jsonl,
    # and update last_run. A 60s poll yields the device the moment .afk flips.
    #
    # *Measuring* needs the hardware; *interpreting* still needs a human —
    # results.jsonl just accumulates. Bench scripts run from $AFK_BENCH_REPO
    # (default ~/src/home), not the store, so they exercise the live tree.
    #
    # Falsification gate (backlog/needs-human after deploy): if 3× same-bench
    # σ/μ of wall-clock > 20% across AFK windows, an unattended desktop is not
    # a controlled bench environment and this lane downgrades to smoke-test.

    state="''${XDG_STATE_HOME:-$HOME/.local/state}/afk-bench"
    repo="''${AFK_BENCH_REPO:-$HOME/src/home}"
    mkdir -p "$state/raw"

    log() { printf 'afk-bench: %s\n' "$*" >&2; }

    # 1. AFK gate. now-context degrades to {"error":...} → .afk null → not AFK.
    afk=$(now-context 2>/dev/null | jq -r '.afk // false' 2>/dev/null || echo false)
    [[ "$afk" == "true" ]] || { log "not AFK; nothing to do"; exit 0; }

    # 2. Lane busy gate. Never pile a bench on real arc/npu work. pueue's
    # status enum is a string in 2.x and a tagged object in 3.x — handle both.
    busy=$(infer-queue status --json 2>/dev/null | jq -r '
      [(.tasks // {})[] | select(.group=="arc" or .group=="npu")
       | (.status | if type=="object" then keys[0] else . end)]
      | any(. == "Running" or . == "Queued")' 2>/dev/null || echo true)
    [[ "$busy" == "false" ]] || { log "arc/npu lane busy; yielding"; exit 0; }

    # 3. Merge state with seed: seed is authoritative for which benches exist
    # (benches added/removed in the repo show up next run); state carries
    # last_run forward so the rotation survives rebuilds.
    manifest="$state/benches.json"
    [[ -f "$manifest" ]] || echo '[]' > "$manifest"
    jq -n --slurpfile seed "${seed}" --slurpfile st "$manifest" '
      ($st[0] | INDEX(.name)) as $S
      | $seed[0] | map(.last_run = ($S[.name].last_run // .last_run))' \
      > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"

    # Pick oldest-stale across the lanes infer-queue actually has (arc/npu/cpu).
    # cuda entries stay manifest-documented but parked until infer-queue grows
    # a cuda lane (and the dGPU is confirmed not vfio-bound).
    pick=$(jq -c '[.[] | select(.lane | IN("arc","npu","cpu"))]
      | sort_by(.last_run // "") | .[0] // empty' "$manifest")
    [[ -n "$pick" ]] || { log "no runnable bench in manifest"; exit 0; }
    name=$(jq -r .name <<<"$pick"); lane=$(jq -r .lane <<<"$pick")
    path=$(jq -r .path <<<"$pick"); max_wall=$(jq -r '.max_wall // 600' <<<"$pick")
    mapfile -t args < <(jq -r '.args[]?' <<<"$pick")

    mark_run() { # $1=verdict $2=wall_s $3=raw_path
      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      jq -cn --arg ts "$ts" --arg b "$name" --arg l "$lane" \
        --argjson w "$2" --arg v "$1" --arg r "$3" \
        '{ts:$ts,bench:$b,lane:$l,wall_s:$w,verdict:$v,raw_path:$r}' \
        >> "$state/results.jsonl"
      jq --arg n "$name" --arg ts "$ts" \
        'map(if .name==$n then .last_run=$ts else . end)' "$manifest" \
        > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
    }

    if [[ ! -f "$repo/$path" ]]; then
      log "missing $repo/$path; recording skip"; mark_run "missing" 0 ""; exit 0
    fi

    # 4. Submit through infer-queue (1-slot accelerator lanes, device tagging)
    # with a hard wall — benches must be bounded.
    t0=$(date +%s)
    raw="$state/raw/$(date -u +%Y%m%dT%H%M%SZ)-$name.log"
    out=$(infer-queue add --lane "$lane" -- timeout "$max_wall" \
            bash "$repo/$path" "''${args[@]}" 2>&1) || {
      log "infer-queue add failed: $out"; mark_run "submit-failed" 0 ""; exit 0
    }
    tid=$(grep -oE '[0-9]+' <<<"$out" | tail -1 || true)
    [[ -n "$tid" ]] || { log "could not parse task id from: $out"; exit 0; }
    log "queued $name (task $tid, lane $lane, wall ''${max_wall}s)"

    # 6. Yield on un-AFK: a 60s poll kills the bench the moment Jonas is back.
    # The user owning the device is a hard constraint, not a nicety.
    yielded=false
    while :; do
      st=$(infer-queue status --json 2>/dev/null | jq -r --arg id "$tid" '
        .tasks[$id].status // "gone"
        | if type=="object" then keys[0] else . end' 2>/dev/null || echo gone)
      [[ "$st" == "Running" || "$st" == "Queued" ]] || break
      sleep 60
      afk=$(now-context 2>/dev/null | jq -r '.afk // false' 2>/dev/null || echo false)
      if [[ "$afk" != "true" ]]; then
        log "un-AFK; killing task $tid"
        pueue kill "$tid" >/dev/null 2>&1 || true
        yielded=true
      fi
    done

    # 5. Record. Snapshot the pueue log before clean/age-out can drop it.
    wall=$(( $(date +%s) - t0 ))
    infer-queue log "$tid" > "$raw" 2>&1 || true
    if [[ "$yielded" == "true" ]]; then
      verdict="yielded"
    else
      verdict=$(infer-queue status --json 2>/dev/null | jq -r --arg id "$tid" '
        .tasks[$id].status
        | if type=="object" and has("Done")
          then (.Done.result // .Done | if type=="object" then keys[0] else . end)
          elif type=="object" then keys[0] else (. // "unknown") end
        | ascii_downcase' 2>/dev/null || echo unknown)
    fi
    mark_run "$verdict" "$wall" "$raw"
    log "$name: $verdict in ''${wall}s → $raw"
  '';
}
