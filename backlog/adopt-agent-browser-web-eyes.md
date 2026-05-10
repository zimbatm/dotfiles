# adopt: agent-browser → web-eyes

## What

Vercel's **agent-browser** (vercel-labs/agent-browser, Rust CLI driving
Chrome via CDP) is now in nixpkgs at our pin — `pkgs.agent-browser`
0.25.4, no flake.lock bump. It exposes `snapshot` (accessibility tree
with element refs — the AI-friendly page representation) and `chat`
(natural-language browser control against any OpenAI-compatible
endpoint).

Mic92's `ai.nix` solves "agents need web access" with `mics-skills`
`browser-cli`. Our angle: ship `packages/web-eyes/` mirroring the shape
`agent-eyes`/`peek` already established for the *desktop* — a
`writeShellApplication` wrapping `pkgs.agent-browser` that:

1. `web-eyes <url>` → `agent-browser open <url> && agent-browser
   snapshot` → prints the accessibility tree to stdout. No daemon, no
   state. Same fire-and-forget as `peek`.
2. `web-eyes <url> --ask "<question>"` → snapshot piped through
   `ask-local` (Arc iGPU llama, port 8088) for a short answer. Mirrors
   `peek --ask` (moondream2 over a screenshot) — same on-device-triage
   gate before deciding whether to ship the page upstream.
3. `web-eyes chat "<instruction>"` → `OPENAI_BASE_URL=http://127.0.0.1:8090/v1
   agent-browser chat …` so the natural-language control loop runs
   through `llm-router`, which decides local-vs-upstream per
   request-shape. This is the genuinely new nv1-LLM thing: a browser
   automation agent whose brain is *routed*, not hardwired.

## Why

The grind scout (this specialist) is currently degraded to
`curl | grep` and unauthenticated GitHub API. This round: `gh search`
failed (no token), label search returned 0 (escaping mismatch),
awesome-nix grep matched mostly noise. A page-snapshot tool with refs
would let the scout actually *survey* (paginate a topic page, follow a
link, read a JS-rendered project README) instead of guessing URL
patterns. And the `chat` mode gives nv1 a daily-driver demo of
local-routed agentic browsing, which is squarely the LLM-future-testbed
mission.

## How much

Small. ~80-line `writeShellApplication` in `packages/web-eyes/`,
pattern-matched from `packages/agent-eyes/default.nix`. Runtime inputs:
`pkgs.agent-browser`, `pkgs.curl`, `pkgs.jq`, `pkgs.coreutils`. Plus
one line in `kin.nix` (or the home-manager module) to put it on nv1.
**No flake.lock change** — `agent-browser` is already at the pin.

One open knot: agent-browser wants Chrome and ships an `install`
subcommand that downloads from Chrome-for-Testing (impure). nixpkgs'
package may already wrap or patch this; if not, set
`AGENT_BROWSER_BROWSER_PATH` (or whatever it reads) to
`${pkgs.chromium}/bin/chromium` inside the wrapper — a one-line env
default, same pattern `peek` uses for `XDG_DATA_HOME/llama`. Check the
nixpkgs derivation first; do not download a browser at runtime.

## Falsifies

- Does the scout's next survey round actually surface anything that
  curl+grep missed? Run web-eyes on the same three sources next round
  and compare the candidate count. If equal, drop it — the bottleneck
  was the brief, not the tool.
- Does `agent-browser chat` through `llm-router` actually route
  short page-action prompts to ask-local? Check
  `$XDG_STATE_HOME/llm-router/decisions.jsonl` after a session. If
  every request goes upstream, the request-shape heuristic doesn't
  cover browser-agent prompts and `llm-router.py` needs another rule —
  which is its own useful finding.
- Does Chromium-on-nv1 fight the Arc iGPU for memory/contention while
  ask-local is resident? `agent-meter --line` before/after a `web-eyes
  --ask` call answers this.
