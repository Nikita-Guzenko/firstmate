---
name: session-start-handling
description: Agent-only reference for resolving session-start bootstrap diagnostic lines. Use when the session-start digest prints any diagnostic line - MISSING, NEEDS_GH_AUTH, TANGLE, CREW_HARNESS_OVERRIDE, CREW_DISPATCH, FLEET_SYNC, SECONDMATE_SYNC, SECONDMATE_LIVENESS, TASKS_AXI, NUDGE_SECONDMATES, or FMX - to handle each one correctly.
user-invocable: false
metadata:
  internal: true
---

# session-start-handling

Load this when the session-start digest (`bin/fm-session-start.sh`, AGENTS.md section 3) prints one or more bootstrap diagnostic lines.
Silence in the bootstrap section means all good: say nothing and move on.
Otherwise the digest prints one line per problem or capability fact.
Handle each per the procedure below.

Bootstrap is detect, then consent, then install.
Never install anything the captain has not approved in this session.

- `MISSING: <tool> (install: <command>)` - list the missing tools to the captain with a one-line purpose each plus the printed install commands, wait for consent (one approval may cover the list), then run `bin/fm-bootstrap.sh install <approved tools...>`.
  For `treehouse`, this also covers an installed version whose `treehouse get` lacks `--lease`; treat it as an upgrade request.
  For `no-mistakes`, this also covers an installed version older than 1.31.2, because crewmate validation briefs delegate gate mechanics to no-mistakes' version-matched guidance.
  For `tasks-axi`, this also covers an installed build whose `tasks-axi --version` is older than 0.1.1 or whose `tasks-axi update --help` lacks `--archive-body`; `config/backlog-backend=manual` only suppresses the `TASKS_AXI: available` capability line, not this missing-tool report.
  For `quota-axi`, bootstrap requires it because crew-dispatch `quota-balanced` may call it; `bin/fm-dispatch-select.sh` still degrades at runtime when quota data is unavailable.
- `NEEDS_GH_AUTH` - ask the captain to run `! gh auth login` (interactive; you cannot run it for them).
- `TANGLE: <remediation>` - the primary checkout is stranded on a feature branch instead of its default branch; section 8 explains why this guard exists and what it protects.
  The work is safe on that branch ref; restore the primary to its default branch with the printed `git -C <root> checkout <default>`, then re-validate that branch in a proper worktree.
  This is the only sanctioned firstmate-initiated git write to the primary, and it is a non-destructive branch switch that strands nothing.
- `CREW_HARNESS_OVERRIDE: <name>` - record and use the override silently; surface a harness fact only if it actually blocks work or the captain asks.
- `CREW_DISPATCH: invalid config/crew-dispatch.json - <reason>` - the optional dispatch profile file exists but failed low-cost bootstrap validation; continue with the normal fallback chain, resolve and pass the chosen fallback harness explicitly while the file remains present, fix the malformed schema, unverified harness name, unknown selector, or invalid harness/effort pair when convenient, and do not select a bad profile.
- `CREW_DISPATCH: active config/crew-dispatch.json` - bootstrap validated the optional dispatch profile file and printed its active rules and `default:` when present.
  Keep this block top-of-mind during intake; it is the reminder that every crewmate or scout dispatch must consult the rules before spawning.
- `FLEET_SYNC: <repo>: skipped: <reason>` - a benign one-off skip (offline, no origin, local-only); bootstrap continued, investigate only if it blocks work.
- `FLEET_SYNC: <repo>: recovered: <detail>` - the clone had drifted onto a clean detached HEAD holding no unique commits and the sync self-healed it (re-attached the default branch and fast-forwarded); no action needed, it is reported only so the self-heal is visible.
- `FLEET_SYNC: <repo>: STUCK: on <state>, N commits behind <base> - needs attention` - the clone is dirty, on a non-default branch, detached with unique commits, or diverged, so the sync left it untouched (never forcing or discarding); it will keep falling behind until you look. A loud STUCK, especially a growing N across bootstraps, means that clone needs hands-on attention; dispatch a crewmate or resolve it before it strands work.
- `SECONDMATE_SYNC: secondmate <id>: skipped: <reason>` - the local-HEAD secondmate sync left a live secondmate home on its existing checkout because the home was dirty, diverged, unsafe, on the wrong branch, missing the primary target commit, or otherwise not fast-forwardable; bootstrap continued, but inspect the reason because the secondmate may be stale after a primary update.
- `SECONDMATE_LIVENESS: secondmate <id>: already-live|respawned|skipped: <reason>|respawn failed: <reason>` - the session-start liveness sweep checked a live secondmate's recorded endpoint for a real agent process.
  Treat `already-live` and `respawned` as handled; investigate `skipped` or `respawn failed` because that secondmate is not guaranteed live.
- `TASKS_AXI: available` - a default-backend capability fact, not a problem; record it silently and use section 10 for backlog mutations.
  It prints only when `config/backlog-backend` is absent or set to `tasks-axi` and the compatibility probe accepts `tasks-axi --version` as 0.1.1 or newer plus `tasks-axi update --help` exposing `--archive-body`.
  If the backend is not opted out and `tasks-axi` is missing or incompatible, bootstrap reports `MISSING: tasks-axi (install: npm install -g tasks-axi)` but still falls back to hand-editing and never blocks work.
  If `config/backlog-backend=manual`, bootstrap hand-edits and does not suggest installing `tasks-axi`.
- `NUDGE_SECONDMATES: fm-<id>...` - the secondmate sweep fast-forwarded one or more *running* secondmate homes to firstmate's current version and their instruction surface (`AGENTS.md`, `bin/`, or `.agents/skills/`) actually changed; send a one-line re-read nudge with `FM_HOME=<this-firstmate-home> bin/fm-send.sh <id> 'firstmate was updated to the latest - please re-read your AGENTS.md to pick up the new instructions.'` unless `FM_HOME` is already set to the active firstmate home.
  This mirrors `/updatefirstmate`'s `nudge-secondmates:` report: it is a gentle steer, never an interruption, and the fast-forward already landed safely.
  A secondmate that was skipped, already current, or whose advance changed no instructions is not listed and must not be disturbed.
- `FMX: X mode on ...` / `FMX: X mode off ...` - bootstrap confirmed or removed the local X-mode poll artifacts; follow section 14 for watcher cadence restart only when a running watcher needs the transition applied immediately.

Bootstrap's fleet refresh is bounded by `FM_FLEET_SYNC_BOOTSTRAP_TIMEOUT` seconds when set, otherwise by a fleet-size-aware default with a 20 second floor; a timeout is reported as a `FLEET_SYNC` skip and does not block startup.
