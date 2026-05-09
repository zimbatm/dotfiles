"""llm-router: request-shape proxy + model lifecycle manager.

Serves OpenAI-compatible /v1/chat/completions on 127.0.0.1:8090 and
routes by shape: short, no-tools, <=4k-ctx -> local; everything else ->
upstream. Every decision is appended to
$XDG_STATE_HOME/llm-router/decisions.jsonl so agent-meter can see
whether the local lane is load-bearing.

The local lane is model-keyed. When a local-routed request's `model`
field resolves to a GGUF under $XDG_DATA_HOME/llama, llm-router spawns
`ask-local --serve --model <path> --port <n>`, polls /health until it
answers, and proxies. A registry (in-memory dict mirrored to
$XDG_STATE_HOME/llm-router/backends.json) tracks model -> {port, pid,
last_used}. An idle reaper SIGTERMs backends untouched for
LLM_ROUTER_IDLE_S (default 300s) and frees the port;
LLM_ROUTER_MAX_RESIDENT (default 1) caps how many are warm at once,
evicting LRU before each spawn. On Arc shared iGPU memory the cap is
the safety valve, not an optimisation: a stale resident model is
contention against transcribe-npu / agent-eyes, not free. Requests
whose `model` does not resolve locally fall back to the legacy fixed
backend at LLM_ROUTER_LOCAL (:8088, an `ask-local --serve` you started
yourself). Each decisions.jsonl line gains {spawn, evict, reuse} so
agent-meter can plot model-residency churn next to Arc/NPU occupancy;
the reaper appends standalone {"event": "evict"} lines.

Opt-in: export OPENAI_BASE_URL=http://127.0.0.1:8090/v1 and start
`llm-router` (or `ask-local --serve` in another terminal for the local
lane). For hosted OpenAI-compatible providers set, for example:
  LLM_ROUTER_UPSTREAM=https://integrate.api.nvidia.com
  LLM_ROUTER_REVIEW_MODEL=minimaxai/minimax-m2.7
  NVIDIA_API_KEY=...
The upstream may be either the origin or its /v1 base URL; duplicate /v1 is
normalized away. Env wiring into agentshell is a deliberate follow-up (ops-*).
"""
import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCAL = os.environ.get("LLM_ROUTER_LOCAL", "http://127.0.0.1:8088")
UPSTREAM = os.environ.get("LLM_ROUTER_UPSTREAM", "https://api.openai.com")
TOKEN_CAP = int(os.environ.get("LLM_ROUTER_TOKEN_CAP", "4096"))
IDLE_S = int(os.environ.get("LLM_ROUTER_IDLE_S", "300"))
MAX_RESIDENT = max(1, int(os.environ.get("LLM_ROUTER_MAX_RESIDENT", "1")))
PORT_BASE = int(os.environ.get("LLM_ROUTER_PORT_BASE", "8100"))
SPAWN_TIMEOUT = int(os.environ.get("LLM_ROUTER_SPAWN_TIMEOUT", "120"))
STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "llm-router",
)
MODEL_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
    "llama",
)
PASS_HDRS = ("authorization", "x-api-key", "anthropic-version",
             "openai-organization", "accept")
COPY_HDRS = ("content-type", "content-length", "cache-control",
             "transfer-encoding")


