/**
 * question — a lightweight "ask the user" tool for pi, modeled on opencode's
 * `question` tool (sst/opencode: packages/opencode/src/tool/question.ts,
 * packages/tui/src/routes/session/question.tsx).
 *
 * Deliberately minimal: single file, no i18n, no RPC fallback, no config, no
 * previews. Reuses pi-tui primitives (Container, Text, Input, DynamicBorder).
 *
 * UX mirrors opencode: a tab per question plus a Review/Confirm tab, number
 * keys 1-9 + ↑↓/j/k to pick, an auto-appended "Type your own answer" row with
 * inline editing, `multiple: true` for multi-select, Enter to submit, Esc to
 * dismiss. Answers come back as arrays of labels per question.
 */

import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import { Type, type Static } from "typebox";
import { Container, Input, Key, Text, matchesKey } from "@earendil-works/pi-tui";

// ---------------------------------------------------------------------------
// Schema — mirrors opencode's question tool (options carry label + description,
// `multiple` allows multi-select, answers return as arrays of labels)
// ---------------------------------------------------------------------------

const OptionSchema = Type.Object({
	label: Type.String({ description: "Display text (1-5 words, concise)" }),
	description: Type.String({ description: "Explanation of the choice or its trade-offs" }),
});

const QuestionSchema = Type.Object({
	question: Type.String({ description: "Complete question" }),
	header: Type.String({ description: "Very short label for the question tab (max 16 chars)" }),
	options: Type.Array(OptionSchema, { description: "Available choices" }),
	multiple: Type.Optional(Type.Boolean({ description: "Allow selecting multiple choices" })),
});

const Parameters = Type.Object({
	questions: Type.Array(QuestionSchema, { description: "Questions to ask" }),
});

type Question = Static<typeof QuestionSchema>;
type QuestionParams = Static<typeof Parameters>;
type QuestionnaireResult = { answers: string[][]; cancelled: boolean };

// ---------------------------------------------------------------------------
// Tool description & prompt guidance (what the LLM sees)
// ---------------------------------------------------------------------------

const DESCRIPTION = `Use this tool when you need to ask the user questions during execution. This allows you to:
1. Gather user preferences or requirements
2. Clarify ambiguous instructions
3. Get decisions on implementation choices as you work
4. Offer choices to the user about what direction to take.

Usage notes:
- A "Type your own answer" row is added to every question automatically; don't include "Other" or catch-all options
- Answers are returned as arrays of labels; set \`multiple: true\` to allow selecting more than one
- If you recommend a specific option, make that the first option in the list and add "(Recommended)" at the end of the label
- Group all clarifying questions into one invocation instead of stacking calls`;

const PROMPT_SNIPPET = `Ask the user up to 4 structured questions (2-4 options each) when requirements are ambiguous`;

const PROMPT_GUIDELINES = [
	`Use question whenever the user's request is underspecified and you cannot proceed without concrete decisions — you can ask up to 4 questions per invocation.`,
	`Each question MUST have 2-4 options. Every option requires a concise label (1-5 words) and a description explaining what the choice means or its trade-offs. A "Type your own answer" row is appended automatically — do NOT author "Other" or "Type your own answer" labels yourself.`,
	`Set multiple: true when multiple answers are valid — answers are returned as arrays of labels. If you recommend a specific option, make it the first option and append "(Recommended)" to its label.`,
	`Do not stack multiple question calls back-to-back — group all clarifying questions into one invocation.`,
];

// ---------------------------------------------------------------------------
// TUI component (opencode question.tsx, rendered with pi-tui primitives)
// ---------------------------------------------------------------------------

const MAX_VISIBLE_ROWS = 9; // number keys 1-9 cover the first 9 rows

class QuestionnaireComponent {
	private tab = 0; // index into questions; questions.length = confirm tab
	private answers: string[][] = []; // per-question selected labels
	private customValues: string[] = []; // per-question typed custom answers
	private selected = 0; // row within the current question (options.length = custom row)
	private editing = false; // typing a custom answer
	private input = new Input();

