/**
 * TinyFish search + fetch client (the only web-search provider for now —
 * Gemini's free tier has no web search, so this is a deliberate, minimal pick).
 */
import { withTimeout, redact } from "./gemini.js";

const SEARCH_URL = "https://api.search.tinyfish.ai";
const FETCH_URL = "https://api.fetch.tinyfish.ai";
const SEARCH_TIMEOUT_MS = 60_000;
const FETCH_TIMEOUT_MS = 150_000;
const MAX_FETCH_URLS_PER_REQUEST = 10;

export interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}

export interface SearchOptions {
  apiKey: string;
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

export interface FetchedPage {
  url: string;
  title: string;
  content: string;
  error: string | null;
}

async function jsonRequest(label: string, url: string, apiKey: string, init: RequestInit, timeoutMs: number, signal?: AbortSignal): Promise<any> {
  let response: Response;
  try {
    response = await fetch(url, {
      ...init,
      headers: {
        "X-API-Key": apiKey,
        ...(init.body ? { "Content-Type": "application/json" } : {}),
        ...init.headers,
      },
      signal: withTimeout(signal, timeoutMs),
    });
  } catch (err) {
    throw new Error(`TinyFish ${label} request failed: ${redact(err instanceof Error ? err.message : String(err), apiKey)}`);
  }
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`TinyFish ${label} API error ${response.status}: ${redact(raw, apiKey).slice(0, 300)}`);
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error(`TinyFish ${label} API returned invalid JSON`);
  }
}

function normalizeDomain(value: string): string | null {
  let input = value.trim().toLowerCase();
  if (!input) return null;
  if (input.startsWith("-")) input = input.slice(1).trim();
  if (!input) return null;
  try {
    const parsed = input.includes("://") ? new URL(input) : new URL(`https://${input}`);
    input = parsed.hostname;
  } catch {
    input = input.split("/")[0]?.split(":")[0] ?? "";
  }
  input = input.replace(/^\.+|\.+$/g, "");
  return /^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/i.test(input) ? input : null;
}

function mapResults(results: any[]): SearchResult[] {
  if (!Array.isArray(results)) return [];
  const out: SearchResult[] = [];
  for (const item of results) {
    if (!item || typeof item.url !== "string" || !item.url.trim()) continue;
    const url = item.url.trim();
    out.push({
      title: typeof item.title === "string" && item.title.trim() ? item.title.trim() : url,
      url,
      snippet: typeof item.snippet === "string" ? item.snippet.replace(/\s+/g, " ").trim() : "",
    });
  }
  return out;
}

export async function tinyfishSearch(query: string, options: SearchOptions): Promise<SearchResponse> {
  const numResults = Math.max(1, Math.min(Math.floor(options.numResults ?? 5), 20));
  const params = new URLSearchParams({ query });
  const include = (options.includeDomains ?? []).map(normalizeDomain).filter((d): d is string => d !== null);
  const exclude = (options.excludeDomains ?? []).map(normalizeDomain).filter((d): d is string => d !== null);
  if (include.length > 0) params.set("include_domains", include.join(","));
  if (exclude.length > 0) params.set("exclude_domains", exclude.join(","));
  if (options.recencyMinutes !== undefined) params.set("recency_minutes", String(options.recencyMinutes));

  const combined: SearchResult[] = [];
  const pages = numResults > 10 ? 2 : 1;
  for (let page = 0; page < pages; page++) {
    const url = `${SEARCH_URL}?${params.toString()}${page > 0 ? `&page=${page}` : ""}`;
    const data = await jsonRequest("Search", url, options.apiKey, { method: "GET" }, SEARCH_TIMEOUT_MS, options.signal);
    if (!Array.isArray(data.results)) throw new Error("TinyFish Search API returned an unexpected response shape");
    combined.push(...mapResults(data.results));
    if (data.results.length < 10) break;
  }

  const seen = new Set<string>();
  const results: SearchResult[] = [];
  for (const result of combined) {
    if (seen.has(result.url)) continue;
    seen.add(result.url);
    results.push(result);
    if (results.length >= numResults) break;
  }

  const answer = results
    .map((r) => (r.snippet ? `${r.snippet}\nSource: ${r.title} (${r.url})` : `Source: ${r.title} (${r.url})`))
    .join("\n\n");
  return { answer, results };
}

export async function tinyfishFetch(urls: string[], options: { apiKey: string; purpose?: string; signal?: AbortSignal }): Promise<FetchedPage[]> {
  const pages: FetchedPage[] = [];
  for (let offset = 0; offset < urls.length; offset += MAX_FETCH_URLS_PER_REQUEST) {
    const batch = urls.slice(offset, offset + MAX_FETCH_URLS_PER_REQUEST);
    const body: Record<string, unknown> = { urls: batch, format: "markdown", per_url_timeout_ms: 110_000 };
    if (options.purpose?.trim()) body.purpose = options.purpose.trim().slice(0, 2_000);
    const data = await jsonRequest("Fetch", FETCH_URL, options.apiKey, { method: "POST", body: JSON.stringify(body) }, FETCH_TIMEOUT_MS, options.signal);
    if (!Array.isArray(data.results) || !Array.isArray(data.errors)) {
      throw new Error("TinyFish Fetch API returned an unexpected response shape");
    }
    for (const url of batch) {
      const result = data.results.find((item: any) => item?.url === url || item?.final_url === url);
      let content = "";
      if (typeof result?.text === "string") content = result.text.trim();
      else if (result?.text && typeof result.text === "object") content = JSON.stringify(result.text);
      if (content) {
        pages.push({ url, title: typeof result.title === "string" ? result.title.trim() : "", content, error: null });
      } else {
        const err = data.errors.find((e: any) => e?.url === url) ?? data.errors[0];
        pages.push({ url, title: "", content: "", error: err?.error ?? "fetch failed" });
      }
    }
  }
  return pages;
}
