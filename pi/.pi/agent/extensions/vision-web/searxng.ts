/**
 * SearXNG search client + lightweight HTML-to-text fetch.
 *
 * SearXNG is a self-hosted meta-search engine. No API key is required for
 * your own instance (public instances may rate-limit).
 */

import { exec } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { randomBytes } from "node:crypto";

const SEARCH_TIMEOUT_MS = 30_000;
const FETCH_TIMEOUT_MS = 30_000;

export interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}

export interface SearchOptions {
  baseUrl: string;
  numResults?: number;
  includeDomains?: string[];
  excludeDomains?: string[];
  recencyMinutes?: number;
  signal?: AbortSignal;
}

export interface SearchResponse {
  answer: string;
  results: SearchResult[];
}

function withTimeout(signal: AbortSignal | undefined, ms: number): AbortSignal {
  const timeout = AbortSignal.timeout(ms);
  if (signal && typeof AbortSignal.any === "function") return AbortSignal.any([signal, timeout]);
  return signal ?? timeout;
}

export async function searxngSearch(query: string, options: SearchOptions): Promise<SearchResponse> {
  const baseUrl = options.baseUrl.replace(/\/+$/, "");
  const qParts = [query];
  for (const d of options.includeDomains ?? []) qParts.push(`site:${d}`);
  for (const d of options.excludeDomains ?? []) qParts.push(`-site:${d}`);

  const timeRange =
    options.recencyMinutes === undefined ? undefined
    : options.recencyMinutes <= 1440 ? "day"
    : options.recencyMinutes <= 43200 ? "month"
    : "year";

  const params = new URLSearchParams({ q: qParts.join(" "), format: "json", pageno: "1" });
  if (timeRange) params.set("time_range", timeRange);

  const url = `${baseUrl}/search?${params.toString()}`;
  const res = await fetch(url, {
    signal: withTimeout(options.signal, SEARCH_TIMEOUT_MS),
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`SearXNG error ${res.status}: ${text.slice(0, 300)}`);
  }
  const data = await res.json();

  const raw: any[] = Array.isArray(data.results) ? data.results : [];
  const results = raw
    .filter((r) => r && typeof r.url === "string" && r.url.trim())
    .map((r) => ({
      title: typeof r.title === "string" && r.title.trim() ? r.title.trim() : r.url,
      url: r.url.trim(),
      snippet: typeof r.content === "string" ? r.content.replace(/\s+/g, " ").trim() : "",
    }))
    .slice(0, Math.min(Math.max(1, options.numResults ?? 5), 20));

  const answer = results
    .map((r) => (r.snippet ? `${r.snippet}\nSource: ${r.title} (${r.url})` : `Source: ${r.title} (${r.url})`))
    .join("\n\n");

  return { answer, results };
}

export interface FetchedPage {
  url: string;
  title: string;
  content: string;
  error: string | null;
}

export async function fetchWebPage(url: string, signal?: AbortSignal): Promise<FetchedPage> {
  let res: Response;
  try {
    res = await fetch(url, {
      redirect: "follow",
      signal: withTimeout(signal, FETCH_TIMEOUT_MS),
      headers: {
        "User-Agent": "vision-web/1.0",
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });
  } catch (err) {
    return { url, title: "", content: "", error: err instanceof Error ? err.message : String(err) };
  }
  if (!res.ok) {
    return { url, title: "", content: "", error: `HTTP ${res.status}` };
  }
  const html = await res.text();
  const parsed = htmlToText(html, url);
  return { url, title: parsed.title, content: parsed.text, error: null };
}

function htmlToText(html: string, baseUrl: string): { title: string; text: string } {
  const titleMatch = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  let title = titleMatch ? titleMatch[1].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim() : "";

  let body = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, "")
    .replace(/<iframe\b[^>]*>[\s\S]*?<\/iframe>/gi, "")
    .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, "")
    .replace(/<canvas\b[^>]*>[\s\S]*?<\/canvas>/gi, "")
    .replace(/<head\b[^>]*>[\s\S]*?<\/head>/gi, "")
    .replace(/<nav\b[^>]*>[\s\S]*?<\/nav>/gi, "")
    .replace(/<header\b[^>]*>[\s\S]*?<\/header>/gi, "")
    .replace(/<footer\b[^>]*>[\s\S]*?<\/footer>/gi, "")
    .replace(/<!--[\s\S]*?-->/g, "");

  body = body
    .replace(/<(h[1-6])\b[^>]*>/gi, "\n\n")
    .replace(/<\/(h[1-6])>/gi, "\n\n")
    .replace(/<(p|div|section|article|main|aside|blockquote|figure|figcaption|details|summary|ul|ol|table|tbody|thead|tfoot|dl)\b[^>]*>/gi, "\n")
    .replace(/<\/(p|div|section|article|main|aside|blockquote|figure|figcaption|details|summary|li|tr|ul|ol|table|tbody|thead|tfoot|dl)>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<(td|th)\b[^>]*>/gi, " ")
    .replace(/<\/(td|th)>/gi, " ")
    .replace(/<li\b[^>]*>/gi, "\n• ")
    .replace(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, (_m, href, text) => {
      const t = text.replace(/<[^>]+>/g, "").trim();
      if (!t) return "";
      let abs = href;
      try { abs = new URL(href, baseUrl).href; } catch {}
      return `${t} (${abs})`;
    })
    .replace(/<[^>]+>/g, " ");

  body = decodeHtmlEntities(body);

  body = body
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  return { title, text: body };
}

