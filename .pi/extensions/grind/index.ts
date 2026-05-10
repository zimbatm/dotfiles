import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as vm from "node:vm";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";

type Json = any;

type Pick = { file: string; touches: string[]; plan: string; slug?: string; subslug?: string };
type AgentOpts = { label: string; phase: string; schema?: Json };
type AgentResult = Json;

type GrindConfig = {
  name: string;
  implementers?: number;
  archCadence?: number;
  rotation?: string[];
  fastCheck: string;
  wtParent?: string;
  treeGuard?: string;
  triageExtra?: (ctx: any) => string;
  implGate?: (ctx: any) => string;
  mergeGate?: (impl: any, files?: string[]) => { needsGate: boolean; cmd: string; instructions: string };
  benchFinal?: (ctx: any) => string;
  metaExtra?: (ctx: any) => string;
  forceSpecialist?: (triage: any) => string | null;
  triageSchema?: Record<string, any>;
  mergeDenylist?: RegExp[];
  architect?: (ctx: any) => string;
  specialists: Record<string, (ctx: any) => string>;
};

type GrindLoadedConfig = { meta?: any; CONFIG: GrindConfig };

type RunningGrind = {
  id: string;
  started: number;
  cwd: string;
  runDir: string;
  status: string;
  stopRequested: boolean;
};

const running = new Map<string, RunningGrind>();

function nowId() {
  const d = new Date();
  const stamp = d.toISOString().replace(/[-:]/g, "").replace(/\..*/, "Z");
  return `grind-${stamp}-${process.pid}`;
}

function safeSlug(s: string) {
  return s.replace(/[^\w.-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80) || "item";
}

async function mkdirp(dir: string) {
  await fs.promises.mkdir(dir, { recursive: true, mode: 0o700 });
}

async function appendJsonl(file: string, obj: any) {
  await fs.promises.appendFile(file, JSON.stringify({ ts: Date.now(), ...obj }) + "\n", "utf8");
}

function parseArgs(input: string): any {
  const s = (input || "").trim();
  if (!s) return {};
  try { return JSON.parse(s); } catch {}
  // Convenience: /grind rounds=1 implementers=2
  const out: any = {};
  for (const part of s.split(/\s+/)) {
    const m = part.match(/^([\w.-]+)=(.*)$/);
    if (!m) continue;
    const v = m[2];
    out[m[1]] = /^\d+$/.test(v) ? Number(v) : v === "true" ? true : v === "false" ? false : v;
  }
  return out;
}

function findConfigPath(cwd: string) {
  const candidates = [
    path.join(cwd, ".pi", "grind.config.js"),
    path.join(cwd, ".claude", "grind.config.js"),
  ];
  return candidates.find(p => fs.existsSync(p));
}

function loadConfig(cwd: string): GrindLoadedConfig {
  const configPath = findConfigPath(cwd);
  if (!configPath) throw new Error("No .pi/grind.config.js or .claude/grind.config.js found");
  let src = fs.readFileSync(configPath, "utf8");
  // Existing Claude config uses `export const meta` plus an unexported CONFIG.
  src = src.replace(/export\s+const\s+meta\s*=/, "const meta =");
  src += "\n;({ meta: (typeof meta !== 'undefined' ? meta : undefined), CONFIG });\n";
  const context = vm.createContext({ console, RegExp });
  const script = new vm.Script(src, { filename: configPath });
  const loaded = script.runInContext(context, { timeout: 1000 });
  if (!loaded?.CONFIG) throw new Error(`${configPath} did not define CONFIG`);
  return loaded;
}

function latestRunSummary(cwd: string): string | null {
  const root = path.join(cwd, ".pi", "grind-runs");
  if (!fs.existsSync(root)) return null;
  const runs = fs.readdirSync(root, { withFileTypes: true })
    .filter(d => d.isDirectory() && d.name.startsWith("grind-"))
    .map(d => {
      const dir = path.join(root, d.name);
      return { name: d.name, dir, mtime: fs.statSync(dir).mtimeMs };
    })
    .sort((a, b) => b.mtime - a.mtime);
  const latest = runs[0];
  if (!latest) return null;
  const eventsFile = path.join(latest.dir, "events.jsonl");
  if (!fs.existsSync(eventsFile)) return `Latest run: ${latest.name}\n  ${latest.dir}\n  no events.jsonl yet`;

  const events = fs.readFileSync(eventsFile, "utf8").trim().split("\n")
    .filter(Boolean)
    .map(line => { try { return JSON.parse(line); } catch { return null; } })
    .filter(Boolean);
  const open = new Map<number, any>();
  for (const e of events) {
    if (e.type === "agent_start") open.set(e.idx, e);
    if (e.type === "agent_end") open.delete(e.idx);
  }
  const last = events[events.length - 1];
  const openLast = Array.from(open.values()).pop();
  const state = openLast
    ? `appears interrupted/running at ${openLast.phase}/${openLast.label}`
    : last
      ? `last event: ${last.phase ?? "-"}/${last.type}${last.message ? ` — ${last.message}` : ""}`
      : "no parseable events";
  return `Latest run: ${latest.name}\n  ${latest.dir}\n  ${state}`;
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
  const currentScript = process.argv[1];
  const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
  if (currentScript && !isBunVirtualScript && fs.existsSync(currentScript)) {
    return { command: process.execPath, args: [currentScript, ...args] };
  }
  const execName = path.basename(process.execPath).toLowerCase();
  if (!/^(node|bun)(\.exe)?$/.test(execName)) return { command: process.execPath, args };
  return { command: "pi", args };
}

function textFromMessage(msg: any): string {
  if (!msg || msg.role !== "assistant") return "";
  const parts = Array.isArray(msg.content) ? msg.content : [];
  return parts.filter((p: any) => p.type === "text").map((p: any) => p.text || "").join("\n");
}

function extractJson(text: string): any {
  const trimmed = text.trim();
  if (!trimmed) return null;
  try { return JSON.parse(trimmed); } catch {}
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced) { try { return JSON.parse(fenced[1]); } catch {} }
  const firstObj = trimmed.indexOf("{");
  const lastObj = trimmed.lastIndexOf("}");
  if (firstObj >= 0 && lastObj > firstObj) { try { return JSON.parse(trimmed.slice(firstObj, lastObj + 1)); } catch {} }
  return null;
}

