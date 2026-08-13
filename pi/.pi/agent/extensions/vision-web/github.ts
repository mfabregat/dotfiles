/**
 * GitHub repo contents, matching the pi-web-access documented behavior:
 *
 *   - GitHub URLs are CLONED locally (shallow) instead of scraped. The agent
 *     gets real file contents AND a local path to explore with read/bash.
 *   - Root URLs → repo tree + README. /tree/ → directory listing.
 *     /blob/ → file contents.
 *   - Repos over `githubClone.maxRepoSizeMB` (default 350MB) get a lightweight
 *     API-based view instead of a full clone (override: `forceClone: true`).
 *   - Commit SHA URLs are handled via the API (raw + tree endpoints).
 *   - Private repos require the `gh` CLI.
 *   - Clones are cached for the session and wiped on session change.
 *   - `githubClone.enabled: false` skips this handling entirely so the URL
 *     falls through to the normal HTTP extraction path (lightweight fetch).
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  existsSync, readFileSync, readdirSync, statSync, openSync, readSync, closeSync,
  rmSync, mkdirSync,
} from "node:fs";
import { homedir } from "node:os";
import { join, sep, extname } from "node:path";
import type { GitHubCloneConfig } from "./config.js";

const execFileAsync = promisify(execFile);

const MAX_TREE_ENTRIES = 200;
const MAX_INLINE_FILE_CHARS = 100_000;
const MAX_README_CHARS = 8_192;
const CLONE_TIMEOUT_MS = 180_000;
const API = "https://api.github.com";
const API_TTL_MS = 10 * 60_000;

const NON_CODE_SEGMENTS = new Set([
  "issues", "pull", "pulls", "releases", "actions", "wiki", "projects",
  "discussions", "security", "settings", "branches", "tags", "stargazers",
  "watchers", "network", "forks", "milestone", "labels", "packages",
  "codespaces", "contribute", "community", "sponsors", "invitations",
  "notifications", "insights", "blame", "commits", "graphs", "compare",
]);

const NOISE_DIRS = new Set([
  "node_modules", "vendor", ".next", "dist", "build", "__pycache__",
  ".venv", "venv", ".tox", ".mypy_cache", ".pytest_cache", "target",
  ".gradle", ".idea", ".vscode",
]);

const BINARY_EXTENSIONS = new Set([
  ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp", ".svg", ".tiff", ".tif",
  ".mp3", ".mp4", ".avi", ".mov", ".mkv", ".flv", ".wmv", ".wav", ".ogg", ".webm", ".flac", ".aac",
  ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".zst",
  ".exe", ".dll", ".so", ".dylib", ".bin", ".o", ".a", ".lib",
  ".woff", ".woff2", ".ttf", ".otf", ".eot",
  ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
  ".sqlite", ".db", ".sqlite3", ".pyc", ".pyo", ".class", ".jar", ".war",
  ".iso", ".img", ".dmg",
]);

export interface GitHubInfo {
  owner: string;
  repo: string;
  path?: string;
  ref?: string;
  isSha?: boolean;
}

export interface GitHubResult {
  title: string;
  content: string;
  error: string | null;
  /** Local clone/checked-out path for the agent to explore with read/bash. */
  localPath?: string;
  /** True when the content came from the API view rather than a clone. */
  apiView?: boolean;
}

export function parseGitHubUrl(url: string): GitHubInfo | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  const host = parsed.hostname.toLowerCase();
  if (host !== "github.com" && host !== "www.github.com") return null;
  const segments = parsed.pathname
    .split("/")
    .filter(Boolean)
    .map((s) => {
      try {
        return decodeURIComponent(s);
      } catch {
        return s;
      }
    });
  if (segments.length < 2) return null;
  const owner = segments[0];
  const repo = segments[1].replace(/\.git$/, "");
  if (NON_CODE_SEGMENTS.has(segments[2]?.toLowerCase() ?? "")) return null;
  const rest = segments.slice(2);

  if (rest.length === 0) return { owner, repo };
  const first = rest[0].toLowerCase();
  if (first === "tree" || first === "blob" || first === "raw") {
    const ref = rest[1];
    if (!ref) return { owner, repo };
    return { owner, repo, ref, path: rest.slice(2).join("/") || undefined };
  }
  if (first === "commit") {
    const sha = rest[1];
    if (!sha) return { owner, repo };
    return { owner, repo, ref: sha, path: rest.slice(2).join("/") || undefined, isSha: true };
  }
  return { owner, repo, path: rest.join("/") };
}

