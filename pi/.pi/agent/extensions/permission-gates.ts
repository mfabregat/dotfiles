/**
 * Simple permission gates for pi.
 *
 * Rules:
 *   1. Inside the folder pi is opened in (and its subfolders): allow everything.
 *   2. Inside the system temp dir (os.tmpdir(), usually /tmp): allow everything.
 *      /dev/null is always safe.
 *   3. Destructive bash commands that target anything outside those safe areas
 *      ask for confirmation first. "Destructive" covers:
 *      - file deletion/overwrite commands: rm, unlink, rmdir, shred, mv,
 *        truncate, tee, dd (with of=), sed/perl/awk -i, sort -o, find -delete,
 *        git rm, rsync --delete
 *      - overwrite commands (only when the target already exists, or a flag
 *        forces overwrite): cp, install, ln -f, unzip -o, tar -x, curl -o/-O,
 *        wget -O. Fresh writes to new files are allowed.
 *      - git history/state destruction: git reset --hard, git clean,
 *        git checkout --, git push --force/-f, git branch -D
 *      - output redirection operators (>, >>, &>, N>, >|) that write to a file
 *        outside the safe areas — e.g. `echo hi > /etc/hosts` (any command).
 *   4. Combined lines (&&, ;, |, parentheses): every destructive segment is
 *      detected; the confirm dialog shows the whole line AND each isolated
 *      destructive part with its external targets.
 *
 * When there is no UI to ask (print/RPC modes), destructive commands on
 * external paths are denied — fail-safe.
 *
 * Pure helpers (tokenize/splitCommands/analyzeSegment/decide) are exported for
 * testing; the default export wires them into pi's tool_call and user_bash.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { homedir } from "node:os";
import path from "node:path";
import os from "node:os";
import fs from "node:fs";

// ── Destructive commands ───────────────────────────────────────────────
const DESTRUCTIVE = new Set([
  "rm", "unlink", "rmdir", "shred", "mv", "truncate", "tee",
  "dd", "sed", "perl", "awk", "sort", "find", "git", "rsync",
]);

// Overwrite commands: destructive only when the target file/dir already
// exists (or a flag forces overwrite). Fresh writes are not destructive.
// Existence is checked with a single stat per target — see decide().
const OVERWRITE = new Set(["cp", "install", "ln", "unzip", "tar", "curl", "wget"]);

const PREFIXES = new Set(["sudo", "env", "nohup", "time", "command", "nice", "exec", "doas"]);

// Redirection operators. `2>&1`-style dups are NOT file writes.
const DUP_REDIR_RE = /^\d*&>\d+$/; // e.g. 2>&1, >&2
const REDIR_RE = /^(?:\d+)?&?>+\|?(.*)$/; // e.g. >, >>, &>, 2>, >|, >file, >>file

/** Quote-aware tokenizer: splits on whitespace outside quotes, strips quotes and escapes. */
export function tokenize(input: string): string[] {
  const tokens: string[] = [];
  let cur = "";
  let quote: "'" | '"' | null = null;
  let escaped = false;
  for (const ch of input) {
    if (escaped) {
      cur += ch;
      escaped = false;
      continue;
    }
    if (ch === "\\" && quote !== "'") {
      escaped = true;
      continue;
    }
    if (quote) {
      if (ch === quote) quote = null;
      else cur += ch;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (/\s/.test(ch)) {
      if (cur) {
        tokens.push(cur);
        cur = "";
      }
      continue;
    }
    cur += ch;
  }
  if (cur) tokens.push(cur);
  return tokens;
}

/** Split on &&, ||, ; and | (outside quotes), strip wrapping parentheses. */
export function splitCommands(command: string): string[] {
  const segments: string[] = [];
  let cur = "";
  let quote: "'" | '"' | null = null;
  let escaped = false;
  for (const ch of command) {
    if (escaped) {
      cur += ch;
      escaped = false;
      continue;
    }
    if (ch === "\\" && quote !== "'") {
      cur += ch;
      escaped = true;
      continue;
    }
    if (quote) {
      cur += ch;
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      cur += ch;
      continue;
    }
    if (ch === "&" || ch === "|" || ch === ";") {
      if (cur.trim()) segments.push(cur.trim());
      cur = "";
      continue;
    }
    cur += ch;
  }
  if (cur.trim()) segments.push(cur.trim());
  return segments.map((s) => {
    let out = s.trim();
    while (out.startsWith("(")) out = out.slice(1).trim();
    while (out.endsWith(")")) out = out.slice(0, -1).trim();
    return out;
  }).filter(Boolean);
}

/** Strip command prefixes (sudo/env/nohup/...) and leading env assignments. */
function stripPrefixes(tokens: string[]): string[] {
  let rest = tokens;
  let changed = true;
  while (changed) {
    changed = false;
    while (rest.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(rest[0]) && !rest[0].startsWith("=")) {
      rest = rest.slice(1);
      changed = true;
    }
    if (rest.length && PREFIXES.has(rest[0])) {
      rest = rest.slice(1);
      changed = true;
    }
  }
  return rest;
}

/** True when a git invocation is destructive per the rules. */
function gitDestructive(tokens: string[]): boolean {
  // skip -C <dir> pairs (the value would otherwise shift the subcommand)
  const args: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] === "-C") {
      i++;
      continue;
    }
    args.push(tokens[i]);
  }
  if (!args.length) return false;
  const sub = args[0];
  if (sub === "reset") return args.slice(1).includes("--hard");
  if (sub === "clean") return true;
  if (sub === "checkout") {
    const rest = args.slice(1);
    return rest.includes("--") || rest.includes(".");
  }
  if (sub === "push") return args.slice(1).some((a) => a === "--force" || a === "-f" || a.startsWith("--force-with-lease"));
  if (sub === "branch") return args.slice(1).includes("-D") || args.slice(1).includes("--delete") || args.slice(1).includes("-d");
  if (sub === "rm") return true; // git rm deletes tracked files
  return false;
}

