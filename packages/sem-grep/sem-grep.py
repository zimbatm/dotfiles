"""sem-grep: hybrid (dense + lexical) retrieval over the assise repos.

Dense: bge-small-en-v1.5 (384-dim) on OpenVINO/NPU; sqlite+blob store
under $XDG_STATE_HOME/sem-grep; brute-force cosine (corpus ~2k files, no
faiss). Lexical: contentless FTS5/BM25 over the same chunk grid (sqlite,
no NPU). Default `--mode hybrid` fuses both rankings with reciprocal-rank
fusion — dense alone misses exact identifiers (`kin.nix` ≈ `kin nicks`
on a small model), lexical alone misses paraphrase. Wrapper at
packages/sem-grep/default.nix sets env + model path. NPU co-residency
and dense/lexical/hybrid recall are post-deploy falsification targets —
see backlog/adopt-sem-grep.md and adopt-sem-grep-hybrid-retrieval.md.
"""
import argparse
import ctypes
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

import numpy as np
import openvino as ov
from transformers import AutoTokenizer

MODEL = os.environ["SEM_GREP_MODEL"]
GRAMMARS = os.environ.get("SEM_GREP_GRAMMARS")  # dir of <lang>.so from withPlugins
RERANK_MODEL = os.environ.get("SEM_GREP_RERANK_MODEL")  # optional, -r only
DEVICE = os.environ.get("SEM_GREP_DEVICE", "NPU")
STATE = os.environ["SEM_GREP_STATE"]
REPOS = [p for p in os.environ["SEM_GREP_REPOS"].split(":") if os.path.isdir(p)]
DB = os.path.join(STATE, "index.db")
DIM = 384
CHUNK_LINES, STRIDE = 24, 12
MAX_LEN = 256  # tokens; bge cap is 512 but shorter = faster, fits more on NPU
RERANK_MAX_LEN = 512  # cross-encoder sees query+passage; needs the headroom
RERANK_POOL = 30  # cosine candidates fed to the cross-encoder
RRF_K = 60        # Cormack/Clarke/Büttcher 2009 — RRF smoothing constant
RRF_POOL = 60     # candidates pulled from each ranker before fusion
BATCH = 8
SKIP_EXT = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".age", ".bin", ".svg",
            ".lock", ".gz", ".zst", ".woff", ".woff2", ".ttf", ".ico"}


def load_embedder():
    tok = AutoTokenizer.from_pretrained(MODEL)
    core = ov.Core()
    net = core.compile_model(f"{MODEL}/openvino_model.xml", DEVICE)
    out = net.outputs[0]
    in_names = {p.any_name for p in net.inputs}

    def embed(texts):
        # max_length padding → static seq dim; NPU prefers fixed shapes.
        enc = tok(texts, padding="max_length", truncation=True,
                  max_length=MAX_LEN, return_tensors="np")
        res = net({k: v for k, v in enc.items() if k in in_names})[out]
        # mean-pool over token axis, masked by attention, then L2-normalise
        mask = enc["attention_mask"][..., None].astype(np.float32)
        pooled = (res * mask).sum(axis=1) / np.clip(mask.sum(axis=1), 1e-9, None)
        n = np.clip(np.linalg.norm(pooled, axis=1, keepdims=True), 1e-9, None)
        return (pooled / n).astype(np.float32)
    return embed


def load_reranker():
    """bge-reranker-base cross-encoder on the same NPU device. Returns
    score(query, passages) -> 1-D float32 logits (higher = more relevant).
    Third NPU tenant alongside Silero VAD + bge-small embed; whether all
    three co-reside is the falsification target — see adopt-rerank-pass."""
    tok = AutoTokenizer.from_pretrained(RERANK_MODEL)
    core = ov.Core()
    net = core.compile_model(f"{RERANK_MODEL}/openvino_model.xml", DEVICE)
    out = net.outputs[0]
    in_names = {p.any_name for p in net.inputs}

    def score(query, passages):
        logits = np.empty(len(passages), dtype=np.float32)
        for j in range(0, len(passages), BATCH):
            part = passages[j:j + BATCH]
            enc = tok([query] * len(part), part, padding="max_length",
                      truncation=True, max_length=RERANK_MAX_LEN,
                      return_tensors="np")
            res = net({k: v for k, v in enc.items() if k in in_names})[out]
            logits[j:j + len(part)] = res.reshape(-1)
        return logits
    return score


