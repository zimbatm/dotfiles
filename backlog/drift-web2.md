# drift: web2 stale (lockring bump d723a82) + needs reboot

**What:** web2 deployed `683by1csf5dh…` (gen-28) but origin/main @
0bcca15 wants `9nf2h5p789gw…`. Same nixpkgs (`549bd84`); the delta is
the lockring bump (d723a82, `6f35b441` → `df3c10a4`, revCount 390 →
441). The ietsd-widening commit (666e423) only added `nv1` to
`services.ietsd.on` — web2 was already in the list, so it does not
move web2's closure.

**Probe (drift @ 0bcca15, 2026-05-11 ~01:30 UTC):**

```
have:   /nix/store/683by1csf5dhskam575gh5lcvw8sp5qn-nixos-system-web2-26.05.20260505.549bd84
want:   /nix/store/9nf2h5p789gwglhv9hx0k16hx41gwcyy-nixos-system-web2-26.05.20260505.549bd84
health: running, 0 failed, uptime 0d11h12m
disk:   7.5G avail / 36.8G total (28G used) — ok, watch
swap:   116 MB in use
needs_reboot: TRUE
```

**Why it matters:** Two distinct things to clear:
1. lockring drift (small, 6h old) — `kin deploy web2`.
2. `needs_reboot: true` — the booted kernel/systemd no longer match
   what the running gen-28 declares. A `kin deploy` *won't* clear this
   on its own; the box needs an actual reboot. Bundle them: deploy then
   reboot (or `kin deploy --reboot web2` if kin supports it).

**Reconcile:** `kin deploy web2` then reboot. Servers OK on instruction
per `feedback_deploy_scope`; bundle with `drift-relay1.md` (same lockring
delta).

**Blockers:** human-gated deploy + reboot.
