/**
 * Media understanding: YouTube URLs, local video files, and PDFs — all via the
 * Gemini API (verified: YouTube fileData works without yt-dlp, PDF inlineData
 * works, Files API upload works).
 *
 * Local video strategy ("auto"):
 *   - ffmpeg available → extract N frames (sampled or at timestamp) → cheap
 *     image analysis.
 *   - otherwise → upload the file to the Gemini Files API (multipart) and
 *     analyze it directly. Uploaded files are deleted afterwards.
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { generateParts, describeImages, fileDataPart, pdfPart, textPart, withTimeout, redact, type ImageInput } from "./gemini.js";

const execFileAsync = promisify(execFile);

const UPLOAD_BASE = "https://generativelanguage.googleapis.com/upload/v1beta";
const API_BASE = "https://generativelanguage.googleapis.com/v1beta";
const DEFAULT_VIDEO_PROMPT =
  "Analyze this video for a coding assistant. Describe what happens, in order, including any visible text, UI, code, diagrams, or audio that matters. Be specific and exhaustive.";
const DEFAULT_PDF_PROMPT =
  "Extract the full text content of this PDF, preserving headings, code blocks, and structure as markdown. If it is scanned (image-based), transcribe the text you can read.";

// ------------------------------------------------------------------- helpers

export function parseYouTubeUrl(url: string): string | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  const host = parsed.hostname.toLowerCase().replace(/^www\.|^m\./, "");
  if (host === "youtu.be") {
    const id = parsed.pathname.split("/").filter(Boolean)[0];
    return id ? `https://www.youtube.com/watch?v=${id}` : null;
  }
  if (host !== "youtube.com" && host !== "youtube-nocookie.com") return null;
  const id = parsed.searchParams.get("v") ?? parsed.pathname.split("/")[2];
  return id ? `https://www.youtube.com/watch?v=${id}` : null;
}

function isLocalVideoPath(path: string): boolean {
  return /\.(mp4|mkv|mov|avi|webm|m4v|flv|wmv|mpeg|mpg)$/i.test(path) && existsSync(path);
}

function isPdfPath(path: string): boolean {
  return /\.pdf$/i.test(path);
}

// ---------------------------------------------------------------- Gemini URL

export async function analyzeYouTubeUrl(videoUrl: string, question: string | undefined, opts: { apiKey: string; model: string; signal?: AbortSignal }): Promise<string> {
  const text = question?.trim() ? `The user asks about this video: ${question.trim()}\n\n${DEFAULT_VIDEO_PROMPT}` : DEFAULT_VIDEO_PROMPT;
  return generateParts([fileDataPart(videoUrl), textPart(text)], {
    apiKey: opts.apiKey,
    model: opts.model,
    signal: opts.signal,
    timeoutMs: 180_000,
  });
}

// ----------------------------------------------------------------- file upload

interface UploadedFile {
  name: string;
  uri: string;
}

export async function uploadGeminiFile(bytes: Uint8Array, mimeType: string, displayName: string, opts: { apiKey: string; signal?: AbortSignal }): Promise<UploadedFile> {
  const boundary = `----visionweb${Date.now()}${Math.random().toString(36).slice(2, 8)}`;
  const meta = JSON.stringify({ file: { display_name: displayName, mime_type: mimeType } });
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="metadata"\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n`),
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${displayName}"\r\nContent-Type: ${mimeType}\r\n\r\n`),
    Buffer.from(bytes),
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  const res = await fetch(`${UPLOAD_BASE}/files?key=${opts.apiKey}`, {
    method: "POST",
    headers: { "Content-Type": `multipart/form-data; boundary=${boundary}` },
    body,
    signal: withTimeout(opts.signal, 300_000),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`Gemini upload failed ${res.status}: ${redact(raw, opts.apiKey).slice(0, 300)}`);
  const file = JSON.parse(raw).file;
  if (!file?.name || !file?.uri) throw new Error("Gemini upload returned an unexpected response");
  return { name: file.name, uri: file.uri };
}

export async function deleteGeminiFile(name: string, apiKey: string): Promise<void> {
  try {
    await fetch(`${API_BASE}/${name}?key=${apiKey}`, { method: "DELETE" });
  } catch {
    // best-effort cleanup
  }
}

/** Poll the Files API until the uploaded file is ACTIVE (or FAILED/times out). */
export async function waitForFileActive(name: string, apiKey: string, signal?: AbortSignal, timeoutMs = 90_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
  while (Date.now() < deadline) {
    if (signal?.aborted) throw new Error("aborted while waiting for file processing");
    const res = await fetch(`${API_BASE}/${name}?key=${apiKey}`, {
      signal: withTimeout(signal, 30_000),
    });
    if (res.ok) {
      const data = await res.json();
      const state = data?.state ?? data?.file?.state; // GET: top-level; upload: nested
      if (state === "ACTIVE") return;
      if (state === "FAILED") throw new Error("Gemini failed to process the uploaded file");
    }
    await sleep(2_000);
  }
  throw new Error(`Gemini file did not become ACTIVE within ${Math.round(timeoutMs / 1000)}s`);
}

