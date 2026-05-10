#!/usr/bin/env python3
"""TOON re-encoder for shell-squeeze JSON shims.

Reads JSON on stdin, emits a denser TOON-ish form for two shapes only:
  (a) array of homogeneous flat objects  -> [N]{f1,f2}: + comma rows
  (b) nested object                      -> key-folded dotted paths
Anything else — and *any* exception — is a strict byte-identical
pass-through of the original input. Never re-serialize, never lossy.
This layer is for the agent's eyes; downstream tools that need real
JSON bypass via SHELL_SQUEEZE=0 or --raw (the shim already guards).
"""
import json
import sys

HINT = "[shell-squeeze: TOON-encoded — append --raw or SHELL_SQUEEZE=0 for plain JSON]"


def _scalar(v):
    if v is None or isinstance(v, (bool, int, float)):
        return json.dumps(v)
    return json.dumps(v) if any(c in v for c in ',\n:"{}[]') or v != v.strip() else v


def _is_flat(o):
    return isinstance(o, dict) and not any(isinstance(v, (dict, list)) for v in o.values())


def _table(rows):
    keys = list(rows[0])
    head = "[%d]{%s}:" % (len(rows), ",".join(keys))
    return "\n".join([head] + ["  " + ",".join(_scalar(r[k]) for k in keys) for r in rows])


def _fold(obj, prefix=""):
    for k, v in obj.items():
        p = f"{prefix}.{k}" if prefix else str(k)
        if isinstance(v, dict) and v:
            yield from _fold(v, p)
        else:
            leaf = json.dumps(v, separators=(",", ":")) if isinstance(v, (dict, list)) else _scalar(v)
            yield f"{p}: {leaf}"


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
        if isinstance(data, list) and len(data) > 1 and all(_is_flat(o) for o in data) \
                and all(o.keys() == data[0].keys() for o in data):
            out = _table(data)
        elif isinstance(data, dict) and data and any(isinstance(v, dict) for v in data.values()):
            out = "\n".join(_fold(data))
        else:
            sys.stdout.write(raw)
            return
        # Only claim a win if we actually shrank it; otherwise pass through.
        if len(out) >= len(raw):
            sys.stdout.write(raw)
            return
        sys.stdout.write(out + "\n")
        print(HINT, file=sys.stderr)
    except Exception:
        sys.stdout.write(raw)


if __name__ == "__main__":
    main()
