# zimbatm's home

Local packages, home-manager modules, and desktop tooling.

## Layout

```sh
modules/home/        # home-manager modules
packages/            # local CLIs and wrappers
tests/               # repo tests and checks
```

The flake exports `packages`, `homeModules`, `formatter`, and `checks`.

## Common Commands

```sh
nix flake show
nix build .#packages.x86_64-linux.<name>
nix fmt
```
