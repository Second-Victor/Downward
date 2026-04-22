import type { AssistantMessage } from "@mariozechner/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

type CodexUsageSnapshot = {
	primaryUsedPercent: number;
	secondaryUsedPercent: number;
	primaryWindowMinutes?: number;
	secondaryWindowMinutes?: number;
	primaryResetAt?: number;
	secondaryResetAt?: number;
	planType?: string;
	activeLimit?: string;
	updatedAt: number;
};

function numberHeader(headers: Record<string, string>, key: string): number | undefined {
	const value = headers[key];
	if (!value) return undefined;
	const parsed = Number(value);
	return Number.isFinite(parsed) ? parsed : undefined;
}

function stringHeader(headers: Record<string, string>, key: string): string | undefined {
	const value = headers[key]?.trim();
	return value ? value : undefined;
}

function sanitizeStatusText(text: string): string {
	return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

function formatWindow(minutes?: number, fallback: string = "?"): string {
	if (!minutes || minutes <= 0) return fallback;
	if (minutes === 300) return "5h";
	if (minutes === 10080) return "wk";
	if (minutes % 1440 === 0) {
		const days = minutes / 1440;
		return days === 7 ? "wk" : `${days}d`;
	}
	if (minutes % 60 === 0) return `${minutes / 60}h`;
	return `${minutes}m`;
}

function usageColor(theme: ExtensionContext["ui"]["theme"], remaining: number, text: string): string {
	if (remaining <= 10) return theme.fg("error", text);
	if (remaining <= 25) return theme.fg("warning", text);
	return theme.fg("success", text);
}

function parseCodexUsage(headers: Record<string, string>): CodexUsageSnapshot | undefined {
	const primaryUsedPercent = numberHeader(headers, "x-codex-primary-used-percent");
	const secondaryUsedPercent = numberHeader(headers, "x-codex-secondary-used-percent");
	if (primaryUsedPercent === undefined && secondaryUsedPercent === undefined) return undefined;

	return {
		primaryUsedPercent: Math.max(0, Math.min(100, primaryUsedPercent ?? 0)),
		secondaryUsedPercent: Math.max(0, Math.min(100, secondaryUsedPercent ?? 0)),
		primaryWindowMinutes: numberHeader(headers, "x-codex-primary-window-minutes"),
		secondaryWindowMinutes: numberHeader(headers, "x-codex-secondary-window-minutes"),
		primaryResetAt: numberHeader(headers, "x-codex-primary-reset-at"),
		secondaryResetAt: numberHeader(headers, "x-codex-secondary-reset-at"),
		planType: stringHeader(headers, "x-codex-plan-type"),
		activeLimit: stringHeader(headers, "x-codex-active-limit"),
		updatedAt: Date.now(),
	};
}

export default function (pi: ExtensionAPI) {
	let latestUsage: CodexUsageSnapshot | undefined;

	function installFooter(ctx: ExtensionContext) {
		if (!ctx.hasUI) return;
		ctx.ui.setFooter((tui, theme, footerData) => {
			const unsubscribe = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: unsubscribe,
				invalidate() {},
				render(width: number): string[] {
					let totalInput = 0;
					let totalOutput = 0;
					let totalCacheWrite = 0;
					let totalCost = 0;

					for (const entry of ctx.sessionManager.getEntries()) {
						if (entry.type === "message" && entry.message.role === "assistant") {
							const message = entry.message as AssistantMessage;
							totalInput += message.usage.input;
							totalOutput += message.usage.output;
							totalCacheWrite += message.usage.cacheWrite;
							totalCost += message.usage.cost.total;
						}
					}

					let cwd = ctx.sessionManager.getCwd();
					const home = process.env.HOME || process.env.USERPROFILE;
					if (home && cwd.startsWith(home)) cwd = `~${cwd.slice(home.length)}`;

					const branch = footerData.getGitBranch();
					if (branch) cwd += ` (${branch})`;

					const sessionName = ctx.sessionManager.getSessionName();
					if (sessionName) cwd += ` • ${sessionName}`;

					const statsParts: string[] = [];
					if (totalInput) statsParts.push(`↑${formatTokens(totalInput)}`);
					if (totalOutput) statsParts.push(`↓${formatTokens(totalOutput)}`);
					if (totalCacheWrite) statsParts.push(`W${formatTokens(totalCacheWrite)}`);

					if (ctx.model?.provider === "openai-codex") {
						if (latestUsage) {
							const primaryRemaining = Math.max(0, 100 - latestUsage.primaryUsedPercent);
							const secondaryRemaining = Math.max(0, 100 - latestUsage.secondaryUsedPercent);
							statsParts.push(
								usageColor(
									theme,
									primaryRemaining,
									`${formatWindow(latestUsage.primaryWindowMinutes, "5h")} ${primaryRemaining}%`,
								),
							);
							statsParts.push(
								usageColor(
									theme,
									secondaryRemaining,
									`${formatWindow(latestUsage.secondaryWindowMinutes, "wk")} ${secondaryRemaining}%`,
								),
							);
						} else {
							statsParts.push(theme.fg("muted", "5h --"));
							statsParts.push(theme.fg("muted", "wk --"));
						}
					} else if (totalCost) {
						statsParts.push(`$${totalCost.toFixed(3)}`);
					}

					const contextUsage = ctx.getContextUsage();
					const contextWindow = contextUsage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
					const contextPercentValue = contextUsage?.percent ?? 0;
					const contextPercent = contextUsage?.percent !== null && contextUsage?.percent !== undefined
						? contextUsage.percent.toFixed(1)
						: "?";
					const contextDisplay = contextPercent === "?"
						? `?/${formatTokens(contextWindow)}`
						: `${contextPercent}%/${formatTokens(contextWindow)}`;
					if (contextWindow > 0) {
						if (contextPercentValue > 90) statsParts.push(theme.fg("error", contextDisplay));
						else if (contextPercentValue > 70) statsParts.push(theme.fg("warning", contextDisplay));
						else statsParts.push(contextDisplay);
					}

					const left = statsParts.join(" ");
					const right = ctx.model?.id || "no-model";

					const leftWidth = visibleWidth(left);
					const rightWidth = visibleWidth(right);
					const minGap = 2;
					let statsLine: string;

					if (leftWidth + minGap + rightWidth <= width) {
						statsLine = left + " ".repeat(width - leftWidth - rightWidth) + right;
					} else if (leftWidth < width) {
						const availableRight = Math.max(0, width - leftWidth - minGap);
						const truncatedRight = truncateToWidth(right, availableRight, "");
						statsLine = truncateToWidth(left, width, "...");
						if (availableRight > 0) {
							const pad = " ".repeat(Math.max(1, width - visibleWidth(statsLine) - visibleWidth(truncatedRight)));
							statsLine = truncateToWidth(left + pad + truncatedRight, width);
						}
					} else {
						statsLine = truncateToWidth(left, width, "...");
					}

					const pwdLine = truncateToWidth(theme.fg("dim", cwd), width, theme.fg("dim", "..."));
					const lines = [pwdLine, theme.fg("dim", statsLine)];

					const extensionStatuses = footerData.getExtensionStatuses();
					if (extensionStatuses.size > 0) {
						const statusLine = Array.from(extensionStatuses.entries())
							.sort(([a], [b]) => a.localeCompare(b))
							.map(([, text]) => sanitizeStatusText(text))
							.join(" ");
						lines.push(truncateToWidth(statusLine, width, theme.fg("dim", "...")));
					}

					return lines;
				},
			};
		});
	}

	pi.on("session_start", async (_event, ctx) => {
		installFooter(ctx);
	});

	pi.on("model_select", async (_event, ctx) => {
		installFooter(ctx);
	});

	pi.on("after_provider_response", async (event, ctx) => {
		if (!ctx.hasUI) return;
		if (ctx.model?.provider !== "openai-codex") return;
		const parsed = parseCodexUsage(event.headers);
		if (!parsed) return;
		latestUsage = parsed;
		installFooter(ctx);
	});
}
