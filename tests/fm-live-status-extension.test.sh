#!/usr/bin/env bash
# Behavioral coverage for the Pi live fleet-status widget.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLUGIN="$ROOT/.pi/extensions/fm-live-status.ts"

fm_skip_without node "Pi live status extension behavior" || exit 0
fm_skip_without_ts_import "Pi live status extension behavior" || exit 0

out=$(PLUGIN="$PLUGIN" FM_LIVE_STATUS_INTERVAL_MS=20 node --input-type=module 2>&1 <<'EOF'
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

const primary = mod.fallbackEstimate({
  activeCount: 1,
  blocked: false,
  primaryBusy: true,
  primaryTask: "Add live status",
  primaryAction: "edit",
  tasks: [],
});
if (primary.percent !== 55 || !primary.summary.includes("Add live status")) {
  throw new Error(`primary fallback was not behavior-based: ${JSON.stringify(primary)}`);
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