export interface SegmentAnalysis {
  raw: string;
  command: string;
  /** Absolute directory this segment executes in. */
  contextDir: string;
  destructive: boolean;
  /** Absolute target paths; empty means "operates on contextDir itself". */
  targets: string[];
}

/**
 * Analyze one command segment in a given working-directory context.
 * Pure: no I/O, no fs access.
 */
export function analyzeSegment(
  segment: string,
  contextDir: string,
  exists: (p: string) => boolean = fs.existsSync,
): SegmentAnalysis {
  const rawTokens = tokenize(segment);

  // 1. Scan for output redirections (>, >>, &>, N>, >|) before anything else,
  //    so redirect files don't leak into the command's own arguments.
  const consumed = new Set<number>();
  const redirFiles: string[] = [];
  for (let i = 0; i < rawTokens.length; i++) {
    const t = rawTokens[i];
    if (DUP_REDIR_RE.test(t)) {
      consumed.add(i);
      continue;
    }
    if (t.startsWith("<")) {
      consumed.add(i); // input redirection / heredoc: not a write
      continue;
    }
    const m = REDIR_RE.exec(t);
    if (!m) continue;
    consumed.add(i);
    let file = m[1];
    if (!file) {
      const next = rawTokens[i + 1];
      if (next === undefined) continue;
      file = next;
      consumed.add(i + 1);
      i++;
    }
    if (file !== "/dev/null") redirFiles.push(file);
  }
  const tokens = rawTokens.filter((_, i) => !consumed.has(i));
  const stripped = stripPrefixes(tokens);
  const command = stripped[0] ?? "";
  const args = stripped.slice(1);

  const analysis: SegmentAnalysis = {
    raw: segment,
    command,
    contextDir,
    destructive: false,
    targets: [],
  };

  const positional = (list: string[]): string[] => {
    const out: string[] = [];
    let endFlags = false;
    for (const t of list) {
      if (!endFlags && t === "--") {
        endFlags = true;
        continue;
      }
      if (!endFlags && t.startsWith("-")) continue;
      out.push(t);
    }
    return out;
  };

  const resolveTarget = (t: string): string => {
    if (t === "~" || t.startsWith("~/")) t = path.join(homedir(), t.slice(1));
    if (t.startsWith("$HOME")) t = path.join(homedir(), t.slice(5));
    if (t.startsWith("${HOME}")) t = path.join(homedir(), t.slice(7));
    return path.resolve(contextDir, t);
  };

  if (DESTRUCTIVE.has(command)) {
    switch (command) {
      case "rm":
      case "unlink":
      case "rmdir":
      case "shred":
      case "mv":
      case "truncate":
      case "tee": {
        analysis.destructive = true;
        analysis.targets = positional(args).map(resolveTarget);
        break;
      }
      case "dd": {
        const of = args.find((a) => a.startsWith("of="));
        if (of) {
          analysis.destructive = true;
          analysis.targets = [resolveTarget(of.slice(3))];
        }
        break;
      }
      case "sed":
      case "perl":
      case "awk": {
        if (args.some((a) => a.startsWith("-i"))) {
          analysis.destructive = true;
          const pos = positional(args);
          if (pos.length) analysis.targets = [resolveTarget(pos[pos.length - 1])];
        }
        break;
      }
      case "sort": {
        const idx = args.findIndex((a) => a === "-o" || a.startsWith("-o") || a === "--output" || a.startsWith("--output="));
        if (idx !== -1) {
          analysis.destructive = true;
          const val = args[idx].startsWith("--output=")
            ? args[idx].slice(9)
            : args[idx].startsWith("-o") && args[idx] !== "-o"
              ? args[idx].slice(2)
              : args[idx + 1];
          if (val) analysis.targets = [resolveTarget(val)];
        }
        break;
      }
      case "find": {
        if (args.includes("-delete")) {
          analysis.destructive = true;
          const pos = positional(args);
          if (pos.length && !pos[0].startsWith("-")) analysis.targets = [resolveTarget(pos[0])];
        }
        break;
      }
      case "git": {
        if (gitDestructive(args)) {
          analysis.destructive = true;
          const cIdx = args.indexOf("-C");
          if (cIdx !== -1 && args[cIdx + 1]) analysis.targets = [resolveTarget(args[cIdx + 1])];
        }
        break;
      }
      case "rsync": {
        if (args.includes("--delete")) {
          analysis.destructive = true;
          const pos = positional(args);
          const dest = pos[pos.length - 1];
          // remote destinations (host:path) can't be resolved statically
          if (dest && !dest.includes(":")) analysis.targets = [resolveTarget(dest)];
        }
        break;
      }
    }
  }

  // 2. Overwrite commands: destructive only when the target already exists
  //    (or the command forces overwrite). Each check is one stat call.
  if (OVERWRITE.has(command)) {
    const pos = positional(args);
    const lastPos = pos[pos.length - 1];
    switch (command) {
      case "cp": {
        if (args.includes("-n") || args.includes("--no-clobber")) break; // never overwrites
        if (lastPos) {
          const dest = resolveTarget(lastPos);
          if (exists(dest)) {
            analysis.destructive = true;
            analysis.targets = [dest];
          }
        }
        break;
      }
      case "install": {
        if (lastPos) {
          const dest = resolveTarget(lastPos);
          if (exists(dest)) {
            analysis.destructive = true;
            analysis.targets = [dest];
          }
        }
        break;
      }
      case "ln": {
        if ((args.includes("-f") || args.includes("--force")) && lastPos) {
          const dest = resolveTarget(lastPos);
          if (exists(dest)) {
            analysis.destructive = true;
            analysis.targets = [dest];
          }
        }
        break;
      }
      case "unzip": {
        if (args.includes("-o")) {
          const dIdx = args.indexOf("-d");
          const destDir = dIdx !== -1 && args[dIdx + 1] ? resolveTarget(args[dIdx + 1]) : analysis.contextDir;
          if (exists(destDir)) {
            analysis.destructive = true;
            analysis.targets = [destDir];
          }
        }
        break;
      }
      case "tar": {
        const flat = " " + args.join(" ");
        const extracts =
          /(^| )-[^ ]*x/.test(flat) ||
          /(^| )--extract( |$)/.test(flat) ||
          /(^| )--get( |$)/.test(flat);
        if (extracts) {
          const cIdx = args.indexOf("-C");
          const destDir = cIdx !== -1 && args[cIdx + 1] ? resolveTarget(args[cIdx + 1]) : analysis.contextDir;
          if (exists(destDir)) {
            analysis.destructive = true;
            analysis.targets = [destDir];
          }
        }
        break;
      }
      case "curl": {
        // -o FILE / --output FILE / --output=FILE → explicit; -O/--remote-name → basename in cwd
        let out: string | undefined;
        const idx = args.findIndex((a) => a === "-o" || a === "--output");
        if (idx !== -1) out = args[idx + 1];
        else {
          const attached = args.find((a) => a.startsWith("--output=") || (a.startsWith("-o") && a.length > 2));
          if (attached) out = attached.startsWith("--output=") ? attached.slice(9) : attached.slice(2);
        }
        if (out) {
          const dest = resolveTarget(out);
          if (exists(dest)) {
            analysis.destructive = true;
            analysis.targets = [dest];
          }
        } else if (args.includes("-O") || args.includes("--remote-name")) {
          analysis.destructive = true; // writes basename into contextDir
        }
        break;
      }
      case "wget": {
        if (args.includes("--no-clobber")) break; // never overwrites
        // -O FILE / --output-document FILE / --output-document=FILE → explicit
        let out: string | undefined;
        const idx = args.findIndex((a) => a === "-O" || a === "--output-document");
        if (idx !== -1) out = args[idx + 1];
        else {
          const attached = args.find((a) => a.startsWith("--output-document=") || (a.startsWith("-O") && a.length > 2));
          if (attached) out = attached.startsWith("--output-document=") ? attached.slice(18) : attached.slice(2);
        }
        if (out) {
          const dest = resolveTarget(out);
          if (exists(dest)) {
            analysis.destructive = true;
            analysis.targets = [dest];
          }
        } else {
          analysis.destructive = true; // writes basename into contextDir
        }
        break;
      }
    }
  }

  // 3. Output redirections make ANY command a file writer (e.g. `echo hi > /etc/x`).
  if (redirFiles.length) {
    analysis.destructive = true;
    for (const f of redirFiles) analysis.targets.push(resolveTarget(f));
  }

  return analysis;
}