function schemaInstruction(schema?: Json) {
  if (!schema) return "";
  return `\n\n## REQUIRED structured return\nReturn ONLY a single JSON object matching this JSON Schema. No markdown, no prose.\n\nSchema:\n${JSON.stringify(schema, null, 2)}\n`;
}

class AgentRunner {
  private idx = 0;
  private active = 0;
  private queue: Array<() => void> = [];
  constructor(private cwd: string, private runDir: string, private maxConcurrency: number, private log: (msg: string) => Promise<void>) {}

  private async slot<T>(fn: () => Promise<T>): Promise<T> {
    if (this.active >= this.maxConcurrency) await new Promise<void>(r => this.queue.push(r));
    this.active++;
    try { return await fn(); }
    finally {
      this.active--;
      const next = this.queue.shift();
      if (next) next();
    }
  }

  async agent(prompt: string, opts: AgentOpts): Promise<AgentResult> {
    const idx = ++this.idx;
    if (idx > 1000) throw new Error("MAX_TOTAL_AGENTS_PER_WORKFLOW exceeded");
    return this.slot(async () => {
      const label = safeSlug(opts.label || `agent-${idx}`);
      const transcript = path.join(this.runDir, `agent-${String(idx).padStart(4, "0")}-${label}.jsonl`);
      await appendJsonl(path.join(this.runDir, "events.jsonl"), { type: "agent_start", idx, label: opts.label, phase: opts.phase });
      await this.log(`▶ ${opts.phase}/${opts.label}`);

      const childPrompt = `${prompt}${schemaInstruction(opts.schema)}\n\nRemember: your final text is consumed by an automation harness. Keep output compact.`;
      const args = ["--no-extensions", "--mode", "json", "-p", "--no-session", "--tools", "read,bash,edit,write,grep,find,ls", childPrompt];
      const invocation = getPiInvocation(args);
      let finalText = "";
      let stderr = "";
      let raw = "";
      const code = await new Promise<number>((resolve) => {
        const proc = spawn(invocation.command, invocation.args, { cwd: this.cwd, stdio: ["ignore", "pipe", "pipe"] });
        let buffer = "";
        const processLine = async (line: string) => {
          if (!line.trim()) return;
          raw += line + "\n";
          try {
            const event = JSON.parse(line);
            if (event.type === "message_end" && event.message?.role === "assistant") {
              const t = textFromMessage(event.message);
              if (t) finalText = t;
            }
          } catch {}
        };
        proc.stdout.on("data", (data) => {
          buffer += data.toString();
          const lines = buffer.split("\n");
          buffer = lines.pop() || "";
          for (const line of lines) void processLine(line);
        });
        proc.stderr.on("data", data => { stderr += data.toString(); });
        proc.on("close", code => { if (buffer.trim()) void processLine(buffer); resolve(code ?? 0); });
        proc.on("error", () => resolve(1));
      });
      await fs.promises.writeFile(transcript, raw || JSON.stringify({ stderr }) + "\n", "utf8");

      let result: any = finalText;
      if (opts.schema) {
        const parsed = extractJson(finalText);
        result = parsed ?? null;
        if (parsed === null) await this.log(`⚠ ${opts.label}: schema parse failed; returning null`);
      }
      await appendJsonl(path.join(this.runDir, "events.jsonl"), { type: "agent_end", idx, label: opts.label, phase: opts.phase, code, ok: code === 0, transcript });
      await this.log(`${code === 0 ? "✓" : "✗"} ${opts.phase}/${opts.label}`);
      return code === 0 ? result : null;
    });
  }
}

