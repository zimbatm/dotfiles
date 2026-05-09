#!/usr/bin/env bash
# bench-structured-cot.sh — free-form vs structured-CoT A/B for ask-cuda on nv1.
#
# Falsifies: does constraining only the <think> scratchpad to GOAL:/APPROACH:/
# EDGE: lines actually shrink Qwen3.6's reasoning channel without the displaced
# verbosity leaking into the answer/comments? The blog (andthattoo.dev) reports
# ~20-40x fewer thinking tokens on Qwen3.6 coding evals; this checks whether
# that holds on the ask-cuda dGPU path with our quant + chat template.
#
# REQUIRES nv1 hardware (RTX 4060 + the Qwen3.6 GGUF on disk). DO NOT run from
# an agent/CI — it loads a ~13 GB model. Run as Jonas, after deploy, with
# nothing else on the GPU.
#
# Tracks per case × mode:
#   * wall-clock ms
#   * generated-token count (from llama_perf eval line)
#   * chars before/after </think>  (rough proxy for thinking vs answer tokens —
#     proper token counts would need a re-tokenize pass; chars are good enough
#     for the >10x deltas we care about)
#   * malformed flag: missing </think>, empty answer, or grammar-mode output
#     missing GOAL:/APPROACH:/EDGE:
#
# usage:  packages/ask-cuda/bench-structured-cot.sh [N_REPEAT]
#
# Verdict heuristic (printed at the end, human still reads the table):
#   PASS  — median grammar think-chars < 25% of free-form AND grammar
#           malformed-rate ≤ free-form malformed-rate.
#   WATCH — think shrank but answer grew >2x (verbosity displaced, not removed).
#   FAIL  — otherwise.
set -euo pipefail

REPEAT="${1:-2}"
N_TOK="${ASK_CUDA_N:-2048}"   # generous cap so free-form thinking can run long
NCMOE="${ASK_CUDA_NCMOE:-20}" # interactive-coding tuning from default.nix notes

# Fixed coding prompt set. Deterministic-ish targets so a human can eyeball
# correctness; not auto-scored. Keep these short — the interesting variable is
# the *thinking*, not the answer.
PROMPTS=(
  "Write a Python function dedup(xs) that removes duplicates from a list while preserving order. No imports."
  "Write a bash one-liner that prints the 3 largest files (by size) under the current directory."
  "Write a Rust function that returns the nth Fibonacci number iteratively. Handle n=0."
  "Write a Nix expression that maps a list of strings to their lengths using builtins only."
  "Write a SQL query that finds users with more than 5 orders, given tables users(id,name) and orders(id,user_id)."
  "Explain in two sentences why TCP needs a three-way handshake."
)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Pull generated-token count from llama_perf stderr footer. Falls back to "?".
gen_tokens() {
  grep -oE 'eval time =.* / +[0-9]+ runs' "$1" | grep -oE '[0-9]+ runs' | grep -oE '^[0-9]+' || echo "?"
}

# Split stdout on </think>: prints "think_chars answer_chars malformed".
# malformed=1 if </think> missing, answer empty, or (grammar mode) the three
# section labels are absent.
analyze() {
  local out="$1" mode="$2"
  python3 - "$out" "$mode" <<'PY'
import sys
out = open(sys.argv[1], encoding="utf-8", errors="replace").read()
mode = sys.argv[2]
tag = "</think>"
if tag in out:
    think, _, answer = out.partition(tag)
    has_close = True
else:
    think, answer, has_close = out, "", False
think_c, ans_c = len(think.strip()), len(answer.strip())
malformed = 0
if not has_close or ans_c == 0:
    malformed = 1
if mode == "grammar":
    for label in ("GOAL:", "APPROACH:", "EDGE:"):
        if label not in think:
            malformed = 1
print(think_c, ans_c, malformed)
PY
}

run_case() { # $1=mode(free|grammar) $2=prompt-idx
  local mode="$1" idx="$2" prompt="${PROMPTS[$2]}"
  local best_ms="" tok="?" tc=0 ac=0 mal=1
  for ((r = 1; r <= REPEAT; r++)); do
    local t0 t1 ms
    t0=$(date +%s%3N)
    if [[ "$mode" == grammar ]]; then
      ASK_CUDA_N="$N_TOK" ASK_CUDA_NCMOE="$NCMOE" \
        ask-cuda --structured-think "$prompt" >"$tmp/out" 2>"$tmp/err" || true
    else
      ASK_CUDA_N="$N_TOK" ASK_CUDA_NCMOE="$NCMOE" \
        ask-cuda "$prompt" >"$tmp/out" 2>"$tmp/err" || true
    fi
    t1=$(date +%s%3N); ms=$((t1 - t0))
    [[ -z "$best_ms" || "$ms" -lt "$best_ms" ]] && {
      best_ms="$ms"
      tok=$(gen_tokens "$tmp/err")
      read -r tc ac mal <<<"$(analyze "$tmp/out" "$mode")"
    }
  done
  printf '%-8s %2d  %7s  %6s  %7s  %7s  %3s  %s\n' \
    "$mode" "$idx" "${best_ms}ms" "$tok" "$tc" "$ac" "$([[ $mal -eq 1 ]] && echo BAD || echo ok)" \
    "$(printf '%.40s' "$prompt")"
  echo "$mode $idx $best_ms $tok $tc $ac $mal" >>"$tmp/rows"
}

printf '%-8s %2s  %7s  %6s  %7s  %7s  %3s  %s\n' "mode" "#" "wall" "gentok" "think_c" "ans_c" "ok?" "prompt"
printf '%-8s %2s  %7s  %6s  %7s  %7s  %3s  %s\n' "----" "--" "----" "------" "-------" "-----" "---" "------"
: >"$tmp/rows"
for i in "${!PROMPTS[@]}"; do run_case free    "$i"; done
for i in "${!PROMPTS[@]}"; do run_case grammar "$i"; done

echo
awk '
  { t[$1]+=$5; a[$1]+=$6; m[$1]+=$7; n[$1]++ }
  END {
    if (n["free"]==0 || n["grammar"]==0) { print "incomplete run"; exit 1 }
    ft=t["free"]/n["free"]; gt=t["grammar"]/n["grammar"]
    fa=a["free"]/n["free"]; ga=a["grammar"]/n["grammar"]
    fm=m["free"]/n["free"]; gm=m["grammar"]/n["grammar"]
    printf "mean think_c: free=%.0f grammar=%.0f  (%.1f%%)\n", ft, gt, 100*gt/(ft>0?ft:1)
    printf "mean ans_c:   free=%.0f grammar=%.0f  (%.1f%%)\n", fa, ga, 100*ga/(fa>0?fa:1)
    printf "malformed:    free=%.0f%% grammar=%.0f%%\n", 100*fm, 100*gm
    if (gt < 0.25*ft && gm <= fm)        v="PASS — adopt as ask-cuda default? consider mirroring into ask-local"
    else if (gt < ft && ga > 2*fa)       v="WATCH — verbosity displaced into answer, not removed"
    else                                 v="FAIL — keep --structured-think opt-in only"
    print "verdict:", v
  }
' "$tmp/rows"