def chunk_text(repo, path, line):
    """Re-read the on-disk text for a stored chunk (we index vectors only)."""
    try:
        with open(os.path.join(repo, path), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return ""
    return "\n".join(lines[line - 1:line - 1 + CHUNK_LINES]).strip()


def db():
    os.makedirs(STATE, exist_ok=True)
    con = sqlite3.connect(DB)
    con.executescript("""
      CREATE TABLE IF NOT EXISTS files(
        repo TEXT, path TEXT, sha TEXT, PRIMARY KEY(repo, path));
      CREATE TABLE IF NOT EXISTS chunks(
        id INTEGER PRIMARY KEY, repo TEXT, path TEXT, line INTEGER, vec BLOB);
      CREATE INDEX IF NOT EXISTS chunks_rp ON chunks(repo, path);
      CREATE TABLE IF NOT EXISTS sigs(
        id INTEGER PRIMARY KEY, repo TEXT, path TEXT, line INTEGER,
        sig TEXT, vec BLOB);
      CREATE INDEX IF NOT EXISTS sigs_rp ON sigs(repo, path);
      CREATE TABLE IF NOT EXISTS refs(
        symbol TEXT, repo TEXT, path TEXT, line INTEGER);
      CREATE INDEX IF NOT EXISTS refs_sym ON refs(symbol);
      CREATE INDEX IF NOT EXISTS refs_rp ON refs(repo, path);
    """)
    try:
        # Lexical leg of hybrid retrieval. Contentless — chunk text already lives
        # on disk (chunk_text()), so we only store the inverted index, not the
        # text. contentless_delete=1 (sqlite ≥3.43) keeps incremental DELETE
        # working without a content table. tokenchars keeps `kin.nix` one token.
        con.execute("""CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
          text, content='', contentless_delete=1,
          tokenize="unicode61 remove_diacritics 2 tokenchars '._-'")""")
    except sqlite3.OperationalError:
        pass  # no FTS5 / pre-3.43 sqlite — hybrid degrades to dense
    return con


def _has_fts(con):
    return bool(con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='chunks_fts'"
    ).fetchone())


# Mirror unicode61's token chars (+ the configured `tokenchars '._-'`) so query
# tokenisation matches index tokenisation.
_FTS_TOKEN = re.compile(r"[\w.\-]+")


def _fts_query(text):
    """Tokenise the query the same way unicode61+tokenchars would, quote each
    token as a phrase, OR-join. Quoting neutralises FTS5 operators (NEAR, *,
    column filters) that would otherwise blow up on natural-language input."""
    return " OR ".join(f'"{t}"' for t in _FTS_TOKEN.findall(text))


def _rrf(*rankings):
    """Reciprocal-rank fusion: score(d) = Σ_i 1/(k + rank_i(d)). Rank-only —
    no learned weights, no score normalisation; robust to the BM25/cosine scale
    mismatch. Returns [(doc, score), …] best-first."""
    score: dict[int, float] = {}
    for ranking in rankings:
        for rank, doc in enumerate(ranking, 1):
            score[doc] = score.get(doc, 0.0) + 1.0 / (RRF_K + rank)
    return sorted(score.items(), key=lambda kv: -kv[1])


def _fts_backfill(con):
    """One-time: chunks has rows but chunks_fts is empty (upgrade from a
    dense-only index.db). Rebuild FTS from on-disk text — no re-embed, no NPU."""
    if not con.execute("SELECT 1 FROM chunks LIMIT 1").fetchone():
        return
    if con.execute("SELECT rowid FROM chunks_fts LIMIT 1").fetchone():
        return
    n = 0
    for rowid, repo, path, line in con.execute(
            "SELECT id, repo, path, line FROM chunks"):
        txt = chunk_text(repo, path, line)
        if txt:
            con.execute("INSERT INTO chunks_fts(rowid,text) VALUES(?,?)",
                        (rowid, txt))
            n += 1
    con.commit()
    if n:
        print(f"sem-grep: backfilled chunks_fts ({n} chunks from disk)",
              file=sys.stderr)


def git_tracked(repo):
    """Yield (path, blob_sha) for text-ish tracked files."""
    out = subprocess.run(["git", "-C", repo, "ls-files", "-s"],
                         capture_output=True, text=True, check=True).stdout
    for ln in out.splitlines():
        meta, path = ln.split("\t", 1)  # <mode> <sha> <stage>\t<path>
        sha = meta.split()[1]
        if os.path.splitext(path)[1].lower() in SKIP_EXT:
            continue
        yield path, sha


