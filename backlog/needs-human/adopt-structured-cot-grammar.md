# adopt: structured CoT grammar for local coding latency

## Status

Prototype landed — opt-in only, not measured yet. **Remaining work needs nv1
hardware (~13 GB model on the dGPU). DO NOT run from an agent.**

What landed (`grind/adopt-structured-cot-grammar`):

- `packages/ask-cuda/structured-think.gbnf` — GBNF that constrains only the
  `<think>` scratchpad to `GOAL:`/`APPROACH:`/`EDGE:` lines; answer channel
  stays maximally permissive (`.+`). Validated against the llama.cpp parser
  source (`.` → `LLAMA_GRETYPE_CHAR_ANY`, `+` → `handle_repetitions(1,-1)`).
- `packages/ask-cuda/default.nix` — `ask-cuda --structured-think "<p>"` and
  `ASK_CUDA_STRUCTURED_COT=1` knobs append `--grammar-file` to the llama-cli
  call. **`--serve` mode deliberately does NOT pass the grammar** (would
  constrain every client + breaks OpenAI `tools`, llama.cpp #22408) — warns
  on stderr if the env knob is set.
- `packages/ask-cuda/bench-structured-cot.sh` — free-form vs grammar A/B over
  6 fixed coding prompts. Reports wall clock, generated tokens, chars
  before/after `</think>`, and a malformed flag; prints a PASS/WATCH/FAIL
  verdict heuristic.

### Remaining (human, on nv1, after `kin deploy nv1`)

1. `packages/ask-cuda/bench-structured-cot.sh` (and re-run with
   `ASK_CUDA_NCMOE=20` for the interactive-coding tuning).
2. Inspect a couple of grammar-mode transcripts: did the verbosity actually go
   away, or did it move into the answer/comments? The bench's `WATCH` verdict
   catches the gross case but a human should eyeball one or two.
3. If the Qwen3.6 chat template pre-inserts `<think>\n`, the grammar will fail
   to start (cannot re-sample `<`). Drop the leading `"<think>\n"` literal from
   the `think` rule and re-bench (the `.gbnf` header documents this).
4. Decide: keep opt-in / make default for ask-cuda / mirror into ask-local
   (smaller Phi-3 model — may or may not respect `<think>` framing). Update or
   delete this file accordingly.

## What

Try the "Structured CoT" inference-time trick from
<https://andthattoo.dev/blog/structured_cot>: constrain only the model's
`<think>` block with a tiny GBNF grammar, while leaving the answer/code channel
permissive. Related llama.cpp discussion:
<https://github.com/ggml-org/llama.cpp/discussions/22408> notes that
`llama-server` currently rejects OpenAI-style `tools` together with a custom
`grammar` (`HTTP 400: Cannot use custom grammar constraints with tools.`).

Candidate shape for a first coding experiment:

```gbnf
root  ::= think answer
think ::= "<think>\n" "GOAL: " line "APPROACH: " line "EDGE: " line "</think>\n\n"
line  ::= [^\n]+ "\n"
answer ::= [\x09\x0A\x0D\x20-\x7E]+
```

Start as an opt-in `ask-cuda` / `llama.cpp` experiment, not a default. The
current `ask-cuda` Qwen3.6 path is the relevant dogfood target; `ask-local`
already has `--grammar` plumbing and can serve as a smaller-control harness.

## Why

Qwen reasoning models can overthink locally, making interactive use feel slow
and wasting tokens/joules. The blog reports large reductions in explicit
thinking tokens on Qwen3.6 coding evals without pass@1 loss in those runs:

- HumanEval+: ~3087 → 138 mean thinking tokens.
- LiveCodeBench public-test slice: ~11553 → 267 mean thinking tokens, with fewer
  empty/malformed-code failures.

This is interesting for home because `nv1` now has a CUDA `ask-cuda` package for
Qwen3.6-35B-A3B, where latency and runaway reasoning are the main UX limits.

## How much

Prototype and measure before adopting:

1. Add an opt-in structured-thinking grammar file and flag/env knob, e.g.
   `ask-cuda --structured-think` or `ASK_CUDA_STRUCTURED_COT=1`.
2. Keep the answer channel permissive; only force the pre-answer scratchpad.
3. Run a small deterministic harness of coding prompts with free-form vs grammar
   modes. Track:
   - wall-clock latency and generated tokens,
   - tokens before/after `</think>`,
   - malformed/empty output rate,
   - whether comments or answer text absorb the displaced reasoning,
   - pass/fail on simple tests where available.
4. If using `llama-server` / OpenAI-compatible requests, explicitly test the
   tools+grammar interaction from llama.cpp discussion #22408. Current behavior
   is to reject custom grammar when `tools` is present, so clients should either
   disable structured CoT for tool-enabled requests, retry without grammar, or
   encode tool calls in the custom grammar instead of using the native `tools`
   field.
5. If it helps, mirror the option into `ask-local` or document why the smaller
   Phi model cannot use it reliably.

Do not claim a hard reasoning-token budget unless the grammar actually bounds
line length under llama.cpp GBNF; the blog's `line ::= [^\n]+` is shape control,
not a strict token cap.

## Blockers

- `ask-cuda` one-shot mode currently has a separate runaway/non-exit bug in
  `backlog/bug-ask-cuda-oneshot.md`; structured CoT can still be tested through
  `llama-server` or after that is fixed.
- Native `llama-server` tool calls and custom grammars do not compose today
  (discussion #22408). This matters for agent/tool harnesses; plain coding
  prompts without `tools` are unaffected.
- Needs a local benchmark run on `nv1`; no deploy should be run by the agent.
