/**
 * Vision handoff: when a text-only model gets an image, describe it with the
 * Gemini API and feed the text description to the model instead.
 *
 * Flow (modeled on pi-vision-handoff, simplified to match the original config:
 * no paste-time prewarm, no async clipboard injection):
 *
 *   1. before_agent_start — prewarm descriptions for attached images so the
 *      later hooks are cache hits (starts the moment you press enter).
 *   2. tool_result (read tool) — strip pi's "[Current model does not support
 *      images…]" note and splice the description into the text; the image
 *      block itself is kept so kitty still renders it and /resume retains it.
 *   3. context (before every LLM call) — swap image blocks for their text
 *      descriptions in the LLM-bound clone.
 *
 * Optimizations: content-hash LRU cache, single-flight batching (multiple
 * images arriving in the same frame coalesce into ONE Gemini request), and
 * turn-abort wiring so Esc cancels in-flight descriptions.
 */
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { describeImages, type ImageInput } from "./gemini.js";
import { resolveCredential } from "./auth.js";
import type { Config } from "./config.js";

export const NON_VISION_IMAGE_NOTE = "[Current model does not support images. The image will be omitted from this request.]";
const DEFAULT_VISION_PROMPT =
  "You are a vision assistant for a coding agent. Describe this image exhaustively. Cover: all visible text (verbatim if possible), code snippets, UI layout and widgets, diagrams and flow arrows, error messages and stack traces, file trees, terminal output, color and style details, spatial relationships between elements, and anything else a developer would need to act on this image. Do not summarize — be exhaustive.";

export function imageHash(img: ImageInput): string {
  return createHash("sha256").update(`${img.mimeType}\0${img.data}`).digest("hex").slice(0, 32);
}

export function extractImageFromBlock(block: unknown): ImageInput | null {
  if (!block || typeof block !== "object") return null;
  const b = block as any;
  if (b.type === "image" && typeof b.data === "string" && typeof b.mimeType === "string") {
    return { data: b.data, mimeType: b.mimeType };
  }
  if (b.type === "image_url" && typeof b.image_url?.url === "string") {
    const parsed = parseDataUrl(b.image_url.url);
    if (parsed) return parsed;
  }
  if (b.type === "input_image") {
    const url = typeof b.image_url === "string" ? b.image_url : b.image_url?.url;
    if (typeof url === "string") {
      const parsed = parseDataUrl(url);
      if (parsed) return parsed;
    }
  }
  return null;
}

function parseDataUrl(url: string): ImageInput | null {
  const m = /^data:([^;,]+);base64,(.+)$/.exec(url);
  if (!m) return null;
  return { mimeType: m[1], data: m[2] };
}

export function isVisionModel(model: { provider?: string; id?: string; input?: string[] } | undefined): boolean {
  return !!model && Array.isArray(model.input) && model.input.includes("image");
}

export function isHandoffTarget(
  model: { provider?: string; id?: string; input?: string[] } | undefined,
  cfg: Config,
): boolean {
  if (!model || !model.provider || !model.id) return false;
  const ref = `${model.provider}/${model.id}`;
  if (cfg.handoffModels.includes(ref)) return true;
  if (cfg.autoHandoff && !isVisionModel(model)) return true;
  return false;
}

interface PendingItem {
  img: ImageInput;
  resolve: (text: string) => void;
  reject: (err: unknown) => void;
}

export class VisionHandoff {
  private cache = new Map<string, Promise<string>>();
  private pending: PendingItem[] = [];
  private flushTimer: NodeJS.Timeout | null = null;
  private turnAbort = new AbortController();
  private turnPrompt = "";
  private lastError: string | null = null;

  constructor(private getConfig: () => Config) {}

  resetTurnAbort(): void {
    this.turnAbort.abort();
    this.turnAbort = new AbortController();
  }

  bindTurnSignal(signal?: AbortSignal): void {
    if (signal && !signal.aborted) {
      signal.addEventListener("abort", () => this.turnAbort.abort(), { once: true });
    }
  }

  setTurnPrompt(prompt: string): void {
    this.turnPrompt = prompt;
  }

