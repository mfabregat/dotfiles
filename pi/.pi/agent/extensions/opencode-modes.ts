/**
 * OpenCode-style Plan/Build modes for pi.
 *
 * - Plan mode: read-only. Ask questions, explore the codebase, create and
 *   iterate on plans. File edits and mutating shell commands are blocked
 *   (the write tools are hidden from the model AND gated as a backstop).
 * - Build mode: full access. Implements plans and quick fixes.
 *
 * The prompt box border changes color with the mode (like OpenCode):
 *   blue  ── PLAN   (read-only)
 *   green ── BUILD  (edits enabled)
 *
 * Toggle: ctrl+space   (keybind; tab is taken by autocomplete)
 * Also:   /plan   /build
 * Plan mode is the default for new sessions (override with /build).
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CustomEditor, isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { Key, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

type Mode = "build" | "plan";

type EditorCtor = typeof CustomEditor;
type EditorTUI = ConstructorParameters<EditorCtor>[0];
type EditorTheme = ConstructorParameters<EditorCtor>[1];
type EditorKeybindings = ConstructorParameters<EditorCtor>[2];

// ---------------------------------------------------------------------------
// Mode state
// ---------------------------------------------------------------------------

let mode: Mode = "plan";
let editorInstance: ModeEditor | undefined;
let toolsBeforePlan: string[] | undefined;

// Built-in tools that modify the filesystem.
const MUTATING_TOOLS = new Set(["edit", "write"]);

// ---------------------------------------------------------------------------
// Prompt-box colors (match pi's dark theme blue/green for a native feel)
// ---------------------------------------------------------------------------

const PLAN_RGB = "95;135;255"; // #5f87ff
const BUILD_RGB = "181;189;104"; // #b5bd68

function borderColorFor(m: Mode): (s: string) => string {
	const rgb = m === "plan" ? PLAN_RGB : BUILD_RGB;
	return (s) => `\x1b[38;2;${rgb}m${s}`;
}

/** Colored "pill" label embedded in the top border of the prompt box. */
function modeLabel(m: Mode): string {
	const rgb = m === "plan" ? PLAN_RGB : BUILD_RGB;
	const text = m === "plan" ? " PLAN " : " BUILD ";
	return `\x1b[1m\x1b[38;2;0;0;0m\x1b[48;2;${rgb}m${text}\x1b[0m`;
}

// ---------------------------------------------------------------------------
// Custom editor: re-colors the prompt box border per mode
// ---------------------------------------------------------------------------

class ModeEditor extends CustomEditor {
	private m: Mode;

	constructor(tui: EditorTUI, theme: EditorTheme, keybindings: EditorKeybindings, initialMode: Mode) {
		super(tui, theme, keybindings);
		this.m = initialMode;
	}

	setMode(next: Mode): void {
		this.m = next;
		this.tui.requestRender();
	}

	render(width: number): string[] {
		// Border is drawn fresh on every render, so just swap the color fn.
		this.borderColor = borderColorFor(this.m);
		const lines = super.render(width);
		if (lines.length === 0) return lines;

		// Embed the mode pill into the top border line.
		const label = modeLabel(this.m);
		const labelWidth = visibleWidth(label);
		lines[0] = truncateToWidth(lines[0]!, Math.max(0, width - labelWidth), "") + label;
		return lines;
	}
}

// ---------------------------------------------------------------------------
// Bash allowlist for plan mode (read-only commands only)
// ---------------------------------------------------------------------------

const DESTRUCTIVE_PATTERNS = [
	/\brm\b/i,
	/\brmdir\b/i,
	/\bmv\b/i,
	/\bcp\b/i,
	/\bmkdir\b/i,
	/\btouch\b/i,
	/\bchmod\b/i,
	/\bchown\b/i,
	/\bchgrp\b/i,
	/\bln\b/i,
	/\btee\b/i,
	/\btruncate\b/i,
	/\bdd\b/i,
	/\bshred\b/i,
	/(^|[^<])>(?!>)/,
	/>>/,
	/\bnpm\s+(install|uninstall|update|ci|link|publish)/i,
	/\byarn\s+(add|remove|install|publish)/i,
	/\bpnpm\s+(add|remove|install|publish)/i,
	/\bpip\s+(install|uninstall)/i,
	/\bapt(-get)?\s+(install|remove|purge|update|upgrade)/i,
	/\bbrew\s+(install|uninstall|upgrade)/i,
	/\bgit\s+(add|commit|push|pull|merge|rebase|reset|checkout|branch\s+-[dD]|stash|cherry-pick|revert|tag|init|clone)/i,
	/\bsudo\b/i,
	/\bsu\b/i,
	/\bkill\b/i,
	/\bpkill\b/i,
	/\bkillall\b/i,
	/\breboot\b/i,
	/\bshutdown\b/i,
	/\bsystemctl\s+(start|stop|restart|enable|disable)/i,
	/\bservice\s+\S+\s+(start|stop|restart)/i,
	/\b(vim?|nano|emacs|code|subl)\b/i,
];