let ghAvailable: boolean | null = null;
async function hasGh(): Promise<boolean> {
  if (ghAvailable !== null) return ghAvailable;
  try {
    await execFileAsync("gh", ["--version"], { timeout: 5_000 });
    ghAvailable = true;
  } catch {
    ghAvailable = false;
  }
  return ghAvailable;
}

// ------------------------------------------------------------ GitHub API/raw

interface RepoMeta {
  defaultBranch: string | null;
  sizeKB: number | null;
  private: boolean | null;
  fetchedAt: number;
}

const repoMetaCache = new Map<string, RepoMeta>();
const treeCache = new Map<string, { entries: { path: string; type: string }[]; fetchedAt: number }>();

async function apiFetch(path: string): Promise<any | null> {
  try {
    const res = await fetch(`${API}${path}`, {
      headers: { "User-Agent": "vision-web", Accept: "application/vnd.github+json" },
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

async function repoMeta(owner: string, repo: string): Promise<RepoMeta | null> {
  const key = `${owner}/${repo}`;
  const cached = repoMetaCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < API_TTL_MS) return cached;
  const data = await apiFetch(`/repos/${owner}/${repo}`);
  if (!data) return null;
  const meta: RepoMeta = {
    defaultBranch: typeof data.default_branch === "string" ? data.default_branch : null,
    sizeKB: typeof data.size === "number" ? data.size : null,
    private: typeof data.private === "boolean" ? data.private : null,
    fetchedAt: Date.now(),
  };
  repoMetaCache.set(key, meta);
  return meta;
}

async function fetchRaw(owner: string, repo: string, ref: string, path: string): Promise<string | null> {
  const url = `https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path}`;
  try {
    const res = await fetch(url, { redirect: "follow" });
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    const text = buf.toString("utf-8");
    return text.length > MAX_INLINE_FILE_CHARS ? text.slice(0, MAX_INLINE_FILE_CHARS) + "\n\n[File truncated]" : text;
  } catch {
    return null;
  }
}

async function treeEntries(owner: string, repo: string, ref: string): Promise<{ path: string; type: string }[] | null> {
  const key = `${owner}/${repo}@${ref}`;
  const cached = treeCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < API_TTL_MS) return cached.entries;
  const data = await apiFetch(`/repos/${owner}/${repo}/git/trees/${encodeURIComponent(ref)}?recursive=1`);
  if (!data || !Array.isArray(data.tree)) return null;
  const entries: { path: string; type: string }[] = data.tree
    .map((t: any) => ({ path: typeof t.path === "string" ? t.path : "", type: t.type === "tree" ? "dir" : "file" }))
    .filter((e) => e.path !== "");
  treeCache.set(key, { entries, fetchedAt: Date.now() });
  return entries;
}

function filterTree(entries: { path: string; type: string }[], prefix: string): string {
  const lines: string[] = [];
  const prefixNorm = prefix ? `${prefix.replace(/\/+$/, "")}/` : "";
  const seenDirs = new Set<string>();
  for (const entry of entries) {
    if (!entry.path.startsWith(prefixNorm)) continue;
    const rel = entry.path.slice(prefixNorm.length);
    if (!rel) continue;
    if (entry.type === "dir") {
      const top = rel.split("/")[0];
      if (NOISE_DIRS.has(top) || seenDirs.has(top)) continue;
      seenDirs.add(top);
      lines.push(`${top}/`);
    } else {
      const parts = rel.split("/");
      if (parts.length > 1) {
        const top = parts[0];
        if (NOISE_DIRS.has(top) || seenDirs.has(top)) continue;
        seenDirs.add(top);
        lines.push(`${top}/`);
      } else {
        lines.push(rel);
      }
    }
    if (lines.length >= MAX_TREE_ENTRIES) break;
  }
  return lines.join("\n");
}

/** Lightweight API view: README + tree for roots, listing for /tree/, contents for /blob/. */
async function apiView(info: GitHubInfo, ref: string): Promise<GitHubResult> {
  const { owner, repo } = info;
  const title = info.path ? `${owner}/${repo} - ${info.path}` : `${owner}/${repo}`;
  if (info.path) {
    const raw = await fetchRaw(owner, repo, ref, info.path);
    if (raw !== null) return { title, content: `# ${info.path}\n\n${raw}`, error: null, apiView: true };
    return { title, content: "", error: `Could not fetch ${info.path} via API`, apiView: true };
  }
  const tree = await treeEntries(owner, repo, ref);
  let content = `Repository tree (${owner}/${repo}${info.ref ? ` @ ${info.ref}` : ""}):\n${tree ? filterTree(tree, "") : "(tree unavailable)"}\n`;
  const readme = (await fetchRaw(owner, repo, ref, "README.md")) ?? (await fetchRaw(owner, repo, ref, "readme.md")) ?? (await fetchRaw(owner, repo, ref, "README.rst"));
  if (readme) content = `# README\n${readme.slice(0, MAX_README_CHARS)}${readme.length > MAX_README_CHARS ? "\n\n[README truncated]" : ""}\n\n---\n\n${content}`;
  return { title, content, error: null, apiView: true };
}

// -------------------------------------------------------------------- clone

function cacheRoot(): string {
  return process.env.XDG_CACHE_HOME
    ? join(process.env.XDG_CACHE_HOME, "vision-web")
    : join(homedir(), ".cache", "vision-web");
}

function cloneDir(info: GitHubInfo): string {
  const key = `${info.owner}__${info.repo}__${info.ref ?? "default"}`.replace(/[^a-zA-Z0-9_.-]/g, "_");
  return join(cacheRoot(), "github", key);
}

/** Remove the per-session clone cache. Called on session change. */
export function wipeCloneCache(): void {
  try {
    rmSync(join(cacheRoot(), "github"), { recursive: true, force: true });
  } catch {
    // best effort
  }
}

async function cloneRepo(info: GitHubInfo): Promise<string | null> {
  const dir = cloneDir(info);
  if (existsSync(dir)) return dir;
  mkdirSync(join(cacheRoot(), "github"), { recursive: true });
  const args = ["clone", "--depth", "1", "--single-branch"];
  if (info.ref) args.push("--branch", info.ref);
  args.push(`https://github.com/${info.owner}/${info.repo}.git`, dir);
  try {
    await execFileAsync("git", args, { timeout: CLONE_TIMEOUT_MS, maxBuffer: 1 << 20 });
    return dir;
  } catch {
    return null;
  }
}

function isBinaryFile(filePath: string): boolean {
  const ext = extname(filePath).toLowerCase();
  if (BINARY_EXTENSIONS.has(ext)) return true;
  let fd: number;
  try {
    fd = openSync(filePath, "r");
  } catch {
    return false;
  }
  try {
    const buf = Buffer.alloc(1024);
    const n = readSync(fd, buf, 0, 1024, 0);
    return buf.subarray(0, n).includes(0);
  } finally {
    closeSync(fd);
  }
}

function readTextFile(filePath: string): string | null {
  try {
    if (isBinaryFile(filePath)) return "[binary file — skipped]";
    const size = statSync(filePath).size;
    if (size > MAX_INLINE_FILE_CHARS * 2) {
      const fd = openSync(filePath, "r");
      const buf = Buffer.alloc(MAX_INLINE_FILE_CHARS);
      const n = readSync(fd, buf, 0, MAX_INLINE_FILE_CHARS, 0);
      closeSync(fd);
      return buf.toString("utf-8").slice(0, n) + "\n\n[File truncated]";
    }
    const text = readFileSync(filePath, "utf-8");
    return text.length > MAX_INLINE_FILE_CHARS ? text.slice(0, MAX_INLINE_FILE_CHARS) + "\n\n[File truncated]" : text;
  } catch {
    return null;
  }
}

function listDirLocal(dir: string, relPrefix: string): string {
  const entries: string[] = [];
  const walk = (current: string, rel: string) => {
    if (entries.length >= MAX_TREE_ENTRIES) return;
    let names: string[];
    try {
      names = readdirSync(current);
    } catch {
      return;
    }
    names.sort((a, b) => {
      const aDir = statSync(join(current, a)).isDirectory();
      const bDir = statSync(join(current, b)).isDirectory();
      if (aDir !== bDir) return aDir ? -1 : 1;
      return a.localeCompare(b);
    });
    for (const name of names) {
      if (entries.length >= MAX_TREE_ENTRIES) return;
      if (name.startsWith(".") && rel === "") continue;
      const full = join(current, name);
      let isDir: boolean;
      try {
        isDir = statSync(full).isDirectory();
      } catch {
        continue;
      }
      if (isDir && NOISE_DIRS.has(name)) continue;
      const relPath = rel ? `${rel}/${name}` : name;
      entries.push(isDir ? `${relPath}/` : relPath);
      if (isDir && rel.split("/").length < 3) walk(full, relPath);
    }
  };
  walk(dir, relPrefix);
  return entries.join("\n");
}

function serveClone(dir: string, info: GitHubInfo): GitHubResult {
  const title = info.path ? `${info.owner}/${info.repo} - ${info.path}` : `${info.owner}/${info.repo}`;
  const rel = info.path ?? "";
  const full = join(dir, rel);
  if (!full.startsWith(dir + sep) && full !== dir) {
    return { title, content: "", error: "Path escapes repository root" };
  }
  if (!existsSync(full)) {
    return { title, content: "", error: `Path not found: ${rel || "(root)"}` };
  }
  const st = statSync(full);
  if (st.isDirectory()) {
    let content = `Repository tree (${info.owner}/${info.repo}${info.ref ? ` @ ${info.ref}` : ""}):\n${listDirLocal(full, rel)}\n`;
    if (rel === "" || rel === ".") {
      const readme = ["README.md", "readme.md", "Readme.md", "README.rst", "README.txt"]
        .map((name) => join(full, name))
        .find((p) => existsSync(p));
      if (readme) {
        const text = readTextFile(readme);
        if (text && !text.startsWith("[binary")) {
          content = `# README\n${text.slice(0, MAX_README_CHARS)}${text.length > MAX_README_CHARS ? "\n\n[README truncated]" : ""}\n\n---\n\n${content}`;
        }
      }
    }
    return { title, content, error: null, localPath: full };
  }
  const text = readTextFile(full);
  if (text === null) return { title, content: "", error: `Could not read file: ${rel}` };
  return { title, content: `# ${rel}\n\n${text}`, error: null, localPath: full };
}

// ------------------------------------------------------------------- public

export async function extractGitHub(url: string, config: GitHubCloneConfig): Promise<GitHubResult | null> {
  if (!config.enabled) return null;
  const info = parseGitHubUrl(url);
  if (!info) return null;
  const { owner, repo } = info;
  const title = info.path ? `${owner}/${repo} - ${info.path}` : `${owner}/${repo}`;
  const meta = await repoMeta(owner, repo);

  // Clone-first (unless: commit SHA, oversized without forceClone, private without gh).
  const sizeKB = meta?.sizeKB ?? null;
  const overLimit = sizeKB !== null && sizeKB > config.maxRepoSizeMB * 1024 && !config.forceClone;
  const isPrivate = meta?.private === true;
  const gh = await hasGh();
  if (!info.isSha && !overLimit && (!isPrivate || gh)) {
    const dir = await cloneRepo(info);
    if (dir) return serveClone(dir, info);
    // Clone failed (e.g. slow/throttled network) → API fallback below.
  }

  // API view for oversized / SHA / private-without-gh / clone failures.
  if (isPrivate && !gh) {
    return { title, content: "", error: "Private repository — install the `gh` CLI and authenticate (`sudo apt install gh && gh auth login`)." };
  }
  const ref = info.ref ?? meta?.defaultBranch ?? "HEAD";
  return apiView(info, ref);
}
