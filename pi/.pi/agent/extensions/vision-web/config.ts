/**
 * Config for the vision-web extension. Loaded from
 * ~/.pi/agent/extensions/vision-web/config.json (missing file = defaults).
 */
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir } from "./auth.js";

export interface GitHubCloneConfig {
  /** Set false to skip GitHub-specific handling entirely (URL falls through to normal HTTP extraction). */
  enabled: boolean;
  /** Repos larger than this (MB) get the lightweight API view instead of a clone. */
  maxRepoSizeMB: number;
  /** Force a clone even for oversized repos. */
  forceClone: boolean;
}

export interface Config {
  /** Master switch for the whole extension. */
  enabled: boolean;
  /** Gemini model used for image/video description, e.g. "gemini-3.6-flash". */
  geminiModel: string;
  /** Hand off images to the vision model for every text-only model. */
  autoHandoff: boolean;
  /** Additional provider/model refs (e.g. "opencode-go/deepseek-v4-flash") to hand off for, regardless of autoHandoff. */
  handoffModels: string[];
  /** Max cached image descriptions per session (LRU). */
  cacheMax: number;
  /** Cap on description length in lines (0 = unbounded). */
  maxDescriptionLines: number;
  /** Images per Gemini request. */
  batchSize: number;
  /** Default result count for web_search (1-20). */
  searchDefaultNumResults: number;
  /** Local video method: "auto" (ffmpeg frames if available, else upload), "frames", or "upload". */
  videoMethod: "auto" | "frames" | "upload";
  /** Max bytes uploaded to the Gemini Files API for local video. */
  maxUploadBytes: number;
  /** Max PDF bytes sent inline to Gemini (base64 overhead excluded). */
  maxPdfBytes: number;
  /** GitHub repo handling (clone-first, API for oversized/SHA/private). */
  githubClone: GitHubCloneConfig;
  /** SearXNG instance base URL, e.g. "http://localhost:8080". */
  searxngBaseUrl?: string;
  /** Spin up a local Docker container on demand when searxngBaseUrl is not set. */
  searxngDockerEnabled?: boolean;
  /** Host port mapped to the SearXNG container (default 18765). */
  searxngDockerPort?: number;
  /** Minutes to keep the container alive after the last search (default 5). */
  searxngDockerIdleMinutes?: number;
  /** Optional literal key override; prefer auth.json. */
  geminiApiKey?: string;
}

const DEFAULTS: Config = {
  enabled: true,
  geminiModel: "gemini-3.6-flash",
  autoHandoff: true,
  handoffModels: [],
  cacheMax: 50,
  maxDescriptionLines: 0,
  batchSize: 8,
  searchDefaultNumResults: 5,
  videoMethod: "auto",
  maxUploadBytes: 512 * 1024 * 1024,
  maxPdfBytes: 15 * 1024 * 1024,
  githubClone: { enabled: true, maxRepoSizeMB: 350, forceClone: false },
  searxngDockerEnabled: false,
  searxngDockerPort: 18765,
  searxngDockerIdleMinutes: 5,
};

export function configPath(): string {
  return join(getAgentDir(), "extensions", "vision-web", "config.json");
}

function clampInt(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Math.floor(value)));
}

export function loadConfig(): Config {
  const base: Config = { ...DEFAULTS };
  try {
    if (!existsSync(configPath())) return base;
    const raw = JSON.parse(readFileSync(configPath(), "utf-8"));
    if (!raw || typeof raw !== "object") return base;
    if (typeof raw.enabled === "boolean") base.enabled = raw.enabled;
    if (typeof raw.geminiModel === "string" && raw.geminiModel.trim()) base.geminiModel = raw.geminiModel.trim();
    if (typeof raw.autoHandoff === "boolean") base.autoHandoff = raw.autoHandoff;
    if (Array.isArray(raw.handoffModels)) {
      base.handoffModels = raw.handoffModels.filter((x): x is string => typeof x === "string");
    }
    if (typeof raw.cacheMax === "number" && raw.cacheMax >= 0) base.cacheMax = Math.floor(raw.cacheMax);
    if (typeof raw.maxDescriptionLines === "number" && raw.maxDescriptionLines >= 0) base.maxDescriptionLines = Math.floor(raw.maxDescriptionLines);
    if (typeof raw.batchSize === "number" && raw.batchSize >= 1) base.batchSize = Math.floor(raw.batchSize);
    if (typeof raw.searchDefaultNumResults === "number") base.searchDefaultNumResults = clampInt(raw.searchDefaultNumResults, 1, 20);
    if (raw.videoMethod === "frames" || raw.videoMethod === "upload") base.videoMethod = raw.videoMethod;
    if (typeof raw.maxUploadBytes === "number" && raw.maxUploadBytes > 0) base.maxUploadBytes = Math.floor(raw.maxUploadBytes);
    if (typeof raw.maxPdfBytes === "number" && raw.maxPdfBytes > 0) base.maxPdfBytes = Math.floor(raw.maxPdfBytes);
    if (raw.githubClone && typeof raw.githubClone === "object") {
      const gc = raw.githubClone;
      if (typeof gc.enabled === "boolean") base.githubClone.enabled = gc.enabled;
      if (typeof gc.maxRepoSizeMB === "number" && gc.maxRepoSizeMB > 0) base.githubClone.maxRepoSizeMB = Math.floor(gc.maxRepoSizeMB);
      if (typeof gc.forceClone === "boolean") base.githubClone.forceClone = gc.forceClone;
    }
    if (typeof raw.searxngBaseUrl === "string" && raw.searxngBaseUrl.trim()) base.searxngBaseUrl = raw.searxngBaseUrl.trim();
    if (typeof raw.searxngDockerEnabled === "boolean") base.searxngDockerEnabled = raw.searxngDockerEnabled;
    if (typeof raw.searxngDockerPort === "number" && raw.searxngDockerPort > 0) base.searxngDockerPort = Math.floor(raw.searxngDockerPort);
    if (typeof raw.searxngDockerIdleMinutes === "number" && raw.searxngDockerIdleMinutes > 0) base.searxngDockerIdleMinutes = Math.floor(raw.searxngDockerIdleMinutes);
    if (typeof raw.geminiApiKey === "string" && raw.geminiApiKey.trim()) base.geminiApiKey = raw.geminiApiKey.trim();
  } catch {
    // Malformed config: fall back to defaults.
  }
  return base;
}
