# nv1: deploy + walk deferred runtime checks

**What:** Run `kin deploy nv1` from a mesh-connected machine, then walk
the deferred runtime checks below.

**Blockers:** Human-gated (CLAUDE.md). Worker identity RESTORED
(kin-bir7vyhu @ 139c681 self-heal) but nv1 reports `not-on-mesh` —
desktop offline or off the maille mesh from this homespace. `kin ssh
nv1` fails (mesh ULA fd0c:…deae unroutable); gen/ssh `ProxyJump
root@95.216.188.155` also fails (proxy leg matches literal IP not `Host
relay1` stanza, so kin-bir7vyhu cert doesn't apply). HAVE unprobeable
for mesh-reachability not identity.

**⚠ Off-main `have`:** nv1 has been deployed from a dirty/off-branch
tree **twice** (d2ad1d1: `gfcs7jg5` matched no origin/main eval;
53bed8f: `sxmv9yvi` again off-main). **Confirm any intentional local
delta on nv1 is committed+pushed before `kin deploy nv1` overwrites
it.** relay1+web2 were both human-deployed Apr-24 20:06 @ fcc6b68-tip
but nv1 was NOT in that batch (off-mesh from homespace) — if Jonas
deployed nv1 locally at the same time it'd be at 77dfr1xn; otherwise
sxmv9yvi carry-forward stays suspect.

## Latest status (drift @ 6753fd8, 2026-05-09)

```
have: ???  (not-on-mesh — relay1 FULLY DOWN, no ProxyJump leg)
want: /nix/store/mbw1f3pr…-nixos-system-nv1-26.05.20260505.549bd84
```

Want progression since fcc6b68 (Apr-24): 77dfr1xn → 1mdzqizi (e960caf) →
n5smybmw (671f35b) → zi5as60q (e3c1cea) → 8l90l7hx (8231b3d) → qjdsdd97
(23975b3) → rsb8r0kg (9def97e) → 53s3xn5k (cce49ee) → isgj6yg9 (80a9212)
→ mbw1f3pr (6753fd8). Dry-build 542 drvs / 1279 fetch / 4.4 GiB.
Last confirmed have==want on origin/main: `www09p3bx` @ 9403a95
(≈ e196255 deploy, 2026-04-11). nv1 unprobeable since — relay1 ProxyJump
leg dead (`ops-relay1-recover.md`).

## Reconcile

```sh
kin deploy nv1
```

Then walk the runtime checks. Then delete this file.

## nv1-affecting commits since e196255 (cumulative bisect log, compacted 2026-04-24)

| commit | what | scope |
|---|---|---|
| c9491bc | desktop: 4 llm-agents pkgs → nixpkgs | nv1 |
| d90e847 | kin/iets/nix-skills/llm-agents bump + gen/ regen | all |
| f4398c4 | transcribe-npu pkg + ptt-dictate NPU-prefer | nv1 |
| 6f87665 | flake.lock follows-dedupe 30→19 nodes | all |
| 3a891ab | agent-eyes: peek --ask moondream2 VLM | nv1 |
| 7d092c5 | kin/iets internal bump | all |
| b1f1bb3 | nix-index-database bump | all |
| f7eaa19 | +treefmt-nix input + formatter/checks | all |
| eea133f | now-context --clip (wl-clipboard fold) | nv1 |
| 325a1bc | wake-listen pkg + user unit, NPU-gated | nv1 |
| 0d2890f | kin/iets internal bump | all |
| 0a84820 | srvos bump f56f105→7983ea7 | all |
| cb57e80 | modules/home self'=self.packages binding | nv1 |
| eb82a38 | ptt-dictate --intent (GBNF→intents.toml) | nv1 |
| 0ce69c5 | **Niri as 2nd GDM session** (modules/nixos/niri.nix) | nv1 |
| 3ae52ac | kin/iets internal bump | nv1+web2 |
| 51cb90c | home-manager bump e35c39f→f6196e5 | nv1 |
| e23db0f | sem-grep pkg (NPU bge-small over assise repos) | nv1 |
| d4e1fea | +crops-demo flake input (lock 19→32) | nv1+web2 |
| fc83166 | **crops-demo userland** (vfio-host + 7 CLIs, gated) | nv1 |
| 0d0321d | coord-panes pkg + agentshell wire | nv1 |
| ffef511 | live-caption-log pkg + hm module (off-by-default) | nv1 |
| dc59a67 | kin/iets internal bump | nv1+web2 |
| 1a5519c d60c257 | man-here pkg + skill | nv1 |
| 3b08f00 821a88e | tab-tap pkg + Firefox native-messaging | nv1 |
| 9b55b4e | kin/iets bump | all |
| c03a8a8 | nixvim bump | nv1 |
| 7cb19d4 | dconf `<Super>Return`→ghostty (fix hm registry wipe) | nv1 |
| 7d300c5 | foot default terminal; `<Super>Return`→foot | nv1 |
| 007ccaa | users.claude.sshKeys rotate + gen/ re-sign | all |
| dacd1ec | crops.nix: drop run-crops (crane IFD) | nv1 |
| c170da0 | packages/nvim: enableMan=false (eval -19%) | nv1 |
| 1201785 | gsnap compositor-aware (portal/grim) + per-session baselines | nv1 |
| f2c38c8 | kin/iets/nix-skills/llm-agents bump | all |
| 2419f94 | sel-act pkg + `<Super>a` keybind | nv1 |
| 107acef | sem-grep `hist` verb + bash feeder | nv1 |
| 082a29f | iets bump 396eb90→ef58583 | nv1+web2 |
| b016581 | home-manager bump f6196e5→8a423e4 | nv1 |
| 65e3984 | kin/iets/llm-agents/nixvim bump | nv1+web2 |
| 0251202 | niri: fonts += font-awesome+nerd-symbols+noto-emoji | nv1 |
| 396d2de | live-caption enable on nv1 (+retentionDays, +CLI) | nv1 |
| 35c8232 | common.nix: cache.assise.systems substituter | nv1+web2 |
| a603e7c | home-manager bump 8a423e4→3c7524c | nv1 |
| 94cf5c6 | wake-listen+transcribe-npu: ship models as FODs | nv1 |
| 2243fd1 | transcribe-npu: TRANSFORMERS_OFFLINE=1 HF_HUB_OFFLINE=1 | nv1 |
| 0580584 | wake-listen: silero-vad v5.1→v4.0; +StartLimitBurst | nv1 |
| e969d2c | wake-listen: res[p_out].item() ([1,1] output) | nv1 |
| 02441a9 | live-caption-log: stop swallowing errors + heartbeat | nv1 |
| e4d45cd | kin/iets/nix-skills/llm-agents bump (incl maille→b849d73) | all |
| 85d68cd | ask-local --fast (llama-lookup speculative + bench.sh) | nv1 |
| 2194b90 | sem-grep -r/--rerank (bge-reranker-base NPU stage-2) | nv1 |
| 07b2b2f | ask-local --agent (bounded ReAct loop, tools.json) | nv1 |
| 99e9212 | sem-grep log/index-log + modules/home/desktop/sem-grep.nix | nv1 |
| dd5677f | ask-local --agent {args} guard + kin-hosts split | nv1 |
| b0b4acd | common.nix: +ca-derivations experimental-feature | all |
| 0319657 | kin gen — per-host certs/fps + tls-ca regen | all |
| cdd1904 | ask-local: mkdir -p before model-not-found check | nv1 |
| 61459a1 | deepfilter noise cancellation (hm module + nv1 enable) | nv1 |
| 497ddec | iets pkg → nv1 home.packages + iets flake.lock bump | nv1 |
| 6759648 | model-autofetch: shared fetch_model helper, auto-fetch on first run | nv1 |
| 11edb95 | maille bump b849d73→156486c peer_fleets cap | all |
| fa68a27 | **nixpkgs 4c1018d→4bd9165** + gitbutler-cli cargoPatches | all |
| 4a60b42 | internal bump kin→e736801 + iets/nix-skills/llm-agents + gen re-sign | all |
| cadfc52 | kin.nix identity.peers.kin-infra + mesh.peerFleets + gen/peers/ | all |
| 8bde140 | packages/lib/fetch-model.sh HF-repo-id validate | nv1 |
| 4ec63e0 | ask-local --diff-gate + llm-router /review + terminal hooks | nv1 |
| 92d2cd8 | sem-grep `sig` verb tree-sitter signature index | nv1 |
| 483fadb | internal bump kin→df0a4b2 + iets/llm-agents | nv1+web2 |
| 69f7bb4 | META keep-6 of 5858216 (hm/iets/kin/llm-agents/maille/nixvim) | all |
| e98e1c5 | **drop crops-demo input** — vendor vfio-host, crops.enable=false | nv1 |
| 3092054 | vfio-host original: +pciIds +pciAddr +amdgpu softdep | nv1 |
| c7939f0 | iets bump 714989b→d6739fad | nv1+web2 |
| b7ea207 | iets bump →68367fb0 + nixfmt→iets-fmt swap | nv1+web2 |
| 608e987 | **nixpkgs 4bd9165→b12141e** | all |
| 206cf2d | internal bump kin→3118eb1d + gen attest keys + drop pin-nixpkgs | all |
| f1e5fca | nix-index-db bedba598→c43246d4 | nv1 |
| 0e4dd69 eb6794c | sem-grep `refs` verb + ask-local `--mem` + sem-grep `runs` | nv1 |
| d7d1096 | iets bump e4098058→e1cd6980 | nv1+web2 |
| c10990b | ask-local owner-only perms 0o700/0o600 | nv1 |
| 7e6e5d5 | terminal +tuicr (TUI diff review) | nv1 |
| b657104 | kin 3118eb1d→7d4c7bfd netrc bridge | all |
| 5963105 | zimbatm flake update (hm/iets/kin/nixvim/llm-agents/nix-skills) | nv1+web2 |
| fee393d | kin →45cd3818 pin-back (drop EROFS regression) | all |
| 28a9fe4 | kin →ba0e1a81 unpin (EROFS fixed) | all |
| 1d32ccb | iets →2c5337f9 + llm-agents →03a24500 | nv1+web2 |
| 575b547 | internal bump kin→757b0221 iets→fa604918 +nix-skills+llm-agents | all |
| cb0180b | home-manager 936d579f→667b3c47 | nv1 |
| 9d52d68 | internal kin 757b0221→76d8b7b2 + iets fa604918→c00eafa8 | all |
| ecada5b | kin →ba4514b9 + iets →14e50511 + settle →de9e8efe | all |
| bdef5f7 | kin.nix identity.peers.kin-infra.net=fdc5:e1a6:b03f (maille /48 route) | all |
| efd470a | internal kin →d1265fc0 iets →c70f78f8 llm-agents →b518f1b6 | nv1+web2 |
| 8c47c57 | zimbatm flake update hm/iets/kin/llm-agents/maille/nix-skills/nixos-hw/nixvim/srvos (NOT nixpkgs) | all |
| 778e7b8 | internal kin →bc87fa28 iets →5e52f1c2 llm-agents →6c3ff21f +maille+settle; gen/ regen | all |
| f5bd72e | flake update — nixpkgs b12141e→0726a0e + hm/iets/kin/llm-agents/maille/nix-index-db/nixvim/settle | all |
| c37cecc 66b1cfa | vim-utils pname overlay added then dropped (nixvim e61a31b5→d404af65 caught up) | nv1 |
| 94dd7b4 | kin 65eccea0→0bfa6d35 + iets/nix-skills/llm-agents bump | all |
| 22bbd1c | home-manager 6f59831b→c55c498c (programs.firefox.configPath warn) | nv1 |
| 232ec0fb | man-here `annotate` verb + reads.jsonl instrument | nv1 |
| e2eda857 | adopt-parakeet-cpu-lane: NEW transcribe-cpu (sherpa-onnx) + ptt-dictate `--backend=auto` + bench-dictate.sh | nv1 |
| 7bdd14f | **drop CROPS vfio passthrough, enable NVIDIA driver for CUDA** | nv1 |
| 052a455 aa07e81 3a81166 | deepfilter: disable, fix, then **remove** (pipewire 1.6 schema bug) | nv1 |
| 7790634 | NEW packages/ask-cuda — CUDA-13 llama.cpp wrapper for Qwen3.6-35B-A3B | nv1 |
| 35b6f06 | llm-router: support NVIDIA upstream | nv1 |
| 2313ae2 | NEW services/llm-nvidia-adapter (NIM → LiteLLM Anthropic shim, pendingOn key) | nv1 |
| 23975b3 | install distro input; **drop modules/nixos/niri.nix**; nv1 config rework | nv1 |
| 2844219 0837c94 | limine 11.4.1 hotfix added then **removed** (modules/nixos/limine-hotfix.nix dropped, fully landed) | all |
| 4b5ca4e | nixpkgs bump | all |
| ecdc26f a1a5da4 ad3ea1a | internal kin/iets/nix-skills/llm-agents bumps | all |
| ffb9aeb | kin llm-adapter | all |
| bfbaf59 eceb5e4 | srvos + nixos-hardware bumps | all |
| e4db263 | nv1: drop stale VFIO comments | nv1 |
| 74d901a | llm-router model-keyed backend lifecycle (spawn/idle-reap/LRU) | nv1 |
| a3f8a1c | afk-bench: opportunistic local-inference bench drain on idle nv1 | nv1 |
| a1a615b | home-manager c55c498c→fdb2ccba | nv1 |
| 318976e | nix-index-database b8eb7ace→dd2d0e3f | nv1 |
| a2759f9 | kin.nix `builders.hcloud-07` → nv1 `nix.buildMachines` + Cedar permit | all |
| 5a218c6 | nv1: `nix.settings.system-features = mkForce [kvm uid-range recursive-nix]` (drop big-parallel/nixos-test/benchmark → dispatch to hcloud-07) | nv1 |
| f94448e | sem-grep hybrid FTS5/BM25 + RRF retrieval | nv1 |
| b2d179c | dictation vocab biasing — ptt-dictate/transcribe-cpu/transcribe-npu source `lib/dictation-vocab.sh` | nv1 |

Closure-neutral (verified): a8d3abd (ask-cuda --structured-think — not in
host closure), 03bb206 (nixvim bump), 2efe8bf, c27c5c1, e170608, 6bf3705,
d00a686, 9dbb216, 8172dfe, 24cc8e8, 2898dcd, 26cb8a9 (nv1-neutral),
bfcd408 (relay1-only), 6673c0c (nv1-neutral internal bump), 9ba7bf5
(.envrc), ead5fd4 (treefmtFor devshell), 4ded977 (backlog), 821b625
srvos (relay1-neutral), 7aa2a6e srvos, aa28b38 keys stage, 3a809a9
nixvim (enableMan=false makes paths unreferenced), 69158d6 fleetManifest
inherit, b911f6e kin gen, 3dd9fb7 nixos-hardware, ed7d465 crops-residue,
6ecfb12 srvos, 0beecde backlog-only, 7184a6d srvos, c68e31a/e8a19f2
agentshell-only (host-closure-neutral), 39f3354 hm→ffbd94a1.

kin home-surface across 9d52d68..778e7b8: 9d6da8cf RestartSec=2 on
kin-secrets/kin-mesh + 053a8092 flake-shim sourceInfo (CLOSES iets-vs-
flake outPath divergence — kin#7ecc09f0 RESOLVED) + ceb1f951 mesh-toml
extract byte-identical + f2a377d7 publishes port-uniq + 5d3d0bae/
85b7e65b mesh.nix simplify. iets: 27855d720 cage RESERVE 8G→16G
(directly relevant, nv1 toplevel). maille: 93186cf half-open fast-start.

## Runtime checks (cumulative, since e196255)

Walk these at the nv1 desk after deploy:

- **NPU** — `python -c 'from openvino import Core; print(Core().available_devices)'` lists NPU
- **ptt-dictate** — `<Super>d` fires; `--intent` mode dispatches per intents.toml
- **ask-local** — ≥15 tok/s on Arc iGPU
- **agent-eyes** — `peek` works under GNOME Wayland; `poke key 125+32` works
- **infer-queue** — `infer-queue add -d arc …` lands in arc lane; `pueue status` shows pueued running
- **agent-meter** — starship segment renders; gauge shows Arc/NPU occupancy + queue depth
- **pty-puppet** — `pty-puppet @t spawn 'nix repl' && pty-puppet @t expect 'nix-repl>'`
- **say-back** — `echo hello | say-back` audible
- **now-context** — `now-context | jq .` shows non-empty `focused.title`
- **llm-router** — `curl -s localhost:8090/v1/models` responds; small-prompt routes to ask-local:8088
- **wake-listen** — `systemctl --user status wake-listen` active (not crash-looping; StartLimitBurst catches it); `journalctl --user -u wake-listen -n5` shows VAD probabilities, no TypeError/OpConversionFailure
- **transcribe-npu** — invoke once with no network; model loads from store path, no HF Hub fetch in stderr
- ~~**niri**~~ — **MOOT** (23975b3 dropped modules/nixos/niri.nix). Confirm Niri *absent* from GDM picker post-deploy.
- **sem-grep** — `sem-grep index && sem-grep "kin deploy"` returns hits; `sem-grep hist "<q>"` returns history lines; `sem-grep index-log && sem-grep log "wake-listen crash"` returns journald lines; walk packages/sem-grep/bench-log.txt (≥7/10 pass = keep, else rm verb + live-caption fold)
- ~~**crops-userland**~~ — **MOOT** (e98e1c5 set home.crops.enable=false, module stubbed)
- ~~**vfio-host**~~ — **MOOT** (7bdd14f dropped CROPS vfio passthrough). Confirm `vfio_pci` *not* loaded and NVIDIA driver active instead.
- **live-caption** — `systemctl --user status live-caption-log` active; `live-caption tail` follows today's jsonl; `live-caption off` stops unit; nightly reindex prunes >30d; `journalctl --user -u live-caption-log -n20` shows heartbeat; forced transcribe error surfaces in journal
- **man-here** — `man-here jq` renders store-exact docs
- **tab-tap** — Firefox about:addons lists tab-tap; `tab-tap read` returns Readability text of active tab
- **foot** — `<Super>Return` opens foot (server mode); ghostty still launchable
- **gsnap** — `gsnap capture` works under both GNOME (portal) and Niri (grim); per-session baseline dirs created
- **sel-act** — select text, hit `<Super>a` → ask-local transform menu; result replaces selection
- **ask-local --fast** — `ask-local --fast "<p>"` via llama-lookup; `packages/ask-local/bench.sh` tok/s ≥ plain on the 4 cases
- **sem-grep -r** — `sem-grep -r "<q>"` loads bge-reranker-base on NPU (3rd tenant); evals.jsonl shows `rerank:true` rows; fetch-hint fires if model dir absent
- **ask-local --agent** — `ask-local --agent "<goal>"` ≤4-turn ReAct; walk `packages/ask-local/bench-agent.jsonl` (20 goals, expect_tool+expect_substr); tools.json CLIs resolve on PATH
- **ask-local --mem** — `packages/ask-local/bench.sh --mem` runs cold×3 / warm-up+index / warm×3 over the 20-case agent bench; record `cold=X/20 warm=Y/20 dP50=+Nms PASS|FAIL`. Bar: warm ≥ cold+3 ∧ dP50 ≤ +150ms. PASS → flip `--mem` default on + llm-router keeps repeat-intent goals local; FAIL → memory-shaped goals route to cloud regardless of complexity gate. Also: `sem-grep index-runs && sem-grep runs "am I AFK?"` returns ≥1 JSON trace line
- **sem-grep timer** — `systemctl --user list-timers | grep sem-grep` shows nightly index-log; `which sem-grep` on PATH (was only hist-sem alias before)
- ~~**deepfilter**~~ — **MOOT** (3a81166 removed module). Confirm *absent* from PipeWire graph: `pw-cli ls Node | grep -i deepfilter` → nothing; `systemctl --user status pipewire` clean.
- **CA derivations** — `nix config show | grep ca-derivations` shows enabled; build a trivial CA drv to confirm store accepts
- **iets** — `which iets` on PATH; `iets --version`
- **fetch_model** — `rm -rf ~/.local/share/ask-local/models/<one>`; `ask-local "<q>"` auto-fetches (curl progress in stderr) instead of printing fetch-hint+exit-1. Same for sem-grep/say-back/agent-eyes/ptt-dictate first-run
- **peer-kin-infra trust** — `grep -c '@cert-authority' /etc/ssh/ssh_known_hosts` includes kin-infra fleet CA; `maille config show | jq .peer_fleets` lists kin-infra; `ip -6 route show dev kinq0 | grep fdc5:e1a6:b03f::/48` present (bdef5f7; verified-live on relay1+web2); ssh from a kin-infra host lands without TOFU prompt
- **ask-local --diff-gate** — stage a diff, `ask-local --diff-gate` returns pass/fail JSON; pre-commit hook fires it; starship `diff_gate` segment renders on dirty tree; `curl -s localhost:8090/review -d @<diff>` responds
- **sem-grep sig** — `sem-grep sig 'def main'` returns tree-sitter signature matches across indexed repos
- **pin-nixpkgs dropped** — `nix registry list | grep nixpkgs` and `echo $NIX_PATH` still resolve to system nixpkgs (kin upstream now provides; regression = `nix-shell -p` pulls channel)
- **attest identity** — `ls /run/kin/identity/attest.*` exists post-deploy (kin 3118eb1d feature)
- **sem-grep refs** — `sem-grep refs <symbol>` returns file:line for every ts-identifier use across indexed repos; walk `packages/sem-grep/bench-refs.txt` ground truth
- **tuicr** — `tuicr` over a staged diff renders TUI; comments export as markdown for backlog/ round-trip
- **ask-local perms** — `stat -c '%a' ~/.local/state/ask-local{,/*.jsonl}` shows 700/600 (c10990b hardening)
- **restic-gotosocial** (web2, carried) — `systemctl status restic-backups-gotosocial.{service,timer}`
- **man-here annotate** — `man-here annotate <cmd>` emits pname-major notes + appends reads.jsonl
- **ptt-dictate cpu lane** — `ptt-dictate --backend=cpu` invokes transcribe-cpu (sherpa-onnx parakeet); `--backend=auto` picks cpu when NPU unavailable; `bench-dictate.sh` reports per-lane latency
- **NVIDIA/CUDA** — `nvidia-smi` reports RTX 4060 with CUDA-13
- **ask-cuda** — `ask-cuda "<p>"` loads Qwen3.6-35B-A3B and answers
- **llm-nvidia-adapter** — unit inert until `kin set llm-nvidia-adapter/api-key/_shared/key` (see `ops-verify-nvidia-nim-adapter.md`)
- **afk-bench** — `systemctl --user list-timers | grep afk-bench` present; fires on AFK window, drains `infer-queue` (see `ops-afk-bench-stability.md`)
- **ask-local --serve** — accepts `--model M` / `--port N`; bare names resolve under `$XDG_DATA_HOME/llama`
- **llm-router lifecycle** — spawn/idle-reap/LRU observable via `/v1/models` + `decisions.jsonl` `{spawn,evict,reuse}` lines (see `adopt-llm-router-model-warm.md`)
- **builders.hcloud-07** — `nix store info --store ssh-ng://hcloud-07` resolves; `nix build --max-jobs 0 <expr>` dispatches remotely (key drop required first — `ops-builders-key-drop.md`)
- **system-features narrow** — `nix config show | grep system-features` shows exactly `kvm uid-range recursive-nix`; a big-parallel drv `--dry-run` reports `will be built` on hcloud-07; KVM/podman still work
- **dictation vocab biasing** — `ptt-dictate --vocab` emits the sem-grep-mined hint list; bench in `ops-dictation-vocab-bench.md`
- **sem-grep hybrid retrieval** — `sem-grep "<q>" --explain` shows the BM25 leg (FTS5 table populated)

---

## drift append-log

(drift-checker appends new `### drift @ <rev>` sections below; META
re-compacts into the table above when this section exceeds 3 entries)

<!-- compacted @ b236e97 (META r1, 2026-04-24): folded 6a4ed7a+1490f45+f4d909c+68ab318+fcc6b68 into table+checks above. want progression dvgqw9cg→av9v7mmc→glivxmgg→48k7pdv5→z0b9vg9s→77dfr1xn. nv1 not-on-mesh entire window; relay1+web2 both human-deployed Apr-24 20:06. -->
<!-- compacted @ META r15 (2026-05-09): folded e960caf+671f35b+e3c1cea+8231b3d+23975b3+9def97e+cce49ee+80a9212 into table+checks above. want progression 77dfr1xn→1mdzqizi→n5smybmw→zi5as60q→8l90l7hx→qjdsdd97→rsb8r0kg→53s3xn5k→isgj6yg9→mbw1f3pr. nv1 not-on-mesh entire window (relay1 down Apr-26→). niri/vfio/deepfilter marked MOOT in checks. -->

### drift @ 6753fd8 (2026-05-09, r15)

```
have: ???  (not-on-mesh — relay1 FULLY DOWN, no ProxyJump leg)
want: /nix/store/mbw1f3pr…-nixos-system-nv1-26.05.20260505.549bd84   (was isgj6yg9)
```

Two closure-affecting commits since 80a9212 (38be12c), both
**nv1-only** desktop packages: `b2d179c` (vocab biasing — ptt-dictate
+15L, transcribe-cpu +29L, transcribe-npu +31L all source
`lib/dictation-vocab.sh`, lands via `modules/home/desktop`) and
`f94448e` (sem-grep hybrid FTS5/BM25 + RRF retrieval, +5L net, also
desktop-only). relay1 `dxirzajg…549bd84` and web2 `msim209r…549bd84`
eval-identical at 80a9212 and 6753fd8.

Dry-build PASS: nv1 542 drvs / 1279 fetch / 4.4 GiB (was 555/1331/4.8G
@ 80a9212). New runtime check post-deploy: (1) `ptt-dictate --vocab`
emits the sem-grep-mined hint list; (2) `sem-grep "test query"` shows
the BM25 leg in `--explain` output (FTS5 table populated). Layered on
top of the system-features and builders.hcloud-07 checks above.
**Reachability still blocked on relay1 recovery.**