// ------------------------------------------------------------------- ffmpeg

let ffmpegAvailable: boolean | null = null;
export async function hasFfmpeg(): Promise<boolean> {
  if (ffmpegAvailable !== null) return ffmpegAvailable;
  try {
    await execFileAsync("ffmpeg", ["-version"], { timeout: 5_000 });
    ffmpegAvailable = true;
  } catch {
    ffmpegAvailable = false;
  }
  return ffmpegAvailable;
}

async function videoDurationSec(filePath: string): Promise<number | null> {
  try {
    const { stdout } = await execFileAsync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", filePath], { timeout: 15_000 });
    const n = Number.parseFloat(stdout.trim());
    return Number.isFinite(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

async function extractFrames(filePath: string, timestampsSec: number[]): Promise<ImageInput[]> {
  const images: ImageInput[] = [];
  let i = 0;
  for (const ts of timestampsSec) {
    const out = join(tmpdir(), `visionweb-frame-${process.pid}-${Date.now()}-${i++}.jpg`);
    try {
      await execFileAsync(
        "ffmpeg",
        ["-v", "error", "-ss", String(ts), "-i", filePath, "-frames:v", "1", "-q:v", "3", "-y", out],
        { timeout: 30_000 },
      );
      const buf = readFileSync(out);
      if (buf.length > 0 && buf.length < 15 * 1024 * 1024) {
        images.push({ data: buf.toString("base64"), mimeType: "image/jpeg" });
      }
    } catch {
      // skip failed frames
    }
  }
  return images;
}

function sampleTimestamps(durationSec: number, frames: number): number[] {
  const out: number[] = [];
  if (durationSec <= 0 || frames <= 0) return out;
  for (let k = 0; k < frames; k++) out.push((durationSec * (k + 0.5)) / frames);
  return out;
}

function parseTimestamp(value: string): number | [number, number] | null {
  const trimmed = value.trim();
  const rangeMatch = /^(\d{1,2}:)?(\d{1,2}):(\d{1,2})-(\d{1,2}:)?(\d{1,2}):(\d{1,2})$/.exec(trimmed);
  if (rangeMatch) {
    const h1 = rangeMatch[1] ? Number(rangeMatch[1].slice(0, -1)) : 0;
    const h2 = rangeMatch[4] ? Number(rangeMatch[4].slice(0, -1)) : 0;
    return [h1 * 3600 + Number(rangeMatch[2]) * 60 + Number(rangeMatch[3]), h2 * 3600 + Number(rangeMatch[5]) * 60 + Number(rangeMatch[6])];
  }
  const single = /^(\d{1,2}:)?(\d{1,2}):(\d{1,2})$/.exec(trimmed);
  if (single) {
    const h = single[1] ? Number(single[1].slice(0, -1)) : 0;
    return h * 3600 + Number(single[2]) * 60 + Number(single[3]);
  }
  const n = Number(trimmed);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

export interface FrameOptions {
  timestamp?: string; // '1:23:45', '23:41-25:00', or seconds
  frames?: number; // 1-12
}

/**
 * Local video analysis. Returns null when neither ffmpeg nor upload can work.
 */
export async function analyzeLocalVideo(
  filePath: string,
  question: string | undefined,
  opts: { apiKey: string; model: string; signal?: AbortSignal; method: "auto" | "frames" | "upload" },
): Promise<string> {
  const text = question?.trim() ? `The user asks about this video: ${question.trim()}\n\n${DEFAULT_VIDEO_PROMPT}` : DEFAULT_VIDEO_PROMPT;
  const useFrames = opts.method !== "upload" && (await hasFfmpeg());
  if (useFrames) {
    const parsed = opts.timestamp ? parseTimestamp(opts.timestamp) : null;
    let timestamps: number[] = [];
    if (Array.isArray(parsed)) {
      const [start, end] = parsed;
      const n = opts.frames ?? 6;
      for (let k = 0; k < n; k++) timestamps.push(start + ((end - start) * (k + 0.5)) / n);
    } else if (typeof parsed === "number") {
      const n = opts.frames ?? 1;
      for (let k = 0; k < n; k++) timestamps.push(parsed + k * 5);
    } else {
      const duration = await videoDurationSec(filePath);
      timestamps = sampleTimestamps(duration ?? 30, opts.frames ?? 6);
    }
    const images = await extractFrames(filePath, timestamps);
    if (images.length > 0) {
      const descs = await describeImages(images, text, {
        apiKey: opts.apiKey,
        model: opts.model,
        signal: opts.signal,
        batchSize: images.length,
        timeoutMs: 120_000,
      });
      const lines = images.map((_, i) => `Frame ${i + 1} (t≈${timestamps[i].toFixed(1)}s):\n${descs[i] ?? ""}`.trim()).filter(Boolean);
      return lines.join("\n\n");
    }
    if (opts.method === "frames") return "ffmpeg frame extraction produced no frames (is the file a valid video?)";
    // fall through to upload
  }

  const buf = await readFile(filePath);
  const mime = videoMime(filePath);
  const uploaded = await uploadGeminiFile(buf, mime, filePath.split("/").pop() ?? "video", {
    apiKey: opts.apiKey,
    signal: opts.signal,
  });
  try {
    await waitForFileActive(uploaded.name, opts.apiKey, opts.signal);
    const result = await generateParts([fileDataPart(uploaded.uri, mime), textPart(text)], {
      apiKey: opts.apiKey,
      model: opts.model,
      signal: opts.signal,
      timeoutMs: 300_000,
    });
    return result;
  } finally {
    void deleteGeminiFile(uploaded.name, opts.apiKey);
  }
}

function videoMime(path: string): string {
  const ext = path.toLowerCase().split(".").pop() ?? "";
  const map: Record<string, string> = {
    mp4: "video/mp4",
    m4v: "video/mp4",
    mov: "video/quicktime",
    mkv: "video/x-matroska",
    avi: "video/x-msvideo",
    webm: "video/webm",
    flv: "video/x-flv",
    wmv: "video/x-ms-wmv",
    mpeg: "video/mpeg",
    mpg: "video/mpeg",
  };
  return map[ext] ?? "video/mp4";
}

// ----------------------------------------------------------------------- PDF

export async function extractPdfText(data: Buffer, question: string | undefined, opts: { apiKey: string; model: string; signal?: AbortSignal }): Promise<string> {
  const text = question?.trim() ? `The user asks about this PDF: ${question.trim()}\n\n${DEFAULT_PDF_PROMPT}` : DEFAULT_PDF_PROMPT;
  return generateParts([pdfPart(data), textPart(text)], {
    apiKey: opts.apiKey,
    model: opts.model,
    signal: opts.signal,
    timeoutMs: 180_000,
  });
}

// -------------------------------------------------------------- URL routing

export function classifyFetchTarget(urlOrPath: string): "youtube" | "github" | "pdf" | "local-video" | "local-pdf" | "web" {
  if (parseYouTubeUrl(urlOrPath)) return "youtube";
  if (urlOrPath.startsWith("https://github.com/") || urlOrPath.startsWith("http://github.com/") || urlOrPath.startsWith("https://www.github.com/")) return "github";
  if (isPdfPath(urlOrPath) && existsSync(urlOrPath)) return "local-pdf";
  if (isLocalVideoPath(urlOrPath)) return "local-video";
  if (isPdfPath(urlOrPath)) return "pdf";
  return "web";
}
