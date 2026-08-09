/**
 * devcontainer-bash — route pi's `bash` tool into a running devcontainer.
 *
 * pi runs on the host (native config, API keys, sessions, packages) while
 * every bash command executes inside the project's devcontainer via
 * `docker exec`, so pi gets the container's exact toolchain (ROS, compilers,
 * DB clients, ...) without losing anything.
 *
 * Agnostic by design — nothing is hardcoded:
 *   - The devcontainer is located from pi's working directory by walking up
 *     to the nearest `.devcontainer/` directory.
 *   - The container is detected via the `devcontainer.local_folder` label
 *     (stamped by the devcontainers CLI), falling back to a container whose
 *     name equals the workspace folder name, falling back to a
 *     `<folder>-…`-prefixed name (docker compose), falling back to an
 *     explicit `container` config value.
 *   - The exec user comes from config, then `remoteUser`/`containerUser` in
 *     the project's devcontainer.json (`${localEnv:X}` / `${env:X}` are
 *     substituted from the host environment — e.g. `"${localEnv:USER}"`),
 *     then the container's own `Config.User`. Unresolvable values fall
 *     through to the next candidate instead of reaching `docker exec`.
 *   - Extra env is taken from the project's `remoteEnv` (with `${localEnv:X}`
 *     substitution) plus config overrides.
 *   - Host cwd is translated to the container using the devcontainer's
 *     `workspaceFolder` (with `${localWorkspaceFolder}` substitution). A
 *     same-path bind mount (compose style) maps 1:1 automatically.
 *   - Timeouts and aborts kill the command's in-container process group.
 *     Killing only the docker CLI would leave the command running inside the
 *     container (verified: `sleep 60` survived a client kill).
 *
 * On/off:
 *   - Auto-loaded from `~/.pi/agent/extensions/` (hot-reload with `/reload`).
 *   - `enabled: false` in config disables it (global or per project).
 *   - `pi --no-devcontainer-bash` disables it for a run.
 *   - `/devcontainer-bash status|recheck|on|off|toggle` shows state or toggles
 *     (on/off/toggle persist `enabled` to the project's `.pi/devcontainer-bash.json`).
 *   - A footer status indicator (TUI) shows the routing state: an
 *     accent-colored (blue) `🐳 g1_ws · devcontainer (marc)` when commands
 *     run inside the container, a dim `○ g1_ws · host shell (no container)`
 *     when no container is running. Nothing is shown when routing is off or
 *     outside a devcontainer workspace. Refreshed at session start, each
 *     turn, and on every bash call.
 *   - If no running container is found, bash falls back to the host shell
 *     (or errors, per `whenNoContainer`). Detection re-runs on a short TTL,
 *     so starting the devcontainer later is picked up automatically.
 *
 * Config files (project takes precedence):
 *   - ~/.pi/agent/extensions/devcontainer-bash.json   (global)
 *   - <workspace>/.pi/devcontainer-bash.json          (project)
 *
 * ```jsonc
 * {
 *   "enabled": true,                  // master switch
 *   "container": "auto",              // "auto" | name | id
 *   "user": "auto",                   // "auto" | "marc" | "root" | uid
 *   "workspaceFolder": null,          // force container workspace path
 *   "interactive": true,              // bash -ic (loads ~/.bashrc) vs bash -lc
 *   "filterJobControlNoise": true,    // strip "no job control" stderr noise
 *   "whenNoContainer": "pass-through",// "pass-through" | "error"
 *   "env": { "SSH_AUTH_SOCK": null }, // extra env; null = copy from host
 *   "recheckIntervalMs": 5000
 * }
 * ```
 */

import { spawn, execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, posix, relative, resolve } from "node:path";
import { StringDecoder } from "node:string_decoder";
import {
	CONFIG_DIR_NAME,
	createBashTool,
	getAgentDir,
	type BashOperations,
	type ExtensionAPI,
	type ExtensionContext,
} from "@earendil-works/pi-coding-agent";

// ---------------------------------------------------------------------------
// Types & defaults
// ---------------------------------------------------------------------------