async function allSettledNull<T>(thunks: Array<() => Promise<T>>, log: (msg: string) => Promise<void>): Promise<Array<T | null>> {
  const settled = await Promise.allSettled(thunks.map(t => t()));
  return settled.map((r, i) => {
    if (r.status === "fulfilled") return r.value;
    void log(`⚠ parallel slot ${i} failed: ${r.reason?.message ?? r.reason}`);
    return null;
  });
}

class GrindRunner {
  private HOSTS = ["nv1", "web2"];
  private round = 0;
  private dryStreak = 0;
  private allCommits: string[] = [];
  private phaseName = "Init";
  private agentRunner!: AgentRunner;
  private REPO = '$(git rev-parse --show-toplevel)';
  private WT_PARENT!: string;
  private BASE!: string;
  private BASE_SETUP!: string;
  private MAIN_GUARD!: string;

  constructor(private state: RunningGrind, private config: GrindConfig, private args: any, private notify: (msg: string) => void) {}

  private async log(msg: string) {
    this.state.status = msg;
    await appendJsonl(path.join(this.state.runDir, "events.jsonl"), { type: "log", phase: this.phaseName, message: msg });
    this.notify(msg);
  }
  private async phase(name: string) {
    this.phaseName = name;
    await appendJsonl(path.join(this.state.runDir, "events.jsonl"), { type: "phase", phase: name });
    this.notify(`${this.state.id}: ${name}`);
  }
  private agent(prompt: string, opts: AgentOpts) { return this.agentRunner.agent(prompt, opts); }