# --- treesitter signature extraction (for the `sig` verb) ------------------
# One query per language; each match yields @def (whole definition node),
# @name (anchor for line number) and optional @doc. sig_text = first line of
# @def (the natural signature) + first docstring line. Interface-shaped text
# embeds differently from body chunks — that's the falsification target.
TS_QUERIES = {
    "nix": """
      (binding attrpath: (attrpath) @name
               expression: (function_expression)) @def
    """,
    "python": """
      (function_definition name: (identifier) @name
        body: (block . (expression_statement
                         (string (string_content) @doc))?)) @def
      (class_definition name: (identifier) @name
        body: (block . (expression_statement
                         (string (string_content) @doc))?)) @def
    """,
    "bash": "(function_definition name: (word) @name) @def",
    "rust": """
      (function_item name: (identifier) @name) @def
      (struct_item name: (type_identifier) @name) @def
      (impl_item type: (_) @name) @def
    """,
}
# Identifier-USE captures for the `refs` verb. Deliberately coarse — name
# match only, no scope/type resolution. Precision vs hand-checked ground
# truth on polyglot assise repos is the falsification target (bench-refs.txt).
TS_REF_QUERIES = {
    "nix": """
      (variable_expression name: (identifier) @ref)
      (inherit (identifier) @ref)
    """,
    "python": """
      (call function: (identifier) @ref)
      (call function: (attribute attribute: (identifier) @ref))
      (identifier) @ref
    """,
    "bash": """
      (command_name (word) @ref)
      (variable_name) @ref
    """,
    "rust": """
      (call_expression function: (identifier) @ref)
      (call_expression function: (scoped_identifier name: (identifier) @ref))
      (identifier) @ref
    """,
}
TS_EXT = {".nix": "nix", ".py": "python", ".sh": "bash", ".bash": "bash",
          ".rs": "rust"}
_ts: dict[str, tuple] = {}  # lang → (Parser, sigQuery, refQuery, QueryCursor)


def _ts_lang(lang):
    if lang not in _ts:
        import tree_sitter as ts  # lazy: keep `query` path import-free
        lib = ctypes.CDLL(os.path.join(GRAMMARS, f"{lang}.so"))
        fn = getattr(lib, f"tree_sitter_{lang}")
        fn.restype = ctypes.c_void_p
        L = ts.Language(fn())
        _ts[lang] = (ts.Parser(L), ts.Query(L, TS_QUERIES[lang]),
                     ts.Query(L, TS_REF_QUERIES[lang]), ts.QueryCursor)
    return _ts[lang]


def sigs_of(repo, path):
    """Yield (line, sig_text) for each top-level definition in the file."""
    lang = TS_EXT.get(os.path.splitext(path)[1].lower())
    if not lang or not GRAMMARS:
        return
    full = os.path.join(repo, path)
    try:
        if os.path.getsize(full) > 256 * 1024:
            return
        with open(full, "rb") as f:
            src = f.read()
    except OSError:
        return
    parser, query, _, QueryCursor = _ts_lang(lang)
    tree = parser.parse(src)
    for _, caps in QueryCursor(query).matches(tree.root_node):
        d, n = caps["def"][0], caps["name"][0]
        head = d.text.decode("utf-8", "replace").splitlines()[0].strip()[:200]
        if doc := caps.get("doc"):
            first = doc[0].text.decode("utf-8", "replace").splitlines()[0].strip()
            if first:
                head = f"{head} — {first[:120]}"
        yield n.start_point[0] + 1, head


def refs_of(repo, path):
    """Yield (symbol, line) for each identifier-use site. Same parse skeleton
    as sigs_of; per-file (symbol,line) dedup keeps the table bounded when a
    name appears many times on one line."""
    lang = TS_EXT.get(os.path.splitext(path)[1].lower())
    if not lang or not GRAMMARS:
        return
    full = os.path.join(repo, path)
    try:
        if os.path.getsize(full) > 256 * 1024:
            return
        with open(full, "rb") as f:
            src = f.read()
    except OSError:
        return
    parser, _, refq, QueryCursor = _ts_lang(lang)
    tree = parser.parse(src)
    seen = set()
    for _, caps in QueryCursor(refq).matches(tree.root_node):
        for node in caps.get("ref", ()):
            sym = node.text.decode("utf-8", "replace")
            ln = node.start_point[0] + 1
            if (sym, ln) not in seen:
                seen.add((sym, ln))
                yield sym, ln


