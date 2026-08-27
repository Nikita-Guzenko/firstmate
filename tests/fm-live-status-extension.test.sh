#!/usr/bin/env bash
# Behavioral coverage for the Pi live fleet-status widget.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLUGIN="$ROOT/.pi/extensions/fm-live-status.ts"
TMP_ROOT=$(fm_test_tmproot fm-live-status-extension)
STATUS_STATE="$TMP_ROOT/state"
mkdir -p "$STATUS_STATE"

fm_skip_without node "Pi live status extension behavior" || exit 0
fm_skip_without_ts_import "Pi live status extension behavior" || exit 0

out=$(PLUGIN="$PLUGIN" FM_STATE_OVERRIDE="$STATUS_STATE" FM_LIVE_STATUS_INTERVAL_MS=20 node --input-type=module 2>&1 <<'EOF'
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const { settle, waitFor } = await import(pathToFileURL(process.env.FM_TEST_WAIT_FOR).href);
const mod = await import(pathToFileURL(process.env.PLUGIN).href);

if (mod.DEFAULT_INTERVAL_MS !== 5000) {
  throw new Error(`expected five-second default, got ${mod.DEFAULT_INTERVAL_MS}`);
}

const parsed = mod.parseAiStatus('prefix {"summary":"Deploying webhook","percent":111} suffix');
if (parsed?.summary !== "Deploying webhook" || parsed.percent !== 100) {
  throw new Error(`AI status parsing/clamping failed: ${JSON.stringify(parsed)}`);
}

const redacted = mod.redactStatusText(
  'reading /home/nikita/project/.env OPENAI_API_KEY=sk-secretvalue123 Authorization: Bearer abc.def.ghi cookie=sessionvalue github_pat_1234567890',
);
for (const leaked of ["/home/nikita", "sk-secretvalue123", "abc.def.ghi", "sessionvalue", "github_pat_1234567890"]) {
  if (redacted.includes(leaked)) {
    throw new Error(`redaction leaked ${leaked}: ${redacted}`);
  }
}
if (!redacted.includes("[path]") || !redacted.includes("[redacted")) {
  throw new Error(`redaction lost useful markers: ${redacted}`);
}

const primary = mod.fallbackEstimate({
  activeCount: 1,
  terminalCount: 0,
  blocked: false,
  primaryBusy: true,
  primaryTask: "Add live status",
  primaryAction: "edit",
  tasks: [],
});
if (primary.percent !== 55 || !primary.summary.includes("Add live status")) {
  throw new Error(`primary fallback was not behavior-based: ${JSON.stringify(primary)}`);
}

const terminal = mod.fallbackEstimate({
  activeCount: 0,
  terminalCount: 1,
  blocked: false,
  primaryBusy: false,
  primaryTask: "",
  primaryAction: "",
  tasks: [{ id: "ship-k9", title: "Ship status", state: "done", detail: "checks green" }],
});
if (terminal.percent !== 100 || !terminal.summary.includes("checks green")) {
  throw new Error(`terminal fallback was not terminal-aware: ${JSON.stringify(terminal)}`);
}

const handlers = new Map();
const widgetWrites = [];
let modelCalls = 0;
let snapshotCalls = 0;
const snapshot = {
  backlog: {
    records: [
      { id: "deploy-k7", state: "in_flight", title: "Deploy purchase attribution", repo: "invoicesnap-expo" },
    ],
  },
  tasks: [
    {
      id: "deploy-k7",
      current_state: { state: "working", detail: "deploying RevenueCat webhook" },
      backlog: { id: "deploy-k7", title: "Deploy purchase attribution" },
      hints: {},
    },
  ],
};

const pi = {
  on(name, handler) {
    handlers.set(name, handler);
  },
  async exec(command) {
    snapshotCalls += 1;
    if (!command.endsWith("/bin/fm-fleet-snapshot.sh")) {
      throw new Error(`wrong snapshot owner: ${command}`);
    }
    return { code: 0, stdout: JSON.stringify(snapshot), stderr: "" };
  },
};

const identity = (_name, text) => text;
const ctx = {
  mode: "tui",
  model: { provider: "fake", id: "fast", contextWindow: 1000 },
  modelRegistry: {
    hasConfiguredAuth: () => true,
    async complete(_model, request, options) {
      modelCalls += 1;
      if (options.maxTokens !== 80 || options.reasoningEffort !== "low") {
        throw new Error(`background AI call was not bounded: ${JSON.stringify(options)}`);
      }
      const prompt = request.messages[0].content[0].text;
      if (!prompt.includes("deploying RevenueCat webhook")) {
        throw new Error(`prompt omitted current fleet state: ${prompt}`);
      }
      return {
        content: [{ type: "text", text: '{"summary":"Deploying secure RevenueCat webhook","percent":82}' }],
      };
    },
  },
  ui: {
    theme: { fg: identity, bold: (text) => text },
    setWidget(id, value, options) {
      widgetWrites.push({ id, value, options, at: Date.now() });
    },
  },
};

mod.default(pi);
const sessionStart = handlers.get("session_start");
const sessionShutdown = handlers.get("session_shutdown");
if (!sessionStart || !sessionShutdown) throw new Error("session lifecycle handlers were not registered");

await sessionStart({}, ctx);
const marker = readFileSync(`${process.env.FM_STATE_OVERRIDE}/.pi-live-status-extension-loaded`, "utf8").trim().split("\n");
if (!marker[0]?.startsWith("sha256:") || marker[1] !== String(process.pid)) {
  throw new Error(`loaded marker did not contain version and process: ${JSON.stringify(marker)}`);
}
await waitFor("the five-second ticker to run repeatedly under the test interval", () => modelCalls >= 2);

const rendered = widgetWrites
  .filter((write) => Array.isArray(write.value))
  .map((write) => write.value.join("\n"))
  .find((text) => text.includes("82%") && text.includes("Deploying secure RevenueCat webhook"));
if (!rendered) {
  throw new Error(`AI result never reached the widget: ${JSON.stringify(widgetWrites)}`);
}
if (!rendered.includes("1 active") || !rendered.includes("refresh 5s")) {
  throw new Error(`widget omitted active count or cadence: ${rendered}`);
}
if (widgetWrites.some((write) => write.options !== undefined)) {
  throw new Error("widget was not placed above the editor by default");
}
if (snapshotCalls < 2) throw new Error(`snapshot did not refresh: ${snapshotCalls}`);

await sessionShutdown({}, ctx);
const callsAtShutdown = modelCalls;
await settle(80, "confirm the status ticker remains stopped after session shutdown");
if (modelCalls !== callsAtShutdown) {
  throw new Error("background AI ticker survived session shutdown");
}
const cleared = widgetWrites.at(-1);
if (cleared?.id !== "fm-live-status" || cleared.value !== undefined) {
  throw new Error(`widget was not cleared on shutdown: ${JSON.stringify(cleared)}`);
}
EOF
)
status=$?
expect_node_ok "$status" "$out" "Pi live status extension must refresh AI fleet progress and clean up"
pass "Pi live status extension refreshes AI fleet progress above the editor"

