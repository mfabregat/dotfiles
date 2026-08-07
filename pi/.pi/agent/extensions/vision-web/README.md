# vision-web

Combined **vision handoff** (pi-vision-handoff) + **web access** (simplified pi-web-access) for pi.

- **Vision handoff** — text-only models get images described by the Gemini API (direct REST call, no pi provider registry needed). Works for attached images (`pi --image`) and images the agent `read`s.
- **Web search** — TinyFish (Gemini's free tier has no web search). Deliberately minimal: one provider, easy to add more later.
- **URL / media fetch** — one `fetch_url` tool that routes:
  | target | engine |
  |---|---|
  | web page | TinyFish markdown extraction |
  | GitHub repo/file/tree | clone-first: shallow `git clone` + **local path for read/bash exploration**; API view for repos > `maxRepoSizeMB` (or commit SHAs / private without `gh`); raw/API fallback if clone fails |
  | YouTube URL | Gemini video understanding (no yt-dlp needed) |
  | PDF (URL or local) | Gemini text extraction (no unpdf needed) |
  | local video file | ffmpeg frames if available, else Gemini Files API upload (auto-deleted after) |

## Keys (centralized in pi's auth.json)

```json
// ~/.pi/agent/auth.json
{
  "google":   { "type": "api_key", "key": "AIza..." },
  "tinyfish": { "type": "api_key", "key": "tf-..." }
}
```

- `google` is pi's **native** Gemini key id — pi itself picks it up too (Gemini models appear in `/model`).
- `tinyfish` is a custom key: pi ignores unknown keys but **preserves them** (its auth store is merge-based).
- Env fallbacks: `GEMINI_API_KEY`, `TINYFISH_API_KEY`.

## Config — `~/.pi/agent/extensions/vision-web/config.json`

| key | default | meaning |
|---|---|---|
| `enabled` | `true` | master switch |
| `geminiModel` | `gemini-3.6-flash` | vision / video / PDF model |
| `autoHandoff` | `true` | describe images for every text-only model |
| `handoffModels` | `[]` | extra `provider/model` refs to always hand off for |
| `cacheMax` | `50` | LRU description cache size (per session) |
| `maxDescriptionLines` | `0` | cap description length (0 = unbounded) |
| `batchSize` | `8` | images per Gemini request |
| `searchDefaultNumResults` | `5` | default `web_search` result count |
| `videoMethod` | `auto` | `auto` (ffmpeg frames if installed, else upload) · `frames` · `upload` |
| `maxUploadBytes` | 512MB | local video upload cap |
| `maxPdfBytes` | 15MB | PDF size cap (Gemini inline limit) |
| `githubClone.enabled` | `true` | `false` = skip GitHub handling; URL falls through to normal HTTP extraction |
| `githubClone.maxRepoSizeMB` | `350` | bigger repos get the lightweight API view instead of a clone |
| `githubClone.forceClone` | `false` | force a full clone even for oversized repos |

## Tools

- `web_search` — query, numResults (1-20), domainFilter (`-site` to exclude), recencyFilter (day/week/month/year), includeContent (fetch top pages as markdown).
- `fetch_url` — url (web/GitHub/YouTube/PDF/local video) + optional `question`, `timestamp` (`1:23:45`, `23:41-25:00`, or seconds), `frames` (1-12, for local videos with ffmpeg).

## Command

- `/vision-web` — status: keys set?, model, handoff target, last error.

## Optimizations

- Content-hash LRU cache: an image described once is reused across turns (no re-billing).
- Single-flight batching: images arriving in the same frame coalesce into **one** Gemini request (up to `batchSize`).
- Prewarm at submit: descriptions start the moment you press enter.
- Turn-abort wiring: Esc cancels in-flight descriptions.
- Error redaction: API keys never leak into tool results or logs.
- GitHub: raw/API first (fast on slow networks), clone only as fallback; caches repo metadata + trees.
- Uploaded video files are deleted after analysis (Files API storage is temporary anyway).
- Zero npm dependencies — plain `fetch` + stdlib (`git` optional, `ffmpeg`/`gh` optional accelerators).
