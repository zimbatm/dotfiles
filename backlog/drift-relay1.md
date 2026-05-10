# drift: relay1 stale (lockring bump d723a82)

**What:** relay1 deployed `dikz2p8m1574…` (gen-1, the May-10 install)
but origin/main @ 0bcca15 wants `zcjjyf5f93dp…`. Same nixpkgs
(`549bd84`); the delta is the lockring bump
(d723a82, `6f35b441` → `df3c10a4`, revCount 390 → 441).

**Probe (drift @ 0bcca15, 2026-05-11 ~01:30 UTC):**

```
have:   /nix/store/dikz2p8m1574axnljwzr5j5awa8sb3fi-nixos-system-relay1-26.05.20260505.549bd84
want:   /nix/store/zcjjyf5f93dp9rhzw3y600xd544km44c-nixos-system-relay1-26.05.20260505.549bd84
health: running, 0 failed, uptime 0d7h54m
disk:   69.2G avail / 74.1G total (1.1G used) — fine
needs_reboot: no
```

**Why it matters:** Drift is ~6h old and small (one input bump). Not
urgent — relay1 is the new install and stable. Reconverging keeps the
"all hosts at want" invariant true.

**Reconcile:** `kin deploy relay1` (servers OK on instruction per
`feedback_deploy_scope` — but bundle with the web2 redeploy and gate
on someone glancing at the lockring 6f35b44..df3c10a4 changelog).

**Blockers:** human-gated deploy. See also `drift-web2.md` (same
lockring delta).