export interface DevcontainerBashConfig {
	enabled?: boolean;
	/** "auto" | explicit container name or id */
	container?: string;
	/** "auto" | explicit exec user */
	user?: string;
	/** Force the container-side workspace path (overrides devcontainer.json) */
	workspaceFolder?: string;
	/** true: bash -ic (sources ~/.bashrc, faithful interactive shell) */
	interactive?: boolean;
	/** Strip "cannot set terminal process group" / "no job control" stderr noise */
	filterJobControlNoise?: boolean;
	/** What bash does when the devcontainer is configured but not running */
	whenNoContainer?: "pass-through" | "error";
	/** Extra env to inject; null = copy from host */
	env?: Record<string, string | null>;
	/** How often container detection re-runs (ms) */
	recheckIntervalMs?: number;
}

export const DEFAULT_CONFIG: Required<
	Omit<DevcontainerBashConfig, "env" | "container" | "user" | "workspaceFolder">
> &
	Pick<DevcontainerBashConfig, "container" | "user" | "workspaceFolder"> = {
	enabled: true,
	container: "auto",
	user: "auto",
	interactive: true,
	filterJobControlNoise: true,
	whenNoContainer: "pass-through",
	recheckIntervalMs: 5000,
};

interface DevcontainerJson {
	remoteUser?: string;
	containerUser?: string;
	workspaceFolder?: string;
	remoteEnv?: Record<string, string | null>;
}

export interface ResolvedDevcontainer {
	root: string;
	containerId: string;
	user?: string;
	toContainerPath: (hostPath: string) => string;
	envEntries: Array<[string, string]>;
	interactive: boolean;
	filterJobControlNoise: boolean;
}

export type RouteMode =
	| { kind: "inert" }
	| { kind: "pass-through"; reason: string }
	| { kind: "error"; reason: string }
	| { kind: "routed"; resolved: ResolvedDevcontainer };

// ---------------------------------------------------------------------------
// Config loading
// ---------------------------------------------------------------------------

export function globalConfigPath(): string {
	return join(getAgentDir(), "extensions", "devcontainer-bash.json");
}

export function projectConfigPath(root: string): string {
	return join(root, CONFIG_DIR_NAME, "devcontainer-bash.json");
}

export function loadConfigFile(path: string): Partial<DevcontainerBashConfig> | null {
	try {
		return JSON.parse(readFileSync(path, "utf8")) as Partial<DevcontainerBashConfig>;
	} catch {
		return null;
	}
}

export function loadMergedConfig(root: string): DevcontainerBashConfig {
	const global = loadConfigFile(globalConfigPath()) ?? {};
	const project = loadConfigFile(projectConfigPath(root)) ?? {};
	return { ...DEFAULT_CONFIG, ...global, ...project };
}

// ---------------------------------------------------------------------------
// Workspace discovery
// ---------------------------------------------------------------------------

/** Walk up from `start` to the nearest directory containing a devcontainer config. */
export function findWorkspaceRoot(start: string): string | null {
	let dir = resolve(start);
	for (;;) {
		if (existsSync(join(dir, ".devcontainer", "devcontainer.json")) || existsSync(join(dir, ".devcontainer.json"))) {
			return dir;
		}
		const parent = dirname(dir);
		if (parent === dir) return null;
		dir = parent;
	}
}

export function readDevcontainerJson(root: string): DevcontainerJson | null {
	for (const candidate of [join(root, ".devcontainer", "devcontainer.json"), join(root, ".devcontainer.json")]) {
		if (!existsSync(candidate)) continue;
		try {
			return JSON.parse(readFileSync(candidate, "utf8")) as DevcontainerJson;
		} catch {
			return null;
		}
	}
	return null;
}

// ---------------------------------------------------------------------------
// Docker helpers
// ---------------------------------------------------------------------------

const DOCKER_TIMEOUT = 3000;

export function isDockerMissing(error: unknown): boolean {
	return (
		typeof error === "object" &&
		error !== null &&
		"code" in error &&
		(error as { code?: unknown }).code === "ENOENT"
	);
}

export function runDocker(
	args: string[],
): Promise<{ stdout: string; stderr: string; code: number | null; error: unknown }> {
	return new Promise((res) => {
		execFile("docker", args, { timeout: DOCKER_TIMEOUT, encoding: "utf8" }, (error, stdout, stderr) => {
			const code = error && typeof error === "object" && typeof (error as { code?: unknown }).code === "number"
				? ((error as { code: number }).code)
				: null;
			res({ stdout, stderr, code, error });
		});
	});
}

function firstLine(stdout: string): string | null {
	const line = stdout.trim().split(/\r?\n/)[0]?.trim();
	return line ? line : null;
}

