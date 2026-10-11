/**
 * Docker lifecycle for the self-hosted SearXNG container.
 *
 * Reliability fixes over the previous vision-web implementation:
 * - Single in-flight startup promise (mutex): parallel searches share one
 *   `docker run` instead of racing into "Conflict: container name already in use".
 * - `docker pull` runs separately with a long timeout (first boot used to die
 *   in the 15s exec timeout while pulling the image).
 * - SearXNG settings are mounted as a single read-only FILE, not a directory:
 *   the old directory mount got chown'ed to the container UID (977) and the
 *   host could no longer write settings.yml ("Permission denied").
 * - Readiness is probed against the real JSON search endpoint, not HEAD /.
 * - A Conflict/"already in use" on `docker run` falls back to reusing the
 *   running container (covers two pi sessions starting at once).
 * - No process signal handlers calling process.exit() (the old code could
 *   kill the pi process itself on SIGINT).
 */
import { exec } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { randomBytes } from "node:crypto";
import { settingsFilePath } from "./config.js";

const READY_TIMEOUT_MS = 90_000;
const READY_POLL_MS = 1_000;
const PULL_TIMEOUT_MS = 300_000;
const RUN_TIMEOUT_MS = 60_000;
const RM_TIMEOUT_MS = 30_000;

export interface DockerConfig {
  image: string;
  containerName: string;
  port: number;
}

function execPromise(command: string, timeoutMs: number): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    exec(command, { timeout: timeoutMs }, (error, stdout, stderr) => {
      if (error) {
        const err = new Error(`Command failed: ${command}\n${String(stdout).slice(0, 500)}${String(stderr).slice(0, 500)}`);
        (err as any).cause = error;
        reject(err);
      } else {
        resolve({ stdout: String(stdout), stderr: String(stderr) });
      }
    });
  });
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Ensure the settings file exists (generating a secret on first run). Returns its path. */
export function ensureSettingsFile(): string {
  const file = settingsFilePath();
  if (!existsSync(file)) {
    mkdirSync(dirname(file), { recursive: true });
    const secretKey = randomBytes(24).toString("base64").replace(/[^a-zA-Z0-9]/g, "").slice(0, 32);
    writeFileSync(file, defaultSettingsYaml(secretKey), "utf-8");
  }
  return file;
}

/**
 * Tuned SearXNG settings. Engine allowlist verified live (2026-10-11) from a
 * residential IP: Big-Tech scrape engines (brave, duckduckgo, google,
 * startpage, qwant, yahoo) are CAPTCHA/rate-limit blocked, while bing,
 * seznam, yep, wiby, bpb, boardreader, mwmbl and the API-based engines
 * (github, stackoverflow, mdn, docker hub, hackernews, npm, arxiv) work.
 * Blocked engines are disabled so requests never waste time triggering
 * suspensions (which then poison follow-up queries for ~180s).
 */
function defaultSettingsYaml(secretKey: string): string {
  const enable = [
    "bing", "seznam", "yep", "wiby", "bpb", "boardreader", "mwmbl",
    "wikipedia", "wikidata",
    "github", "stackoverflow", "mdn", "docker hub", "hackernews", "npm", "pypi",
    "arxiv",
  ];
  const disable = [
    "brave", "duckduckgo", "google cse", "startpage", "qwant", "yahoo",
    "mojeek", "crowdview", "encyclosearch",
    "google scholar", "semantic scholar",
  ];
  const lines = [
    "use_default_settings: true",
    "server:",
    `  secret_key: "${secretKey}"`,
    "  image_proxy: true",
    "search:",
    "  formats:",
    "    - html",
    "    - json",
    "outgoing:",
    "  retries: 2",
    "  max_timeout: 12.0",
    "engines:",
    // NOTE: the engine schema key is `disabled`, NOT `enabled` (verified
    // against the image's own settings.yml / settings_loader.py).
    ...enable.map((n) => `  - name: ${n}\n    disabled: false\n    timeout: 8.0`),
    ...disable.map((n) => `  - name: ${n}\n    disabled: true`),
    "",
  ];
  return lines.join("\n");
}

export async function isDockerAvailable(): Promise<boolean> {
  try {
    await execPromise("docker --version", 5_000);
    return true;
  } catch {
    return false;
  }
}

export async function isContainerRunning(name: string): Promise<boolean> {
  try {
    const { stdout } = await execPromise(`docker ps --filter name=^/${name}$ --format '{{.Names}}'`, 10_000);
    return stdout.split("\n").map((s) => s.trim()).includes(name);
  } catch {
    return false;
  }
}

/** A container entry (running or stopped) holding the name, if any. */
async function containerPresent(name: string): Promise<boolean> {
  try {
    const { stdout } = await execPromise(`docker ps -a --filter name=^/${name}$ --format '{{.Names}}'`, 10_000);
    return stdout.split("\n").map((s) => s.trim()).includes(name);
  } catch {
    return false;
  }
}

async function imagePresent(image: string): Promise<boolean> {
  try {
    await execPromise(`docker image inspect ${image}`, 15_000);
    return true;
  } catch {
    return false;
  }
}

async function pullImage(image: string): Promise<void> {
  await execPromise(`docker pull ${image}`, PULL_TIMEOUT_MS);
}

