/**
 * vision-web — combined vision handoff + web access for pi.
 *
 * - Vision handoff: text-only models get images described by the Gemini API
 *   (direct REST call, no pi provider registry needed).
 * - Web search + URL fetch via TinyFish.
 *
 * Keys (centralized in ~/.pi/agent/auth.json):
 *   { "google":   { "type": "api_key", "key": "AIza..." },
 *     "tinyfish": { "type": "api_key", "key": "tf-..." } }
 * Env fallbacks: GEMINI_API_KEY, TINYFISH_API_KEY.
 *
 * Config: ~/.pi/agent/extensions/vision-web/config.json
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { readFile } from "node:fs/promises";
import { loadConfig, type Config } from "./config.js";
import { resolveCredential, getAgentDir } from "./auth.js";
import { tinyfishSearch, tinyfishFetch } from "./tinyfish.js";
import { withTimeout } from "./gemini.js";
import { extractGitHub, wipeCloneCache } from "./github.js";
import { analyzeYouTubeUrl, analyzeLocalVideo, extractPdfText, parseYouTubeUrl, classifyFetchTarget } from "./media.js";
import {
  VisionHandoff,
  extractImageFromBlock,
  imageHash,
  isHandoffTarget,
  isVisionModel,
  NON_VISION_IMAGE_NOTE,
  readImageFileBounded,
  resolveImagePath,
  formatModelRef,
} from "./handoff.js";

const MAX_FETCH_OUTPUT_CHARS = 60_000;
const MAX_INLINE_FETCH_URLS = 3;
const MISSING_GEMINI =
  "Gemini API key missing. Add { \"google\": { \"type\": \"api_key\", \"key\": \"...\" } } to auth.json or set GEMINI_API_KEY.";

export default function (pi: ExtensionAPI) {
  let config: Config = loadConfig();
  const handoff = new VisionHandoff(() => config);

  pi.on("session_shutdown", () => {
    handoff.dispose();
    wipeCloneCache();
  });

  pi.on("session_start", async (_event, ctx) => {
    if (!config.enabled) return;
    const [gemini, tinyfish] = await Promise.all([
      handoff.geminiKey(),
      resolveCredential({ authKey: "tinyfish", envVar: "TINYFISH_API_KEY", configValue: config.tinyfishApiKey }),
    ]);
    if (ctx.hasUI && (!gemini || !tinyfish)) {
      const missing = [gemini ? null : "google/GEMINI_API_KEY", tinyfish ? null : "tinyfish/TINYFISH_API_KEY"]
        .filter((x): x is string => x !== null)
        .join(", ");
      ctx.ui.notify(`vision-web: missing API keys — ${missing}. Add them to ${getAgentDir()}/auth.json`, "info");
    }
  });

  // ------------------------------------------------------------------ tools

  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web using TinyFish. Returns an AI-synthesized answer plus ranked results with title, URL, and snippet. Optionally fetch page content for the top results.",
    promptSnippet: "Search the web for: ",
    parameters: Type.Object({
      query: Type.String({ description: "Search query. Use 2-4 varied angles for broad coverage." }),
      numResults: Type.Optional(Type.Number({ description: "Number of results (1-20, default 5)." })),
      domainFilter: Type.Optional(
        Type.Array(Type.String({ description: "Restrict results to these domains. Prefix with - to exclude, e.g. \"-reddit.com\"." })),
      ),
      recencyFilter: Type.Optional(
        Type.Union(
          [Type.Literal("day"), Type.Literal("week"), Type.Literal("month"), Type.Literal("year")],
          { description: "Only results from this recency window." },
        ),
      ),
      includeContent: Type.Optional(
        Type.Boolean({ description: "Also fetch readable markdown content for the top results (default false)." }),
      ),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const apiKey = await resolveCredential({
        authKey: "tinyfish",
        envVar: "TINYFISH_API_KEY",
        configValue: config.tinyfishApiKey,
      });
      if (!apiKey) {
        return {
          content: [
            {
              type: "text",
              text: "Web search unavailable: TinyFish API key missing. Add { \"tinyfish\": { \"type\": \"api_key\", \"key\": \"...\" } } to auth.json or set TINYFISH_API_KEY.",
            },
          ],
          details: {},
        };
      }
      const recencyMinutes =
        params.recencyFilter === "day" ? 1440
        : params.recencyFilter === "week" ? 10080
        : params.recencyFilter === "month" ? 43200
        : params.recencyFilter === "year" ? 525600
        : undefined;
      const includeDomains: string[] = [];
      const excludeDomains: string[] = [];
      for (const raw of params.domainFilter ?? []) {
        if (raw.trim().startsWith("-")) excludeDomains.push(raw.trim().slice(1));
        else includeDomains.push(raw.trim());
      }
      const { answer, results } = await tinyfishSearch(params.query, {
        apiKey,
        numResults: params.numResults ?? config.searchDefaultNumResults,
        includeDomains: includeDomains.length > 0 ? includeDomains : undefined,
        excludeDomains: excludeDomains.length > 0 ? excludeDomains : undefined,
        recencyMinutes,
        signal,
      });

      const lines = [`Search results for "${params.query}":`, "", answer];
      let fetched = "";
      if (params.includeContent && results.length > 0) {
        const pages = await tinyfishFetch(
          results.slice(0, MAX_INLINE_FETCH_URLS).map((r) => r.url),
          { apiKey, purpose: `Extract content relevant to: ${params.query}`, signal },
        );
        const parts: string[] = [];
        for (const page of pages) {
          if (page.error) continue;
          parts.push(`## ${page.title || page.url}\n${page.content.slice(0, MAX_FETCH_OUTPUT_CHARS)}`);
        }
        if (parts.length > 0) fetched = `\n\n--- Page content ---\n${parts.join("\n\n---\n\n")}`;
      }
      return {
        content: [{ type: "text", text: lines.join("\n") + fetched }],
        details: { results: results.map((r) => ({ title: r.title, url: r.url, snippet: r.snippet })) },
      };
    },
  });

  pi.registerTool({
    name: "fetch_url",
    label: "Fetch URL",
    description:
      "Fetch content from a URL or local path. Handles: web pages (markdown via TinyFish), GitHub repositories (README/tree/file, via git clone), YouTube videos (Gemini video understanding), PDF files (Gemini text extraction), and local video files (ffmpeg frames or Gemini upload).",
    promptSnippet: "Fetch the content of: ",
    parameters: Type.Object({
      url: Type.String({ description: "A web URL, GitHub URL, YouTube URL, PDF URL, or local file path." }),
      question: Type.Optional(
        Type.String({ description: "Question or instruction for video/PDF analysis, e.g. 'what is shown at 23:41?'. For web pages, an extraction hint." }),
      ),
      timestamp: Type.Optional(
        Type.String({
          description:
            "Video frame extraction (local videos with ffmpeg). Single: '1:23:45', '23:45', or '85' (seconds). Range: '23:41-25:00' extracts evenly-spaced frames (default 6).",
        }),
      ),
      frames: Type.Optional(
        Type.Integer({ minimum: 1, maximum: 12, description: "Number of video frames to extract (1-12, default 6 for ranges, 6 sampled)." }),
      ),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const target = params.url.trim();
      const kind = classifyFetchTarget(target);

      // --- GitHub -----------------------------------------------------------
      if (kind === "github") {
        const result = await extractGitHub(target, config.githubClone);
        if (!result) {
          // githubClone.enabled = false → fall through to the normal HTTP path.
        } else {
          const header = result.error
            ? `Failed to fetch ${target}: ${result.error}`
            : `# ${result.title}\n\n${result.content}`;
          const localLine =
            result.localPath && !result.error
              ? `\n\nLocal clone available at: ${result.localPath} — use the read/bash tools to explore it.`
              : "";
          return {
            content: [{ type: "text", text: (header + localLine).slice(0, 150_000) }],
            details: { localPath: result.localPath ?? null, apiView: result.apiView ?? false },
          };
        }
      }

      const geminiKey = await handoff.geminiKey();

      // --- YouTube -----------------------------------------------------------
      if (kind === "youtube") {
        if (!geminiKey) return { content: [{ type: "text", text: MISSING_GEMINI }], details: {} };
        const videoUrl = parseYouTubeUrl(target)!;
        try {
          const analysis = await analyzeYouTubeUrl(videoUrl, params.question, {
            apiKey: geminiKey,
            model: config.geminiModel,
            signal,
          });
          return { content: [{ type: "text", text: `# YouTube analysis\nVideo: ${videoUrl}\n\n${analysis}` }], details: {} };
        } catch (err) {
          return { content: [{ type: "text", text: `YouTube analysis failed: ${err instanceof Error ? err.message : String(err)}` }], details: {} };
        }
      }

      // --- Local video --------------------------------------------------------
      if (kind === "local-video") {
        if (!geminiKey) return { content: [{ type: "text", text: MISSING_GEMINI }], details: {} };
        try {
          const analysis = await analyzeLocalVideo(target, params.question, {
            apiKey: geminiKey,
            model: config.geminiModel,
            signal,
            method: config.videoMethod,
            ...(params.timestamp || params.frames ? { timestamp: params.timestamp, frames: params.frames } : {}),
          });
          return { content: [{ type: "text", text: `# Video analysis\nFile: ${target}\n\n${analysis}` }], details: {} };
        } catch (err) {
          return { content: [{ type: "text", text: `Video analysis failed: ${err instanceof Error ? err.message : String(err)}` }], details: {} };
        }
      }

      // --- PDF ----------------------------------------------------------------
      if (kind === "pdf" || kind === "local-pdf") {
        if (!geminiKey) return { content: [{ type: "text", text: MISSING_GEMINI }], details: {} };
        try {
          let buf: Buffer;
          if (kind === "local-pdf") {
            buf = await readFile(target);
          } else {
            const res = await fetch(target, { redirect: "follow", signal: withTimeout(signal, 60_000) });
            if (!res.ok) return { content: [{ type: "text", text: `Failed to download PDF: HTTP ${res.status}` }], details: {} };
            buf = Buffer.from(await res.arrayBuffer());
          }
          if (buf.length > config.maxPdfBytes) {
            return {
              content: [{ type: "text", text: `PDF too large (${(buf.length / 1024 / 1024).toFixed(1)}MB, max ${(config.maxPdfBytes / 1024 / 1024).toFixed(0)}MB)` }],
              details: {},
            };
          }
          const text = await extractPdfText(buf, params.question, { apiKey: geminiKey, model: config.geminiModel, signal });
          return { content: [{ type: "text", text: `# PDF content\nSource: ${target}\n\n${text.slice(0, 150_000)}` }], details: {} };
        } catch (err) {
          return { content: [{ type: "text", text: `PDF extraction failed: ${err instanceof Error ? err.message : String(err)}` }], details: {} };
        }
      }

      // --- Web page (TinyFish) ------------------------------------------------
      const apiKey = await resolveCredential({
        authKey: "tinyfish",
        envVar: "TINYFISH_API_KEY",
        configValue: config.tinyfishApiKey,
      });
      if (!apiKey) {
        return {
          content: [
            {
              type: "text",
              text: "Fetch unavailable: TinyFish API key missing. Add { \"tinyfish\": { \"type\": \"api_key\", \"key\": \"...\" } } to auth.json or set TINYFISH_API_KEY.",
            },
          ],
          details: {},
        };
      }
      try {
        const pages = await tinyfishFetch([target], { apiKey, purpose: params.question, signal });
        const page = pages[0];
        if (!page || page.error) {
          return { content: [{ type: "text", text: `Failed to fetch ${target}: ${page?.error ?? "unknown error"}` }], details: {} };
        }
        const header = page.title ? `# ${page.title}\n\nSource: ${target}\n` : `Source: ${target}\n`;
        return { content: [{ type: "text", text: header + page.content.slice(0, MAX_FETCH_OUTPUT_CHARS) }], details: { url: page.url } };
      } catch (err) {
        return { content: [{ type: "text", text: `Fetch failed: ${err instanceof Error ? err.message : String(err)}` }], details: {} };
      }
    },
  });

  // ---------------------------------------------------------------- handoff

  pi.on("before_agent_start", async (event, ctx) => {
    if (!config.enabled || !isHandoffTarget(ctx.model, config)) return;
    handoff.resetTurnAbort();
    handoff.bindTurnSignal(ctx.signal);
    handoff.setTurnPrompt(event.prompt ?? "");
    if (!(await handoff.geminiKey())) return; // context/tool_result will surface the missing-key note
    for (const image of event.images ?? []) {
      if (!image || typeof image !== "object") continue;
      const img = extractImageFromBlock(image);
      if (img) handoff.loadDescription(img).catch(() => {});
    }
  });

  pi.on("tool_result", async (event, ctx) => {
    if (!config.enabled || !isHandoffTarget(ctx.model, config)) return;
    if (event.toolName !== "read") return;
    const content = event.content;
    if (!Array.isArray(content)) return;

    handoff.bindTurnSignal(ctx.signal);

    const images: ReturnType<typeof extractImageFromBlock>[] = [];
    const omittedIndices: number[] = [];
    for (const block of content) {
      const img = extractImageFromBlock(block);
      if (img) images.push(img);
    }
    if (images.length === 0) {
      // Photon/decode failure path: pi emitted "[Image omitted: …]" text with no
      // image block. Re-read the raw file and describe the bytes directly.
      for (let i = 0; i < content.length; i++) {
        const block = content[i];
        if (block && typeof block === "object" && (block as any).type === "text" && typeof (block as any).text === "string") {
          const text = (block as any).text as string;
          if (text.startsWith("[Image omitted:") || text.includes("image was omitted") || text.includes(NON_VISION_IMAGE_NOTE)) {
            omittedIndices.push(i);
          }
        }
      }
      if (omittedIndices.length > 0 && typeof event.input?.path === "string") {
        const resolved = resolveImagePath(ctx.cwd, event.input.path);
        const img = await readImageFileBounded(resolved);
        if (img) {
          for (let i = 0; i < omittedIndices.length; i++) images.push(img);
        } else {
          omittedIndices.length = 0;
        }
      }
    }
    if (images.length === 0) return;

    const descs = await handoff.describeAll(images.filter((x): x is NonNullable<typeof x> => x !== null));
    if (descs.size === 0) return;

    const next = content.slice();
    let changed = false;

    // 1) Omitted-note recovery: replace the note text with the description.
    if (omittedIndices.length > 0) {
      const values = [...descs.values()];
      for (let i = 0; i < omittedIndices.length && i < values.length; i++) {
        next[omittedIndices[i]] = { type: "text", text: values[i] };
        changed = true;
      }
    }

    // 2) Normal path: strip the "[Current model does not support images…]"
    //    note (the description replaces it for the LLM via the context hook;
    //    the image block stays so kitty renders it and /resume retains it).
    for (let i = 0; i < next.length; i++) {
      const block = next[i];
      if (block && typeof block === "object" && (block as any).type === "text" && typeof (block as any).text === "string") {
        const text = (block as any).text as string;
        if (text.includes(NON_VISION_IMAGE_NOTE)) {
          const cleaned = text.split(NON_VISION_IMAGE_NOTE).join("").replace(/\n+$/, "");
          next[i] = { type: "text", text: cleaned };
          changed = true;
        }
      }
    }

    if (changed) return { content: next };
    return undefined;
  });

  pi.on("context", async (event, ctx) => {
    if (!config.enabled || !isHandoffTarget(ctx.model, config)) return;
    const messages = event.messages;
    if (!Array.isArray(messages)) return;

    const images: NonNullable<ReturnType<typeof extractImageFromBlock>>[] = [];
    const seen = new Set<string>();
    for (const msg of messages) {
      const content = msg?.content;
      if (!Array.isArray(content)) continue;
      for (const block of content) {
        const img = extractImageFromBlock(block);
        if (!img) continue;
        const hash = imageHash(img);
        if (!seen.has(hash)) {
          seen.add(hash);
          images.push(img);
        }
      }
    }
    if (images.length === 0) return;

    handoff.bindTurnSignal(ctx.signal);
    const descs = await handoff.describeAll(images);

    let changed = false;
    for (const msg of messages) {
      const content = msg?.content;
      if (!Array.isArray(content)) continue;
      const next: unknown[] = [];
      for (const block of content) {
        const img = extractImageFromBlock(block);
        if (img) {
          const desc = descs.get(imageHash(img));
          if (desc !== undefined) {
            next.push({ type: "text", text: desc });
            changed = true;
            continue;
          }
          const reason = handoff.lastErrorText;
          next.push({ type: "text", text: reason ? `[Image could not be described: ${reason.slice(0, 200)}]` : "[Image could not be described]" });
          changed = true;
          continue;
        }
        next.push(block);
      }
      msg.content = next;
    }
    if (changed) return { messages };
    return undefined;
  });

  // -------------------------------------------------------------- command

  pi.registerCommand("vision-web", {
    description: "Show vision-web status: keys, model, handoff target.",
    handler: async (_args, ctx) => {
      const [gemini, tinyfish] = await Promise.all([
        handoff.geminiKey(),
        resolveCredential({ authKey: "tinyfish", envVar: "TINYFISH_API_KEY", configValue: config.tinyfishApiKey }),
      ]);
      const current = ctx.model;
      const lines = [
        "vision-web status",
        `enabled: ${config.enabled}`,
        `geminiModel: ${config.geminiModel} (key: ${gemini ? "set" : "MISSING"})`,
        `tinyfish: key ${tinyfish ? "set" : "MISSING"}`,
        `handoff: auto=${config.autoHandoff} models=[${config.handoffModels.join(", ")}]`,
        `video: method=${config.videoMethod} model=${config.geminiModel}`,
        `current model: ${formatModelRef(current)} (${isVisionModel(current) ? "vision-capable" : "text-only"}) — handoff ${isHandoffTarget(current, config) ? "active" : "inactive"}`,
        `cache: ${config.cacheMax} max · batch: ${config.batchSize} images/request`,
      ];
      if (handoff.lastErrorText) lines.push(`last error: ${handoff.lastErrorText.slice(0, 160)}`);
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });
}