function escapeNameFilter(name: string): string {
	return name.replace(/[.+^$[\]\\|(){}]/g, "\\$&");
}

/**
 * Find a running container for a devcontainer workspace.
 * 1. `devcontainer.local_folder` label (stamped by the devcontainers CLI)
 * 2. a plain `local_folder` label (some tooling)
 * 3. a container named after the workspace folder (compose with explicit container_name)
 * 4. a `<workspace-folder>-…` prefixed name (docker compose default naming)
 * 5. an explicit `container` config value (trusted even if `ps` fails —
 *    `docker exec` will surface a precise error then)
 */
export async function findContainerId(root: string, explicit?: string): Promise<string | null> {
	if (explicit && explicit !== "auto") {
		const r = await runDocker(["ps", "-q", "--no-trunc", "--filter", `name=^/${escapeNameFilter(explicit)}$`]);
		return firstLine(r.stdout) ?? explicit;
	}
	const labelCandidates = [
		`label=devcontainer.local_folder=${root}`,
		`label=local_folder=${root}`,
	];
	for (const filter of labelCandidates) {
		const r = await runDocker(["ps", "-q", "--no-trunc", "--filter", filter]);
		const id = firstLine(r.stdout);
		if (id) return id;
	}
	const base = escapeNameFilter(basename(root));
	for (const filter of [`name=^/${base}$`, `name=^/${base}-`]) {
		const r = await runDocker(["ps", "-q", "--no-trunc", "--filter", filter]);
		const id = firstLine(r.stdout);
		if (id) return id;
	}
	return null;
}

/**
 * Resolve a devcontainer.json value with `${localEnv:X}` / `${env:X}`
 * substitution from the host environment. Returns null when the value is an
 * unsupported or unresolvable substitution (callers skip it), otherwise the
 * substituted value.
 */
export function resolveEnvSubstitution(value: string): string | null {
	const trimmed = value.trim();
	const m = ENV_VAR_PATTERN.exec(trimmed);
	if (m) {
		const hostValue = process.env[m[1]];
		return hostValue !== undefined && hostValue !== "" ? hostValue : null;
	}
	// Unsupported substitution (e.g. ${containerWorkspaceFolder}) — skip rather
	// than pass garbage on.
	if (trimmed.includes("${")) return null;
	return trimmed;
}

/** Resolve the exec user: config → devcontainer.json → container Config.User. */
export async function resolveUser(
	containerId: string,
	dc: DevcontainerJson | null,
	configUser?: string,
): Promise<string | undefined> {
	if (configUser && configUser !== "auto") return configUser;
	// devcontainer.json frequently uses ${localEnv:USER} here; resolve it from
	// the host environment. Unresolvable values fall through to the container's
	// default user instead of breaking every docker exec.
	for (const candidate of [dc?.remoteUser, dc?.containerUser]) {
		if (!candidate) continue;
		const user = resolveEnvSubstitution(candidate);
		if (user) return user;
	}
	const r = await runDocker(["inspect", "--format", "{{.Config.User}}", containerId]);
	const user = r.stdout.trim();
	return user && user !== "<no value>" ? user : undefined;
}

// ---------------------------------------------------------------------------
// Path mapping (host path ↔ container path)
// ---------------------------------------------------------------------------

/** Resolve the container-side workspace path from devcontainer.json. */
export function resolveWorkspaceFolder(
	root: string,
	dc: DevcontainerJson | null,
	override?: string,
): string | null {
	const raw = override || dc?.workspaceFolder;
	if (!raw) return null;
	let value = raw.trim();
	if (!value) return null;
	if (value.startsWith("${localWorkspaceFolder}")) {
		value = root + value.slice("${localWorkspaceFolder}".length);
	}
	// Unresolvable variables (e.g. ${containerWorkspaceFolder}) or relative
	// values: fall back to same-path mapping.
	if (value.includes("${") || !value.startsWith("/")) return null;
	return value;
}

/**
 * Translate a host path into the container. With a same-path bind mount
 * (compose style, like `-v /home/u/proj:/home/u/proj`) this is identity.
 * Otherwise it maps relative to the workspace root into `workspaceFolder`.
 */
