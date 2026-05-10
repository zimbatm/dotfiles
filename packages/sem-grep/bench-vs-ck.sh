#!/usr/bin/env bash
# Head-to-head bench: is sem-grep's NPU dense embedder load-bearing?
# Three legs over bench-refs.txt (20 hand-checked symbol queries):
#   A  sem-grep --mode dense    bge-small on NPU   (current default body leg)
#   B  sem-grep --mode lexical  FTS5 BM25, no NPU  (sem-grep.py:_fts_backfill floor)
#   C  ck --hybrid              BM25 + bundled CPU ONNX (llm-agents flake input, pinned to lock rev)
# Scores file-level recall@5. Run on nv1 only; see backlog/needs-human/adopt-ck-bench-npu-embed.md.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REFS="$HERE/bench-refs.txt"
ck_rev=$(nix eval --raw --impure --expr '(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.llm-agents.locked.rev')
MODEL="${SEM_GREP_MODEL:-${XDG_DATA_HOME:-$HOME/.local/share}/openvino/bge-small-en-v1.5}"
IFS=: read -ra DIRS <<<"${SEM_GREP_REPOS:-$HOME/src/home:$HOME/src/kin:$HOME/src/iets:$HOME/src/maille:$HOME/src/meta}"

# Fail loudly off-nv1: this bench needs the live NPU + fetched bge-small IR + index.db.
[[ -e /dev/accel/accel0 ]]            || { echo "FATAL: no NPU (/dev/accel/accel0) — run on nv1, not in CI." >&2; exit 1; }
[[ -f "$MODEL/openvino_model.xml" ]]  || { echo "FATAL: bge-small IR absent at $MODEL — 'sem-grep index' on nv1 first." >&2; exit 1; }
command -v sem-grep >/dev/null         || { echo "FATAL: sem-grep not on PATH." >&2; exit 1; }

# norm: lines → "repo/sub/path" (drop ~/src/ prefix, score, :line), order-preserving dedupe.
norm() { grep -oE '(~/src/|/root/src/|\./)?(home|kin|iets|maille|meta)/[A-Za-z0-9_./-]+' | sed -E 's#^(~/src/|/root/src/|\./)##; s#:[0-9].*$##' | awk '!s[$0]++'; }
# recall@5 of expected files (space-sep, file-level) against top-5 hit files on stdin.
r5() { local exp="$1" hits; hits=$(norm | head -5); local n=0 t=0
  for e in $exp; do t=$((t+1)); grep -qxF "${e%%:*}" <<<"$hits" && n=$((n+1)); done
  awk -v n="$n" -v t="$t" 'BEGIN{printf "%.3f", t? n/t : 0}'; }

declare -A SUM=([A]=0 [B]=0 [C]=0); Q=0
printf '%-22s %7s %7s %7s\n' query dense lexical ck-hybrid
while IFS=$'\t' read -r q exp; do
  [[ "$q" =~ ^#|^$ ]] && continue; Q=$((Q+1))
  a=$(sem-grep query -n 5 --mode dense   "$q" 2>/dev/null | r5 "$exp")
  b=$(sem-grep query -n 5 --mode lexical "$q" 2>/dev/null | r5 "$exp")
  c=$(nix run "github:numtide/llm-agents.nix?rev=${ck_rev}#ck" -- --hybrid --top-k 5 "$q" "${DIRS[@]}" 2>/dev/null | r5 "$exp")
  printf '%-22s %7s %7s %7s\n' "$q" "$a" "$b" "$c"
  SUM[A]=$(awk -v x="${SUM[A]}" -v y="$a" 'BEGIN{print x+y}'); SUM[B]=$(awk -v x="${SUM[B]}" -v y="$b" 'BEGIN{print x+y}'); SUM[C]=$(awk -v x="${SUM[C]}" -v y="$c" 'BEGIN{print x+y}')
done <"$REFS"
mean() { awk -v s="${SUM[$1]}" -v q="$Q" 'BEGIN{printf "%.3f", q? s/q : 0}'; }
printf '%-22s %7s %7s %7s   (n=%d)\n' "mean recall@5" "$(mean A)" "$(mean B)" "$(mean C)" "$Q"
cat <<'EOF'

Falsification thresholds (from backlog/adopt-ck-bench-npu-embed.md, verbatim):
- ck-hybrid >= sem-grep-dense - 0.05  ->  file simplify-sem-grep-body-embedder.md
  (swap to CPU ONNX, drop OpenVINO from sem-grep's body leg; measure closure delta).
- sem-grep-dense > ck-hybrid + 0.10 AND sem-grep-dense > sem-grep-lexical + 0.10
  ->  keep as-is, record margin in bench-log.txt, mark this question answered.
- sem-grep-dense ~= sem-grep-lexical  ->  drop the body dense leg entirely;
  the FTS path is sufficient for the grind's query shape.
EOF