out=$(PLUGIN="$PLUGIN" FM_STATE_OVERRIDE="$STATUS_STATE" FM_LIVE_STATUS_INTERVAL_MS=30 node --input-type=module 2>&1 <<'EOF'
import { pathToFileURL } from "node:url";

const { settle, waitFor } = await import(pathToFileURL(process.env.FM_TEST_WAIT_FOR).href);
const mod = await import(pathToFileURL(process.env.PLUGIN).href);

const handlers = new Map();
const widgetWrites = [];
let modelCalls = 0;
let snapshotCalls = 0;

const pi = {
  on(name, handler) {
    handlers.set(name, handler);
  },
  async exec() {
    snapshotCalls += 1;
    return { code: 0, stdout: JSON.stringify({ backlog: { records: [] }, tasks: [] }), stderr: "" };
  },
};

const identity = (_name, text) => text;
const ctx = {
  mode: "tui",
  model: { provider: "fake", id: "idle", contextWindow: 1000 },
  modelRegistry: {
    hasConfiguredAuth: () => true,
    async complete(_model, request) {
      modelCalls += 1;
      const prompt = request.messages[0].content[0].text;
      if (!prompt.includes('"tasks":[]')) {
        throw new Error(`idle prompt omitted idle fleet state: ${prompt}`);
      }
      return {
        content: [{ type: "text", text: '{"summary":"Waiting for new work","percent":100}' }],
      };
    },
  },
  ui: {
    theme: { fg: identity, bold: (text) => text },
    setWidget(id, value) {
      widgetWrites.push({ id, value });
    },
  },
};

mod.default(pi);
await handlers.get("session_start")({}, ctx);
await waitFor("idle AI estimate to render", () =>
  widgetWrites.some((write) => Array.isArray(write.value) && write.value.join("\n").includes("Waiting for new work")),
);
if (modelCalls < 1) throw new Error("idle state did not ask the model for an explanation");
await handlers.get("session_shutdown")({}, ctx);
await settle(50, "confirm idle ticker stopped");
if (snapshotCalls < 1) throw new Error("idle state did not refresh authoritative fleet state");
EOF
)
status=$?
expect_node_ok "$status" "$out" "Pi live status extension must ask AI to explain idle state"
pass "Pi live status extension explains idle state with AI"