export function toContainerPathFn(
	root: string,
	dc: DevcontainerJson | null,
	override?: string,
): (hostPath: string) => string {
	const workspace = resolveWorkspaceFolder(root, dc, override);
	if (!workspace) return (hostPath) => hostPath;
	return (hostPath) => {
		const abs = resolve(hostPath);
		const rel = relative(root, abs);
		// Paths outside the workspace root can't be mapped into workspaceFolder —
		// pass them through as-is (best effort).
		if (rel.startsWith("..") || isAbsolute(rel)) return abs;
		return rel ? posix.join(workspace, rel.split(/[\\/]+/).join(posix.sep)) : workspace;
	};
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

const ENV_VAR_PATTERN = /^\$\{(?:localEnv|env):([^}]+)\}$/;

/** Merge devcontainer `remoteEnv` (with ${localEnv:X} substitution) + config env (wins). */
export function resolveEnvEntries(
	dc: DevcontainerJson | null,
	configEnv?: Record<string, string | null>,
): Array<[string, string]> {
	const entries = new Map<string, string>();
	const host = process.env;
	const add = (key: string, value: string | null | undefined) => {
		if (!key) return;
		// null/undefined = copy from host if set
		if (value === null || value === undefined) {
			const hv = host[key];
			if (hv !== undefined) entries.set(key, hv);
			return;
		}
		const resolved = resolveEnvSubstitution(value);
		if (resolved === null) return; // unresolvable — skip rather than inject garbage
		entries.set(key, resolved);
	};
	for (const [k, v] of Object.entries(dc?.remoteEnv ?? {})) add(k, v);
	for (const [k, v] of Object.entries(configEnv ?? {})) add(k, v);
	return [...entries.entries()];
}

// ---------------------------------------------------------------------------
// Job-control noise filter (from `bash -ic` without a TTY)
// ---------------------------------------------------------------------------

const JOB_CONTROL_NOISE = [/^bash: cannot set terminal process group/, /^bash: no job control in this shell/];

export class JobControlNoiseFilter {
	private buffer = "";
	private decoder = new StringDecoder("utf8");
	constructor(private readonly enabled: boolean) {}

	transform(chunk: Buffer): Buffer {
		if (!this.enabled) return chunk;
		this.buffer += this.decoder.write(chunk);
		let out = "";
		let idx: number;
		while ((idx = this.buffer.indexOf("\n")) !== -1) {
			const line = this.buffer.slice(0, idx);
			this.buffer = this.buffer.slice(idx + 1);
			if (!JOB_CONTROL_NOISE.some((re) => re.test(line))) out += line + "\n";
		}
		return Buffer.from(out);
	}

	flush(): Buffer {
		if (!this.enabled) return Buffer.alloc(0);
		const rest = this.buffer + this.decoder.end();
		this.buffer = "";
		return JOB_CONTROL_NOISE.some((re) => re.test(rest)) ? Buffer.alloc(0) : Buffer.from(rest);
	}
}

// ---------------------------------------------------------------------------
// Docker bash operations
// ---------------------------------------------------------------------------

const MAX_TIMEOUT_MS = 2_147_483_647;
const MAX_TIMEOUT_SECONDS = MAX_TIMEOUT_MS / 1000;

/** pi passes the bash `timeout` parameter in seconds; node timers want ms. */
export function resolveTimeoutMs(timeout?: number): number | undefined {
	if (timeout === undefined) return undefined;
	if (!Number.isFinite(timeout) || timeout <= 0) {
		throw new Error("Invalid timeout: must be a finite number of seconds");
	}
	const timeoutMs = timeout * 1000;
	if (timeoutMs > MAX_TIMEOUT_MS) {
		throw new Error(`Invalid timeout: maximum is ${MAX_TIMEOUT_SECONDS} seconds`);
	}
	return timeoutMs;
}

function newToken(): string {
	return randomUUID().replace(/-/g, "").slice(0, 12);
}

/**
 * Kill the in-container process group of a timed-out/aborted command.
 *
 * The exec'd bash is its own session and process-group leader (pid==pgid),
 * and the script records its pid in a per-exec token file inside the
 * container. Killing only the docker CLI would leave the command running
 * inside the container (the exec session survives client disconnects).
 *
 * Fire-and-forget: spawned detached from the caller's flow; a best-effort
 * SIGKILL escalation follows after a short grace period.
 */
