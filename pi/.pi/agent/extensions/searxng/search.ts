/**
 * SearXNG search client with retries, multi-instance fallback and a
 * last-resort DuckDuckGo HTML fallback.
 *
 * Lessons baked in (all verified live against a local container):
 * - Never send `time_range`: bing (the best working general engine) returns
 *   ZERO results whenever the parameter is present. Callers asking for a
 *   recency filter get results + an explicit warning instead of nothing.
 * - Never send an `engines=` allowlist from the client: an invalid engine
 *   name makes SearXNG silently run ALL default engines (including the
 *   CAPTCHA-blocked ones). Engine scoping lives server-side in settings.yml.
 * - Empty results WITH unresponsive engines (suspended/CAPTCHA) are transient:
 *   retry with backoff. Empty results with NO unresponsive engines are genuine.
 * - Big-Tech scrape engines (brave/duckduckgo/google/startpage/...) are
 *   unreliable from a single IP; API-backed engines (github, stackoverflow,
 *   arxiv, mdn, hackernews, npm) + bing/seznam/yep/wiby/bpb/boardreader/mwmbl
 *   do the heavy lifting. Query the `general,it,science` categories so the
 *   API-backed engines are actually consulted (default `general` misses them).
 */
import type { Config } from "./config.js";

export interface SearchResult {
  title: string;
  url: string;
  snippet: string;
  engine?: string;
}

export interface SearchOutcome {
  /** True when at least one instance answered (even with zero results). */
  ok: boolean;
  /** Human-readable answer block (may be empty when nothing found). */
  answer: string;
  results: SearchResult[];
  /** Non-fatal caveats for the model (recency ignored, engines down, fallbacks used...). */
  warnings: string[];
  /** Which instance served the results ("ddg-html" for the last-resort fallback). */
  instance: string | null;
  /** SearXNG-reported unresponsive engines from the serving instance. */
  unresponsive: Array<{ engine: string; reason: string }>;
}

export interface SearchInput {
  query: string;
  numResults?: number;
  includeDomains?: string[];
  excludeDomains?: string[];
  /** Accepted for API compatibility but NOT forwarded (see module doc). */
  recencyLabel?: string;
  signal?: AbortSignal;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function timeoutSignal(signal: AbortSignal | undefined, ms: number): AbortSignal {
  const t = AbortSignal.timeout(ms);
  if (signal && typeof AbortSignal.any === "function") return AbortSignal.any([signal, t]);
  return signal ?? t;
}

export function buildQueryText(query: string, include?: string[], exclude?: string[]): string {
  const parts = [query.trim()];
  for (const d of include ?? []) {
    const clean = d.trim();
    if (clean && !/\s/.test(clean)) parts.push(`site:${clean}`);
  }
  for (const d of exclude ?? []) {
    const clean = d.trim();
    if (clean && !/\s/.test(clean)) parts.push(`-site:${clean}`);
  }
  return parts.join(" ");
}

interface InstanceHit {
  ok: boolean;
  results: SearchResult[];
  unresponsive: Array<{ engine: string; reason: string }>;
  httpStatus?: number;
  error?: string;
}

async function queryInstance(
  baseUrl: string,
  q: string,
  categories: string,
  language: string | undefined,
  timeoutMs: number,
  signal?: AbortSignal,
): Promise<InstanceHit> {
  const params = new URLSearchParams({ q, format: "json", pageno: "1", categories });
  if (language) params.set("language", language);
  const url = `${baseUrl.replace(/\/+$/, "")}/search?${params.toString()}`;
  let res: Response;
  try {
    res = await fetch(url, {
      headers: { Accept: "application/json", "User-Agent": "pi-searxng/1.0" },
      signal: timeoutSignal(signal, timeoutMs),
    });
  } catch (err) {
    return { ok: false, results: [], unresponsive: [], error: err instanceof Error ? err.message : String(err) };
  }
  if (!res.ok) {
    return { ok: false, results: [], unresponsive: [], httpStatus: res.status, error: `HTTP ${res.status}` };
  }
  let data: any;
  try {
    data = await res.json();
  } catch {
    return { ok: false, results: [], unresponsive: [], error: "invalid JSON response" };
  }
  const raw: any[] = Array.isArray(data?.results) ? data.results : [];
  const results: SearchResult[] = [];
  for (const r of raw) {
    if (!r || typeof r.url !== "string" || !r.url.trim()) continue;
    results.push({
      title: typeof r.title === "string" && r.title.trim() ? r.title.trim() : r.url.trim(),
      url: r.url.trim(),
      snippet: typeof r.content === "string" ? r.content.replace(/\s+/g, " ").trim() : "",
      engine: typeof r.engine === "string" ? r.engine : undefined,
    });
  }
  const unresponsive: Array<{ engine: string; reason: string }> = [];
  const rawUn: any[] = Array.isArray(data?.unresponsive_engines) ? data.unresponsive_engines : [];
  for (const u of rawUn) {
    if (Array.isArray(u) && typeof u[0] === "string") {
      unresponsive.push({ engine: u[0], reason: typeof u[1] === "string" ? u[1] : "unresponsive" });
    }
  }
  return { ok: true, results, unresponsive };
}

export function formatAnswer(results: SearchResult[]): string {
  return results
    .map((r) => (r.snippet ? `${r.snippet}\nSource: ${r.title} (${r.url})` : `Source: ${r.title} (${r.url})`))
    .join("\n\n");
}

// ------------------------------------------------------------------
// Last-resort fallback: DuckDuckGo HTML endpoint (no Docker, no key).
// Best effort: DDG rate-limits aggressively, so this is only tried after
// every SearXNG instance failed or came back empty.
// ------------------------------------------------------------------

function decodeEntities(s: string): string {
  return s
    .replace(/&#(\d+);/g, (_m, n) => {
      try { return String.fromCodePoint(parseInt(n, 10)); } catch { return _m; }
    })
    .replace(/&#x([0-9a-fA-F]+);/g, (_m, h) => {
      try { return String.fromCodePoint(parseInt(h, 16)); } catch { return _m; }
    })
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, " ");
}