	constructor(
		private questions: Question[],
		private theme: Theme,
		private tui: { requestRender: () => void },
		private done: (result: QuestionnaireResult) => void,
	) {
		this.answers = questions.map(() => []);
		this.customValues = questions.map(() => "");
	}

	/** A single non-multiple question submits immediately — no tabs, no confirm. */
	private get single(): boolean {
		return this.questions.length === 1 && this.questions[0].multiple !== true;
	}

	private get tabCount(): number {
		return this.single ? 1 : this.questions.length + 1;
	}

	private get confirmTab(): boolean {
		return !this.single && this.tab === this.questions.length;
	}

	private get question(): Question {
		return this.questions[this.tab]!;
	}

	// -- input --------------------------------------------------------------

	handleInput(data: string): void {
		if (this.editing) {
			this.input.handleInput(data);
			this.tui.requestRender();
			return;
		}

		if (matchesKey(data, Key.escape)) {
			this.done({ answers: [], cancelled: true });
			return;
		}

		// Tab navigation — always active, including the confirm tab (matches opencode,
		// where left/h/right/l/tab keep working while reviewing).
		if (matchesKey(data, Key.left) || data === "h") {
			this.selectTab((this.tab - 1 + this.tabCount) % this.tabCount);
		} else if (matchesKey(data, Key.right) || data === "l") {
			this.selectTab((this.tab + 1) % this.tabCount);
		} else if (matchesKey(data, Key.tab)) {
			this.selectTab((this.tab + 1) % this.tabCount);
		} else if (matchesKey(data, Key.shift("tab"))) {
			this.selectTab((this.tab - 1 + this.tabCount) % this.tabCount);
		} else if (this.confirmTab) {
			if (matchesKey(data, Key.enter) || matchesKey(data, Key.return)) this.submit();
		} else {
			const total = this.question.options.length + 1; // + "Type your own answer" row
			if (matchesKey(data, Key.up) || data === "k") {
				this.selected = (this.selected - 1 + total) % total;
			} else if (matchesKey(data, Key.down) || data === "j") {
				this.selected = (this.selected + 1) % total;
			} else if (data.length === 1 && data >= "1" && data <= "9" && Number(data) - 1 < total) {
				this.selected = Number(data) - 1;
				this.selectOption();
			} else if (matchesKey(data, Key.enter) || matchesKey(data, Key.return)) {
				this.selectOption();
			}
		}

		this.tui.requestRender();
	}

	private selectTab(tab: number): void {
		this.tab = tab;
		this.selected = 0;
	}

	private selectOption(): void {
		const q = this.question;
		const isCustom = this.selected === q.options.length;
		if (isCustom) {
			if (q.multiple) {
				const value = this.customValues[this.tab];
				if (value && this.answers[this.tab].includes(value)) this.toggle(value);
				else this.startEditing();
			} else {
				this.startEditing();
			}
			return;
		}
		const label = q.options[this.selected]!.label;
		if (q.multiple) this.toggle(label);
		else this.pick(label, false);
	}

	private pick(label: string, isCustom: boolean): void {
		this.answers[this.tab] = [label];
		if (isCustom) this.customValues[this.tab] = label;
		if (this.single) {
			this.submit();
			return;
		}
		this.tab = Math.min(this.tab + 1, this.tabCount - 1);
		this.selected = 0;
	}

	private toggle(label: string): void {
		const current = this.answers[this.tab];
		const index = current.indexOf(label);
		if (index === -1) current.push(label);
		else current.splice(index, 1);
	}

	private startEditing(): void {
		this.editing = true;
		this.input.focused = true;
		this.input.setValue(this.customValues[this.tab] ?? "");
		this.input.onSubmit = (value) => this.commitCustom(value);
		this.input.onEscape = () => {
			this.editing = false;
			this.input.focused = false;
		};
	}