export interface CaughtSegment {
  /** The isolated segment text as it appeared in the combined line. */
  segment: string;
  /** Absolute directory the segment runs in (after any cd). */
  contextDir: string;
  /** External target paths that triggered the gate. */
  targets: string[];
}

export interface Decision {
  allow: boolean;
  /** Every destructive segment that hits an external path. */
  caught: CaughtSegment[];
  /** Unique external targets across all caught segments. */
  externalTargets: string[];
  reason: string;
}

function isInside(child: string, parent: string): boolean {
  const rel = path.relative(parent, child);
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

function isSafePath(p: string, rootDir: string, tmpDir: string): boolean {
  if (p === "/dev/null") return true;
  return isInside(p, rootDir) || isInside(p, tmpDir);
}

/**
 * Apply the user's rules to a full bash command.
 * @param command  the raw bash command string
 * @param rootDir  the opened folder (everything inside is allowed)
 * @param startDir initial working directory (defaults to rootDir)
 */
export function decide(command: string, rootDir: string, startDir = rootDir): Decision {
  const caught: CaughtSegment[] = [];
  let contextDir = path.resolve(startDir);
  rootDir = path.resolve(rootDir);
  const tmpDir = os.tmpdir();

  for (const segment of splitCommands(command)) {
    const tokens = tokenize(segment);
    const stripped = stripPrefixes(tokens);

    // cd handling: update context for subsequent segments
    if (stripped[0] === "cd") {
      const dest = stripped[1];
      if (!dest) contextDir = homedir();
      else if (dest === "~" || dest.startsWith("~/")) contextDir = path.resolve(homedir(), dest.slice(1));
      else contextDir = path.resolve(contextDir, dest);
      continue;
    }

    const analysis = analyzeSegment(segment, contextDir);
    if (!analysis.destructive) continue;

    const targets = analysis.targets.length ? analysis.targets : [analysis.contextDir];
    const external = targets.filter((t) => !isSafePath(t, rootDir, tmpDir));
    if (external.length) {
      caught.push({
        segment: analysis.raw,
        contextDir: analysis.contextDir,
        targets: [...new Set(external)],
      });
    }
  }

  if (caught.length === 0) {
    return { allow: true, caught: [], externalTargets: [], reason: "" };
  }
  const externalTargets = [...new Set(caught.flatMap((c) => c.targets))];
  const more = caught.length > 1 ? ` (+${caught.length - 1} more)` : "";
  return {
    allow: false,
    caught,
    externalTargets,
    reason: `destructive command targets outside workspace: ${caught[0].segment}${more}`,
  };
}

function formatPrompt(command: string, decision: Decision, rootDir: string): string {
  const lines = [`Command: ${command}`, ""];
  lines.push(
    decision.caught.length === 1
      ? "Destructive command outside the workspace:"
      : `${decision.caught.length} destructive commands outside the workspace:`,
  );
  for (const c of decision.caught) {
    const runIn = c.contextDir !== rootDir ? `   (run in ${c.contextDir})` : "";
    lines.push(`  • ${c.segment}${runIn}`);
    if (c.targets.length) lines.push(`      → targets: ${c.targets.join(", ")}`);
    else lines.push(`      → operates on ${c.contextDir}`);
  }
  return lines.join("\n");
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;
    const input = event.input as { command?: string; cwd?: string };
    const startDir = input.cwd ? path.resolve(ctx.cwd, input.cwd) : ctx.cwd;
    const decision = decide(input.command ?? "", ctx.cwd, startDir);
    if (decision.allow) return;
    if (!ctx.hasUI) {
      return { block: true, reason: `Denied: ${decision.reason}` };
    }
    const ok = await ctx.ui.confirm(
      "Destructive command outside workspace?",
      formatPrompt(input.command ?? "", decision, ctx.cwd),
    );
    if (!ok) {
      return { block: true, reason: `Denied by user: ${decision.reason}` };
    }
  });

  pi.on("user_bash", async (event, ctx) => {
    const decision = decide(event.command, ctx.cwd, event.cwd ?? ctx.cwd);
    if (decision.allow) return;
    if (!ctx.hasUI) {
      return {
        result: { output: `Blocked: ${decision.reason}`, exitCode: 1, cancelled: false, truncated: false },
      };
    }
    const ok = await ctx.ui.confirm(
      "Destructive command outside workspace?",
      formatPrompt(event.command, decision, ctx.cwd),
    );
    if (!ok) {
      return {
        result: { output: `Blocked by user: ${decision.reason}`, exitCode: 1, cancelled: false, truncated: false },
      };
    }
  });
}