function decodeHtmlEntities(text: string): string {
  const entities: Record<string, string> = {
    "&amp;": "&",
    "&lt;": "<",
    "&gt;": ">",
    "&quot;": '"',
    "&#39;": "'",
    "&apos;": "'",
    "&nbsp;": " ",
    "&ndash;": "–",
    "&mdash;": "—",
    "&hellip;": "…",
  };
  return text.replace(/&(?:#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/g, (m) => entities[m] ?? m);
}

// ------------------------------------------------------------------
// Lazy Docker SearXNG container
// ------------------------------------------------------------------

const DOCKER_IMAGE = "searxng/searxng:latest";
const DEFAULT_CONTAINER_NAME = "pi-searxng";
const STARTUP_TIMEOUT_MS = 20_000;
const HEALTH_POLL_MS = 500;

function getSearxngConfigDir(): string {
  const dir = join(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"), "extensions", "vision-web", "searxng-config");
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const settingsPath = join(dir, "settings.yml");
  if (!existsSync(settingsPath)) {
    const secretKey = randomBytes(24).toString("base64").replace(/[^a-zA-Z0-9]/g, "").slice(0, 24);
    const yaml = `use_default_settings: true\nserver:\n  secret_key: "${secretKey}"\n  image_proxy: true\nsearch:\n  formats:\n    - html\n    - json\n`;
    writeFileSync(settingsPath, yaml, "utf-8");
  }
  return dir;
}

function execPromise(command: string, timeout = 15_000): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    exec(command, { timeout }, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
  });
}

async function isDockerAvailable(): Promise<boolean> {
  try {
    await execPromise("docker --version", 3_000);
    return true;
  } catch {
    return false;
  }
}

async function isContainerRunning(name: string): Promise<boolean> {
  try {
    const { stdout } = await execPromise(`docker ps --filter name=^/${name}$ --format '{{.Names}}'`);
    return stdout.trim() === name;
  } catch {
    return false;
  }
}

async function startContainer(name: string, port: number): Promise<void> {
  // Clean up any leftover (stopped) container with the same name
  try {
    await execPromise(`docker rm -f ${name}`);
  } catch {
    // ignore
  }
  const configDir = getSearxngConfigDir();
  await execPromise(
    `docker run --rm -d -p 127.0.0.1:${port}:8080 -v "${configDir}:/etc/searxng" --name ${name} ${DOCKER_IMAGE}`,
    15_000,
  );
}

async function stopContainer(name: string): Promise<void> {
  try {
    await execPromise(`docker stop ${name}`);
  } catch {
    // ignore
  }
}

async function waitForReady(baseUrl: string, signal?: AbortSignal, maxWaitMs = STARTUP_TIMEOUT_MS): Promise<boolean> {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    if (signal?.aborted) return false;
    try {
      const res = await fetch(baseUrl.replace(/\/+$/, "") + "/", {
        method: "HEAD",
        redirect: "follow",
        signal: withTimeout(signal, 2_000),
      });
      if (res.ok || res.status === 404) return true;
    } catch {
      // not ready yet
    }
    await new Promise((r) => setTimeout(r, HEALTH_POLL_MS));
  }
  return false;
}

let idleTimer: ReturnType<typeof setTimeout> | null = null;
let cleanupRegistered = false;

function registerProcessCleanup(name: string): void {
  if (cleanupRegistered) return;
  cleanupRegistered = true;

  const cleanup = () => {
    stopContainer(name).catch(() => {});
    process.exit();
  };

  process.once("SIGINT", cleanup);
  process.once("SIGTERM", cleanup);
  process.once("SIGHUP", cleanup);
  process.once("beforeExit", () => {
    stopContainer(name).catch(() => {});
  });
}

export function scheduleDockerStop(name: string, idleMs: number): void {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    stopContainer(name).catch(() => {});
    idleTimer = null;
  }, idleMs);
}

export function cancelDockerIdleTimer(): void {
  if (idleTimer) {
    clearTimeout(idleTimer);
    idleTimer = null;
  }
}

export async function ensureDockerSearxng(
  port: number,
  signal?: AbortSignal,
  containerName = DEFAULT_CONTAINER_NAME,
): Promise<string | null> {
  if (!(await isDockerAvailable())) return null;
  if (!(await isContainerRunning(containerName))) {
    await startContainer(containerName, port);
    registerProcessCleanup(containerName);
    const baseUrl = `http://127.0.0.1:${port}`;
    const ready = await waitForReady(baseUrl, signal);
    if (!ready) {
      await stopContainer(containerName);
      return null;
    }
    return baseUrl;
  }
  return `http://127.0.0.1:${port}`;
}

export async function shutdownDockerSearxng(containerName = DEFAULT_CONTAINER_NAME): Promise<void> {
  cancelDockerIdleTimer();
  await stopContainer(containerName);
}