/** `2>&1`, `>&2`, `3>&-` fd dups/closes are NOT file writes — no filesystem impact. */
const FD_DUP_RE = /[0-9]*>[ \t]*&[ \t]*(?:-|[0-9]+)/g;

/** Redirects to these device paths discard output — nothing persists to disk. */
const DEV_NULL_REDIR_RE = /[0-9]*&?>+\|?[ \t]*\/dev\/(?:null|stdout|stderr|fd\/[0-9]+)\b/g;

const SAFE_PATTERNS = [
	/^\s*cat\b/,
	/^\s*head\b/,
	/^\s*tail\b/,
	/^\s*less\b/,
	/^\s*more\b/,
	/^\s*grep\b/,
	/^\s*find\b/,
	/^\s*ls\b/,
	/^\s*pwd\b/,
	/^\s*echo\b/,
	/^\s*printf\b/,
	/^\s*wc\b/,
	/^\s*sort\b/,
	/^\s*uniq\b/,
	/^\s*diff\b/,
	/^\s*file\b/,
	/^\s*stat\b/,
	/^\s*du\b/,
	/^\s*df\b/,
	/^\s*tree\b/,
	/^\s*which\b/,
	/^\s*whereis\b/,
	/^\s*type\b/,
	/^\s*env\b/,
	/^\s*printenv\b/,
	/^\s*uname\b/,
	/^\s*whoami\b/,
	/^\s*id\b/,
	/^\s*date\b/,
	/^\s*cal\b/,
	/^\s*uptime\b/,
	/^\s*ps\b/,
	/^\s*top\b/,
	/^\s*htop\b/,
	/^\s*free\b/,
	/^\s*git\s+(status|log|diff|show|branch|remote|config\s+--get)/i,
	/^\s*git\s+ls-/i,
	/^\s*npm\s+(list|ls|view|info|search|outdated|audit)/i,
	/^\s*yarn\s+(list|info|why|audit)/i,
	/^\s*node\s+--version/i,
	/^\s*python\s+--version/i,
	/^\s*curl\s/i,
	/^\s*wget\s+-O\s*-/i,
	/^\s*jq\b/,
	/^\s*sed\s+-n/i,
	/^\s*awk\b/,
	/^\s*rg\b/,
	/^\s*fd\b/,
	/^\s*bat\b/,
	/^\s*eza\b/,
];

function isSafeCommand(command: string): boolean {
	// `2>&1`-style dups and `/dev/null`-family redirects are harmless: strip them
	// before the destructive check so they don't trip the bare `>` pattern.
	const sanitized = command.replace(FD_DUP_RE, "").replace(DEV_NULL_REDIR_RE, "");
	const isDestructive = DESTRUCTIVE_PATTERNS.some((p) => p.test(sanitized));
	const isSafe = SAFE_PATTERNS.some((p) => p.test(sanitized));
	return !isDestructive && isSafe;
}

// ---------------------------------------------------------------------------
// Mode switching
// ---------------------------------------------------------------------------

const TOGGLE_HINT = "ctrl+space";

function persistState(pi: ExtensionAPI): void {
	pi.appendEntry("opencode-modes", { mode });
}

function updateUI(): void {
	editorInstance?.setMode(mode);
}

function enterPlanMode(pi: ExtensionAPI, ctx: ExtensionContext): void {
	// Hide mutating tools from the model entirely (remember what to restore).
	const current = toolsBeforePlan ?? pi.getActiveTools();
	toolsBeforePlan = current;
	pi.setActiveTools([...new Set(current.filter((t) => !MUTATING_TOOLS.has(t)))]);
	mode = "plan";
	updateUI();
	persistState(pi);
}

function enterBuildMode(pi: ExtensionAPI, ctx: ExtensionContext): void {
	if (toolsBeforePlan) {
		pi.setActiveTools(toolsBeforePlan);
	} else {
		pi.setActiveTools([...new Set([...pi.getActiveTools(), ...MUTATING_TOOLS])]);
	}
	toolsBeforePlan = undefined;
	mode = "build";
	updateUI();
	persistState(pi);
}

function setMode(pi: ExtensionAPI, ctx: ExtensionContext, next: Mode): void {
	if (next === mode) return;
	if (next === "plan") enterPlanMode(pi, ctx);
	else enterBuildMode(pi, ctx);
}