out=$(PLUGIN="$PLUGIN" FM_STATE_OVERRIDE="$STATUS_STATE" FM_LIVE_STATUS_INTERVAL_MS=30 node --input-type=module 2>&1 <<'EOF'
import { pathToFileURL } from "node:url";

const { settle, waitFor } = await import(pathToFileURL(process.env.FM_TEST_WAIT_FOR).href);
const mod = await import(pathToFileURL(process.env.PLUGIN).href);

const handlers = new Map();
const widgetWrites = [];
let modelCalls = 0;
let activeModelCalls = 0;
let maxConcurrentModelCalls = 0;
let snapshotCalls = 0;

const pi = {
  on(name, handler) {
    handlers.set(name, handler);
  },
  async exec() {
    snapshotCalls += 1;
    return {
      code: 0,
      stdout: JSON.stringify({
        backlog: { records: [] },
        tasks: [
          { id: "done-a1", current_state: { state: "done", detail: "checks green" }, backlog: { title: "Done task" } },
          { id: "fail-b2", current_state: { state: "failed", detail: "test failed" }, backlog: { title: "Failed task" } },
        ],
      }),
      stderr: "",
    };
  },
};

const identity = (_name, text) => text;
const ctx = {
  mode: "tui",
  model: { provider: "fake", id: "slow", contextWindow: 1000 },
  modelRegistry: {
    hasConfiguredAuth: () => true,
    complete(_model, _request, options) {
      modelCalls += 1;
      activeModelCalls += 1;
      maxConcurrentModelCalls = Math.max(maxConcurrentModelCalls, activeModelCalls);
      return new Promise((_resolve, reject) => {
        options.signal.addEventListener("abort", () => {
          activeModelCalls -= 1;
          reject(new Error("aborted"));
        }, { once: true });
      });
    },
  },
  ui: {
    theme: { fg: identity, bold: (text) => text },
    setWidget(id, value) {
      widgetWrites.push({ id, value, at: Date.now() });
    },
  },
};

mod.default(pi);
await handlers.get("session_start")({}, ctx);
await waitFor("several visible refreshes while AI is slow", () => snapshotCalls >= 3 && widgetWrites.length >= 3);
await settle(80, "confirm no overlapping slow AI calls are alive");
if (maxConcurrentModelCalls > 1) {
  throw new Error(`model calls overlapped: ${maxConcurrentModelCalls}`);
}
if (!widgetWrites.some((write) => Array.isArray(write.value) && write.value.join("\n").includes("0 active, 2 terminal"))) {
  throw new Error(`terminal tasks were not counted separately: ${JSON.stringify(widgetWrites)}`);
}
if (modelCalls < 2) throw new Error("AI calls were not retried after timeout");
await handlers.get("session_shutdown")({}, ctx);
EOF
)
status=$?
expect_node_ok "$status" "$out" "Pi live status extension must keep refreshing while AI is slow"
pass "Pi live status extension keeps ticker visible while AI is slow"