  private initPrompts() {
    this.WT_PARENT = this.config.wtParent ?? `${this.REPO}/../${this.config.name}-grind`;
    this.BASE = `${this.WT_PARENT}/_base`;
    this.BASE_SETUP = `
## Setup — work in the grind base worktree, not the user's tree

Invoke shell via the Bash tool directly, never inside REPL. For long commands (>2min), keep output flowing/poll separately.
Keep output small: prefer Read/Glob/Grep over cat/ls/grep -rn; cap with head.

\`\`\`sh
BASE="${this.BASE}"
git fetch origin
USER_TREE="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
git -C "$USER_TREE" ls-files --others --exclude-standard -- 'backlog/*.md' | grep -q . && \\
  git -C "$USER_TREE" add -- 'backlog/*.md' && git -C "$USER_TREE" commit -m 'backlog(auto-salvage): stranded cross-repo dispatch'
if [[ -n "$(git -C "$USER_TREE" log origin/main..HEAD -- backlog/ 2>/dev/null)" && \\
      -z "$(git -C "$USER_TREE" diff --name-only origin/main..HEAD | grep -v '^backlog/')" ]]; then
  git -C "$USER_TREE" pull --rebase origin main && git -C "$USER_TREE" push origin HEAD:main && git fetch origin
fi
git worktree add -f --detach "$BASE" origin/main 2>/dev/null || \\
  (cd "$BASE" && git reset --hard origin/main)
cd "$BASE"
nix build .#agentshell --out-link .claude/profile 2>/dev/null && PATH=".claude/profile/bin:$PATH" || true
DIRTY="$(git -C "$USER_TREE" status --porcelain | grep -Fvx '?? .grind-stop' | grep -Ev '^[?][?] backlog/[^/]*[.]md$')"
[[ -z "$DIRTY" ]] || { echo "tree-guard: user tree $USER_TREE has uncommitted changes:" >&2; echo "$DIRTY" | sed 's/^/  /' >&2; exit 1; }
${this.config.treeGuard ?? ""}
\`\`\`
`;
    this.MAIN_GUARD = `
## Commit discipline — REQUIRED

You're on a detached HEAD in \`_base\`. Do NOT create branches. Your output is append-only docs/backlog/tests unless explicitly implementing.

\`\`\`sh
git add <your files> && git commit -m "..."
git pull --rebase origin main
git push origin HEAD:main
\`\`\`

## Epilogue — clean-tree guard (REQUIRED)
After push, \`git status --porcelain\` MUST be empty. Report clean_tree:false and uncommitted lines if non-empty.
`;
  }

