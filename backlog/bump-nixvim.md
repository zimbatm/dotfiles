# bump: nixvim (13.0d stale)

**What:** `nix flake update nixvim`. Currently `d404af65`
(2026-04-26 15:52 UTC, 13.0d), upstream tip `7986a276`
(nix-community/nixvim main, ls-remote 2026-05-09).

**Why:** >7d stale per drift policy. Tied second-oldest external (with
home-manager) as of `drift @ a73c579`.

**How much:** nixvim is consumed only by `packages/nvim` (`makeNixvim`),
pulled into nv1 + web2 user closures. relay1 likely neutral (no nvim).
The vim-utils pname overlay was already dropped at `66b1cfa` — verify it
stays dropped (re-check `packDir` / plugin `pname` requirement on the
new pin).

**Blockers:** none. Standard bumper round; lowest priority of the three
filed at `drift @ a73c579` (smallest scope).
