#!/usr/bin/env bash
# bench-model-swap.sh — falsification harness for adopt-llm-router-model-warm.
#
# Question: is on-demand model swap usable on Meteor Lake shared iGPU
# memory, or does the load latency make MAX_RESIDENT=1 the only sane
# default? Alternates two model targets through llm-router N times so
# every odd request is a cold swap (registry miss -> evict LRU -> spawn
# -> /health). Records first-token latency (TTFB on a streamed request)
# and one intel_gpu_top -J sample per swap.
#
# PASS  post-swap p95 ≤ 5s for the 3.8B, ≤ 1s for the embed model, no
#       OOM at MAX_RESIDENT=2.
# FAIL  post-swap p95 > 10s, or iGPU memory pressure stutters
#       ptt-dictate. Then keep MAX_RESIDENT=1 and document the
#       constraint in llm-router.py's header.
#
# Run on nv1 (Arc iGPU + models in $XDG_DATA_HOME/llama). NOT grind-safe.
#
# usage:  packages/ask-local/bench-model-swap.sh [N] [MODEL_A] [MODEL_B]
#   N        swap pairs (default 20 -> 40 requests)
#   MODEL_A  default Phi-3-mini-4k-instruct-Q4_K_M  (the "3.8B")
#   MODEL_B  default bge-small-en-v1.5-q8_0          (the "embed")
#
# env:
#   BENCH_ROUTER  router base URL (default http://127.0.0.1:8090)
#   LLM_ROUTER_MAX_RESIDENT  set to 1 to force a swap every turn (default
#       behaviour assumed); set to 2 to test coexistence.
set -euo pipefail

N="${1:-20}"
A="${2:-Phi-3-mini-4k-instruct-Q4_K_M}"
B="${3:-bge-small-en-v1.5-q8_0}"
ROUTER="${BENCH_ROUTER:-http://127.0.0.1:8090}"

if ! curl -sf "$ROUTER/v1/models" -o /dev/null 2>/dev/null \
    && ! curl -sf "$ROUTER" -o /dev/null 2>/dev/null; then
  echo "bench-model-swap: no router at $ROUTER — start llm-router first" >&2
  exit 1
fi

igpu_sample() {
  # One intel_gpu_top JSON frame; print "rc6 vram_used" or "- -" if unavailable.
  if ! command -v intel_gpu_top >/dev/null 2>&1; then
    echo "- -"
    return
  fi
  intel_gpu_top -J -s 200 -o - 2>/dev/null | head -c 65536 \
    | python3 -c '
import json, sys
buf = sys.stdin.read()
# intel_gpu_top -J streams concatenated objects; take the first.
dec = json.JSONDecoder()
try:
    obj, _ = dec.raw_decode(buf.lstrip().lstrip("[").lstrip(","))
except Exception:
    print("- -"); raise SystemExit
rc6 = obj.get("rc6", {}).get("value", "-")
mem = "-"
for k in ("vram", "memory", "imc-bandwidth"):
    if k in obj:
        v = obj[k]
        mem = v.get("value", v) if isinstance(v, dict) else v
        break
print(f"{rc6} {mem}")
' 2>/dev/null || echo "- -"
}

ttfb() {
  # Streamed chat completion; %{time_starttransfer} ~= time-to-first-token.
  local model="$1" prompt="$2"
  curl -sS -N -o /dev/null -w '%{time_starttransfer}\n' \
    -X POST "$ROUTER/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c '
import json, sys
print(json.dumps({
    "model": sys.argv[1],
    "stream": True,
    "max_tokens": 32,
    "messages": [{"role": "user", "content": sys.argv[2]}],
}))' "$model" "$prompt")"
}

printf 'i\tmodel\tttfb_s\tswap\trc6\tigpu_mem\n'
swaps=()
prev=""
for ((i = 1; i <= 2 * N; i++)); do
  if ((i % 2)); then m="$A"; else m="$B"; fi
  swap=0
  [[ "$m" != "$prev" && -n "$prev" || $i -eq 1 ]] && swap=1
  t=$(ttfb "$m" "ping $i") || t="nan"
  read -r rc6 mem < <(igpu_sample)
  printf '%d\t%s\t%s\t%d\t%s\t%s\n' "$i" "$m" "$t" "$swap" "$rc6" "$mem"
  ((swap)) && [[ "$t" != "nan" ]] && swaps+=("$t")
  prev="$m"
done

if ((${#swaps[@]})); then
  printf '%s\n' "${swaps[@]}" | python3 -c '
import sys
xs = sorted(float(x) for x in sys.stdin if x.strip())
if not xs:
    raise SystemExit
n = len(xs)
p95 = xs[min(n - 1, int(round(0.95 * (n - 1))))]
verdict = "PASS" if p95 <= 5.0 else ("WATCH" if p95 <= 10.0 else "FAIL")
print(f"\n# post-swap n={n} median={xs[n // 2]:.2f}s p95={p95:.2f}s -> {verdict}",
      file=sys.stderr)
'
fi