async function removeIfPresent(name: string): Promise<void> {
  if (await containerPresent(name)) {
    try {
      await execPromise(`docker rm -f ${name}`, RM_TIMEOUT_MS);
    } catch {
      // ignore: best effort, run below will surface real problems
    }
  }
}

function isNameConflict(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return /already in use|Conflict/i.test(msg);
}

async function runContainer(cfg: DockerConfig, settingsFile: string): Promise<void> {
  try {
    await execPromise(
      `docker run --rm -d -p 127.0.0.1:${cfg.port}:8080 -v "${settingsFile}:/etc/searxng/settings.yml:ro" --name ${cfg.containerName} ${cfg.image}`,
      RUN_TIMEOUT_MS,
    );
  } catch (err) {
    if (!isNameConflict(err)) throw err;
    // Another process (e.g. a second pi session) may have won the race.
    await sleep(1_500);
    if (await isContainerRunning(cfg.containerName)) return;
    // Stale entry: force-remove and try once more.
    await removeIfPresent(cfg.containerName);
    await execPromise(
      `docker run --rm -d -p 127.0.0.1:${cfg.port}:8080 -v "${settingsFile}:/etc/searxng/settings.yml:ro" --name ${cfg.containerName} ${cfg.image}`,
      RUN_TIMEOUT_MS,
    );
  }
}

function timeoutSignal(signal: AbortSignal | undefined, ms: number): AbortSignal {
  const t = AbortSignal.timeout(ms);
  if (signal && typeof AbortSignal.any === "function") return AbortSignal.any([signal, t]);
  return signal ?? t;
}

/** Poll the real JSON search endpoint until it serves (or timeout/abort). */
async function waitForReady(baseUrl: string, signal?: AbortSignal, maxWaitMs = READY_TIMEOUT_MS): Promise<boolean> {
  const deadline = Date.now() + maxWaitMs;
  const url = `${baseUrl.replace(/\/+$/, "")}/search?q=searxng+readiness+probe&format=json`;
  while (Date.now() < deadline) {
    if (signal?.aborted) return false;
    try {
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: timeoutSignal(signal, 5_000),
      });
      if (res.ok) {
        const data = await res.json();
        if (data && Array.isArray((data as any).results)) return true;
      }
    } catch {
      // not ready yet
    }
    await sleep(READY_POLL_MS);
  }
  return false;
}

// ------------------------------------------------------------------
// Public lifecycle API (mutex + idle stop)
// ------------------------------------------------------------------

let pendingStartup: Promise<string | null> | null = null;
let idleTimer: ReturnType<typeof setTimeout> | null = null;

export function baseUrlFor(port: number): string {
  return `http://127.0.0.1:${port}`;
}

/**
 * Ensure the container is up and serving. Concurrent callers share one
 * startup. Returns the base URL, or null when Docker is unavailable or
 * startup failed (callers must fall back / report, never throw).
 */
export function ensureReady(cfg: DockerConfig, signal?: AbortSignal): Promise<string | null> {
  if (!pendingStartup) {
    pendingStartup = startup(cfg, signal).finally(() => {
      pendingStartup = null;
    });
  }
  return pendingStartup;
}

async function startup(cfg: DockerConfig, signal?: AbortSignal): Promise<string | null> {
  if (!(await isDockerAvailable())) return null;
  const baseUrl = baseUrlFor(cfg.port);
  if (await isContainerRunning(cfg.containerName)) {
    if (await waitForReady(baseUrl, signal, 15_000)) return baseUrl;
    // Running but not serving: recycle it.
    await removeIfPresent(cfg.containerName);
  } else {
    await removeIfPresent(cfg.containerName);
  }
  if (!(await imagePresent(cfg.image))) {
    try {
      await pullImage(cfg.image);
    } catch {
      return null;
    }
  }
  let settingsFile: string;
  try {
    settingsFile = ensureSettingsFile();
  } catch {
    return null;
  }
  try {
    await runContainer(cfg, settingsFile);
  } catch {
    return null;
  }
  const ready = await waitForReady(baseUrl, signal);
  if (!ready) {
    await stopContainer(cfg.containerName).catch(() => {});
    return null;
  }
  return baseUrl;
}

export async function stopContainer(name: string): Promise<void> {
  cancelIdleStop();
  try {
    await execPromise(`docker stop ${name}`, RM_TIMEOUT_MS);
  } catch {
    // ignore: already stopped / gone
  }
}

/** (Re)schedule stopping the container after idleMs without searches. */
export function scheduleIdleStop(name: string, idleMs: number): void {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    idleTimer = null;
    stopContainer(name).catch(() => {});
  }, idleMs);
  // Don't keep the pi process alive just for this timer.
  (idleTimer as any)?.unref?.();
}

export function cancelIdleStop(): void {
  if (idleTimer) {
    clearTimeout(idleTimer);
    idleTimer = null;
  }
}

export async function containerStatus(name: string, port: number): Promise<{ running: boolean; present: boolean; url: string }> {
  return {
    running: await isContainerRunning(name),
    present: await containerPresent(name),
    url: baseUrlFor(port),
  };
}

export async function containerLogs(name: string, tail = 30): Promise<string> {
  try {
    const { stdout } = await execPromise(`docker logs --tail ${Math.max(1, Math.min(200, tail))} ${name}`, 10_000);
    return stdout.trim() || "(no logs)";
  } catch (err) {
    return `(could not read logs: ${err instanceof Error ? err.message.split("\n")[0] : String(err)})`;
  }
}
