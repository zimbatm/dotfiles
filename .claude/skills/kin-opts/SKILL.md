---
name: kin-opts
description: Query this fleet's evaluated NixOS option tree before writing option paths. Use whenever you're about to set or reference an option in machines/ or modules/ and aren't certain the path exists — it returns the merged value, type, and which file set it.
---

Before writing any `services.*` / `programs.*` / `kin.*` / etc. option path in
`machines/<host>/configuration.nix` or `modules/nixos/*.nix`, confirm it exists
on the target host:

```sh
kin-opts <host> <option.path>     # leaf → {value,type,description,declared,defined}
                                  # non-leaf → {children:[...]} to drill down
kin-opts <host> --search <regex>  # full-tree path grep (kin/maille/local included)
kin-opts <host> --pkgs            # flat name list of environment.systemPackages
kin-opts --diff <h1> <h2> <path>  # unified diff of config.<path> between two hosts
kin-opts --hosts                  # nv1 web2
```

`defined` shows which file in *this* repo (or kin/srvos) actually set the
value — generic nixpkgs docs can't tell you that. If the lookup errors, the
path is wrong; `--search` or drill from a parent before guessing again.

**simplifier/drift specialists**: reach for `kin-opts` over `grep -rn modules/`.
The merged option value + `defined` locations answer "where is X set" in one
eval; `--diff` answers "do nv1 and web2 actually differ here" without reading
both machines/ trees; `--pkgs | grep <name>` answers "is X installed on <host>"
without tracing systemPackages assignments by hand.