def log_decision(rec):
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(os.path.join(STATE, "decisions.jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")
    except OSError:
        pass


def resolve_local_model(name):
    """Map a request `model` field to a local GGUF path, or None.

    Same resolution order ask-local --serve --model uses: an absolute
    or .gguf path is taken verbatim if present; bare names are looked
    up under $XDG_DATA_HOME/llama with and without the .gguf suffix.
    Returning None means "not ours" -> legacy fixed LOCAL backend.
    """
    if not name or not isinstance(name, str):
        return None
    if (os.sep in name or name.endswith(".gguf")) and os.path.isfile(name):
        return name
    base = os.path.basename(name)
    for cand in (base, base + ".gguf"):
        p = os.path.join(MODEL_DIR, cand)
        if os.path.isfile(p):
            return p
    return None


class Registry:
    """model -> warm `ask-local --serve` backend.

    Thread-safe map of resident llama-server processes, mirrored to
    $XDG_STATE_HOME/llm-router/backends.json for visibility (cat shows
    what is sitting on the iGPU). Both the HTTP handler threads and the
    idle-reaper touch it; the lock guards the dict and process table,
    /health polling happens outside the lock.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._b = {}  # model -> {port, pid, path, last_used, proc}

    def _save(self):
        try:
            os.makedirs(STATE, exist_ok=True)
            snap = {m: {k: v for k, v in b.items() if k != "proc"}
                    for m, b in self._b.items()}
            tmp = os.path.join(STATE, "backends.json.tmp")
            with open(tmp, "w") as f:
                json.dump(snap, f, indent=2, sort_keys=True)
            os.replace(tmp, os.path.join(STATE, "backends.json"))
        except OSError:
            pass

    @staticmethod
    def _alive(b):
        proc = b.get("proc")
        return proc is not None and proc.poll() is None

    def _free_port(self):
        used = {b["port"] for b in self._b.values()}
        for p in range(PORT_BASE, PORT_BASE + 64):
            if p in used:
                continue
            with socket.socket() as s:
                try:
                    s.bind(("127.0.0.1", p))
                except OSError:
                    continue
            return p
        return None

    def _kill(self, model, why):
        """Drop `model` from the registry and SIGTERM its process. Lock held."""
        b = self._b.pop(model, None)
        if not b:
            return
        proc = b.get("proc")
        if proc and proc.poll() is None:
            try:
                proc.terminate()
            except OSError:
                pass
        self._save()
        log_decision({"ts": time.time(), "event": "evict", "model": model,
                      "port": b.get("port"), "why": why})

    @staticmethod
    def _wait_healthy(url):
        deadline = time.monotonic() + SPAWN_TIMEOUT
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(url + "/health", timeout=5) as r:
                    if r.status == 200:
                        return True
            except (urllib.error.URLError, ConnectionError, OSError):
                pass
            time.sleep(0.5)
        return False

    def acquire(self, model, path):
        """Get a live backend URL for `model`, spawning on miss.

        Returns (url|None, action, evicted) where action is one of
        "reuse" (live backend hit), "spawn" (launched + healthy), or
        "miss" (could not spawn -> caller falls back to legacy LOCAL).
        """
        with self._lock:
            b = self._b.get(model)
            if b and self._alive(b):
                b["last_used"] = time.time()
                self._save()
                return "http://127.0.0.1:%d" % b["port"], "reuse", 0
            if b:
                self._kill(model, "dead")
            evicted = 0
            while self._b and len(self._b) >= MAX_RESIDENT:
                lru = min(self._b, key=lambda m: self._b[m]["last_used"])
                self._kill(lru, "lru")
                evicted += 1
            port = self._free_port()
            if port is None:
                return None, "miss", evicted
            try:
                proc = subprocess.Popen(
                    ["ask-local", "--serve", "--model", path,
                     "--port", str(port)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except (FileNotFoundError, OSError):
                return None, "miss", evicted
            self._b[model] = {"port": port, "pid": proc.pid, "path": path,
                              "last_used": time.time(), "proc": proc}
            self._save()
            url = "http://127.0.0.1:%d" % port
        # Health poll outside the lock so concurrent requests don't stall.
        if self._wait_healthy(url):
            return url, "spawn", evicted
        with self._lock:
            self._kill(model, "unhealthy")
        return None, "miss", evicted

    def reap_idle(self):
        """Background loop: evict backends untouched for IDLE_S, prune dead."""
        while True:
            time.sleep(min(max(IDLE_S, 1), 30))
            now = time.time()
            with self._lock:
                for m in list(self._b):
                    b = self._b[m]
                    if not self._alive(b):
                        self._kill(m, "dead")
                    elif now - b["last_used"] > IDLE_S:
                        self._kill(m, "idle")


REG = Registry()


class Router(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _target_url(self, base):
        base = base.rstrip("/")
        # Tools usually call the router with /v1/..., while provider docs give
        # either an origin (https://api.openai.com) or a /v1 base URL
        # (https://integrate.api.nvidia.com/v1). Accept both shapes.
        if base.endswith("/v1") and self.path.startswith("/v1/"):
            base = base[:-3]
        return base + self.path

    def _forward(self, base, body, inject_env_key=False):
        req = urllib.request.Request(self._target_url(base), data=body,
                                     method=self.command)
        req.add_header("Content-Type",
                       self.headers.get("Content-Type", "application/json"))
        have_auth = False
        for h in PASS_HDRS:
            v = self.headers.get(h)
            if v:
                if h == "authorization":
                    have_auth = True
                req.add_header(h, v)
        if inject_env_key and not have_auth:
            key = os.environ.get("LLM_ROUTER_API_KEY")
            if not key:
                key = os.environ.get("OPENAI_API_KEY")
            if not key:
                key = os.environ.get("NVIDIA_API_KEY")
            if key:
                req.add_header("Authorization", "Bearer " + key)
        return urllib.request.urlopen(req, timeout=600)

    def _relay(self, resp):
        self.send_response(resp.status)
        for h in COPY_HDRS:
            v = resp.headers.get(h)
            if v:
                self.send_header(h, v)
        if not resp.headers.get("content-length"):
            self.send_header("Connection", "close")
        self.end_headers()
        while True:
            chunk = resp.read(8192)
            if not chunk:
                break
            self.wfile.write(chunk)
            self.wfile.flush()

    def _reply_json(self, obj, status=200):
        msg = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(msg)))
        self.end_headers()
        self.wfile.write(msg)

    def _review(self, diff: bytes):
        """POST /review: model-gated diff triage. ask-local --diff-gate decides
        low/high; low → local one-line summary, high → upstream chat review.
        Falls back to linecount when ask-local is absent (pre-deploy)."""
        t0 = time.monotonic()
        text = diff.decode("utf-8", "replace")
        try:
            p = subprocess.run(["ask-local", "--diff-gate"], input=text,
                               capture_output=True, text=True, timeout=30)
            risk = "low" if p.returncode == 0 else "high"
            why = p.stdout.strip() or p.stderr.strip()[:80]
            gate = "model"
        except (FileNotFoundError, subprocess.TimeoutExpired):
            risk = "high" if text.count("\n") > 200 else "low"
            why = "linecount fallback (ask-local unavailable)"
            gate = "linecount"
        lane = "local" if risk == "low" else "upstream"
        out = {"risk": risk, "why": why, "lane": lane, "gate": gate}
        try:
            if lane == "local":
                s = subprocess.run(
                    ["ask-local", "--fast",
                     "Summarize this diff in one line:\n" + text[:4000]],
                    capture_output=True, text=True, timeout=30)
                out["summary"] = s.stdout.strip().splitlines()[-1][:200]
            else:
                content = "Review this diff briefly:\n" + text[:12000]
                req = json.dumps({
                    "model": os.environ.get("LLM_ROUTER_REVIEW_MODEL", "gpt-4o"),
                    "messages": [{"role": "user", "content": content}],
                }).encode()
                self.path = "/v1/chat/completions"
                r = json.load(self._forward(UPSTREAM, req, inject_env_key=True))
                out["review"] = r["choices"][0]["message"]["content"]
        except Exception as e:
            out["error"] = str(e)
        self._reply_json(out)
        log_decision({
            "ts": time.time(), "lane": lane, "path": "/review", "gate": gate,
            "risk": risk, "tokens_in": len(text) // 4, "status": 200,
            "latency_ms": int((time.monotonic() - t0) * 1000),
        })

    def do_GET(self):
        self.do_POST()

    def do_POST(self):
        body = self._body()
        if self.path == "/review":
            return self._review(body)
        lane, tokens, model = "upstream", 0, None
        if self.path.startswith("/v1/chat/completions") and body:
            try:
                j = json.loads(body)
                msgs = j.get("messages") or []
                tokens = len(json.dumps(msgs)) // 4
                has_tools = bool(j.get("tools") or j.get("functions"))
                model = j.get("model")
                if tokens <= TOKEN_CAP and not has_tools:
                    lane = "local"
            except (ValueError, TypeError):
                pass
        spawn = reuse = 0
        evict = 0
        target = UPSTREAM
        if lane == "local":
            target = LOCAL
            path = resolve_local_model(model)
            if path:
                url, action, evict = REG.acquire(model, path)
                if url:
                    target = url
                    spawn = int(action == "spawn")
                    reuse = int(action == "reuse")
        t0 = time.monotonic()
        status = 0
        try:
            try:
                resp = self._forward(target, body, inject_env_key=(target == UPSTREAM))
            except urllib.error.URLError:
                if lane != "local":
                    raise
                lane = "local-unavailable"
                resp = self._forward(UPSTREAM, body, inject_env_key=True)
            status = resp.status
            self._relay(resp)
        except urllib.error.HTTPError as e:
            status = e.code
            self._relay(e)
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
            status = 502
            msg = json.dumps({"error": str(e)}).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
        finally:
            log_decision({
                "ts": time.time(), "lane": lane, "path": self.path,
                "model": model, "tokens_in": tokens, "status": status,
                "latency_ms": int((time.monotonic() - t0) * 1000),
                "spawn": spawn, "evict": evict, "reuse": reuse,
            })

    def log_message(self, fmt, *args):
        sys.stderr.write("llm-router: %s\n" % (fmt % args))


def main():
    addr = ("127.0.0.1", int(os.environ.get("LLM_ROUTER_PORT", "8090")))
    sys.stderr.write(
        "llm-router: %s:%d  local=%s  upstream=%s  cap=%d  "
        "idle=%ds  max_resident=%d\n"
        % (addr[0], addr[1], LOCAL, UPSTREAM, TOKEN_CAP, IDLE_S, MAX_RESIDENT))
    threading.Thread(target=REG.reap_idle, daemon=True).start()
    ThreadingHTTPServer(addr, Router).serve_forever()


if __name__ == "__main__":
    main()