out=$(PLUGIN="$PLUGIN" FM_STATE_OVERRIDE="$STATUS_STATE" FM_LIVE_STATUS_INTERVAL_MS=30 node --input-type=module 2>&1 <<'EOF'
import { pathToFileURL } from "node:url";

const { settle, waitFor } = await import(pathToFileURL(process.env.FM_TEST_WAIT_FOR).href);
const mod = await import(pathToFileURL(process.env.PLUGIN).href);

const handlers = new Map();
const widgetWrites = [];
let modelCalls = 0;
let snapshotCalls = 0;

const pi = {
  on(name, handler) {
    handlers.set(name, handler);
  },
  async exec() {
    snapshotCalls += 1;
    return {
      code: 0,
      stdout: JSON.stringify({
        backlog: {
          records: [
            { id: "secret-a1", state: "in_flight", title: "Read /home/nikita/app/.env OPENAI_API_KEY=sk-titleSecret123" },
          ],
        },
        tasks: [
          {
            id: "secret-a1",
            current_state: { state: "working", raw: "Bearer abc.def.ghi in /Users/nikita/src/app SESSION=secretcookie" },
            hints: { last_event_text: "ghp_hidden1234567890" },
          },
        ],
      }),
      stderr: "",
    };
  },
};

const identity = (_name, text) => text;
const ctx = {
  mode: "tui",
  model: { provider: "fake", id: "redact", contextWindow: 1000 },
  modelRegistry: {
    hasConfiguredAuth: () => true,
    async complete(_model, request) {
      modelCalls += 1;
      const prompt = request.messages[0].content[0].text;
      for (const leaked of ["/home/nikita", "/Users/nikita", "sk-titleSecret123", "abc.def.ghi", "secretcookie", "ghp_hidden1234567890"]) {
        if (prompt.includes(leaked)) throw new Error(`prompt leaked ${leaked}: ${prompt}`);
      }
      if (!prompt.includes("[path]") || !prompt.includes("[redacted")) throw new Error(`prompt lost redaction markers: ${prompt}`);
      return { content: [{ type: "text", text: '{"summary":"Reading redacted status","percent":40}' }] };
    },
  },
  ui: {
    theme: { fg: identity, bold: (text) => text },
    setWidget(id, value) {
      widgetWrites.push({ id, value });
    },
  },
};

mod.default(pi);
await handlers.get("session_start")({}, ctx);
await waitFor("redacted status prompt to be checked", () => modelCalls >= 1);
await handlers.get("session_shutdown")({}, ctx);
await settle(50, "confirm redaction test stopped");
EOF
)
status=$?
expect_node_ok "$status" "$out" "Pi live status extension must redact model prompts"
pass "Pi live status extension redacts model prompt status"

