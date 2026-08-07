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
 *     name equals the workspace folder name, falling back to an explicit
 *     `container` config value.
 *   - The exec user comes from config, then `remoteUser`/`containerUser` in
 *     the project's devcontainer.json, then the container's own `Config.User`.
 *   - Extra env is taken from the project's `remoteEnv` (with `${localEnv:X}`
 *     substitution) plus config overrides.
 *   - Host cwd is translated to the container using the devcontainer's
 *     `workspaceFolder` (with `${localWorkspaceFolder}` substitution). A
 *     same-path bind mount (compose style) maps 1:1 automatically.
 *
 * On/off:
 *   - Auto-loaded from `~/.pi/agent/extensions/` (hot-reload with `/reload`).
 *   - `enabled: false` in config disables it (global or per project).
 *   - `pi --no-devcontainer-bash` disables it for a run.
 *   - `/devcontainer-bash status|recheck|on|off` shows state or toggles.
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
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, posix, relative, resolve } from "node:path";
import {
	CONFIG_DIR_NAME,
	createBashTool,
	getAgentDir,
	type BashOperations,
	type ExtensionAPI,
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
 * 4. an explicit `container` config value (trusted even if `ps` fails —
 *    `docker exec` will surface a precise error then)
 */
export async function findContainerId(root: string, explicit?: string): Promise<string | null> {
	if (explicit && explicit !== "auto") {
		const r = await runDocker(["ps", "-q", "--filter", `name=^/${escapeNameFilter(explicit)}$`]);
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
	const r = await runDocker(["ps", "-q", "--filter", `name=^/${escapeNameFilter(basename(root))}$`]);
	return firstLine(r.stdout);
}

/** Resolve the exec user: config → devcontainer.json → container Config.User. */
export async function resolveUser(
	containerId: string,
	dc: DevcontainerJson | null,
	configUser?: string,
): Promise<string | undefined> {
	if (configUser && configUser !== "auto") return configUser;
	if (dc?.remoteUser) return dc.remoteUser;
	if (dc?.containerUser) return dc.containerUser;
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
		const m = ENV_VAR_PATTERN.exec(value.trim());
		if (m) {
			const hv = host[m[1]];
			if (hv !== undefined) entries.set(m[1], hv);
			return;
		}
		// Unsupported substitution — skip rather than inject garbage.
		if (value.includes("${")) return;
		entries.set(key, value);
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
	constructor(private readonly enabled: boolean) {}

	transform(chunk: Buffer): Buffer {
		if (!this.enabled) return chunk;
		this.buffer += chunk.toString("utf8");
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
		if (!this.enabled || !this.buffer) return Buffer.alloc(0);
		const rest = this.buffer;
		this.buffer = "";
		return JOB_CONTROL_NOISE.some((re) => re.test(rest)) ? Buffer.alloc(0) : Buffer.from(rest);
	}
}

// ---------------------------------------------------------------------------
// Docker bash operations
// ---------------------------------------------------------------------------

/**
 * BashOperations that execute inside the devcontainer:
 *   docker exec -i [-u user] -w <containerCwd> [-e K=V ...] <container> bash -ic <command>
 */
export function createDockerBashOperations(resolved: ResolvedDevcontainer): BashOperations {
	return {
		async exec(command, cwd, { onData, signal, timeout }) {
			const containerCwd = resolved.toContainerPath(resolve(cwd));
			// Non-interactive mode: best-effort source of ~/.bashrc (a guard in
			// the rc may still skip it — that's why interactive is the default).
			const script = resolved.interactive ? command : `source ~/.bashrc 2>/dev/null; ${command}`;
			const args = ["exec", "-i"];
			if (resolved.user) args.push("-u", resolved.user);
			args.push("-w", containerCwd);
			for (const [k, v] of resolved.envEntries) args.push("-e", `${k}=${v}`);
			args.push(resolved.containerId, "bash", resolved.interactive ? "-ic" : "-lc", script);

			const filter = new JobControlNoiseFilter(resolved.filterJobControlNoise);
			const child = spawn("docker", args, { signal, timeout });
			child.stdout?.on("data", (d: Buffer) => onData(filter.transform(d)));
			child.stderr?.on("data", (d: Buffer) => onData(filter.transform(d)));

			return new Promise((res, rej) => {
				child.on("error", (err) => {
					if (isDockerMissing(err)) {
						rej(new Error("devcontainer-bash: `docker` CLI not found on the host."));
					} else {
						rej(err);
					}
				});
				child.on("close", (code, signalCode) => {
					const tail = filter.flush();
					if (tail.length) onData(tail);
					res({ exitCode: signalCode ? null : code });
				});
			});
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
		const reason = `No running devcontainer found for ${root}. Start it (e.g. VSCode → Reopen in Container), or set "container" in the devcontainer-bash config.`;
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
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	pi.registerFlag("no-devcontainer-bash", {
		description: "Disable devcontainer bash routing",
		type: "boolean",
		default: false,
	});

	/** In-memory toggle set by `/devcontainer-bash on|off`; null = use config. */
	let enabledOverride: boolean | null = null;
	let cache: { cwd: string; at: number; ttlMs: number; mode: RouteMode } | null = null;
	let notifiedPassThrough = false;

	async function resolve(cwd: string, force = false): Promise<RouteMode> {
		const root = findWorkspaceRoot(cwd);
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

	pi.registerTool({
		...createBashTool(process.cwd()),
		label: "bash (devcontainer)",
		async execute(id, params, signal, onUpdate, ctx) {
			const mode = await resolve(ctx.cwd);
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
		if (mode.kind !== "routed") return undefined;
		return { operations: createDockerBashOperations(mode.resolved) };
	});

	pi.registerCommand("devcontainer-bash", {
		description: "Devcontainer bash routing: status, recheck, on, off",
		getArgumentCompletions: (prefix: string) =>
			["status", "recheck", "on", "off"]
				.filter((c) => c.startsWith(prefix))
				.map((c) => ({ value: c, label: c })),
		handler: async (args, ctx) => {
			const action = (args ?? "").trim().toLowerCase();
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
				return;
			}
			if (action === "recheck") cache = null;
			const mode = await resolve(ctx.cwd, true);
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
