/**
 * Central credential resolution for vision-web.
 *
 * Keys live in pi's native auth.json (~/.pi/agent/auth.json) so there is a
 * single source of truth. Pi itself only ever writes auth.json with merge
 * semantics (it preserves unknown top-level keys), so adding non-pi providers
 * The `google` key doubles as pi's native Gemini
 * provider id: whatever you store there is also picked up by pi itself.
 *
 * Resolution order per credential:
 *   1. pi auth.json entry (authKey) — supports $ENV interpolation
 *   2. environment variable (envVar)
 *   3. extension config.json value (configValue, discouraged)
 */
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface CredentialOptions {
  /** Key name in pi's auth.json, e.g. "google". */
  authKey?: string;
  /** Fallback environment variable, e.g. "GEMINI_API_KEY". */
  envVar?: string;
  /** Last-resort literal from the extension config. */
  configValue?: string;
}

/** pi's agent config dir, honoring PI_CODING_AGENT_DIR overrides. */
export function getAgentDir(): string {
  return process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
}

function readAuthJson(): Record<string, any> {
  try {
    const path = join(getAgentDir(), "auth.json");
    if (!existsSync(path)) return {};
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return {};
  }
}

/**
 * Resolve a configured key value the same way pi does:
 *   $VAR / ${VAR}  -> environment variable
 *   $$             -> literal "$"
 *   $!             -> literal "!"
 *   anything else  -> literal value
 */
export function resolveConfigValue(value: string): string | undefined {
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  if (trimmed.startsWith("$$")) return trimmed.slice(1);
  if (trimmed.startsWith("$!")) return trimmed.slice(1);
  const explicit = /^\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})$/.exec(trimmed);
  if (explicit) {
    const name = explicit[1] ?? explicit[2];
    const env = process.env[name];
    return env && env.trim() ? env.trim() : undefined;
  }
  return trimmed;
}

export async function resolveCredential(options: CredentialOptions): Promise<string | undefined> {
  if (options.authKey) {
    const auth = readAuthJson();
    const entry = auth[options.authKey];
    if (entry && typeof entry === "object") {
      const raw = entry.key;
      if (typeof raw === "string" && raw.trim()) {
        const resolved = resolveConfigValue(raw);
        if (resolved) return resolved;
      }
    } else if (typeof entry === "string" && entry.trim()) {
      const resolved = resolveConfigValue(entry);
      if (resolved) return resolved;
    }
  }
  if (options.envVar) {
    const env = process.env[options.envVar];
    if (env && env.trim()) return env.trim();
  }
  if (options.configValue && options.configValue.trim()) return options.configValue.trim();
  return undefined;
}
