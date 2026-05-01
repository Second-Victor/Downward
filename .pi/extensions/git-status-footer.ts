import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const STATUS_KEY = "git-status";
const REFRESH_INTERVAL_MS = 5_000;
const REFRESH_DEBOUNCE_MS = 250;

type GitSummary = {
	branch: string;
	ahead: number;
	behind: number;
	modified: number;
	added: number;
	deleted: number;
	renamed: number;
	untracked: number;
	conflicts: number;
};

function parseCount(value: string | undefined): number {
	if (!value) return 0;
	const parsed = Number(value);
	return Number.isFinite(parsed) ? parsed : 0;
}

function parseGitStatus(output: string): GitSummary {
	const summary: GitSummary = {
		branch: "repo",
		ahead: 0,
		behind: 0,
		modified: 0,
		added: 0,
		deleted: 0,
		renamed: 0,
		untracked: 0,
		conflicts: 0,
	};

	for (const line of output.split(/\r?\n/)) {
		if (!line) continue;

		if (line.startsWith("# branch.head ")) {
			const branch = line.slice("# branch.head ".length).trim();
			summary.branch = branch === "(detached)" ? "detached" : branch || summary.branch;
			continue;
		}

		if (line.startsWith("# branch.ab ")) {
			const match = line.match(/\+(\d+)\s+-(\d+)/);
			summary.ahead = parseCount(match?.[1]);
			summary.behind = parseCount(match?.[2]);
			continue;
		}

		if (line.startsWith("? ")) {
			summary.untracked += 1;
			continue;
		}

		if (line.startsWith("u ")) {
			summary.conflicts += 1;
			continue;
		}

		if (line.startsWith("1 ") || line.startsWith("2 ")) {
			const xy = line.slice(2, 4);
			if (xy.includes("U")) summary.conflicts += 1;
			else if (xy.includes("R")) summary.renamed += 1;
			else if (xy.includes("A") || xy.includes("C")) summary.added += 1;
			else if (xy.includes("D")) summary.deleted += 1;
			else if (xy.includes("M") || xy.includes("T")) summary.modified += 1;
		}
	}

	return summary;
}

function formatGitStatus(summary: GitSummary, theme: ExtensionContext["ui"]["theme"]): string {
	const syncParts: string[] = [];
	if (summary.ahead > 0) syncParts.push(`↑${summary.ahead}`);
	if (summary.behind > 0) syncParts.push(`↓${summary.behind}`);

	const changeParts: string[] = [];
	if (summary.modified > 0) changeParts.push(`${summary.modified}M`);
	if (summary.added > 0) changeParts.push(`${summary.added}A`);
	if (summary.deleted > 0) changeParts.push(`${summary.deleted}D`);
	if (summary.renamed > 0) changeParts.push(`${summary.renamed}R`);
	if (summary.untracked > 0) changeParts.push(`${summary.untracked}?`);
	if (summary.conflicts > 0) changeParts.push(`${summary.conflicts}!`);

	const branch = theme.fg("accent", summary.branch);
	const sync = syncParts.length > 0 ? ` ${theme.fg("muted", syncParts.join(" "))}` : "";
	const state = changeParts.length === 0
		? theme.fg("success", "clean")
		: summary.conflicts > 0
			? theme.fg("error", changeParts.join(" "))
			: theme.fg("warning", changeParts.join(" "));

	return `${theme.fg("dim", "git")} ${branch}${sync} • ${state}`;
}

export default function (pi: ExtensionAPI) {
	let latestContext: ExtensionContext | undefined;
	let refreshInterval: ReturnType<typeof setInterval> | undefined;
	let refreshTimer: ReturnType<typeof setTimeout> | undefined;
	let refreshInFlight = false;
	let refreshPending = false;
	let sessionGeneration = 0;

	function clearTimers() {
		if (refreshTimer) clearTimeout(refreshTimer);
		if (refreshInterval) clearInterval(refreshInterval);
		refreshTimer = undefined;
		refreshInterval = undefined;
	}

	async function refresh(ctx: ExtensionContext) {
		if (!ctx.hasUI) return;
		latestContext = ctx;
		const generation = sessionGeneration;

		if (refreshInFlight) {
			refreshPending = true;
			return;
		}

		refreshInFlight = true;
		try {
			const cwd = ctx.sessionManager.getCwd();
			const result = await pi.exec(
				"git",
				["-C", cwd, "status", "--porcelain=v2", "--branch", "--untracked-files=normal"],
				{ timeout: 2_000 },
			);

			if (generation !== sessionGeneration) return;

			if (result.code !== 0) {
				ctx.ui.setStatus(STATUS_KEY, undefined);
				return;
			}

			ctx.ui.setStatus(STATUS_KEY, formatGitStatus(parseGitStatus(result.stdout), ctx.ui.theme));
		} catch {
			if (generation !== sessionGeneration) return;
			ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("muted", "git status unavailable"));
		} finally {
			refreshInFlight = false;
			if (refreshPending) {
				refreshPending = false;
				const nextContext = latestContext;
				if (nextContext) void refresh(nextContext);
			}
		}
	}

	function scheduleRefresh(ctx: ExtensionContext, delay = REFRESH_DEBOUNCE_MS) {
		if (!ctx.hasUI) return;
		latestContext = ctx;
		if (refreshTimer) clearTimeout(refreshTimer);
		refreshTimer = setTimeout(() => {
			refreshTimer = undefined;
			void refresh(ctx);
		}, delay);
	}

	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		sessionGeneration += 1;
		latestContext = ctx;
		clearTimers();
		void refresh(ctx);
		refreshInterval = setInterval(() => {
			const ctx = latestContext;
			if (ctx) scheduleRefresh(ctx, 0);
		}, REFRESH_INTERVAL_MS);
	});

	pi.on("tool_execution_end", async (_event, ctx) => {
		scheduleRefresh(ctx);
	});

	pi.on("agent_end", async (_event, ctx) => {
		scheduleRefresh(ctx);
	});

	pi.on("user_bash", async (_event, ctx) => {
		scheduleRefresh(ctx, 1_000);
	});

	pi.registerCommand("git-status-refresh", {
		description: "Refresh the footer git status line",
		handler: async (_args, ctx) => {
			await refresh(ctx);
		},
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		sessionGeneration += 1;
		clearTimers();
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
		latestContext = undefined;
	});
}
