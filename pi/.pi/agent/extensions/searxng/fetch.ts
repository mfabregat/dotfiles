/**
 * Lightweight HTML-to-text page fetch (moved from vision-web/searxng.ts).
 * Used by web_search includeContent. vision-web's fetch_url imports this
 * module instead of keeping its own copy.
 */
import { timeoutSignal } from "./search.js";

const FETCH_TIMEOUT_MS = 30_000;

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
      signal: timeoutSignal(signal, FETCH_TIMEOUT_MS),
      headers: {
        "User-Agent": "pi-searxng/1.0",
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
  const title = titleMatch ? titleMatch[1].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim() : "";

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
      try { abs = new URL(href, baseUrl).href; } catch { /* keep raw */ }
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
