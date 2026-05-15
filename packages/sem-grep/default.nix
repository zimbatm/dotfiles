{ pkgs, ... }:
let
  # Subset of transcribe-npu's closure (openvino+numpy+transformers) — no new
  # python deps land on nv1. sqlite3 is stdlib. tree-sitter is for the `sig`
  # verb's signature extraction at index time (zero new flake inputs).
  py = pkgs.python3.withPackages (ps: [
    ps.openvino
    ps.numpy
    ps.transformers
    ps.tree-sitter
  ]);
  # withPlugins emits a dir of <lang>.so → grammar parser; sem-grep.py loads
  # them via ctypes. Covers the local source trees we index by default.
  grammars = pkgs.tree-sitter.withPlugins (g: [
    g.tree-sitter-nix
    g.tree-sitter-python
    g.tree-sitter-bash
    g.tree-sitter-rust
  ]);
in
pkgs.writeShellApplication {
  name = "sem-grep";
  runtimeInputs = [
    py
    pkgs.git
    pkgs.coreutils
    pkgs.systemd # journalctl for `index-log`
  ];
  text = ''
    # Semantic grep over local repos. Index: git-tracked text in
    # ~/src/{home,meta} by default → chunked → sqlite+blob (dense) +
    # contentless FTS5 (lexical) at $XDG_STATE_HOME/sem-grep. Query: by default
    # both legs are run and RRF-fused — dense (bge-small cosine on the Meteor
    # Lake NPU) catches paraphrase, lexical (BM25, pure sqlite) catches exact
    # identifiers. Reuses transcribe-npu's OpenVINO closure so
    # the Arc iGPU stays free for ask-local.
    #
    #   sem-grep "<query>"            → ranked file:line hits (top 10, hybrid)
    #   sem-grep -n 20 "<query>"      → top N
    #   sem-grep --mode dense   "..." → cosine only (original path)
    #   sem-grep --mode lexical "..." → BM25 only (no NPU, exact identifiers)
    #   sem-grep --mode hybrid  "..." → RRF-fused (default)
    #   sem-grep -r "<query>"         → rerank candidate pool with bge-reranker
    #   sem-grep sig "<query>"        → ranked file:line  signature (treesitter)
    #   sem-grep index                → (re)build; incremental on git blob-sha
    #   sem-grep hist "<query>"       → ranked shell-history (hist-sem alias)
    #   sem-grep log "<query>"        → ranked journald lines (7d, hour-deduped)
    #   sem-grep index-log            → (re)build the journald index (nightly)
    #
    # Model: bge-small-en-v1.5 OpenVINO IR (~130 MB, 384-dim) under XDG_DATA_HOME.
    # Rerank model (opt-in, -r): bge-reranker-base OpenVINO IR (~280 MB fp16).
    MODEL="''${SEM_GREP_MODEL:-''${XDG_DATA_HOME:-$HOME/.local/share}/openvino/bge-small-en-v1.5}"
    RERANK_MODEL="''${SEM_GREP_RERANK_MODEL:-''${XDG_DATA_HOME:-$HOME/.local/share}/openvino/bge-reranker-base}"
    DEVICE="''${SEM_GREP_DEVICE:-NPU}"
    STATE="''${SEM_GREP_STATE:-''${XDG_STATE_HOME:-$HOME/.local/state}/sem-grep}"
    REPOS="''${SEM_GREP_REPOS:-$HOME/src/home:$HOME/src/meta}"

    # shellcheck source=/dev/null
    . ${../lib/fetch-model.sh}
    # huggingface-cli is on PATH via transformers → huggingface-hub in `py`.
    fetch_hf_repo "$MODEL" OpenVINO/bge-small-en-v1.5-fp16-ov

    # reranker is opt-in: only fetch when -r/--rerank requested
    for a in "$@"; do
      if [[ "$a" == "-r" || "$a" == "--rerank" ]]; then
        fetch_hf_repo "$RERANK_MODEL" OpenVINO/bge-reranker-base-fp16-ov
        break
      fi
    done

    export SEM_GREP_MODEL="$MODEL" SEM_GREP_RERANK_MODEL="$RERANK_MODEL" \
           SEM_GREP_DEVICE="$DEVICE" SEM_GREP_STATE="$STATE" \
           SEM_GREP_REPOS="$REPOS" SEM_GREP_GRAMMARS="${grammars}"
    exec python3 ${./sem-grep.py} "$@"
  '';
}
