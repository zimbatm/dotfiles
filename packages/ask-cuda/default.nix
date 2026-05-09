{
  pkgs,
  inputs,
  system,
  ...
}:
let
  # Re-import nixpkgs scoped to the 4060's compute capability (Ada = sm_89).
  # Default cudaPackages flags fan out to 9 arches (7.5…12.1), making nvcc
  # do ~9× the work for a single-GPU workstation. Re-import keeps the
  # narrowing local to ask-cuda — the rest of the flake's pkgs is untouched.
  pkgsCuda = import inputs.nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      cudaCapabilities = [ "8.9" ];
    };
  };
  # CUDA build of llama.cpp pinned to cudaPackages_13 (driver on nv1 is
  # 595.58.03 → CUDA 13.2 capable). Sister of ask-local (vulkan/Arc iGPU,
  # Phi-3-mini): this one targets the RTX 4060 dGPU for big-model work.
  llama = pkgsCuda.llama-cpp.override {
    cudaSupport = true;
    cudaPackages = pkgsCuda.cudaPackages_13;
  };
in
pkgs.writeShellApplication {
  name = "ask-cuda";
  runtimeInputs = [
    llama
    pkgs.coreutils
    pkgs.curl
  ];
  text = ''
    # One-shot LLM on the NVIDIA dGPU (CUDA 13). Defaults to Qwen3.6-35B-A3B
    # UD-IQ3_XXS (Unsloth) — MoE 35B/3B-active fits ~13 GB weights + ~1.3 GB
    # KV at 131k q8.
    #   ask-cuda "<prompt>"        → llama-cli completion to stdout
    #   ask-cuda --serve           → llama-server :8089 (OpenAI-compat)
    #
    # Env knobs (all optional):
    #   ASK_CUDA_MODEL  override .gguf path (default: Qwen3.6-35B-A3B UD-IQ3_XXS)
    #   ASK_CUDA_NGL    layers to offload to GPU (default 99 = all dense/shared)
    #   ASK_CUDA_NCMOE  MoE expert layers to keep on CPU (default 40 = all)
    #   ASK_CUDA_CTX    context size (default 8192)
    #   ASK_CUDA_KV     KV cache type (default f16; q8_0 halves KV memory)
    #   ASK_CUDA_N      max tokens to generate (default 256; -1 = until ctx fills)
    #
    # Tuning notes for nv1 (RTX 4060 Mobile, 8 GB) — Qwen3.6-35B-A3B
    # UD-IQ3_XXS, llama.cpp b8770, KV f16, fa on, ctx 4k bench:
    #   ncmoe=40 (default)  → pp 124  tg 2.27 t/s   fits any ctx ≤131k
    #   ncmoe=20            → pp 201  tg 3.74 t/s   ctx ≤~8k (32k OOMs)
    #   ncmoe=19            → pp 182  tg 3.97 t/s   tightest fit, best gen
    #   ncmoe ≤17           → OOM at load
    # Default is safe (any ctx). For interactive coding at small ctx, set
    # ASK_CUDA_NCMOE=20 to ~double generation speed.
    #
    # Stderr is intentionally NOT redirected — llama-cli prints model load
    # info and the timing footer there; pipe `2>/dev/null` at the call site
    # if you want it silent.
    # shellcheck source=/dev/null
    . ${../lib/fetch-model.sh}
    MODEL="''${ASK_CUDA_MODEL:-''${XDG_DATA_HOME:-$HOME/.local/share}/llama/Qwen3.6-35B-A3B-UD-IQ3_XXS.gguf}"
    fetch_model "$MODEL" \
      https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-IQ3_XXS.gguf

    NGL="''${ASK_CUDA_NGL:-99}"
    NCMOE="''${ASK_CUDA_NCMOE:-40}"
    CTX="''${ASK_CUDA_CTX:-8192}"
    KV="''${ASK_CUDA_KV:-f16}"
    N="''${ASK_CUDA_N:-256}"

    common=(
      -m "$MODEL"
      -ngl "$NGL"
      -ncmoe "$NCMOE"
      --ctx-size "$CTX"
      --flash-attn on
      --cache-type-k "$KV"
      --cache-type-v "$KV"
    )

    if [[ "''${1:-}" == "--serve" ]]; then
      exec llama-server "''${common[@]}" -np 1 --host 127.0.0.1 --port 8089
    fi

    # llama.cpp b8770 reworked llama-cli into a chat-only tool: -no-cnv is a
    # non-fatal warning (the chat loop runs regardless) and --no-display-prompt
    # is parsed but never read. Without -st the loop re-prompts on stdin EOF
    # forever once -p is consumed, spewing "\n> " indefinitely — the observed
    # runaway. -st (--single-turn) breaks after the first response; -n caps
    # generation as before.
    exec llama-cli "''${common[@]}" -st -n "$N" -p "$*"
  '';
}