export function cleanupContainerProcessGroup(
	containerId: string,
	user: string | undefined,
	token: string,
): void {
	const pgidFile = `/tmp/pi-dcb-${token}.pgid`;
	const script =
		`p=$(cat ${pgidFile} 2>/dev/null) || exit 0; ` +
		`rm -f ${pgidFile}; ` +
		`kill -TERM -- -$p 2>/dev/null || kill -TERM -$p 2>/dev/null; ` +
		`(sleep 1; kill -KILL -- -$p 2>/dev/null || kill -KILL -$p 2>/dev/null) &`;
	const args = ["exec"];
	if (user) args.push("-u", user);
	args.push(containerId, "bash", "-lc", script);
	const child = spawn("docker", args, { stdio: "ignore" });
	child.on("error", () => {});
}

/**
 * BashOperations that execute inside the devcontainer:
 *   docker exec -i [-u user] -w <containerCwd> [-e K=V ...] <container> bash -ic <command>
 */
export function createDockerBashOperations(resolved: ResolvedDevcontainer): BashOperations {
	return {
		async exec(command, cwd, { onData, signal, timeout }) {
			const timeoutMs = resolveTimeoutMs(timeout);
			if (signal?.aborted) throw new Error("aborted");

			const containerCwd = resolved.toContainerPath(resolve(cwd));
			const token = newToken();
			const pgidFile = `/tmp/pi-dcb-${token}.pgid`;
			// Record the exec'd bash's pid (it is its own group leader) and
			// remove the record when the command completes normally, so a
			// timeout/abort can kill the exact process group and a stale pid
			// is never reused against a different group.
			const script =
				`echo $$ >${pgidFile} 2>/dev/null; trap 'rm -f ${pgidFile}' EXIT; ` +
				(resolved.interactive ? command : `source ~/.bashrc 2>/dev/null; ${command}`);

			const args = ["exec", "-i"];
			if (resolved.user) args.push("-u", resolved.user);
			args.push("-w", containerCwd);
			for (const [k, v] of resolved.envEntries) args.push("-e", `${k}=${v}`);
			args.push(resolved.containerId, "bash", resolved.interactive ? "-ic" : "-lc", script);

			const filter = new JobControlNoiseFilter(resolved.filterJobControlNoise);
			// stdin: ignore — mirrors pi's local bash backend and avoids the
			// docker CLI holding the exec session open on an idle stdin pipe.
			const child = spawn("docker", args, { stdio: ["ignore", "pipe", "pipe"] });
			child.stdout?.on("data", (d: Buffer) => onData(filter.transform(d)));
			child.stderr?.on("data", (d: Buffer) => onData(filter.transform(d)));

			let timedOut = false;
			let timeoutHandle: NodeJS.Timeout | undefined;
			let terminated = false;
			const terminate = () => {
				if (terminated) return;
				terminated = true;
				// Detach from the docker CLI so we don't wait for it, then kill
				// the command's process group inside the container.
				try {
					child.kill("SIGTERM");
				} catch {
					// already gone
				}
				cleanupContainerProcessGroup(resolved.containerId, resolved.user, token);
				// Escalate if the client ignores SIGTERM.
				setTimeout(() => {
					try {
						child.kill("SIGKILL");
					} catch {
						// already gone
					}
				}, 2000).unref();
			};
			if (timeoutMs !== undefined) {
				timeoutHandle = setTimeout(() => {
					timedOut = true;
					terminate();
				}, timeoutMs);
				timeoutHandle.unref();
			}
			const onAbort = () => terminate();
			if (signal) signal.addEventListener("abort", onAbort, { once: true });

			try {
				return await new Promise<{ exitCode: number | null }>((res, rej) => {
					let settled = false;
					const settle = (fn: () => void) => {
						if (!settled) {
							settled = true;
							fn();
						}
					};
					child.on("error", (err) => {
						settle(() =>
							rej(isDockerMissing(err) ? new Error("devcontainer-bash: `docker` CLI not found on the host.") : err),
						);
					});
					child.on("close", (code, signalCode) => {
						const tail = filter.flush();
						if (tail.length) onData(tail);
						settle(() => {
							// Match pi's local backend: abort and timeout are
							// reported as errors, not as successful exits.
							if (signal?.aborted) rej(new Error("aborted"));
							else if (timedOut) rej(new Error(`timeout:${timeout}`));
							else res({ exitCode: signalCode ? null : code });
						});
					});
				});
			} finally {
				if (timeoutHandle) clearTimeout(timeoutHandle);
				if (signal) signal.removeEventListener("abort", onAbort);
			}
		},
	};
}