  async run() {
    this.initPrompts();
    const maxConc = Math.max(2, (os.cpus()?.length ?? 4) - 2);
    this.agentRunner = new AgentRunner(this.state.cwd, this.state.runDir, maxConc, msg => this.log(msg));
    await this.log(`run dir: ${this.state.runDir}`);

    const MAX_ROUNDS = this.args?.rounds ?? Infinity;
    const IMPLEMENTERS = this.args?.implementers ?? this.config.implementers ?? 6;
    const DRY_LIMIT = this.args?.dryLimit ?? 2;
    const ARCH_CADENCE = this.args?.archCadence ?? this.config.archCadence ?? 5;
    const SPECIALIST_NAMES = this.config.rotation ?? Object.keys(this.config.specialists);

    while (this.round < MAX_ROUNDS && this.dryStreak < DRY_LIMIT && !this.state.stopRequested) {
      this.round++;
      await this.log(`=== Round ${this.round}/${MAX_ROUNDS} (dry ${this.dryStreak}/${DRY_LIMIT}) ===`);
      const ctx0 = { round: this.round, picks: [], BASE_SETUP: this.BASE_SETUP, MAIN_GUARD: this.MAIN_GUARD, IMPLEMENTERS };
      await this.phase("Triage");
      const triage = await this.agent(`
Triage backlog/ for the ${this.config.name} project — pick up to ${IMPLEMENTERS} items for parallel implementation.
${this.BASE_SETUP}
0. Salvage orphaned work from user-tree backlog and interrupted grind worktrees, per existing grind discipline.
1. \`ls backlog/*.md | grep -v README\` — report count as backlog_count
${this.config.triageExtra ? this.config.triageExtra(ctx0) : ""}
3. Pick ${IMPLEMENTERS} items by priority. Avoid duplicate backlog entries and obvious contention clusters. Prefer regressions > bugs > correctness > arch > features.
`, { label: `triage-r${this.round}`, phase: "Triage", schema: { type: "object", properties: { picks: { type: "array", items: { type: "object", properties: { file: { type: "string" }, touches: { type: "array", items: { type: "string" } }, plan: { type: "string" } }, required: ["file", "touches", "plan"] } }, backlog_count: { type: "number" }, ...(this.config.triageSchema ?? {}) }, required: ["picks", "backlog_count"] } });

      const picks: Pick[] = triage?.picks ?? [];
      const seen: Record<string, number> = {};
      for (const p of picks) {
        p.file = String(p.file || "").replace(/^.*?(backlog\/)/, "$1");
        const base = (p as any).subslug ?? p.file.replace(/^backlog\//, "").replace(/\.md$/, "");
        seen[base] = (seen[base] ?? 0) + 1;
        p.slug = seen[base] > 1 ? `${base}-p${seen[base]}` : base;
      }
      const backlogBefore = triage?.backlog_count ?? 0;
      await this.log(picks.length === 0 ? "Backlog empty or all in-flight — specialist-only round" : `Picked ${picks.length} items for implementers`);

      await this.phase("Work");
      const ctx = { round: this.round, picks, BASE_SETUP: this.BASE_SETUP, MAIN_GUARD: this.MAIN_GUARD, IMPLEMENTERS };
      const implStage = (pick: Pick) => this.implStage(pick, ctx);
      const specName = this.config.forceSpecialist?.(triage) ?? SPECIALIST_NAMES[(this.round - 1) % SPECIALIST_NAMES.length];
      const specSchema = { type: "object", properties: { clean_tree: { type: "boolean" }, uncommitted: { type: "array", items: { type: "string" } }, notes: { type: "string" } }, required: ["clean_tree"] };
      const specTask = () => this.agent(this.config.specialists[specName](ctx), { label: `${specName}-r${this.round}`, phase: "Work", schema: specSchema });
      const runArch = this.config.architect && this.round % ARCH_CADENCE === 0;
      const archTask = () => this.agent(this.config.architect!(ctx), { label: `architect-r${this.round}`, phase: "Work", schema: specSchema });
      const [specOut, archOut, implsNested] = await allSettledNull<any>([
        specTask,
        ...(runArch ? [archTask] : [() => Promise.resolve(null)]),
        () => allSettledNull(picks.map(p => () => implStage(p)), msg => this.log(msg)),
      ], msg => this.log(msg));
      const impls = (implsNested ?? []).filter(Boolean);

      await this.phase("Merge");
      const scopeMap = await this.scopeProbe(impls);
      let mergedThisRound = 0, abandonedThisRound = 0;
      for (const impl of impls) {
        const m = await this.mergeOne(impl, scopeMap);
        if (m?.merged) { mergedThisRound++; this.allCommits.push(impl.branch); }
        if (m?.abandoned) abandonedThisRound++;
      }
      const ok = (x: any) => !x ? "—" : x.clean_tree ? "✓" : `✗ uncommitted:[${(x.uncommitted ?? []).slice(0, 5).join(" ")}]`;
      await this.log(`${specName} ${ok(specOut)}${runArch ? ` architect ${ok(archOut)}` : ""} · Merged ${mergedThisRound}/${picks.length}, Abandoned ${abandonedThisRound}`);
      if (mergedThisRound > 0 && this.config.benchFinal) await this.agent(this.config.benchFinal({ ...ctx, mergedThisRound }), { label: `bench-final-r${this.round}`, phase: "Merge" });

      await this.phase("Meta");
      const meta = await this.meta(ctx, specName, specOut, archOut, runArch, mergedThisRound, abandonedThisRound, picks, ok);
      if (meta?.user_attention) await this.log(`⚠ Meta flagged: ${meta.user_attention}`);
      if (meta?.stop_requested) { await this.log(`Stop signal — exiting cleanly after round ${this.round}`); break; }
      const backlogAfter = meta?.backlog_count ?? backlogBefore;
      const madeProgress = picks.length > 0 || backlogAfter > backlogBefore;
      this.dryStreak = madeProgress ? 0 : this.dryStreak + 1;
      if (this.dryStreak > 0) await this.log(`Dry round (${this.dryStreak}/${DRY_LIMIT})`);
    }
    await this.phase("Meta");
    const sync = await this.syncUserTree();
    await this.log(`user-tree: ${sync?.user_tree ?? "?"}`);
    await this.log(`finished: ${this.dryStreak >= (this.args?.dryLimit ?? 2) ? "dry-streak" : this.state.stopRequested ? "stop" : "round-cap"}`);
  }

  private implStage(pick: Pick, ctx: any) {
    if (!/^backlog\/[\w.-]+\.md$/.test(pick.file)) { void this.log(`SKIP impl: unsafe pick.file ${JSON.stringify(pick.file)}`); return Promise.resolve(null); }
    const file = pick.file.replace(/^.*\//, "");
    const slug = pick.slug || safeSlug(file.replace(/\.md$/, ""));
    return this.agent(`
You are an IMPLEMENTER for the ${this.config.name} project. Item: backlog/${file}.

## Setup
\`\`\`sh
git fetch origin main
WT="${this.WT_PARENT}/${slug}"
git worktree add "$WT" -b grind/${slug} origin/main 2>/dev/null || \\
  (cd "$WT" && git rebase origin/main)
cd "$WT"
\`\`\`

## Implement
Plan: ${pick.plan}
Expected files: ${(pick.touches ?? []).join(", ")}

1. Read backlog/${file} + backlog/tried/.
2. Implement in "$WT".
3. \`${this.config.fastCheck}\` — invoke via Bash directly.
${this.config.implGate ? this.config.implGate({ ...ctx, pick, slug }) : "4. Report worst_regression_pct: 0 (no perf gate configured)"}
5. Commit. Single-phase: git rm backlog item. DO NOT push — merge agent handles that.

Report: branch, worktree, commits, files touched, worst_regression_pct.
`, { label: `impl-${slug}`, phase: "Work", schema: { type: "object", properties: { branch: { type: "string" }, worktree: { type: "string" }, commits: { type: "array", items: { type: "string" } }, files_touched: { type: "array", items: { type: "string" } }, backlog_deleted: { type: "boolean" }, worst_regression_pct: { type: "number" }, worst_regression_query: { type: "string" }, notes: { type: "string" } }, required: ["branch", "commits", "worst_regression_pct"] } }).then(r => r && { ...r, pick });
  }

  private async scopeProbe(impls: any[]): Promise<Map<string, string[]>> {
    const branches = impls.map(i => i.branch).filter((b: string) => /^grind\/[\w.-]+$/.test(b));
    if (!branches.length) return new Map();
    const r = await this.agent(`
Report the diff scope of each branch. Do exactly:
\`\`\`sh
git fetch -q origin main
for b in ${branches.join(" ")}; do
  echo "## $b"; git diff --name-only "origin/main...$b"
done
\`\`\`
Return one entry per branch with its file list.`, { label: `scope-r${this.round}`, phase: "Merge", schema: { type: "object", properties: { scopes: { type: "array", items: { type: "object", properties: { branch: { type: "string" }, files: { type: "array", items: { type: "string" } } }, required: ["branch", "files"] } } }, required: ["scopes"] } });
    return new Map((r?.scopes ?? []).map((s: any) => [s.branch, s.files]));
  }

  private async mergeOne(impl: any, scopeMap: Map<string, string[]>) {
    if (!/^grind\/[\w.-]+$/.test(impl.branch ?? "")) { await this.log(`SKIP merge: unsafe branch ${JSON.stringify(impl.branch)}`); return null; }
    const actualFiles = (scopeMap.get(impl.branch) ?? []).filter(f => /^[\w./-]+$/.test(f));
    const MERGE_DENY = this.config.mergeDenylist ?? [/^\.claude\/workflows\//, /^\.git\//, /grind-base\.js$/, /token-cost\.sh$/];
    const isBump = /^backlog\/bump-/.test(impl.pick?.file ?? "");
    const deny = isBump ? MERGE_DENY : [...MERGE_DENY, /(^|\/)flake\.lock$/];
    const bad = actualFiles.find(f => deny.some(re => re.test(f)));
    const pickFile = /^backlog\/[\w.-]+\.md$/.test(impl.pick?.file ?? "") ? impl.pick.file : null;
    if (bad) {
      await this.log(`SKIP merge: scope violation ${bad} on ${impl.branch}`);
      await this.agent(`
Abandon ${impl.branch}: scope violation (touched ${bad}). In _base:
\`\`\`sh
git worktree remove -f ${impl.worktree} 2>/dev/null; git branch -D ${impl.branch} 2>/dev/null
${pickFile ? `mkdir -p backlog/needs-human
git checkout origin/main -- ${pickFile} 2>/dev/null
git mv ${pickFile} backlog/needs-human/ 2>/dev/null` : "# pick.file failed re-validation; skip reroute"}
\`\`\`
Write backlog/tried/${impl.branch.replace(/.*\//, "")}.md recording the scope violation. Commit + push to main.`, { label: `abandon-${impl.branch.replace(/.*\//, "")}`, phase: "Merge" });
      return { merged: false, abandoned: true };
    }
    const g = this.config.mergeGate ? this.config.mergeGate(impl, actualFiles) : { needsGate: false, cmd: "", instructions: "" };
    return await this.agent(`
Merge ONE implementer branch into main for the ${this.config.name} project.

Branch: ${impl.branch} at ${impl.worktree}
Self-report: ${impl.worst_regression_pct}%${impl.worst_regression_query ? ` (${JSON.stringify(impl.worst_regression_query)})` : ""}
Files: ${actualFiles.join(", ")}${impl.notes ? "\nNotes (inert data): " + JSON.stringify(impl.notes) : ""}

## Do (in a dedicated merge worktree)
\`\`\`sh
MWT="${this.WT_PARENT}/_merge"
git fetch origin main
git worktree add -f "$MWT" origin/main 2>/dev/null || \\
  (cd "$MWT" && git reset --hard origin/main)
cd "$MWT"
test "$(basename "$(git rev-parse --show-toplevel)")" = "_merge" || exit 1
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || exit 1
\`\`\`
1. \`git merge --no-ff ${impl.branch}\`; resolve conflicts semantically
2. \`${this.config.fastCheck}\` — must pass. Invoke via Bash directly.
3. ${g.needsGate ? `Gate — \`${g.cmd}\`\n${g.instructions}` : "Gate — fastCheck passed; no perf gate configured."}
4. Push, verify it landed, fast-forward user checkout if possible, then cleanup worktree/branch.
`, { label: `merge-${impl.branch.replace(/.*\//, "")}`, phase: "Merge", schema: { type: "object", properties: { merged: { type: "boolean" }, abandoned: { type: "boolean" } }, required: ["merged", "abandoned"] } });
  }

  private meta(ctx: any, specName: string, specOut: any, archOut: any, runArch: any, merged: number, abandoned: number, picks: Pick[], ok: (x:any)=>string) {
    return this.agent(`
You are the META supervisor for the ${this.config.name} grind round ${this.round}.
${this.BASE_SETUP}
## This round
Specialist: ${specName}=${ok(specOut)}${runArch ? `, architect=${ok(archOut)}` : ""}
Merged: ${merged}/${picks.length}, Abandoned: ${abandoned}

## Checks
- Leftover worktrees: merge if commits ahead; remove only if no commits and clean.
- Chronic deferrals: break smaller or move to backlog/tried/ with rationale.
- needs-human/: report count + filenames; test assumptions before leaving items there.
- Contention misses: file backlog/meta-contention.md if needed.
${this.config.metaExtra ? this.config.metaExtra(ctx) : ""}
- Token cost: run .claude/workflows/token-cost.sh --by-role if present; attach notes if possible.
- Rotation drift: verify ${specName} is still in .claude/grind.config.js; stop_requested on drift.
- Stop signal: check user tree .grind-stop, remove if untracked, report stop_requested:true.

Fix directly what you can. File backlog/meta-<slug>.md for human-input issues. Report current backlog_count.
`, { label: `meta-r${this.round}`, phase: "Meta", schema: { type: "object", properties: { fixes_applied: { type: "array", items: { type: "string" } }, issues_filed: { type: "array", items: { type: "string" } }, user_attention: { type: "string" }, backlog_count: { type: "number" }, stop_requested: { type: "boolean" } }, required: ["fixes_applied", "issues_filed", "backlog_count", "stop_requested"] } });
  }

  private syncUserTree() {
    return this.agent(`
Sync the user's checkout to origin/main now that the grind has finished pushing.
\`\`\`sh
git fetch -q origin main
USER_TREE="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
git -C "$USER_TREE" merge --ff-only origin/main 2>&1 || true
echo "behind=$(git -C "$USER_TREE" rev-list --count HEAD..origin/main)"
echo "ahead=$(git -C "$USER_TREE" rev-list --count origin/main..HEAD)"
git -C "$USER_TREE" status --porcelain | head -5
\`\`\`
Report user_tree: "synced" if behind=0, else "N behind (dirty|ahead M)" with reason.`, { label: "user-tree-sync", phase: "Meta", schema: { type: "object", properties: { user_tree: { type: "string" } }, required: ["user_tree"] } });
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("grind", {
    description: "Run the pi-native grind harness (loads .pi/grind.config.js or .claude/grind.config.js)",
    handler: async (argText, ctx) => {
      const args = parseArgs(argText || "");
      const loaded = loadConfig(ctx.cwd);
      const id = nowId();
      const runDir = path.join(ctx.cwd, ".pi", "grind-runs", id);
      await mkdirp(runDir);
      await fs.promises.writeFile(path.join(runDir, "config.snapshot.json"), JSON.stringify({ meta: loaded.meta, args, cwd: ctx.cwd }, null, 2), "utf8");
      const state: RunningGrind = { id, started: Date.now(), cwd: ctx.cwd, runDir, status: "starting", stopRequested: false };
      running.set(id, state);
      ctx.ui.notify(`Started ${id}\n${runDir}`, "info");
      ctx.ui.setStatus("grind", `${id}: starting`);
      const runner = new GrindRunner(state, loaded.CONFIG, args, msg => {
        ctx.ui.setStatus("grind", `${id}: ${msg.slice(0, 80)}`);
      });
      void runner.run().catch(async err => {
        state.status = `failed: ${err?.message ?? err}`;
        await appendJsonl(path.join(runDir, "events.jsonl"), { type: "error", error: String(err?.stack ?? err) });
        ctx.ui.notify(`${id} failed: ${err?.message ?? err}`, "error");
      }).finally(() => {
        running.delete(id);
        ctx.ui.setStatus("grind", `${id}: done`);
      });
    },
  });

  pi.registerCommand("grind-status", {
    description: "Show active pi grind runs",
    handler: async (_args, ctx) => {
      if (running.size === 0) {
        const latest = latestRunSummary(ctx.cwd);
        return ctx.ui.notify(`No active grind runs in this pi process${latest ? `\n\n${latest}` : ""}`, "info");
      }
      const lines = Array.from(running.values()).map(r => `${r.id}: ${r.status}\n  ${r.runDir}`);
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });

  pi.registerCommand("grind-stop", {
    description: "Request graceful grind stop by touching .grind-stop and marking active runs",
    handler: async (_args, ctx) => {
      await fs.promises.writeFile(path.join(ctx.cwd, ".grind-stop"), "", { flag: "w" });
      for (const r of running.values()) if (r.cwd === ctx.cwd) r.stopRequested = true;
      ctx.ui.notify("Grind stop requested (.grind-stop touched)", "info");
    },
  });

  pi.registerTool({
    name: "grind_start",
    label: "Grind Start",
    description: "Start the pi-native grind harness. Prefer the /grind command for interactive use.",
    parameters: Type.Object({ args: Type.Optional(Type.Any()) }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const args = params.args ?? {};
      const loaded = loadConfig(ctx.cwd);
      const id = nowId();
      const runDir = path.join(ctx.cwd, ".pi", "grind-runs", id);
      await mkdirp(runDir);
      const state: RunningGrind = { id, started: Date.now(), cwd: ctx.cwd, runDir, status: "starting", stopRequested: false };
      running.set(id, state);
      const runner = new GrindRunner(state, loaded.CONFIG, args, msg => ctx.ui.setStatus("grind", `${id}: ${msg.slice(0, 80)}`));
      void runner.run().catch(err => appendJsonl(path.join(runDir, "events.jsonl"), { type: "error", error: String(err?.stack ?? err) })).finally(() => running.delete(id));
      return { content: [{ type: "text", text: `Started ${id}\nRun dir: ${runDir}` }], details: { id, runDir } };
    },
  });
}
