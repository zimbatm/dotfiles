# bump: add `lockring` flake input + wire `services.lockring` (Track L)

Filed by meta r10, 2026-05-10. Splits the bump-shaped half out of
`needs-human/feat-lockring-ssh-agent.md` (deploy + week-of-use stay
human-gated there).

## what

The kin pin landed `services/lockring.nix` this round (kin
`4db2186d -> fb13c282`, includes `d21658e7`). That module needs the
downstream to pass `lockring` via `mkFleet { extraInputs = ... }` —
without it, the throw at kin `services/lockring.nix:80-82` fires on the
first nixos build. So `services.lockring` cannot be declared until home
adds the input. Lock-touching ⇒ this is a `bump-*` item.

## how

1. `flake.nix` inputs: add
   ```nix
   lockring = {
     url = "git+ssh://git@github.com/assise/lockring";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```
   (lockring is a blueprint flake — `nixosModules.lockring` resolves from
   `modules/nixos/lockring.nix`, confirmed at origin/main.)
2. `nix flake lock`.
3. `flake.nix:156` mkFleet: add `extraInputs = { inherit (inputs) lockring; };`.
4. `kin.nix`: add `services.lockring = { on = ["nv1"]; sshAgent = true; };`
   (default `policyFile` = lockring's
   `crates/lockring-core/examples/policy.cedar` — exists at origin/main).
5. `kin gen`.
6. Gate: all 3 hosts eval + dry-build. nv1 picks up the lockring user
   unit; web2/relay1 unchanged.

## why

Track L (`meta/next.md`). lockring ships a real nv1 ssh-agent surface;
the kin wrapper is the assise piece. The dogfood (week of normal ssh +
audit verify) is the falsification test — but it can't start until this
bump lands and a human runs `kin deploy nv1`.

## blockers

- None for the bump itself. The kin pin gate cleared this round.
- `needs-human/feat-lockring-ssh-agent.md` carries the deploy + week
  procedure. Update its blockers section once this lands.

## how much

Small. ~6 lines of flake.nix, 1 line of kin.nix, lock regen, gen regen.
The `kin.nix` line is the spine change for the round.