async function ddgHtmlFallback(q: string, limit: number, signal?: AbortSignal): Promise<SearchResult[]> {
  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(q)}`;
  const res = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
      Accept: "text/html,application/xhtml+xml",
      "Accept-Language": "en-US,en;q=0.9",
    },
    signal: timeoutSignal(signal, 20_000),
  });
  if (!res.ok) throw new Error(`DDG fallback HTTP ${res.status}`);
  const html = await res.text();
  const out: SearchResult[] = [];
  const re = /<a[^>]+class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null && out.length < limit) {
    let href = m[1];
    try {
      if (href.startsWith("//duckduckgo.com/l/?")) {
        const inner = new URL("https:" + href);
        const uddg = inner.searchParams.get("uddg");
        if (uddg) href = uddg;
      }
    } catch { /* keep raw href */ }
    if (/^\/\//.test(href) || /^https?:\/\//i.test(href)) {
      const normalized = href.startsWith("//") ? "https:" + href : href;
      const title = decodeEntities(m[2].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim());
      if (title && !out.some((r) => r.url === normalized)) {
        out.push({ title, url: normalized, snippet: "", engine: "ddg-html" });
      }
    }
  }
  return out;
}

// ------------------------------------------------------------------

export async function searxngSearch(
  input: SearchInput,
  config: Pick<Config, "categories" | "language" | "searchTimeoutMs" | "maxRetries" | "ddgHtmlFallback">,
  instances: string[],
): Promise<SearchOutcome> {
  const warnings: string[] = [];
  if (input.recencyLabel) {
    warnings.push(
      `Recency filter "${input.recencyLabel}" was not applied: the reliable engines ` +
        `do not support time_range (requesting it returns zero results). Results are unfiltered by date.`,
    );
  }
  const q = buildQueryText(input.query, input.includeDomains, input.excludeDomains);
  const limit = Math.min(Math.max(1, input.numResults ?? 5), 20);

  const attempts: string[] = [];
  let lastUnresponsive: InstanceHit["unresponsive"] = [];
  let sawHttpError: string | null = null;

  for (const baseUrl of instances) {
    let hit: InstanceHit | null = null;
    const tries = 1 + Math.max(0, config.maxRetries);
    for (let attempt = 1; attempt <= tries; attempt++) {
      if (input.signal?.aborted) break;
      attempts.push(`${baseUrl} (try ${attempt})`);
      hit = await queryInstance(baseUrl, q, config.categories, config.language, config.searchTimeoutMs, input.signal);
      if (!hit.ok) {
        sawHttpError = `${baseUrl}: ${hit.error ?? "request failed"}`;
        break; // transport failure: try next instance, don't hammer this one
      }
      lastUnresponsive = hit.unresponsive;
      if (hit.results.length > 0) break;
      if (hit.unresponsive.length === 0) break; // genuine empty: no point retrying
      if (attempt < tries) await sleep(1_500 * attempt);
    }
    if (input.signal?.aborted) break;
    if (hit?.ok && hit.results.length > 0) {
      const results = hit.results.slice(0, limit);
      if (hit.unresponsive.length > 0) {
        warnings.push(
          `Partial results: ${hit.unresponsive.length} engine(s) unresponsive ` +
            `(${hit.unresponsive.map((u) => u.engine).join(", ")}).`,
        );
      }
      return { ok: true, answer: formatAnswer(results), results, warnings, instance: baseUrl, unresponsive: hit.unresponsive };
    }
  }

  // Every instance failed or came back empty: last resort.
  if (config.ddgHtmlFallback && !input.signal?.aborted) {
    try {
      const fb = await ddgHtmlFallback(q, limit, input.signal);
      if (fb.length > 0) {
        warnings.push("Results via DuckDuckGo HTML fallback (SearXNG instances returned nothing). Snippets unavailable.");
        return { ok: true, answer: formatAnswer(fb), results: fb, warnings, instance: "ddg-html", unresponsive: [] };
      }
    } catch (err) {
      warnings.push(`DuckDuckGo fallback also failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  if (sawHttpError && attempts.length > 0 && lastUnresponsive.length === 0) {
    warnings.push(`No SearXNG instance reachable (${sawHttpError}). Is Docker running? See /searxng status.`);
  }
  void attempts;
  return { ok: false, answer: "", results: [], warnings, instance: null, unresponsive: lastUnresponsive };
}
