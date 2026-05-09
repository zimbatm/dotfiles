# adopt: kin services.llm-adapter (drop local llm-nvidia-adapter)

## what

kin@3012f7da ships `services.llm-adapter` as a builtin — generalized
from `services/llm-nvidia-adapter.nix` here (openai backend, hosted
apiBase, external api-key secret) and kin-infra's ollama variant.
Switch `kin.nix` from `extraServices.llm-nvidia-adapter` to the
builtin:

```nix
services.llm-adapter = {
  on = "nv1";
  backend = "openai";
  apiBase = "https://integrate.api.nvidia.com/v1";
  upstreamModel = "minimaxai/minimax-m2.7";
  model = "claude-nvidia";
  apiKeySecret = true;       # kin set llm-adapter/api-key key
};
```

Then `git rm services/llm-nvidia-adapter.nix`. The gen id moves
`llm-nvidia-adapter/api-key` → `llm-adapter/api-key`; re-set the
NVIDIA key via `kin set llm-adapter/api-key key` (or `mv` the
checked-in `.age` if for-set matches). Any `services.grind.llm =
"llm-nvidia-adapter"` becomes `"llm-adapter"`.

**Requires `flake.lock` bump** to a kin rev ≥ 3012f7da — the builtin
doesn't exist at the current pin.

## why

N≥2 service-promotion gate cleared (kin-infra + this repo); the local
extraService was the second arm that unblocked the lift. Carrying a
private copy means re-stating litellm proxy-extras + drop_params +
hardenedServiceConfig wiring that now ships in kin and gets coverage
+ VM-test there.

## how-much

~10L kin.nix delta + 1 file delete + 1 gen re-key + flake.lock bump.

## falsifies

`curl -fsS http://[::1]:4000/health/liveliness` on nv1 returns
"alive" and a `claude-nvidia` /v1/messages round-trip via the proxy
gets a model response (not 401/404).

## blockers

~~kin input bump to ≥ 3012f7da.~~ **Cleared 2026-05-09** — grind/bump-kin
merged at 1b86152 moved the pin to `303dcb2e`, which has 3012f7da as an
ancestor. `services.llm-adapter` builtin should now be available.

Remaining: secret re-key (`kin set llm-adapter/api-key` OR
`git mv gen/llm-nvidia-adapter/api-key gen/llm-adapter/api-key` if the
recipient set matches — try the mv first; only escalate to needs-human
if `kin gen` rejects it). This is a `kin.nix` change — one-per-round
spine budget applies.
