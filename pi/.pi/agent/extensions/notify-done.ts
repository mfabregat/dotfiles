/**
 * Pi notify-done extension
 *
 * Sends a Linux desktop notification when Pi's agent has fully finished a
 * task and is waiting for input. Uses `agent_settled` (not `agent_end`)
 * because agent_end fires while Pi may still auto-retry, auto-compact, or
 * process queued follow-up messages — agent_settled is the true "task done"
 * moment.
 *
 * Click-to-raise: the notification is sent with a `desktop-entry` hint, so
 * desktop environments (GNOME) activate the terminal app — and its most
 * recently focused window — when the notification body is clicked. External
 * window focus is blocked on Wayland, so this is app-level activation: with
 * several Pi terminals open, the most recently used one gets raised.
 *
 * Config (environment variables, all optional):
 *   PI_NOTIFY_MIN_SECONDS    minimum task duration in seconds to notify (default 10)
 *   PI_NOTIFY_URGENCY        low | normal | critical (default normal)
 *   PI_NOTIFY_ICON           icon name (default utilities-terminal)
 *   PI_NOTIFY_DESKTOP_ENTRY  desktop-entry hint → body click raises this app
 *                            (default com.mitchellh.ghostty; empty = no click action)
 *
 * Fallbacks:
 *   - gdbus unavailable/failing → notify-send (no click-to-raise)
 *   - notify-send missing/headless → terminal OSC 777 notification
 *   - Nothing here ever throws — a failure can never break Pi.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { appendFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

// ── Debug log (append-only; helps diagnose why a notification didn't show) ──
const LOG_FILE = join(homedir(), ".pi", "notify-done.log");
function log(...parts: unknown[]): void {
  try {
    appendFileSync(LOG_FILE, `${new Date().toISOString()} ${parts.join(" ")}\n`);
  } catch {
    // logging must never break the extension
  }
}

// ── Config ─────────────────────────────────────────────────────────────
const parsedMin = parseFloat(process.env.PI_NOTIFY_MIN_SECONDS ?? "10");
const MIN_SECONDS = Number.isFinite(parsedMin) && parsedMin >= 0 ? parsedMin : 10;
const URGENCY = process.env.PI_NOTIFY_URGENCY ?? "normal";
const ICON = process.env.PI_NOTIFY_ICON ?? "utilities-terminal";
const DESKTOP_ENTRY = process.env.PI_NOTIFY_DESKTOP_ENTRY ?? "com.mitchellh.ghostty";
const DEBOUNCE_MS = 5_000; // ignore agent_settled re-fires within this window

// ── State (reset on session shutdown) ──────────────────────────────────
let turnStartTime: number | null = null;
let lastNotifiedAt = 0;

// ── Helpers ─────────────────────────────────────────────────────────────

function formatDuration(ms: number): string {
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

function hasDesktopSession(): boolean {
  return Boolean(
    process.env.DISPLAY || process.env.WAYLAND_DISPLAY || process.env.DBUS_SESSION_BUS_ADDRESS,
  );
}

/** Escape a string for use as a GVariant single-quoted literal. */
function gvariantString(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/[\x00-\x1f\x7f]/g, " ");
}

function urgencyByte(): number {
  switch (URGENCY) {
    case "low": return 0;
    case "critical": return 2;
    default: return 1;
  }
}

/** Fallback: terminal OSC 777 notification (Ghostty, iTerm2, WezTerm, rxvt-unicode). */
function notifyTerminal(title: string, body: string): void {
  const safe = (s: string) => s.replace(/[\x07\x1b;]/g, " ").replace(/\s+/g, " ").trim();
  process.stdout.write(`\x1b]777;notify;${safe(title)};${safe(body)}\x07`);
}

/** Simple notification, no click-to-raise (no hints support). */
function notifyViaNotifySend(title: string, body: string): void {
  execFile("/usr/bin/notify-send", ["-a", "pi", "-i", ICON, "-u", URGENCY, title, body], { timeout: 5_000 }, (err) => {
    if (err) {
      log("notify-send failed:", (err as NodeJS.ErrnoException).code ?? err.message);
      notifyTerminal(title, body); // missing binary / no daemon → OSC
    } else {
      log("notify-send ok:", title, body);
    }
  });
}

/**
 * Primary path: DBus Notify with a desktop-entry hint so clicking the
 * notification body raises the terminal app. On any failure, falls back to
 * notify-send, which falls back to the OSC terminal notification.
 */
function notifySystem(title: string, body: string): void {
  if (!hasDesktopSession()) {
    log("no desktop session -> OSC");
    notifyTerminal(title, body);
    return;
  }

  const hints: string[] = [];
  if (DESKTOP_ENTRY) hints.push(`'desktop-entry': <'${gvariantString(DESKTOP_ENTRY)}'>`);
  hints.push(`'urgency': <byte ${urgencyByte()}>`);

  execFile("gdbus", [
    "call", "--session",
    "--dest", "org.freedesktop.Notifications",
    "--object-path", "/org/freedesktop/Notifications",
    "--method", "org.freedesktop.Notifications.Notify",
    "pi",                       // app_name
    "0",                        // replaces_id
    ICON,                       // app_icon
    gvariantString(title),      // summary
    gvariantString(body),       // body
    "[]",                       // actions
    `{${hints.join(", ")}}`,    // hints
    "5000",                     // expire_timeout (ms)
  ], { timeout: 5_000 }, (err) => {
    if (err) {
      log("gdbus failed:", (err as NodeJS.ErrnoException).code ?? err.message);
      notifyViaNotifySend(title, body);
    } else {
      log("gdbus ok:", title, body);
    }
  });
}

// ── Extension ──────────────────────────────────────────────────────────
export default function (pi: ExtensionAPI) {
  // Remember when a run started.
  pi.on("agent_start", () => {
    turnStartTime = Date.now();
    log("agent_start, turnStartTime =", turnStartTime);
  });

  // The real "done" moment: no retry/compaction/follow-up left.
  pi.on("agent_settled", async (_event, ctx) => {
    try {
      if (!ctx.isIdle()) { log("agent_settled: not idle, skip"); return; }
      if (turnStartTime === null) { log("agent_settled: no turnStartTime, skip"); return; }

      const elapsed = Date.now() - turnStartTime;
      log("agent_settled: elapsed =", elapsed, "ms");

      // Debounce: skip quick tasks and rapid re-fires.
      if (elapsed < MIN_SECONDS * 1000) { log("agent_settled: below MIN_SECONDS, skip"); return; }
      if (Date.now() - lastNotifiedAt < DEBOUNCE_MS) { log("agent_settled: debounce, skip"); return; }
      lastNotifiedAt = Date.now();

      log("notifying:", `Task finished in ${formatDuration(elapsed)}`);
      notifySystem("Pi — done", `Task finished in ${formatDuration(elapsed)}`);
    } catch (e) {
      log("agent_settled error:", (e as Error).message);
    }
  });

  // Reset per-session state.
  pi.on("session_shutdown", () => {
    turnStartTime = null;
    lastNotifiedAt = 0;
    log("session_shutdown: state reset");
  });
}