// ---------------------------------------------------------------------------
// Route resolution
// ---------------------------------------------------------------------------

export async function resolveRoute(cwd: string, config: DevcontainerBashConfig): Promise<RouteMode> {
	const root = findWorkspaceRoot(cwd);
	if (!root) return { kind: "inert" };
	if (config.enabled === false) return { kind: "inert" };

	const dc = readDevcontainerJson(root);
	const containerId = await findContainerId(root, config.container);
	if (!containerId) {
		let reason = `No running devcontainer found for ${root}. Start it (e.g. VSCode → Reopen in Container), or set "container" in the devcontainer-bash config.`;
		// Surface docker daemon problems (daemon down, CLI broken) instead of
		// silently falling back to the host shell.
		const diag = await runDocker(["ps", "-q"]);
		const errLine = firstLine(diag.stderr);
		if (errLine) reason += ` Docker error: ${errLine}`;
		return config.whenNoContainer === "error" ? { kind: "error", reason } : { kind: "pass-through", reason };
	}

	const user = await resolveUser(containerId, dc, config.user);
	const toContainerPath = toContainerPathFn(root, dc, config.workspaceFolder);
	const envEntries = resolveEnvEntries(dc, config.env);

	return {
		kind: "routed",
		resolved: {
			root,
			containerId,
			user,
			toContainerPath,
			envEntries,
			interactive: config.interactive ?? DEFAULT_CONFIG.interactive,
			filterJobControlNoise: config.filterJobControlNoise ?? DEFAULT_CONFIG.filterJobControlNoise,
		},
	};
}

// ---------------------------------------------------------------------------
// Footer status indicator
// ---------------------------------------------------------------------------

export type RouteStatusLabel = { symbol: string; text: string; color: "accent" | "warning" | "dim" } | null;

/**
 * Footer status for the routing state. Returns null when nothing should be
 * shown: outside devcontainer workspaces, or when routing is switched off
 * (config `enabled: false`, `--no-devcontainer-bash`, `/devcontainer-bash off`).
 */
