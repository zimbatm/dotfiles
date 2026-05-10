{ pkgs, ... }:
# web-eyes — agent-browser wrapper, the "browser counterpart" to agent-eyes/peek.
#
# Why it exists: the grind scout is currently degraded to `curl | grep` —
# unauthenticated GitHub API, brittle regex on HTML. agent-browser
# (vercel-labs, Rust CLI driving Chrome via CDP, in nixpkgs at our pin)
# exposes `snapshot` (accessibility tree with @ref handles — the AI-friendly
# page representation) and `chat` (NL browser control against an
# OpenAI-compatible endpoint). Wrapping it here mirrors the peek/poke shape:
# fire-and-forget, no daemon, on-device triage gate before shipping anything
# upstream.
#
#   web-eyes <url>                  → open + snapshot, accessibility tree on stdout
#   web-eyes <url> --ask "<q>"      → snapshot piped through ask-local (Arc iGPU,
#                                     port 8088) for a short answer — same
#                                     local-triage gate peek --ask uses for pixels
#   web-eyes chat "<instruction>"   → agent-browser chat through llm-router
#                                     (port 8090) so per-request routing
#                                     local-vs-upstream applies to browser actions
#
# Knots resolved (verified against the 0.25.4 binary, not the README):
#   - Browser path: nixpkgs' agent-browser does NOT wrap or patch the Chrome
#     lookup — left alone it tries Chrome-for-Testing download (impure). The
#     binary reads AGENT_BROWSER_EXECUTABLE_PATH; default it to pkgs.chromium
#     so the wrapper never downloads a browser at runtime.
#   - chat endpoint: the binary reads AI_GATEWAY_URL / AI_GATEWAY_API_KEY,
#     not OPENAI_BASE_URL. Default the URL to llm-router and the key to a
#     placeholder (llm-router ignores it; upstream routes carry their own).
#   - ask-local is NOT a runtimeInput — call it from PATH so the dependency
#     stays soft (peek-style). Falls over with a clear error if missing.
pkgs.writeShellApplication {
  name = "web-eyes";
  runtimeInputs = [
    pkgs.agent-browser
    pkgs.chromium
    pkgs.curl
    pkgs.jq
    pkgs.coreutils
  ];
  text = ''
        export AGENT_BROWSER_EXECUTABLE_PATH="''${AGENT_BROWSER_EXECUTABLE_PATH:-${pkgs.chromium}/bin/chromium}"

        usage() {
          echo "usage: web-eyes <url> [--ask <question>]" >&2
          echo "       web-eyes chat <instruction>" >&2
          exit 1
        }

        [[ $# -ge 1 ]] || usage

        if [[ "$1" == "chat" ]]; then
          shift
          [[ $# -ge 1 ]] || usage
          # Route the NL control loop through llm-router so request-shape decides
          # local-vs-upstream per turn. Falsifier: check
          # $XDG_STATE_HOME/llm-router/decisions.jsonl after a session — if every
          # browser-action prompt goes upstream, llm-router needs another rule.
          export AI_GATEWAY_URL="''${AI_GATEWAY_URL:-http://127.0.0.1:8090/v1}"
          export AI_GATEWAY_API_KEY="''${AI_GATEWAY_API_KEY:-llm-router}"
          exec agent-browser chat "$@"
        fi

        url="$1"; shift
        ask=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --ask) ask="''${2:?--ask needs a question}"; shift 2 ;;
            *)     echo "web-eyes: unknown arg: $1" >&2; usage ;;
          esac
        done

        agent-browser open "$url" >/dev/null
        snap=$(agent-browser snapshot)
        # Best-effort cleanup of the headless session; ignore failures.
        agent-browser close >/dev/null 2>&1 || true

        if [[ -z "$ask" ]]; then
          printf '%s\n' "$snap"
          exit 0
        fi

        command -v ask-local >/dev/null 2>&1 || {
          echo "web-eyes: --ask needs ask-local on PATH (Arc iGPU triage, port 8088)" >&2
          exit 1
        }
        exec ask-local "Page accessibility snapshot of ''${url}:

    $snap

    Question: $ask
    Answer briefly using only the snapshot above."
  '';
}