def chunks_of(repo, path):
    full = os.path.join(repo, path)
    try:
        if os.path.getsize(full) > 256 * 1024:
            return
        with open(full, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return
    i = 0
    while i < max(1, len(lines)):
        body = "\n".join(lines[i:i + CHUNK_LINES]).strip()
        if body:
            yield i + 1, body
        if i + CHUNK_LINES >= len(lines):
            break
        i += STRIDE


def cmd_index(_args):
    con = db()
    has_fts = _has_fts(con)
    if has_fts:
        _fts_backfill(con)
    embed = load_embedder()
    cur = con.cursor()
    n_new = n_skip = 0

    def drop_chunks(repo, path):
        # FTS rows must go first — we need the rowids that are about to vanish.
        if has_fts:
            con.execute("DELETE FROM chunks_fts WHERE rowid IN "
                        "(SELECT id FROM chunks WHERE repo=? AND path=?)",
                        (repo, path))
        con.execute("DELETE FROM chunks WHERE repo=? AND path=?", (repo, path))

    for repo in REPOS:
        prev = dict(con.execute(
            "SELECT path, sha FROM files WHERE repo=?", (repo,)))
        live = set()
        for path, sha in git_tracked(repo):
            live.add(path)
            if prev.get(path) == sha:
                n_skip += 1
                continue
            drop_chunks(repo, path)
            con.execute("DELETE FROM sigs WHERE repo=? AND path=?",
                        (repo, path))
            con.execute("DELETE FROM refs WHERE repo=? AND path=?",
                        (repo, path))
            batch = list(chunks_of(repo, path))
            for j in range(0, len(batch), BATCH):
                part = batch[j:j + BATCH]
                vecs = embed([t for _, t in part])
                # row-at-a-time so lastrowid links chunks↔chunks_fts
                for k, (ln, txt) in enumerate(part):
                    cur.execute(
                        "INSERT INTO chunks(repo,path,line,vec) VALUES(?,?,?,?)",
                        (repo, path, ln, vecs[k].tobytes()))
                    if has_fts:
                        cur.execute(
                            "INSERT INTO chunks_fts(rowid,text) VALUES(?,?)",
                            (cur.lastrowid, txt))
            sigs = list(sigs_of(repo, path))
            for j in range(0, len(sigs), BATCH):
                part = sigs[j:j + BATCH]
                vecs = embed([t for _, t in part])
                con.executemany(
                    "INSERT INTO sigs(repo,path,line,sig,vec) VALUES(?,?,?,?,?)",
                    [(repo, path, ln, t, vecs[k].tobytes())
                     for k, (ln, t) in enumerate(part)])
            con.executemany(
                "INSERT INTO refs(symbol,repo,path,line) VALUES(?,?,?,?)",
                [(sym, repo, path, ln) for sym, ln in refs_of(repo, path)])
            con.execute("INSERT OR REPLACE INTO files VALUES(?,?,?)",
                        (repo, path, sha))
            n_new += 1
        for path in set(prev) - live:
            drop_chunks(repo, path)
            con.execute("DELETE FROM sigs WHERE repo=? AND path=?",
                        (repo, path))
            con.execute("DELETE FROM refs WHERE repo=? AND path=?",
                        (repo, path))
            con.execute("DELETE FROM files WHERE repo=? AND path=?",
                        (repo, path))
        con.commit()
    print(f"sem-grep: indexed {n_new} changed, skipped {n_skip} unchanged → {DB}",
          file=sys.stderr)


def cmd_hist(args):
    """Semantic recall over shell history fed by the bash PROMPT_COMMAND hook."""
    con = db()
    con.executescript("""
      CREATE TABLE IF NOT EXISTS hist(
        id INTEGER PRIMARY KEY, ts INTEGER, cwd TEXT, cmd TEXT,
        exit INTEGER, vec BLOB);
      CREATE TABLE IF NOT EXISTS hist_mark(k TEXT PRIMARY KEY, v INTEGER);
    """)
    log = os.path.join(
        os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
        "hist-sem", "log.jsonl")
    off = (con.execute("SELECT v FROM hist_mark WHERE k='off'").fetchone()
           or (0,))[0]
    new = []
    if os.path.isfile(log):
        with open(log, "rb") as f:
            f.seek(off)
            raw = f.read()
        off += len(raw)
        for ln in raw.decode("utf-8", "replace").splitlines():
            try:
                new.append(json.loads(ln))
            except json.JSONDecodeError:
                pass  # tolerate the rare malformed line from the shell hook
    embed = load_embedder()
    if new:
        for j in range(0, len(new), BATCH):
            part = new[j:j + BATCH]
            vecs = embed([r["cmd"] for r in part])
            con.executemany(
                "INSERT INTO hist(ts,cwd,cmd,exit,vec) VALUES(?,?,?,?,?)",
                [(r["ts"], r.get("cwd", ""), r["cmd"], r.get("exit", 0),
                  vecs[k].tobytes()) for k, r in enumerate(part)])
        con.execute("INSERT OR REPLACE INTO hist_mark VALUES('off',?)", (off,))
        con.commit()
        print(f"sem-grep hist: embedded {len(new)} new commands", file=sys.stderr)
    rows = con.execute("SELECT ts, cwd, cmd, vec FROM hist").fetchall()
    if not rows:
        print("sem-grep hist: no history yet — log feeds from the shell hook "
              "in modules/home/terminal", file=sys.stderr)
        sys.exit(1)
    q = embed(["Represent this sentence for searching relevant passages: "
               + args.text])[0]
    mat = np.frombuffer(b"".join(r[3] for r in rows),
                        dtype=np.float32).reshape(-1, DIM)
    scores = mat @ q
    top = np.argsort(-scores)[: args.n]
    home = os.path.expanduser("~")
    for rank, i in enumerate(top, 1):
        ts, cwd, cmd, _ = rows[i]
        if args.pick:
            if rank == args.pick:
                print(cmd)
            continue
        date = time.strftime("%Y-%m-%d", time.localtime(ts))
        print(f"{scores[i]:.3f}  {date}  {cwd.replace(home, '~', 1)}$ {cmd}")


def _journal(argv):
    """Yield (unit, ts_seconds, message) from a journalctl -o json invocation.
    Tolerates absence/permission denial — returns nothing rather than raising."""
    p = subprocess.run(["journalctl", "-o", "json", "--no-pager", *argv],
                       capture_output=True, text=True)
    if p.returncode != 0:
        print(f"sem-grep index-log: journalctl {' '.join(argv)}: {p.stderr.strip()}",
              file=sys.stderr)
        return
    for ln in p.stdout.splitlines():
        try:
            r = json.loads(ln)
        except json.JSONDecodeError:
            continue
        msg = r.get("MESSAGE", "")
        if isinstance(msg, list):  # journald emits non-UTF8 payloads as byte arrays
            msg = bytes(msg).decode("utf-8", "replace")
        msg = msg.strip()
        if not msg:
            continue
        unit = (r.get("_SYSTEMD_UNIT") or r.get("SYSLOG_IDENTIFIER")
                or r.get("_COMM") or "-")
        ts = int(r.get("__REALTIME_TIMESTAMP", "0")) // 1_000_000
        yield unit, ts, msg


def cmd_index_log(_args):
    """Nightly: last-7d journald → hour-bucket dedup → embed → logs table.
    Full rebuild each run; the -S -7d window makes it rolling. Dedup keeps the
    same template line once per (unit, hour) so the corpus stays brute-forceable
    (~2k chunks). Falsifies whether bge-small embeds machine log text usefully —
    see backlog/adopt-log-sem.md."""
    con = db()
    con.execute("""CREATE TABLE IF NOT EXISTS logs(
        id INTEGER PRIMARY KEY, unit TEXT, ts INTEGER, msg TEXT, vec BLOB)""")
    buckets: dict[tuple[str, int], dict[str, int]] = {}
    for argv in (["--user", "-S", "-7d"], ["-S", "-7d", "-p", "warning"]):
        for unit, ts, msg in _journal(argv):
            buckets.setdefault((unit, ts // 3600), {}).setdefault(msg, ts)
    rows = [(unit, ts, msg) for (unit, _), msgs in buckets.items()
            for msg, ts in msgs.items()]
    embed = load_embedder()
    con.execute("DELETE FROM logs")
    for j in range(0, len(rows), BATCH):
        part = rows[j:j + BATCH]
        vecs = embed([m for _, _, m in part])
        con.executemany("INSERT INTO logs(unit,ts,msg,vec) VALUES(?,?,?,?)",
                        [(u, t, m, vecs[k].tobytes())
                         for k, (u, t, m) in enumerate(part)])
    con.commit()
    print(f"sem-grep index-log: {len(rows)} lines (7d, hour-dedup) → {DB}",
          file=sys.stderr)


def cmd_log(args):
    con = db()
    con.execute("""CREATE TABLE IF NOT EXISTS logs(
        id INTEGER PRIMARY KEY, unit TEXT, ts INTEGER, msg TEXT, vec BLOB)""")
    rows = con.execute("SELECT unit, ts, msg, vec FROM logs").fetchall()
    if not rows:
        print("sem-grep log: index empty — run `sem-grep index-log` first "
              "(nightly timer in modules/home/desktop/sem-grep.nix)",
              file=sys.stderr)
        sys.exit(1)
    embed = load_embedder()
    q = embed(["Represent this sentence for searching relevant passages: "
               + args.text])[0]
    mat = np.frombuffer(b"".join(r[3] for r in rows),
                        dtype=np.float32).reshape(-1, DIM)
    scores = mat @ q
    if args.rerank:
        pool = np.argsort(-scores)[: max(RERANK_POOL, args.n)]
        rscore = load_reranker()(args.text, [rows[i][2] for i in pool])
        order = np.argsort(-rscore)[: args.n]
        top, disp = [pool[k] for k in order], rscore[order]
    else:
        top = np.argsort(-scores)[: args.n]
        disp = scores[top]
    for s, i in zip(disp, top):
        unit, ts, msg, _ = rows[i]
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(ts))
        print(f"{s:+.3f}  {unit}\t{when}\t{msg}")


def cmd_index_runs(_args):
    """Embed ask-local --agent run traces (goal → vec) into a `runs` table for
    retrieval-augmented few-shot. Dedupe by sha1(goal); runs.jsonl is
    append-only so last-write-wins per goal within a batch. Same NPU bge-small
    path as hist/log. Falsifies sub-4B-benefits-from-own-trace — see
    backlog/adopt-trace-mem.md."""
    con = db()
    con.execute("""CREATE TABLE IF NOT EXISTS runs(
        h TEXT PRIMARY KEY, goal TEXT, trace TEXT, ok INTEGER, vec BLOB)""")
    log = os.path.join(
        os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
        "ask-local", "runs.jsonl")
    if not os.path.isfile(log):
        print(f"sem-grep index-runs: no runs yet at {log}", file=sys.stderr)
        return
    have = {h for (h,) in con.execute("SELECT h FROM runs")}
    new: dict[str, dict] = {}
    with open(log, encoding="utf-8") as f:
        for ln in f:
            try:
                r = json.loads(ln)
            except json.JSONDecodeError:
                continue
            goal = r.get("goal", "")
            if not goal:
                continue
            h = hashlib.sha1(goal.encode()).hexdigest()
            if h in have:
                continue
            new[h] = r  # dict keyed by h → last line for a goal wins
    if not new:
        print("sem-grep index-runs: 0 new goals", file=sys.stderr)
        return
    embed = load_embedder()
    items = list(new.items())
    for j in range(0, len(items), BATCH):
        part = items[j:j + BATCH]
        vecs = embed([r["goal"] for _, r in part])
        con.executemany(
            "INSERT OR REPLACE INTO runs(h,goal,trace,ok,vec) VALUES(?,?,?,?,?)",
            [(h, r["goal"],
              json.dumps({"tool_calls": r.get("tool_calls", []),
                          "final": r.get("final", "")}),
              int(bool(r.get("ok"))), vecs[k].tobytes())
             for k, (h, r) in enumerate(part)])
    con.commit()
    print(f"sem-grep index-runs: embedded {len(new)} new goals → {DB}",
          file=sys.stderr)


def cmd_runs(args):
    """Top-n past agent traces by goal similarity. One JSON line per hit
    {"goal","tool_calls","final","ok"} so ask-local --agent --mem can prepend
    them verbatim as few-shot examples. Silent on empty index so the cold-start
    --mem path degrades to no-mem."""
    con = db()
    con.execute("""CREATE TABLE IF NOT EXISTS runs(
        h TEXT PRIMARY KEY, goal TEXT, trace TEXT, ok INTEGER, vec BLOB)""")
    rows = con.execute("SELECT goal, trace, ok, vec FROM runs").fetchall()
    if not rows:
        return
    embed = load_embedder()
    q = embed(["Represent this sentence for searching relevant passages: "
               + args.text])[0]
    mat = np.frombuffer(b"".join(r[3] for r in rows),
                        dtype=np.float32).reshape(-1, DIM)
    scores = mat @ q
    top = np.argsort(-scores)[: args.n]
    for i in top:
        goal, trace, ok, _ = rows[i]
        t = json.loads(trace)
        print(json.dumps({"goal": goal, "tool_calls": t.get("tool_calls", []),
                          "final": t.get("final", ""), "ok": bool(ok)}))


def cmd_sig(args):
    """Rank treesitter-extracted signatures by interface shape. Output is
    `file:line  signature` so an agent can Read(offset,limit) the hit directly
    — the zat win without the zat dep."""
    con = db()
    rows = con.execute("SELECT repo, path, line, sig, vec FROM sigs").fetchall()
    if not rows:
        print("sem-grep sig: index empty — run `sem-grep index` first",
              file=sys.stderr)
        sys.exit(1)
    embed = load_embedder()
    q = embed(["Represent this sentence for searching relevant passages: "
               + args.text])[0]
    mat = np.frombuffer(b"".join(r[4] for r in rows),
                        dtype=np.float32).reshape(-1, DIM)
    scores = mat @ q
    top = np.argsort(-scores)[: args.n]
    home = os.path.expanduser("~") + "/"
    for i in top:
        repo, path, line, sig, _ = rows[i]
        loc = os.path.join(repo, path).replace(home, "~/", 1)
        print(f"{scores[i]:.3f}  {loc}:{line}  {sig}")


def cmd_refs(args):
    """Who references this exact symbol name. Pure sqlite — no embed/model load,
    so it's the cheap structural leg of the embed/sig/refs tripod. Precision
    bench: packages/sem-grep/bench-refs.txt."""
    con = db()
    rows = con.execute(
        "SELECT repo, path, line FROM refs WHERE symbol=? "
        "ORDER BY repo, path, line LIMIT ?", (args.symbol, args.n)).fetchall()
    if not con.execute("SELECT 1 FROM refs LIMIT 1").fetchone():
        print("sem-grep refs: index empty — run `sem-grep index` first",
              file=sys.stderr)
        sys.exit(1)
    home = os.path.expanduser("~") + "/"
    for repo, path, line in rows:
        loc = os.path.join(repo, path).replace(home, "~/", 1)
        print(f"{loc}:{line}")


# --- vocab: decoder-biasing word list for the dictation pipeline -----------
# Identifier-shaped, reasonable length, not punctuation soup. dots/dashes are
# allowed because Nix attrpaths and package names use them (kin.nix, sem-grep).
VOCAB_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]{2,39}$")
# Language keywords + generic programming nouns + bare common English. These
# dominate the refs table by raw DF but are noise for ASR biasing — the model
# already knows them, and a long prompt of generics dilutes the jargon signal.
VOCAB_STOP = frozenset("""
    let in if then else with rec inherit import builtins true false null or and
    def class return yield from as for while try except finally pass break
    continue lambda not is none self args kwargs print isinstance super
    pub mod use mut impl struct enum trait match where async await dyn ref
    local function echo exit shift case esac done fi elif read printf source
    set unset export eval test command type hash alias declare typeset
    the this that these those was were has had have are not all any can may
    src lib bin etc tmp var usr dev opt run sys proc home root user
    pkgs config options modules system services environment programs
    name path file line text data value key index list dict tuple item
    str int float bool len map env cmd out err log msg ret res buf ptr cur
    main init test setup teardown update build check make clean install
    get set new old add del put pop push end top low high min max sum avg
    foo bar baz qux tmp aux util utils misc common core base impl
    arg argv argc opts flags params input output result status err
    json yaml toml xml html css js ts py sh nix txt md rst cfg ini
    true false null none nil void unit some ok err result option
""".split())


def cmd_vocab(args):
    """Top-N project identifiers by document frequency, mined from the existing
    `refs` table (treesitter identifier-use sites populated at index time).
    This is the decoder-biasing list for the dictation pipeline —
    packages/lib/dictation-vocab.sh caches it under $XDG_RUNTIME_DIR and the
    three transcribers thread it as --prompt / --hotwords-file / initial_prompt.
    Pure sqlite, no embed/model load (cheap like `refs`). Recency is implicit:
    cmd_index deletes refs for files no longer git-tracked, so the table always
    reflects the *current* working trees, not historical noise."""
    con = db()
    if not con.execute("SELECT 1 FROM refs LIMIT 1").fetchone():
        # Cold index: emit nothing. dictation-vocab.sh notices the empty
        # output and falls back to its static seed list.
        return
    rows = con.execute(
        "SELECT symbol, COUNT(DISTINCT repo || '/' || path) AS df "
        "FROM refs GROUP BY symbol ORDER BY df DESC, symbol").fetchall()
    out = []
    for sym, df in rows:
        if df < 2:
            break  # df-sorted: everything after is also a singleton (typo/local)
        if not VOCAB_RE.match(sym) or sym.lower() in VOCAB_STOP:
            continue
        out.append((sym, df))
        if len(out) >= args.top:
            break
    if args.json:
        print(json.dumps([{"term": s, "df": d} for s, d in out]))
    else:
        for s, _ in out:
            print(s)


def cmd_query(args):
    """Hybrid retrieval over the chunks index. --mode picks the leg(s):
      dense   — brute-force cosine over the bge-small embeddings (original path)
      lexical — FTS5 BM25 over chunks_fts (exact identifiers, no NPU)
      hybrid  — both, fused with reciprocal-rank fusion (default)
    Falsification: hit@3 across modes on a fixed identifier-heavy query set —
    see backlog/adopt-sem-grep-hybrid-retrieval.md."""
    con = db()
    rows = con.execute("SELECT id, repo, path, line, vec FROM chunks").fetchall()
    if not rows:
        print("sem-grep: index empty — run `sem-grep index` first",
              file=sys.stderr)
        sys.exit(1)
    mode = args.mode
    if mode != "dense" and not _has_fts(con):
        print("sem-grep: chunks_fts missing (run `sem-grep index` to build the "
              "lexical leg) — falling back to --mode dense", file=sys.stderr)
        mode = "dense"
    by_id = {r[0]: i for i, r in enumerate(rows)}  # rowid → row index
    pool_n = max(RRF_POOL, args.n, RERANK_POOL if args.rerank else 0)

    dense_rank, lex_rank, cos, bm25 = [], [], None, {}
    if mode in ("dense", "hybrid"):
        embed = load_embedder()
        # bge s2p retrieval prefix on the query side only
        q = embed(["Represent this sentence for searching relevant passages: "
                   + args.text])[0]
        mat = np.frombuffer(b"".join(r[4] for r in rows),
                            dtype=np.float32).reshape(-1, DIM)
        cos = mat @ q
        dense_rank = np.argsort(-cos)[:pool_n].tolist()
    if mode in ("lexical", "hybrid"):
        match = _fts_query(args.text)
        if match:
            for rowid, b in con.execute(
                    "SELECT rowid, bm25(chunks_fts) FROM chunks_fts "
                    "WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts) LIMIT ?",
                    (match, pool_n)):
                if rowid in by_id:
                    i = by_id[rowid]
                    lex_rank.append(i)
                    bm25[i] = -b  # bm25() is more-negative = more relevant

    if mode == "dense":
        ranked = [(i, float(cos[i])) for i in dense_rank]
    elif mode == "lexical":
        ranked = [(i, bm25[i]) for i in lex_rank]
    else:
        ranked = _rrf(dense_rank, lex_rank)

    home = os.path.expanduser("~") + "/"
    if args.rerank:
        # stage-2: candidate pool → cross-encoder rerank → top-N
        pool = [i for i, _ in ranked[: max(RERANK_POOL, args.n)]]
        passages = [chunk_text(rows[i][1], rows[i][2], rows[i][3]) for i in pool]
        rscore = load_reranker()(args.text, passages)
        order = np.argsort(-rscore)[: args.n]
        out = [(pool[k], float(rscore[k])) for k in order]
    else:
        out = ranked[: args.n]
    for i, s in out:
        _, repo, path, line, _ = rows[i]
        loc = os.path.join(repo, path).replace(home, "~/", 1)
        print(f"{s:+.4f}  {loc}:{line}")
    # falsification log → feeds the dense/lexical/hybrid + rerank A/B evals
    try:
        with open(os.path.join(STATE, "evals.jsonl"), "a") as f:
            f.write(json.dumps({
                "ts": time.time(), "q": args.text, "mode": mode,
                "rerank": args.rerank,
                "top": [f"{rows[i][2]}:{rows[i][3]}" for i, _ in out[:5]],
            }) + "\n")
    except OSError:
        pass


def main():
    ap = argparse.ArgumentParser(prog="sem-grep")
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("index").set_defaults(fn=cmd_index)
    qp = sub.add_parser("query")
    qp.add_argument("-n", type=int, default=10)
    qp.add_argument("-r", "--rerank", action="store_true",
                    help="rerank candidate pool with bge-reranker-base on NPU")
    qp.add_argument("--mode", choices=("dense", "lexical", "hybrid"),
                    default="hybrid",
                    help="retrieval mode: dense cosine, lexical BM25, or "
                         "RRF-fused hybrid (default)")
    qp.add_argument("text")
    qp.set_defaults(fn=cmd_query)
    sp = sub.add_parser("sig")
    sp.add_argument("-n", type=int, default=10)
    sp.add_argument("text")
    sp.set_defaults(fn=cmd_sig)
    hp = sub.add_parser("hist")
    hp.add_argument("-n", type=int, default=10)
    hp.add_argument("--pick", type=int, metavar="N",
                    help="print only the Nth-ranked command (for shell recall)")
    hp.add_argument("text")
    hp.set_defaults(fn=cmd_hist)
    sub.add_parser("index-log").set_defaults(fn=cmd_index_log)
    lp = sub.add_parser("log")
    lp.add_argument("-n", type=int, default=10)
    lp.add_argument("-r", "--rerank", action="store_true",
                    help="rerank cosine top-30 with bge-reranker-base on NPU")
    lp.add_argument("text")
    lp.set_defaults(fn=cmd_log)
    rp = sub.add_parser("refs")
    rp.add_argument("-n", type=int, default=50)
    rp.add_argument("symbol")
    rp.set_defaults(fn=cmd_refs)
    sub.add_parser("index-runs").set_defaults(fn=cmd_index_runs)
    tp = sub.add_parser("runs")
    tp.add_argument("text")
    tp.add_argument("-n", type=int, default=2)
    tp.set_defaults(fn=cmd_runs)
    vp = sub.add_parser("vocab")
    vp.add_argument("--top", type=int, default=200, metavar="N")
    fmt = vp.add_mutually_exclusive_group()
    fmt.add_argument("--lines", action="store_true",
                     help="one term per line (default)")
    fmt.add_argument("--json", action="store_true",
                     help='[{"term":..,"df":..}, ...]')
    vp.set_defaults(fn=cmd_vocab)
    # bare `sem-grep "<text>"` → query
    argv = sys.argv[1:]
    if argv and argv[0] not in {"index", "query", "sig", "hist", "index-log",
                                "log", "refs", "index-runs", "runs", "vocab",
                                "-h", "--help"}:
        argv = ["query", *argv]
    args = ap.parse_args(argv)
    if not args.cmd:
        ap.print_help(sys.stderr)
        sys.exit(2)
    args.fn(args)


if __name__ == "__main__":
    main()