export function routeStatusLabel(root: string | null, mode: RouteMode): RouteStatusLabel {
	if (!root) return null;
	const name = basename(root);
	switch (mode.kind) {
		case "routed": {
			const r = mode.resolved;
			return {
				symbol: "🐳",
				text: `${name} · devcontainer${r.user ? ` (${r.user})` : ""}`,
				color: "accent",
			};
		}
		case "inert":
			// Routing switched off — no indicator at all.
			return null;
		case "pass-through":
			return { symbol: "○", text: `${name} · host shell (no container)`, color: "dim" };
		case "error":
			return { symbol: "○", text: `${name} · error — no container`, color: "warning" };
	}
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	pi.registerFlag("no-devcontainer-bash", {
		description: "Disable devcontainer bash routing",
		type: "boolean",
		default: false,
	});

	const STATUS_KEY = "devcontainer-bash";

	/** In-memory toggle set by `/devcontainer-bash on|off`; null = use config. */
	let enabledOverride: boolean | null = null;
	let cache: { cwd: string; at: number; ttlMs: number; mode: RouteMode } | null = null;
	let notifiedPassThrough = false;
	/** Workspace root of the last resolve; null = not a devcontainer workspace. */
	let lastRoot: string | null = null;

	/** Show the routing state in the TUI footer (no-op outside TUI/RPC). */
	function updateStatus(ctx: ExtensionContext, mode: RouteMode): void {
		if (!ctx.hasUI) return;
		const label = routeStatusLabel(lastRoot, mode);
		if (!label) {
			ctx.ui.setStatus(STATUS_KEY, undefined);
			return;
		}
		// Whole line in a single color: accent (blue) when routed, dim/warning
		// for the transient no-container states.
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg(label.color, `${label.symbol} ${label.text}`));
	}

	async function resolve(cwd: string, force = false): Promise<RouteMode> {
		const root = findWorkspaceRoot(cwd);
		lastRoot = root;
		if (!root || pi.getFlag("no-devcontainer-bash") || enabledOverride === false) return { kind: "inert" };

		const now = Date.now();
		if (!force && cache && cache.cwd === cwd && now - cache.at < cache.ttlMs) return cache.mode;

		const config = loadMergedConfig(root);
		if (enabledOverride === true) config.enabled = true;
		const ttlMs = config.recheckIntervalMs ?? DEFAULT_CONFIG.recheckIntervalMs;
		const mode = await resolveRoute(cwd, config);
		cache = { cwd, at: now, ttlMs, mode };
		return mode;
	}

	// Keep the footer status current: at session start (eager), each turn
	// (non-blocking, cached), and on every bash call below.
	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		try {
			const mode = await resolve(ctx.cwd, true);
			updateStatus(ctx, mode);
		} catch {
			// Best-effort status refresh.
		}
	});

	pi.on("turn_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		resolve(ctx.cwd)
			.then((mode) => updateStatus(ctx, mode))
			.catch(() => {});
	});

	pi.registerTool({
		...createBashTool(process.cwd()),
		label: "bash (devcontainer)",
		async execute(id, params, signal, onUpdate, ctx) {
			const mode = await resolve(ctx.cwd);
			updateStatus(ctx, mode);
			if (mode.kind === "pass-through") {
				if (!notifiedPassThrough && ctx.hasUI) {
					notifiedPassThrough = true;
					ctx.ui.notify(`devcontainer-bash: ${mode.reason} Using the host shell for now (auto-detects once the container starts).`, "warning");
				}
				return createBashTool(ctx.cwd).execute(id, params, signal, onUpdate);
			}
			if (mode.kind === "error") {
				throw new Error(mode.reason);
			}
			if (mode.kind === "inert") {
				return createBashTool(ctx.cwd).execute(id, params, signal, onUpdate);
			}
			const tool = createBashTool(ctx.cwd, {
				operations: createDockerBashOperations(mode.resolved),
				exposeSessionEnvironment: false,
			});
			return tool.execute(id, params, signal, onUpdate);
		},
	});

	// `!` / `!!` user commands route into the container too.
	pi.on("user_bash", async (_event, ctx) => {
		const mode = await resolve(ctx.cwd);
		updateStatus(ctx, mode);
		if (mode.kind !== "routed") return undefined;
		return { operations: createDockerBashOperations(mode.resolved) };
	});

	pi.registerCommand("devcontainer-bash", {
		description: "Devcontainer bash routing: status, recheck, on, off, toggle",
		getArgumentCompletions: (prefix: string) =>
			["status", "recheck", "on", "off", "toggle"]
				.filter((c) => c.startsWith(prefix))
				.map((c) => ({ value: c, label: c })),
		handler: async (args, ctx) => {
			let action = (args ?? "").trim().toLowerCase();
			if (action === "toggle") {
				const root = findWorkspaceRoot(ctx.cwd);
				const config = root ? loadMergedConfig(root) : null;
				enabledOverride = !(enabledOverride ?? (config?.enabled !== false));
				action = enabledOverride ? "on" : "off";
			}
			if (action === "on" || action === "off") {
				enabledOverride = action === "on";
				const root = findWorkspaceRoot(ctx.cwd);
				if (root) {
					try {
						mkdirSync(join(root, CONFIG_DIR_NAME), { recursive: true });
						writeFileSync(projectConfigPath(root), JSON.stringify({ enabled: enabledOverride }, null, 2) + "\n");
					} catch (err) {
						ctx.ui.notify(`devcontainer-bash: could not persist ${action} (${(err as Error).message})`, "error");
						return;
					}
				}
				ctx.ui.notify(`devcontainer-bash: ${action} (persisted to ${root ? projectConfigPath(root) : "memory"})`, "info");
				const mode = await resolve(ctx.cwd, true);
				updateStatus(ctx, mode);
				return;
			}
			if (action === "recheck") cache = null;
			const mode = await resolve(ctx.cwd, true);
			updateStatus(ctx, mode);
			const lines: string[] = [`devcontainer-bash: ${mode.kind}`];
			if (mode.kind === "routed") {
				const r = mode.resolved;
				lines.push(
					`  workspace: ${r.root}`,
					`  container: ${r.containerId}`,
					`  user: ${r.user ?? "(default)"}`,
					`  shell: ${r.interactive ? "bash -ic" : "bash -lc"}`,
					`  env: ${r.envEntries.length ? r.envEntries.map(([k]) => k).join(", ") : "(none)"}`,
					`  cwd mapping: ${r.toContainerPath(r.root)}`,
				);
			} else if (mode.kind === "pass-through" || mode.kind === "error") {
				lines.push(`  ${mode.reason}`);
			}
			ctx.ui.notify(lines.join("\n"), "info");
		},
	});
}