	private commitCustom(text: string): void {
		const value = text.trim();
		const prev = this.customValues[this.tab];
		this.input.focused = false;
		if (!value) {
			if (prev) {
				this.customValues[this.tab] = "";
				this.answers[this.tab] = this.answers[this.tab].filter((x) => x !== prev);
			}
			this.editing = false;
			return;
		}
		if (this.question.multiple) {
			this.customValues[this.tab] = value;
			this.answers[this.tab] = this.answers[this.tab].filter((x) => x !== prev);
			if (!this.answers[this.tab].includes(value)) this.answers[this.tab].push(value);
			this.editing = false;
			return;
		}
		this.editing = false;
		this.pick(value, true);
	}

	private submit(): void {
		this.done({ answers: this.questions.map((_, i) => [...(this.answers[i] ?? [])]), cancelled: false });
	}

	// -- rendering ----------------------------------------------------------

	invalidate(): void {}

	render(width: number): string[] {
		const { theme } = this;
		const container = new Container();
		container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));

		if (!this.single) container.addChild(this.renderTabs());

		if (this.confirmTab) {
			container.addChild(new Text(theme.fg("accent", theme.bold("Review")), 1, 0));
			this.questions.forEach((q, i) => {
				const answer = (this.answers[i] ?? []).join(", ");
				container.addChild(
					new Text(
						theme.fg("muted", `${q.header}: `) +
							(answer ? theme.fg("text", answer) : theme.fg("muted", "(not answered)")),
						2,
						0,
					),
				);
			});
		} else {
			const q = this.question;
			const multi = q.multiple === true;
			container.addChild(
				new Text(
					theme.fg("text", theme.bold(q.question)) +
						(multi ? theme.fg("muted", " (select all that apply)") : ""),
					1,
					0,
				),
			);
			for (const row of this.renderRows(q, multi)) container.addChild(row);
			if (this.editing) container.addChild(this.input);
			else if (this.customValues[this.tab]) {
				container.addChild(new Text(theme.fg("muted", this.customValues[this.tab]), 4, 0));
			}
		}

		container.addChild(new Text(theme.fg("dim", this.renderFooter()), 1, 0));
		container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));

		return container.render(width);
	}

	private renderTabs(): Text {
		const { theme } = this;
		const parts = this.questions.map((q, i) => {
			const answered = (this.answers[i]?.length ?? 0) > 0;
			if (i === this.tab) return theme.fg("accent", theme.bold(q.header));
			return answered ? theme.fg("text", q.header) : theme.fg("muted", q.header);
		});
		parts.push(this.confirmTab ? theme.fg("accent", theme.bold("Confirm")) : theme.fg("muted", "Confirm"));
		return new Text(parts.join("   "), 1, 0);
	}

	private renderRows(q: Question, multi: boolean): Text[] {
		const total = q.options.length + 1;
		const rows: Text[] = [];
		const maxVisible = Math.min(MAX_VISIBLE_ROWS, total);
		const start =
			total > MAX_VISIBLE_ROWS ? Math.max(0, Math.min(this.selected - 4, total - MAX_VISIBLE_ROWS)) : 0;
		for (let i = start; i < start + maxVisible; i++) {
			if (i < q.options.length) {
				const opt = q.options[i]!;
				rows.push(this.renderOptionRow(opt, i, multi));
				rows.push(this.renderOptionDescription(opt, i));
			} else {
				rows.push(this.renderCustomRow(multi, i));
			}
		}
		return rows;
	}

	private renderOptionRow(opt: Question["options"][number], index: number, multi: boolean): Text {
		const { theme } = this;
		const selected = index === this.selected;
		const picked = this.answers[this.tab].includes(opt.label);
		const prefix = selected ? theme.fg("accent", `${index + 1}.`) : theme.fg("muted", `${index + 1}.`);
		const label = selected
			? theme.fg("accent", opt.label)
			: picked
				? theme.fg("success", opt.label)
				: theme.fg("text", opt.label);
		const primary = multi
			? `${picked ? theme.fg("success", "[✓]") : theme.fg("muted", "[ ]")} ${label}`
			: picked
				? `${label} ${theme.fg("success", "✓")}`
				: label;
		return new Text(`${prefix} ${primary}`, 2, 0);
	}

	private renderOptionDescription(opt: Question["options"][number], index: number): Text {
		const { theme } = this;
		const muted = index === this.selected ? theme.fg("dim", opt.description) : theme.fg("muted", opt.description);
		return new Text(`   ${muted}`, 2, 0);
	}

	private renderCustomRow(multi: boolean, index: number): Text {
		const { theme } = this;
		const selected = index === this.selected;
		const value = this.customValues[this.tab];
		const picked = Boolean(value && this.answers[this.tab].includes(value));
		const prefix = selected ? theme.fg("accent", `${index + 1}.`) : theme.fg("muted", `${index + 1}.`);
		const label = selected
			? theme.fg("accent", "Type your own answer")
			: picked
				? theme.fg("success", "Type your own answer")
				: theme.fg("text", "Type your own answer");
		const primary = multi
			? `${picked ? theme.fg("success", "[✓]") : theme.fg("muted", "[ ]")} ${label}`
			: picked
				? `${label} ${theme.fg("success", "✓")}`
				: label;
		return new Text(`${prefix} ${primary}`, 2, 0);
	}

	private renderFooter(): string {
		const { theme } = this;
		const muted = (s: string) => theme.fg("muted", s);
		if (this.editing) return `enter ${muted("commit")}   esc ${muted("cancel")}`;
		const parts: string[] = [];
		if (!this.single) parts.push(`⇆ ${muted("tab")}`);
		parts.push(`↑↓ ${muted("select")}`);
		parts.push(`enter ${muted(this.confirmTab ? "submit" : this.question.multiple ? "toggle" : "select")}`);
		parts.push(`esc ${muted("dismiss")}`);
		return parts.join("   ");
	}
}

