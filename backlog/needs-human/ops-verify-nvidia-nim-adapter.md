# ops: deploy and verify NVIDIA NIM adapter on nv1

## what

`services.llm-adapter` is declared on nv1 and the encrypted API key is set. Human-deploy nv1, then verify the LiteLLM adapter exposes NVIDIA NIM as an Anthropic-shaped endpoint.

Do **not** paste the API key into logs/backlog.

## why

The implementation is safe to eval/dry-build, but runtime validation needs the live nv1 machine and a human-gated deploy. The adapter is mesh-only on port 4000 and publishes `apiShape = "anthropic"`, making it suitable for later `services.grind.llm = "llm-adapter"` or manual Claude Code probes.

## human steps

From a reviewed tree, deploy nv1 manually:

```sh
kin deploy nv1
```

Then on/against nv1:

```sh
systemctl status kin-llm-adapter.service --no-pager -l
journalctl -u kin-llm-adapter.service --no-pager -n 80
curl -s http://[fd0c:3964:8cda::6e42:b995:2026:deae]:4000/health/liveliness
```

Probe Anthropic-compatible inference with the local published model name (`claude-nvidia`). Example body shape:

```sh
curl -s http://[fd0c:3964:8cda::6e42:b995:2026:deae]:4000/v1/messages \
  -H 'content-type: application/json' \
  -H 'x-api-key: sk-local' \
  -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"claude-nvidia","max_tokens":32,"messages":[{"role":"user","content":"Say hello in one sentence."}]}'
```

If that works, optionally test a low-risk agent session by setting:

```sh
export ANTHROPIC_BASE_URL='http://[fd0c:3964:8cda::6e42:b995:2026:deae]:4000'
export ANTHROPIC_AUTH_TOKEN=local
export ANTHROPIC_MODEL=claude-nvidia
```

## close when

- `kin-llm-adapter.service` is active on nv1.
- `/health/liveliness` returns alive.
- `/v1/messages` returns a small model response via NVIDIA NIM.
- No plaintext NVIDIA key appears in git, logs, or the Nix store.
- kin builtin `services.llm-adapter` adopted (was local `services/llm-nvidia-adapter.nix`).