function toggleMode(pi: ExtensionAPI, ctx: ExtensionContext): void {
	setMode(pi, ctx, mode === "plan" ? "build" : "plan");
}

// ---------------------------------------------------------------------------
// Extension wiring
// ---------------------------------------------------------------------------

export default function opencodeModes(pi: ExtensionAPI): void {
	pi.registerFlag("plan", {
		description: "Start in plan mode (read-only)",
		type: "boolean",
		default: false,
	});

	pi.registerShortcut(Key.ctrl("space"), {
		description: "Toggle plan/build mode (ctrl+space)",
		handler: async (ctx) => toggleMode(pi, ctx),
	});

	pi.registerCommand("plan", {
		description: "Switch to plan mode (read-only)",
		handler: async (_args, ctx) => setMode(pi, ctx, "plan"),
	});

	pi.registerCommand("build", {
		description: "Switch to build mode (edits enabled)",
		handler: async (_args, ctx) => setMode(pi, ctx, "build"),
	});

	// Gate: enforce plan mode even if the model somehow calls a blocked tool.
	pi.on("tool_call", (event) => {
		if (mode !== "plan") return;

		if (isToolCallEventType("bash", event)) {
			if (!isSafeCommand(event.input.command)) {
				return {
					block: true,
					reason: `Plan mode: command blocked (read-only mode). Toggle to build mode with ${TOGGLE_HINT} to run it.\nCommand: ${event.input.command}`,
				};
			}
			return;
		}

		if (MUTATING_TOOLS.has(event.toolName)) {
			return {
				block: true,
				reason: `Plan mode: file edits are disabled. Toggle to build mode with ${TOGGLE_HINT} to make changes.`,
			};
		}
	});

	// Drop stale plan-mode instructions from context once we leave plan mode.
	pi.on("context", (event) => {
		if (mode === "plan") return;
		const filtered = event.messages.filter(
			(m) => (m as { customType?: string }).customType !== "opencode-modes-plan",
		);
		if (filtered.length === event.messages.length) return;
		return { messages: filtered };
	});

	// Tell the model what plan mode is for, per turn.
	pi.on("before_agent_start", (_event) => {
		if (mode !== "plan") return;
		return {
			message: {
				customType: "opencode-modes-plan",
				content: `[PLAN MODE - READ ONLY]
You are in plan mode: read files, search, and run read-only commands to understand the codebase, but NEVER modify anything (no file edits, no writes, no mutating shell commands — they are blocked). When the user asks for changes, produce a plan instead of making them; when they are ready to act, tell them to switch to build mode (${TOGGLE_HINT}).

Use this mode to answer questions about the code and to create, refine, and iterate on plans.

Planning process:
1. Explore before proposing: read the actual files involved and how they connect; find existing patterns and similar features to reuse. Ground every step in the real codebase.
2. Clarify before guessing: ask about requirements, edge cases, error handling, and constraints when anything is ambiguous.
3. Consider trade-offs: weigh alternatives briefly, follow existing conventions, and flag risks and dependencies.

Plan format — concise and scannable (bullets, not prose):
- Goal: one or two sentences.
- Approach: what changes where; name the concrete files.
- Steps: numbered, small, independent, each verifiable on its own; note dependencies and sequencing.
- Verify: how to check each step (tests, linters, type checks, manual checks).
- Open questions: assumptions and unknowns to confirm before building.

End with the numbered step list as the last visible lines, then list 3-5 critical files for implementation.`,
				display: false,
			},
		};
	});

	// Install the mode-colored prompt box and restore state.
	pi.on("session_start", async (_event, ctx) => {
		// Restore persisted mode (resume / reload), else flag, else default.
		const entries = ctx.sessionManager.getEntries();
		const last = [...entries]
			.reverse()
			.find((e) => (e as { type?: string; customType?: string }).type === "custom"
				&& (e as { customType?: string }).customType === "opencode-modes");
		const savedMode = (last as { data?: { mode?: Mode } } | undefined)?.data?.mode;
		if (savedMode === "plan" || savedMode === "build") {
			mode = savedMode;
		} else if (pi.getFlag("plan")) {
			mode = "plan";
		} else {
			mode = "plan"; // default: plan mode for new sessions
		}

		ctx.ui.setEditorComponent((tui, theme, kb) => {
			editorInstance = new ModeEditor(tui, theme, kb, mode);
			return editorInstance;
		});

		// Apply the tool set for the restored mode.
		if (mode === "plan") {
			const current = toolsBeforePlan ?? pi.getActiveTools();
			toolsBeforePlan = current;
			pi.setActiveTools([...new Set(current.filter((t) => !MUTATING_TOOLS.has(t)))]);
		}

		updateUI();
	});
}
