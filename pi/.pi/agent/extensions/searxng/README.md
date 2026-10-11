# searxng

Standalone **web search** for pi via a self-hosted SearXNG instance. Extracted
from `vision-web` (which keeps vision handoff + `fetch_url`).

## Why it exists

Self-hosted SearXNG with default settings returns **zero results** most of the
time: the default general engines (brave, duckduckgo, google, startpage) are
CAPTCHA / rate-limit blocked from a single IP, `bing` (which works) is
**disabled by default**, the API-backed engines (github, stackoverflow, arxiv…)
are never consulted (default category is `general` only), and sending
`time_range` makes bing return nothing. This extension fixes all of that:

- **Tuned `searxng-config/settings.yml`** — enables the engines verified
  working without API keys (bing, seznam, yep, wiby, bpb, boardreader, mwmbl,
  github, stackoverflow, mdn, docker hub, hackernews, npm, arxiv), disables
  the blocked ones (so they can't poison later queries with suspensions).
  Schema note: the toggle is `disabled: true/false`, not `enabled`.
- **Queries `general,it,science` categories** so code questions hit
  stackoverflow/github/arxiv, not just the general web.
- **Never sends `time_range`** — verified: bing returns 0 results whenever it
  is present. A requested `recencyFilter` is reported as "not applied"
  instead of silently-regurgitating nothing.
- **No invalid `engines=` parameter** — an unknown engine name makes SearXNG
  silently run *all* default engines (including blocked ones). Engine scoping
  lives server-side in settings.yml.
- **Docker handling that doesn't race or kill pi** — one shared startup
  promise across parallel searches (no more "container name already in use"),
  separate `docker pull` with a long timeout, readiness probed against the
  real JSON endpoint, settings mounted as a read-only **file** (the old
  directory mount got chown'ed to UID 977 → "Permission denied"), and no
  `process.exit()` in signal handlers.
- **Retries + fallbacks** — empty results *with* unresponsive engines are
  retried with backoff; extra `fallbackInstances` are tried in order; last
  resort is a direct DuckDuckGo HTML scrape (no Docker, no key).
- **Never crashes the tool call** — every failure becomes readable text with
  `details` (instance, warnings), so the model can rephrase/retry.

## Tools

- `web_search` — query, numResults (1-20), domainFilter (`-site` to exclude),
  recencyFilter (**accepted but not applied**, see above), includeContent
  (fetch top pages as text).

## Command

- `/searxng` — `status` (default), `start`, `stop`, `logs [n]`.

## Config — `extensions/searxng/config.json`

| key | default | meaning |
|---|---|---|
| `enabled` | `true` | master switch |
| `baseUrl` | — | explicit instance URL (takes precedence over Docker) |
| `dockerEnabled` | `true` | spin up local Docker container on demand |
| `dockerPort` | `18765` | host port mapped to the container |
| `dockerIdleMinutes` | `5` | stop container after this many idle minutes |
| `dockerImage` | `searxng/searxng:latest` | image to run/pull |
| `containerName` | `pi-searxng` | container name |
| `stopOnShutdown` | `true` | stop container on pi session shutdown |
| `warmupOnStart` | `false` | start container in background on session start |
| `categories` | `general,it,science` | SearXNG categories per query |
| `language` | — | SearXNG language code, e.g. `"en"` (unset = instance default) |
| `defaultNumResults` | `5` | default result count |
| `searchTimeoutMs` | `45000` | per-attempt HTTP timeout |
| `maxRetries` | `2` | retries on empty-with-unresponsive-engines |
| `fallbackInstances` | `[]` | extra instance URLs, tried in order |
| `ddgHtmlFallback` | `true` | last-resort DuckDuckGo HTML scrape |
| `maxFetchChars` | `60000` | chars kept per page for includeContent |
| `maxInlineFetch` | `3` | pages fetched inline for includeContent |

First run with no `config.json` inherits the old vision-web keys
(`searxngBaseUrl`, `searxngDockerEnabled`, `searxngDockerPort`,
`searxngDockerIdleMinutes`, `searchDefaultNumResults`).

## Files

```
extensions/searxng/
  index.ts    pi wiring: web_search tool + /searxng command + lifecycle
  config.ts   config load/validate + vision-web migration
  docker.ts   container lifecycle (mutex startup, ro file mount, idle stop)
  search.ts   query client (retries, instance chain, DDG fallback)
  fetch.ts    HTML-to-text page fetch (also imported by vision-web/fetch_url)
  config.json user config
  searxng-config/settings.yml  tuned engine allowlist (mounted read-only)
```

`search.ts`, `docker.ts`, `config.ts`, `fetch.ts` are pi-independent — test
with plain node: `node --experimental-strip-types` or `node test-*.ts`.
