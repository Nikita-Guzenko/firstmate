import { randomUUID } from "node:crypto";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export const DEFAULT_INTERVAL_MS = 5_000;
const WIDGET_ID = "fm-live-status";
const PULSE = ["●", "◐", "○", "◑"];

type CurrentState = {
  state?: string;
  detail?: string;
  raw?: string;
};

type BacklogRecord = {
  id?: string;
  state?: string;
  title?: string;
  repo?: string | null;
};

type FleetTask = {
  id?: string;
  kind?: string;
  current_state?: CurrentState;
  backlog?: BacklogRecord | null;
  hints?: { last_event_text?: string };
};

type FleetSnapshot = {
  backlog?: { records?: BacklogRecord[] };
  tasks?: FleetTask[];
};

export type LiveStatusEstimate = {
  summary: string;
  percent: number;
};

type StatusInput = {
  activeCount: number;
  blocked: boolean;
  primaryBusy: boolean;
  primaryTask: string;
  primaryAction: string;
  tasks: Array<{
    id: string;
    title: string;
    state: string;
    detail: string;
  }>;
};

const extensionFile = fileURLToPath(import.meta.url);
const root = resolve(dirname(extensionFile), "../..");

function clampPercent(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(100, Math.round(value)));
}

export function sanitizeStatusText(value: unknown, maxLength = 88): string {
  const text = String(value ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

export function parseAiStatus(text: string): LiveStatusEstimate | null {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const value = JSON.parse(text.slice(start, end + 1)) as {
      summary?: unknown;
      percent?: unknown;
    };
    const summary = sanitizeStatusText(value.summary, 72);
    const percent = Number(value.percent);
    if (!summary || !Number.isFinite(percent)) return null;
    return { summary, percent: clampPercent(percent) };
  } catch {
    return null;
  }
}

function detailProgress(detail: string): number {
  const text = detail.toLowerCase();
  if (/checks green|pr ready|ready in branch|deployed and verified|complete/.test(text)) return 95;
  if (/deploy|publish|shipping|merge|ci\b/.test(text)) return 85;
  if (/test|verify|validat|review|lint|check/.test(text)) return 75;
  if (/implement|edit|fix|build|configur|migrat|integrat/.test(text)) return 55;
  if (/research|audit|investigat|inventory|repro|plan/.test(text)) return 30;
  if (/start|setup|reading|required context/.test(text)) return 15;
  return 45;
}

function taskProgress(task: StatusInput["tasks"][number]): number {
  const state = task.state.toLowerCase();
  if (state === "done") return 100;
  if (state === "failed") return 100;
  if (state === "blocked" || state === "parked" || state === "needs-decision") return 65;
  if (state === "unknown") return 20;
  return detailProgress(task.detail);
}

export function fallbackEstimate(input: StatusInput): LiveStatusEstimate {
  if (input.activeCount === 0 && !input.primaryBusy) {
    return { summary: "Idle - nothing is running", percent: 100 };
  }

  if (input.tasks.length > 0) {
    const percent = Math.round(
      input.tasks.reduce((sum, task) => sum + taskProgress(task), 0) / input.tasks.length,
    );
    const first = input.tasks[0]!;
    const summary = first.detail || first.title || `${first.id} is ${first.state}`;
    return {
      summary: sanitizeStatusText(summary, 72) || "Work is in progress",
      percent: clampPercent(percent),
    };
  }

  const actionProgress: Record<string, number> = {
    read: 25,
    grep: 25,
    find: 25,
    ls: 25,
    web_search: 30,
    source_check: 30,
    fetch_content: 30,
    edit: 55,
    write: 55,
    bash: 65,
  };
  const summary = input.primaryAction
    ? `${input.primaryTask || "Firstmate task"}: ${input.primaryAction}`
    : input.primaryTask || "Firstmate is working";
  return {
    summary: sanitizeStatusText(summary, 72),
    percent: actionProgress[input.primaryAction] ?? 15,
  };
}

function toolAction(event: { toolName?: string; input?: Record<string, unknown> }): string {
  const name = sanitizeStatusText(event.toolName, 24);
  if (!name) return "working";
  if (["read", "edit", "write"].includes(name)) {
    const path = typeof event.input?.path === "string" ? basename(event.input.path) : "";
    return path ? `${name} ${sanitizeStatusText(path, 30)}` : name;
  }
  if (name === "bash") return "running checks";
  if (name === "web_search" || name === "source_check" || name === "fetch_content") return "researching";
  return name.replaceAll("_", " ");
}

function buildInput(snapshot: FleetSnapshot, primaryBusy: boolean, primaryAction: string): StatusInput {
  const records = snapshot.backlog?.records ?? [];
  const backlogById = new Map(records.map((record) => [record.id ?? "", record]));
  const tasks = (snapshot.tasks ?? []).map((task) => {
    const backlog = task.backlog ?? backlogById.get(task.id ?? "");
    const current = task.current_state ?? {};
    return {
      id: task.id ?? "task",
      title: backlog?.title ?? task.id ?? "Task",
      state: current.state ?? "unknown",
      detail: sanitizeStatusText(
        current.detail || current.raw || task.hints?.last_event_text || backlog?.title || "",
        120,
      ),
    };
  });
  const primaryRecord = records.find((record) => record.state === "in_flight");
  return {
    activeCount: tasks.length + (primaryBusy && tasks.length === 0 ? 1 : 0),
    blocked: tasks.some((task) => /^(blocked|parked|needs-decision)$/.test(task.state)),
    primaryBusy,
    primaryTask: sanitizeStatusText(primaryRecord?.title, 90),
    primaryAction,
    tasks,
  };
}

function aiPrompt(input: StatusInput): string {
  return [
    "You write one live engineering status line.",
    "Return exactly one JSON object: {\"summary\":\"at most 9 concrete words\",\"percent\":0-100}.",
    "Say what is happening now, not what should happen next.",
    "Estimate real completion from the supplied state. Never invent work, outcomes, or blockers.",
    "A blocked task can still be partly complete. A finished or failed task is 100 percent terminal.",
    JSON.stringify(input),
  ].join("\n");
}

function responseText(response: { content?: Array<{ type?: string; text?: string }> }): string {
  return (response.content ?? [])
    .filter((part) => part.type === "text" && typeof part.text === "string")
    .map((part) => part.text ?? "")
    .join("\n");
}

function renderLine(ctx: ExtensionContext, estimate: LiveStatusEstimate, input: StatusInput, pulse: string): string {
  const theme = ctx.ui.theme;
  const percentColor: "success" | "warning" | "accent" =
    estimate.percent >= 100 ? "success" : input.blocked ? "warning" : "accent";
  const count = input.activeCount === 1 ? "1 active" : `${input.activeCount} active`;
  return [
    theme.fg("accent", pulse),
    theme.fg(percentColor, theme.bold(`${estimate.percent}%`)),
    theme.fg("muted", "AI:"),
    theme.fg("text", estimate.summary),
    theme.fg("dim", `(${count}, refresh 5s)`),
  ].join(" ");
}

export default function fmLiveStatus(pi: ExtensionAPI): void {
  const interval = Math.max(250, Number(process.env.FM_LIVE_STATUS_INTERVAL_MS) || DEFAULT_INTERVAL_MS);
  const snapshotCommand = process.env.FM_LIVE_STATUS_SNAPSHOT_CMD || `${root}/bin/fm-fleet-snapshot.sh`;
  let timer: ReturnType<typeof setInterval> | undefined;
  let controller: AbortController | undefined;
  let running = false;
  let stopped = false;
  let primaryBusy = false;
  let primaryAction = "";
  let pulseIndex = 0;
  let lastEstimate: LiveStatusEstimate = { summary: "Loading live fleet status", percent: 0 };

  const stop = (ctx?: ExtensionContext) => {
    stopped = true;
    if (timer) clearInterval(timer);
    timer = undefined;
    controller?.abort();
    controller = undefined;
    running = false;
    ctx?.ui.setWidget(WIDGET_ID, undefined);
  };

  const tick = async (ctx: ExtensionContext) => {
    if (stopped || running || ctx.mode !== "tui") return;
    running = true;
    controller = new AbortController();
    try {
      const snapshotResult = await pi.exec(snapshotCommand, [], {
        timeout: Math.min(4_000, interval),
        signal: controller.signal,
      });
      if (snapshotResult.code !== 0) throw new Error("fleet snapshot failed");
      const snapshot = JSON.parse(snapshotResult.stdout) as FleetSnapshot;
      const input = buildInput(snapshot, primaryBusy, primaryAction);
      const fallback = fallbackEstimate(input);
      pulseIndex = (pulseIndex + 1) % PULSE.length;
      ctx.ui.setWidget(WIDGET_ID, [renderLine(ctx, lastEstimate.summary ? lastEstimate : fallback, input, PULSE[pulseIndex]!)]);

      if (input.activeCount === 0 && !primaryBusy) {
        lastEstimate = fallback;
      } else if (ctx.model && ctx.modelRegistry.hasConfiguredAuth(ctx.model)) {
        const response = await ctx.modelRegistry.complete(
          ctx.model,
          {
            messages: [
              {
                role: "user",
                content: [{ type: "text", text: aiPrompt(input) }],
                timestamp: Date.now(),
              },
            ],
          },
          {
            maxTokens: 80,
            reasoningEffort: "low",
            cacheRetention: "none",
            sessionId: randomUUID(),
            signal: controller.signal,
          },
        );
        lastEstimate = parseAiStatus(responseText(response)) ?? fallback;
      } else {
        lastEstimate = fallback;
      }

      if (!stopped) {
        ctx.ui.setWidget(WIDGET_ID, [renderLine(ctx, lastEstimate, input, PULSE[pulseIndex]!)]);
      }
    } catch {
      if (!stopped) {
        const input: StatusInput = {
          activeCount: primaryBusy ? 1 : 0,
          blocked: false,
          primaryBusy,
          primaryTask: "",
          primaryAction,
          tasks: [],
        };
        const fallback = fallbackEstimate(input);
        pulseIndex = (pulseIndex + 1) % PULSE.length;
        ctx.ui.setWidget(WIDGET_ID, [renderLine(ctx, fallback, input, PULSE[pulseIndex]!)]);
      }
    } finally {
      running = false;
      controller = undefined;
    }
  };

  pi.on("session_start", async (_event, ctx) => {
    stop();
    stopped = false;
    if (ctx.mode !== "tui") return;
    await tick(ctx);
    timer = setInterval(() => void tick(ctx), interval);
    timer.unref?.();
  });

  pi.on("turn_start", async (_event, ctx) => {
    primaryBusy = true;
    await tick(ctx);
  });

  pi.on("tool_execution_start", async (event, ctx) => {
    primaryAction = toolAction(event as { toolName?: string; input?: Record<string, unknown> });
    await tick(ctx);
  });

  pi.on("turn_end", async (_event, ctx) => {
    primaryBusy = false;
    primaryAction = "";
    await tick(ctx);
  });

  pi.on("session_shutdown", async (_event, ctx) => stop(ctx));
}