// ---------------------------------------------------------------------------
// Tool registration
// ---------------------------------------------------------------------------

function validateQuestions(questions: Question[]): string | null {
	if (!Array.isArray(questions) || questions.length === 0) return "Error: questions must be a non-empty array.";
	if (questions.length > 4) return "Error: at most 4 questions per invocation — group them into one call.";
	for (const q of questions) {
		if (!q.question?.trim() || !q.header?.trim()) return "Error: every question needs question and header text.";
		if (!Array.isArray(q.options) || q.options.length < 2) {
			return `Error: question "${q.question}" needs at least 2 options.`;
		}
		for (const opt of q.options) {
			if (!opt.label?.trim()) return `Error: question "${q.question}" has an option without a label.`;
		}
	}
	return null;
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "question",
		label: "Ask User Question",
		description: DESCRIPTION,
		promptSnippet: PROMPT_SNIPPET,
		promptGuidelines: PROMPT_GUIDELINES,
		parameters: Parameters,

		async execute(_toolCallId, params: QuestionParams, _signal, _onUpdate, ctx) {
			const questions = params.questions;

			const invalid = validateQuestions(questions);
			if (invalid) {
				return { content: [{ type: "text", text: invalid }], details: { answers: [], cancelled: true }, isError: true };
			}

			if (!ctx.hasUI) {
				return {
					content: [
						{
							type: "text",
							text: "Error: UI not available in this mode. Ask the questions as plain text instead, without using this tool.",
						},
					],
					details: { answers: [], cancelled: true },
					isError: true,
				};
			}

			const result = await ctx.ui.custom<QuestionnaireResult>(
				(tui, theme, _keybindings, done) => new QuestionnaireComponent(questions, theme, tui, done),
				{
					overlay: true,
					overlayOptions: {
						anchor: "bottom-center",
						width: "100%",
						maxHeight: "100%",
						margin: { left: 0, right: 0, bottom: 0 },
					},
				},
			);

			if (!result || result.cancelled) {
				return {
					content: [
						{
							type: "text",
							text: "The user dismissed the questionnaire without answering. Do not re-ask; proceed using your best judgment.",
						},
					],
					details: { answers: [], cancelled: true },
				};
			}

			const formatted = questions
				.map((q, i) => `"${q.question}"="${(result.answers[i] ?? []).join(", ") || "Unanswered"}"`)
				.join(", ");

			return {
				content: [
					{
						type: "text",
						text: `User has answered your questions: ${formatted}. You can now continue with the user's answers in mind.`,
					},
				],
				details: { answers: result.answers, cancelled: false },
			};
		},
	});
}