  get lastErrorText(): string | null {
    return this.lastError;
  }

  async geminiKey(): Promise<string | undefined> {
    const cfg = this.getConfig();
    return resolveCredential({ authKey: "google", envVar: "GEMINI_API_KEY", configValue: cfg.geminiApiKey });
  }

  loadDescription(img: ImageInput): Promise<string> {
    const hash = imageHash(img);
    const hit = this.cache.get(hash);
    if (hit) return hit;
    const promise = new Promise<string>((resolvePromise, rejectPromise) => {
      this.pending.push({ img, resolve: resolvePromise, reject: rejectPromise });
    });
    this.cache.set(hash, promise);
    if (this.cache.size > this.getConfig().cacheMax) {
      const oldest = this.cache.keys().next().value;
      if (oldest !== undefined) this.cache.delete(oldest);
    }
    this.scheduleFlush();
    return promise;
  }

  private scheduleFlush(): void {
    if (this.flushTimer) return;
    this.flushTimer = setImmediate(() => {
      this.flushTimer = null;
      void this.flushBatch();
    });
  }

  private async flushBatch(): Promise<void> {
    const cfg = this.getConfig();
    const batch = this.pending.splice(0, cfg.batchSize);
    if (batch.length === 0) return;
    try {
      const apiKey = await this.geminiKey();
      if (!apiKey) {
        throw new Error(
          "Gemini API key not found. Add { \"google\": { \"type\": \"api_key\", \"key\": \"...\" } } to ~/.pi/agent/auth.json or set GEMINI_API_KEY.",
        );
      }
      const prompt = this.turnPrompt
        ? `The user's request about this image: ${this.turnPrompt}\n\n${DEFAULT_VISION_PROMPT}`
        : DEFAULT_VISION_PROMPT;
      const descriptions = await describeImages(
        batch.map((item) => item.img),
        prompt,
        {
          apiKey,
          model: cfg.geminiModel,
          signal: this.turnAbort.signal,
          batchSize: cfg.batchSize,
          maxDescriptionLines: cfg.maxDescriptionLines,
        },
      );
      this.lastError = null;
      batch.forEach((item, i) => item.resolve(descriptions[i] ?? ""));
    } catch (err) {
      this.lastError = err instanceof Error ? err.message : String(err);
      const reason = err instanceof Error ? err.message : String(err);
      for (const item of batch) item.reject(new Error(reason));
    } finally {
      if (this.pending.length > 0) this.scheduleFlush();
    }
  }

  /** Describe every image, awaiting cache hits/misses. Used by context hook. */
  async describeAll(images: ImageInput[]): Promise<Map<string, string>> {
    const out = new Map<string, string>();
    if (images.length === 0) return out;
    const results = await Promise.allSettled(images.map((img) => this.loadDescription(img)));
    images.forEach((img, i) => {
      const result = results[i];
      if (result.status === "fulfilled") out.set(imageHash(img), result.value);
    });
    return out;
  }

  dispose(): void {
    if (this.flushTimer) clearImmediate(this.flushTimer);
    this.flushTimer = null;
    this.turnAbort.abort();
    this.cache.clear();
    this.pending = [];
  }
}

/** Re-read a file as base64 (used to recover images pi's read tool omitted). */
export async function readImageFileBounded(path: string): Promise<ImageInput | null> {
  try {
    const buf = await readFile(path);
    const mime = mimeFromPath(path);
    if (buf.length > 15 * 1024 * 1024) return null;
    return { data: buf.toString("base64"), mimeType: mime };
  } catch {
    return null;
  }
}

function mimeFromPath(path: string): string {
  const lower = path.toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".heic") || lower.endsWith(".heif")) return "image/heic";
  return "image/png";
}

export function resolveImagePath(cwd: string, inputPath: string): string {
  return isAbsolute(inputPath) ? inputPath : resolve(cwd, inputPath);
}

export function formatModelRef(model: { provider?: string; id?: string } | undefined): string {
  return model ? `${model.provider}/${model.id}` : "none";
}
