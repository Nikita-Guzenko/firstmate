---
name: fleet-runtime
description: >-
  Agent-only canonical runtime playbook for firstmate home layout, session-start recovery, and live supervision.
  Load after session start when work is in flight, before handling any wake, or whenever runtime state/layout details are needed.
user-invocable: false
metadata:
  internal: true
---

# fleet-runtime

This skill owns the conditional runtime detail referenced by `AGENTS.md` sections 2, 3, 5, and 8.
Load it after the mandatory session-start command when direct reports are present, before handling any wake, or when home/state layout details are needed.

## 2. Layout and state

`FM_HOME` selects the operational home.
Unset, most scripts use this repo root as the home (today's behavior); set, scripts still use their own `bin/` but take `state/`, `data/`, `config/`, and `projects/` from `$FM_HOME`.
Compatible overrides remain: `FM_STATE_OVERRIDE` points at a custom state dir, and `FM_ROOT_OVERRIDE` behaves like the old whole-root override when `FM_HOME` is unset.
`bin/fm-send.sh` is the fail-closed exception: it requires `FM_HOME` set so target resolution is always scoped to an explicit home.
Each secondmate gets its own persistent `FM_HOME`, isolating its state, backlog, projects, and lock from the main firstmate.

```
AGENTS.md            this file (CLAUDE.md is a symlink to it)
CONTRIBUTING.md      contributor workflow and repo conventions
README.md            public overview and development notes
.github/workflows/   shared CI and PR enforcement, committed
.tasks.toml          tasks-axi backend config for the default backlog (section 10)
.agents/skills/      firstmate-loaded internal skills, committed; metadata.internal=true for installers
.claude/skills       symlink to .agents/skills for claude compatibility
skills/              public installer-facing skills, committed; NOT loaded by firstmate
bin/                 helper scripts, committed; read each script's header before first use
.env                 optional X-mode pairing token; LOCAL; presence-gates section 14
config/              LOCAL, gitignored knobs: crew-harness, crew-dispatch.json, secondmate-harness (section 4); backlog-backend (section 10); backend, cmux-socket-password; x-mode.env (section 14). Per-file semantics: docs/configuration.md
data/                personal fleet records; LOCAL, gitignored
  backlog.md         task queue (section 10)
  captain.md         captain's preferences and working style; LOCAL; canonical over harness memory; inspect-then-update
  learnings.md       fleet-local operational facts and gotchas; LOCAL; dated, evidence-backed, curated, inspect-then-update; created lazily, absent until this home has a learning
  projects.md        thin project navigation registry (section 6)
  secondmates.md     secondmate routing table (section 6)
  <id>/brief.md      per-task crewmate brief, or charter brief when kind=secondmate
  <id>/report.md     scout deliverable, written by the crewmate; survives teardown
projects/            cloned repos; gitignored; READ-ONLY for you
state/               volatile runtime signals; gitignored
  <id>.status        crewmate-appended "<state>: <note>" wake events, not current-state truth
  <id>.turn-ended    touched by turn-end hooks
  <id>.meta          written by fm-spawn: window=, worktree=, project=, harness=, model=, effort=, kind=, mode=, yolo=, tasktmp=; kind=secondmate adds home=, projects=; a non-default backend adds backend fields (bin/fm-backend.sh; docs/configuration.md "Runtime backend"); fm-pr-check/-merge append pr=/pr_head=; fm-x-link appends x_* (section 14)
  <id>.check.sh      optional per-task slow poll you write (e.g. merged-PR check)
  .wake-queue        durable queued wakes
  .afk               away-mode flag (section 8 away-mode stub)
  .last-watcher-beat watcher liveness beacon, touched every poll
  (x-*, <id>.grok-turnend-token, .watch*.lock, .watch-triage.log, and .hash-*/.stale-*/.wedge-*/.subsuper-*/.supervise-daemon.* are X-mode, watcher, and sub-supervisor internals - never touch; see docs/architecture.md and section 14)
.no-mistakes/        local validation state and evidence; gitignored
```

The shell working directory persists between commands, so after any `cd` away from the home, invoke `bin/` scripts by absolute path; they self-locate internally.
Task ids are short kebab slugs with a random suffix, e.g. `fix-login-k3`.
For tmux the task window is `fm-<id>`; per-backend window/tab naming for herdr, zellij, orca, and cmux lives in docs/configuration.md ("Runtime backend") and each backend's own doc.

## 3. Session start (run at every session start)

Session start is one command: `bin/fm-session-start.sh`.
It composes `fm-lock.sh`, `fm-bootstrap.sh`, and `fm-wake-drain.sh` as real subprocesses and prints one ordered, delimited report:

1. **Lock** - acquires the per-home session lock before anything mutates shared state.
2. **Bootstrap** - detect-only diagnostics (tools/versions, GitHub auth, worktree-tangle, harness override, dispatch-profile validation, backlog-backend) always run and print; the four MUTATING sweeps (fleet sync, local secondmate fast-forward, secondmate liveness, X-mode artifacts) run only when this session holds the lock.
3. **Wake queue** - when locked, drains the durable wake queue and prints it as this turn's first work queue.
4. **Context digest** - full `data/projects.md`, `data/secondmates.md`, `data/captain.md`, and `data/learnings.md`, each delimited; a missing file prints an explicit `ABSENT` marker (absence is meaningful, never confused with empty-but-present).
5. **Fleet-state digest** - full `data/backlog.md`; every `state/<id>.meta`; a bounded tail of each `state/<id>.status` (wake-EVENT history, not current state, with the full log path for a deeper read); the `state/.afk` flag; and one cheap alive/dead read of each task's backend endpoint.
6. **Supervision block** - emits exactly one operating block for the detected primary harness, which owns the exact wait or wake mechanism; the script itself never starts supervision.

**Everything in this digest is read exactly once.**
Do not separately run those three scripts, and do not re-read `data/projects.md`, `data/secondmates.md`, `data/captain.md`, `data/learnings.md`, `data/backlog.md`, or any `state/*.meta` or `state/*.status` afterward - they were just printed in full.
Re-read a file only if the digest flagged it `ABSENT` (then rebuild or create it per this section and section 6), if it looked corrupt, or for older wake-event history in an individual status log.
This does not block a targeted current-state read immediately before a workflow writes one of these files (such as `/stow`'s inspect-then-update pass or a backlog mutation).

If the lock could not be acquired, the digest prints a loud, bordered read-only banner: another live session holds the fleet, every mutating step was skipped, and only the read-only-safe subset above is shown.
Tell the captain another session is managing the work and operate read-only - do not spawn, steer, merge, or otherwise mutate fleet state.

Bootstrap is detect, then consent, then install; never install anything the captain has not approved this session.
The mutating sweeps are best-effort and non-fatal: fleet sync (`bin/fm-fleet-sync.sh`, `FM_FLEET_PRUNE=0` disables branch pruning), the local secondmate fast-forward that converges every live secondmate home's worktree onto firstmate's own current default-branch commit, and inheritable-config propagation of `config/crew-dispatch.json`, `config/crew-harness`, and `config/backlog-backend` into each live secondmate home.
All of this is purely local fast-forward/config copy that never touches the gitignored operational dirs; a dirty, diverged, or in-flight home is skipped untouched.
For a mid-session inheritable-config push without a full session start, run `bin/fm-config-push.sh` (config-only, does not fast-forward tracked files or nudge secondmates).
The sweep prints `NUDGE_SECONDMATES:` only when a running secondmate advanced with an instruction-surface change (`AGENTS.md`, `bin/`, or `.agents/skills/`), so you know which to live-converge.
Silence in the bootstrap section means all good.
If the digest prints any diagnostic line - `MISSING`, `NEEDS_GH_AUTH`, `TANGLE`, `CREW_HARNESS_OVERRIDE`, `CREW_DISPATCH`, `FLEET_SYNC`, `SECONDMATE_SYNC`, `SECONDMATE_LIVENESS`, `TASKS_AXI`, `NUDGE_SECONDMATES`, or `FMX` - load `session-start-handling`.

Treat harness memory of captain preferences as a recall cache; `data/captain.md` is canonical.
If `data/projects.md` is `ABSENT` or disagrees with what is under `projects/`, rebuild it from the clones (a README skim each) before taking on work.
An `ABSENT` `captain.md`, `secondmates.md`, or `learnings.md` means template defaults, no secondmates, or nothing captured yet - not a problem to fix.

Do not dispatch work until the tools it needs are present and GitHub auth is good.
Use `gh-axi` for GitHub, `chrome-devtools-axi` for browser, and `lavish-axi` for a rich review surface; their `--help` and session hooks are the source of truth, not memorized flags.
A captain's static crewmate-harness choice goes in `config/crew-harness`; a standing dispatch preference goes in `config/crew-dispatch.json`.

## 5. Recovery (run at every session start, after the digest)

You may have been restarted mid-flight.
Reconcile from the `bin/fm-session-start.sh` digest - its lock step, wake drain, and fleet-state digest ARE recovery's data-gathering; do not re-run it or bulk-read its inputs:

1. Act on the digest's lock status (locked vs read-only) exactly as section 3 describes.
2. Keep the digest's drained wake records as the first work queue for this recovery turn.
3. Treat the digest's status tails as wake-event history; for a live current-state read of a direct report, use `bin/fm-crew-state.sh <id>`, not the last status line.
4. Use `window=` from each `state/*.meta` as the live direct-report set and the digest's per-task `endpoint: alive|dead` line - do not re-probe. Do not sweep every backend window/tab across all sessions; another home's endpoints share the namespace and are not your orphans.
5. For a meta with no `window=` or a dead endpoint, reconcile by kind: ordinary crewmates via recorded backend metadata (`treehouse status`, or recorded `orca_worktree_id=`/`terminal=`); for `kind=secondmate`, load `secondmate-provisioning` and respawn from meta or the registry. Do not reconstruct a secondmate's tree from the main home - the main firstmate reconciles only direct reports, and each secondmate reconciles only its own work in its own home.
6. If `state/.afk` is present, load `/afk`, ensure the daemon is running (it owns the watcher - do not separately arm), and resume away-mode.
7. Surface only what needs the captain (decisions, PRs to merge, failures, credentials); otherwise say nothing and resume via the emitted supervision block.

A firstmate restart must be a non-event.
All truth lives in each task's backend live-task inventory, state files, `data/*`, persistent secondmate homes, treehouse, and Orca's recorded ids; your conversation memory is a cache.

## 8. Supervision protocol

The watcher is the backbone.
Whenever at least one task is in flight, keep exactly one live supervision wait owned by the emitted primary-harness protocol from `bin/fm-session-start.sh` - the only per-harness recipe in context; never substitute another harness's command shape.

**Always-on wake triage.**
`bin/fm-watch.sh` classifies every wake in bash and absorbs the benign majority (a provably-working crewmate, a no-change heartbeat) without waking you, writing to `state/.wake-queue` only on an actionable wake (a captain-relevant verb, a `check`, a not-provably-working stale pane, a wedged provably-working pane, or the heartbeat backstop).
So you resume once per actionable event, not per wake.
The absorb logic (provably-working predicate, wedge counters, classifier, away-mode fallback) is mechanism in docs/architecture.md "Event-driven supervision" and the `fm-watch.sh`/`fm-crew-state.sh`/`fm-classify-lib.sh` headers.

**Drain first.**
At the start of every wake-handling turn, run `bin/fm-wake-drain.sh` before peeking panes, reading beyond the reason line, or starting new work.
Session-start recovery is the exception: the digest already drained (or skipped it, read-only).
The drained queue is the lossless backlog; the reason line is a hint.

**Keep exactly one live cycle.**
While any task is in flight, the active protocol must maintain one wait that wakes this primary on an actionable reason; resume it after handling drained wakes, before ending the turn.
Never use shell `&` as a substitute for a verified harness wake mechanism.
The watcher is singleton-safe (race-proof acquisition; a duplicate self-evicts within one poll).
If the arm wrapper attaches to an existing healthy watcher, do not start another; if it reports failure, drain queued wakes then repair per the emitted block.

**No turn ends blind, holds included.**
Never end a turn with a task in flight and no live supervision - a text-only "holding" or "waiting" reply with crewmates live is a bug that the script-only guard cannot catch, so this discipline must.
For a genuine forced restart use `bin/fm-watch-arm.sh --restart` (signals only this home's watcher); never `pkill -f bin/fm-watch.sh`, which matches every home's watcher, including secondmates.
While `state/.afk` exists the daemon owns the watcher.
Waiting is intentionally silent: after starting the wait, send no idle progress updates; wait for `signal`, `stale`, `check`, or `heartbeat` unless the captain asks.
Empty polls and elapsed time are bookkeeping, not conversational progress.

```sh
bin/fm-supervision-instructions.sh  # render the current harness block or one-line repair text
bin/fm-watch-arm.sh [--restart]     # verified arm wrapper; --restart is home-scoped, never a broad pkill
bin/fm-watch-checkpoint.sh          # bounded foreground checkpoint for Codex-style protocols
bin/fm-watch.sh                     # the watcher; exits signal|stale|check|heartbeat
bin/fm-wake-drain.sh                # drain queued wakes at turn start; asserts guard
bin/fm-crew-state.sh <id>           # one-line current-state read
bin/fm-fleet-view.sh                # read-only whole-fleet Markdown view
```

On wake, cheapest first:

1. Read the reason line and drain with `bin/fm-wake-drain.sh`.
2. `signal:` read the listed status files first (~30 tokens each, usually enough); a wake lists every signal in the coalescing window. A status line is the wake event, not current state - confirm a `needs-decision`/`blocked` is still real with `bin/fm-crew-state.sh <id>`, never `tail` the status log as current state.
3. `stale:` the crewmate stopped without reporting - peek the pane (`bin/fm-peek.sh <window>`). If the reason includes `demand-deep-inspection`, inspect the pane, `fm-crew-state.sh`, and validation logs first. If the pane is waiting/looping/confused/unresponsive, load `stuck-crewmate-recovery`.
4. `check:` a per-task poll fired (merge, or X mode) - act on it.
5. `heartbeat:` reaches you only when the bash fleet-scan caught a captain-relevant status the per-wake path missed - treat it as "something turned up" and review the whole fleet (`bin/fm-fleet-view.sh` first, `fm-crew-state.sh` for follow-up, peek panes that look off, check PR-ready tasks, reconcile the backlog), then resume. Never report the fleet is unchanged.

When a task reaches a terminal state (a `done`/merge `check:`, a `failed` signal, a scout report, a local-only merge) and X mode is on, load `fmx-respond` and post the mention's **final** completion follow-up if the task is X-linked (`bin/fm-x-followup.sh --check <id>` then `bin/fm-x-followup.sh <id> --final --text-file <path>`), so the link clears regardless of earlier milestones.
When any wake reports a merged PR naming a project also cloned here under `projects/`, run `bin/fm-fleet-sync.sh <project-name>`.

Heartbeats back off exponentially while they are the only wakes firing (600s doubling to a 2h cap); any signal/stale/check resets to the base interval.
Due per-task checks run before signal scanning so chatty status cannot starve slow polls like merge detection.
When a heartbeat does reach you, whole-fleet review is mandatory.
Each task's backend live-task inventory is ground truth (tmux by default; meta may record another `backend=`).
For `kind=secondmate` an idle pane is healthy (it may sit on its own watcher), so `fm-watch.sh` skips stale-pane wakes for secondmate windows; ordinary crewmates still trip stale detection.

**Guard banners.**
The supervision scripts and `bin/fm-wake-drain.sh` call `bin/fm-guard.sh`, which prints a bordered ●-banner when supervision has lapsed - pending queued wakes, a stale liveness beacon (`state/.last-watcher-beat` beyond `FM_GUARD_GRACE`), or the primary checkout stranded on a non-default branch (a worktree tangle).
The banner is only a warning; the guarded operation still runs.
Act on it: drain pending wakes first; on stale liveness, drain then resume the emitted protocol; on a tangle, restore with the printed `git -C <root> checkout <default>`.
A tracked turn-end hook (`bin/fm-turnend-guard.sh`) adds a push-based backstop that blocks or forces one bounded follow-up turn when work is in flight without a live watcher.
Mechanism: docs/architecture.md, docs/turnend-guard.md, and the guard headers.

Token discipline: prefer `bin/fm-crew-state.sh <id>` for current state; default peeks to 40 lines; never stream a pane repeatedly; batch what you tell the captain.
Ignore the context-% in a peek; intervene only on real signals (`signal`/`stale`/`needs-decision`/`blocked`), looping or confusion, or a brief-answered question.

### Away-mode stub

Invoke `/afk` when the captain says `/afk` or that they are going afk, `state/.afk` exists, an incoming message starts with `FM_INJECT_MARK`, or any `state/.subsuper-*` marker is involved.
The skill owns the full daemon (classification, batching, injection hardening, max-defer, verified submit, marker stripping, lock, dedupe, target discovery, `FM_INJECT_SKIP`).
Facts that must survive with no skill loaded:

- Every daemon injection is prefixed with `FM_INJECT_MARK` (ASCII unit separator `0x1f`), distinguishing an internal escalation from a captain message.
- While `state/.afk` exists the daemon owns the watcher; do not separately arm it.
- A marked message while afk is an internal escalation: stay afk and process it. A message starting with `/afk`: stay afk, refresh the flag. Any other unmarked message means the captain is back: clear `state/.afk`, stop the daemon, flush catch-up from `state/.wake-queue` and the subsuper markers, then resume the emitted protocol.
- Afk never changes approval authority (PR merges, ask-user findings, destructive/irreversible/security-sensitive choices need the same approval as before).
- Bias ambiguous cases toward exit: a present captain beats token savings, and a false exit self-corrects.

### Stuck-crewmate recovery

On `stale`, looping, repeated confusion, a brief-answered question, an unresponsive pane, or a failed steer, load `stuck-crewmate-recovery` (it escalates peek -> one-line steer -> harness interrupt -> relaunch with a progress note -> `failed` with evidence).
