/**
 * Config for the searxng extension (standalone web search via self-hosted SearXNG).
 *
 * Loaded from ~/.pi/agent/extensions/searxng/config.json (missing file = defaults).
 *
 * First-run migration: if config.json does not exist, the old vision-web keys
 * (searxngBaseUrl, searxngDockerEnabled, searxngDockerPort, searxngDockerIdleMinutes,
 * searchDefaultNumResults) are read from
 * ~/.pi/agent/extensions/vision-web/config.json so existing setups keep working.
 */
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

export interface Config {
  /** Master switch for the whole extension. */
  enabled: boolean;
  /** Explicit SearXNG instance URL, e.g. "http://localhost:8080". Takes precedence over Docker. */
  baseUrl?: string;
  /** Spin up a local Docker container on demand when baseUrl is not set. */
  dockerEnabled: boolean;
  /** Host port mapped to the SearXNG container. */
  dockerPort: number;
  /** Minutes to keep the container alive after the last search. */
  dockerIdleMinutes: number;
  /** Docker image for SearXNG. */
  dockerImage: string;
  /** Container name. */
  containerName: string;
  /** Stop the container on pi session shutdown. */
  stopOnShutdown: boolean;
  /** Warm up the container in the background on session start (no first-search latency). */
  warmupOnStart: boolean;
  /** SearXNG categories to query (server-side engine scoping lives in settings.yml). */
  categories: string;
  /** Optional SearXNG language code, e.g. "en". Unset = instance default. */
  language?: string;
  /** Default result count for web_search (1-20). */
  defaultNumResults: number;
  /** Per-attempt HTTP timeout for the SearXNG API (ms). */
  searchTimeoutMs: number;
  /** Retries on empty results caused by unresponsive/rate-limited engines. */
  maxRetries: number;
  /** Extra SearXNG instance URLs tried in order after the primary (optional). */
  fallbackInstances: string[];
  /** Last-resort fallback: scrape DuckDuckGo HTML directly (no Docker, no key). */
  ddgHtmlFallback: boolean;
  /** Max chars per fetched page for web_search includeContent. */
  maxFetchChars: number;
  /** Max pages fetched inline for web_search includeContent. */
  maxInlineFetch: number;
}

const DEFAULTS: Config = {
  enabled: true,
  dockerEnabled: true,
  dockerPort: 18765,
  dockerIdleMinutes: 5,
  dockerImage: "searxng/searxng:latest",
  containerName: "pi-searxng",
  stopOnShutdown: true,
  warmupOnStart: false,
  categories: "general,it,science",
  defaultNumResults: 5,
  searchTimeoutMs: 45_000,
  maxRetries: 2,
  fallbackInstances: [],
  ddgHtmlFallback: true,
  maxFetchChars: 60_000,
  maxInlineFetch: 3,
};

export function getAgentDir(): string {
  return process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
}

export function extensionDir(): string {
  return join(getAgentDir(), "extensions", "searxng");
}

export function configPath(): string {
  return join(extensionDir(), "config.json");
}

export function settingsFilePath(): string {
  return join(extensionDir(), "searxng-config", "settings.yml");
}

function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(value)));
}

function cleanUrl(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim().replace(/\/+$/, "");
  return trimmed ? trimmed : undefined;
}

function cleanString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function cleanStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((x): x is string => typeof x === "string").map((x) => x.trim()).filter(Boolean);
}

/** Raw old vision-web config (migration source). Returns {} when absent/unparseable. */
function readVisionWebConfig(): Record<string, any> {
  try {
    const path = join(getAgentDir(), "extensions", "vision-web", "config.json");
    if (!existsSync(path)) return {};
    const raw = JSON.parse(readFileSync(path, "utf-8"));
    return raw && typeof raw === "object" ? raw : {};
  } catch {
    return {};
  }
}

export function loadConfig(): Config {
  const base: Config = { ...DEFAULTS };
  let raw: Record<string, any> = {};
  let migrated = false;
  try {
    if (existsSync(configPath())) {
      const parsed = JSON.parse(readFileSync(configPath(), "utf-8"));
      if (parsed && typeof parsed === "object") raw = parsed;
    } else {
      // First run: inherit the old vision-web search settings so nothing breaks.
      const vw = readVisionWebConfig();
      raw = {
        baseUrl: vw.searxngBaseUrl,
        dockerEnabled: vw.searxngDockerEnabled,
        dockerPort: vw.searxngDockerPort,
        dockerIdleMinutes: vw.searxngDockerIdleMinutes,
        defaultNumResults: vw.searchDefaultNumResults,
      };
      migrated = Object.values(raw).some((v) => v !== undefined);
    }
  } catch {
    // Malformed config: fall back to defaults.
    raw = {};
  }

  if (typeof raw.enabled === "boolean") base.enabled = raw.enabled;
  const baseUrl = cleanUrl(raw.baseUrl);
  if (baseUrl) base.baseUrl = baseUrl;
  if (typeof raw.dockerEnabled === "boolean") base.dockerEnabled = raw.dockerEnabled;
  base.dockerPort = clampInt(raw.dockerPort, 1, 65535, base.dockerPort);
  base.dockerIdleMinutes = clampInt(raw.dockerIdleMinutes, 1, 1440, base.dockerIdleMinutes);
  const image = cleanString(raw.dockerImage);
  if (image) base.dockerImage = image;
  const cname = cleanString(raw.containerName);
  if (cname) base.containerName = cname;
  if (typeof raw.stopOnShutdown === "boolean") base.stopOnShutdown = raw.stopOnShutdown;
  if (typeof raw.warmupOnStart === "boolean") base.warmupOnStart = raw.warmupOnStart;
  const cats = cleanString(raw.categories);
  if (cats) base.categories = cats;
  const lang = cleanString(raw.language);
  if (lang) base.language = lang;
  base.defaultNumResults = clampInt(raw.defaultNumResults, 1, 20, base.defaultNumResults);
  base.searchTimeoutMs = clampInt(raw.searchTimeoutMs, 5_000, 300_000, base.searchTimeoutMs);
  base.maxRetries = clampInt(raw.maxRetries, 0, 5, base.maxRetries);
  const fallbacks = cleanStringList(raw.fallbackInstances).map((u) => u.replace(/\/+$/, ""));
  if (raw.fallbackInstances !== undefined) base.fallbackInstances = fallbacks;
  if (typeof raw.ddgHtmlFallback === "boolean") base.ddgHtmlFallback = raw.ddgHtmlFallback;
  base.maxFetchChars = clampInt(raw.maxFetchChars, 1_000, 500_000, base.maxFetchChars);
  base.maxInlineFetch = clampInt(raw.maxInlineFetch, 1, 10, base.maxInlineFetch);
  return base;
}