out=$(PLUGIN="$PLUGIN" FM_STATE_OVERRIDE="$STATUS_STATE" FM_LIVE_STATUS_INTERVAL_MS=30 node --input-type=module 2>&1 <<'EOF'
import { pathToFileURL } from "node:url";

const { settle, waitFor } = await import(pathToFileURL(process.env.FM_TEST_WAIT_FOR).href);
const mod = await import(pathToFileURL(process.env.PLUGIN).href);

const handlers = new Map();
const widgetWrites = [];
const resolvers = [];
let session = "old";
let modelCalls = 0;

const pi = {
  on(name, handler) {
    handlers.set(name, handler);
  },
  async exec() {
    return {
      code: 0,
      stdout: JSON.stringify({
        backlog: { records: [] },
        tasks: [{ id: session, current_state: { state: "working", detail: `${session} work` }, backlog: { title: `${session} task` } }],
      }),
      stderr: "",
    };
  },
};

const identity = (_name, text) => text;
const ctx = {
  mode: "tui",
  model: { provider: "fake", id: "generation", contextWindow: 1000 },
  modelRegistry: {
    hasConfiguredAuth: () => true,
    complete() {
      modelCalls += 1;
      return new Promise((resolve) => resolvers.push(resolve));
    },
  },
  ui: {
    theme: { fg: identity, bold: (text) => text },
    setWidget(id, value) {
      widgetWrites.push({ id, value });
    },
  },
};

mod.default(pi);
await handlers.get("session_start")({}, ctx);
await waitFor("old session model call to start", () => resolvers.length >= 1);
session = "new";
await handlers.get("session_start")({}, ctx);
await waitFor("new session model call to start", () => resolvers.length >= 2);
resolvers[0]({ content: [{ type: "text", text: '{"summary":"STALE OLD SESSION","percent":9}' }] });
await settle(80, "give stale AI callback a chance to render");
if (widgetWrites.some((write) => Array.isArray(write.value) && write.value.join("\n").includes("STALE OLD SESSION"))) {
  throw new Error(`stale AI callback rendered after reload: ${JSON.stringify(widgetWrites)}`);
}
resolvers[1]({ content: [{ type: "text", text: '{"summary":"Fresh new session","percent":60}' }] });
await waitFor("new session result to render", () =>
  widgetWrites.some((write) => Array.isArray(write.value) && write.value.join("\n").includes("Fresh new session")),
);
await handlers.get("session_shutdown")({}, ctx);
if (modelCalls < 2) throw new Error("reload did not start a new AI request");
EOF
)
status=$?
expect_node_ok "$status" "$out" "Pi live status extension must ignore stale AI callbacks"
pass "Pi live status extension ignores stale AI callbacks"

out=$(PLUGIN="$PLUGIN" FM_STATE_OVERRIDE="$STATUS_STATE" FM_LIVE_STATUS_INTERVAL_MS=30 node --input-type=module 2>&1 <<'EOF'
import { pathToFileURL } from "node:url";

const { settle, waitFor } = await import(pathToFileURL(process.env.FM_TEST_WAIT_FOR).href);
const mod = await import(pathToFileURL(process.env.PLUGIN).href);

const handlers = new Map();
const widgetWrites = [];
let modelCalls = 0;
let snapshotCalls = 0;

const pi = {
  on(name, handler) {
    handlers.set(name, handler);
  },
  async exec() {
    snapshotCalls += 1;
    return {
      code: 0,
      stdout: JSON.stringify({
        backlog: { records: [] },
        tasks: [{ id: "hung", current_state: { state: "working", detail: `cycle ${snapshotCalls}` }, backlog: { title: "Hung model" } }],
      }),
      stderr: "",
    };
  },
};

const identity = (_name, text) => text;
const ctx = {
  mode: "tui",
  model: { provider: "fake", id: "hung", contextWindow: 1000 },
  modelRegistry: {
    hasConfiguredAuth: () => true,
    complete() {
      modelCalls += 1;
      return new Promise(() => {});
    },
  },
  ui: {
    theme: { fg: identity, bold: (text) => text },
    setWidget(id, value) {
      widgetWrites.push({ id, value });
    },
  },
};

mod.default(pi);
await handlers.get("session_start")({}, ctx);
await waitFor("hung provider slot to be released for another AI attempt", () => modelCalls >= 2, { timeoutMs: 1200 });
if (snapshotCalls < 2 || widgetWrites.length < 2) {
  throw new Error(`ticker froze while provider hung: snapshots=${snapshotCalls} writes=${widgetWrites.length}`);
}
await handlers.get("session_shutdown")({}, ctx);
await settle(50, "confirm hung-provider test stopped");
EOF
)
status=$?
expect_node_ok "$status" "$out" "Pi live status extension must recover from hung AI providers"
pass "Pi live status extension recovers from hung AI providers"
