---
name: task-lifecycle
description: >-
  Agent-only canonical project and task lifecycle for firstmate.
  Load before project registration or removal, task intake, backlog mutation, briefing, dispatch, validation, PR/local delivery, reporting, or teardown.
user-invocable: false
metadata:
  internal: true
---

# task-lifecycle

This skill owns the project, task, backlog, and brief contracts referenced by `AGENTS.md` sections 6, 7, 10, and 11.
Load it before any project registration or removal, project-specific investigation or change, backlog mutation, briefing, dispatch, validation, delivery, reporting, or teardown.

## 6. Project management

All projects live flat under `projects/`.

`data/projects.md` is the thin navigation registry - one line per project:

```markdown
- <name> [<mode>] - <one-line description> (added <date>)
```

It records name, delivery mode, optional `+yolo`, and description.
Add the line on clone/create, drop it on removal, and keep it a navigation aid - descriptive detail belongs in the project's own `AGENTS.md`, not here.

`data/secondmates.md` is the routing table - one line per secondmate:

```markdown
- <id> - <charter summary> (home: <absolute-home-path>; scope: <natural-language responsibility>; projects: <a>, <b>; added <date>)
```

`scope:` is used during intake; `projects:` is a non-exclusive clone list, not ownership.
Load `secondmate-provisioning` before creating, seeding, validating, launching, handing backlog to, recovering, pushing config into, or retiring a secondmate, and before editing `data/secondmates.md`; it owns leases, harness pins, rollback, validation, clone restrictions, handoff edges, charter copy, and teardown internals.

A secondmate is idle by default: it acts only on routed work.
On startup and restart it runs the normal digest and recovery solely to reconcile its own work, then waits silently; it must never self-initiate a survey, audit, or "find improvements" task, and an empty queue is a healthy resting state.
This idle contract is encoded in the charter brief (section 11) so it travels with the live secondmate.

**Hand off in-scope backlog on creation.**
When a secondmate is created, move existing main-backlog items under its scope into its home with `bin/fm-backlog-handoff.sh <secondmate-id> <item-key>...` (scope-matching is judgment against the natural-language scope, not keywords).
Do not hand off `local-only` items; that work stays with the main firstmate (section 7).

### Project memory ownership

Project-intrinsic knowledge (build, test, release, architecture conventions, sharp edges) belongs in the project's committed `AGENTS.md` (the real file, `CLAUDE.md` a symlink to it) and only when broadly useful; the canonical self-governance wording lives in `bin/fm-ensure-agents-md.sh`.
Fleet and captain-private knowledge (delivery mode, `+yolo`, in-flight work, strategy, go-live state, the registry line) belongs in firstmate's `data/`, never in the project.
This does not relax prime directive #1: firstmate never hand-writes project `AGENTS.md` (that would dirty the clone and bypass the gate); crewmates create and update them inside their worktrees, committed through delivery.
Create one lazily - the first ship task touching a project that lacks one and has durable knowledge runs `bin/fm-ensure-agents-md.sh` and commits both through the pipeline.

### Knowledge routing

Route each durable fact to its most specific home:

| Kind of knowledge | Home |
| --- | --- |
| Captain preferences and working style | `data/captain.md` (inspect-then-update) |
| Project-intrinsic knowledge | that project's `AGENTS.md`, via crewmate delivery |
| Fleet-local operational facts and gotchas | `data/learnings.md` (inspect-then-update) |
| Generalizable to every firstmate user | the shared `AGENTS.md`, via PR |
| Task-scoped notes | backlog item notes (section 10) |
| Investigation findings | scout reports at `data/<id>/report.md` |

On `/stow`, load the `stow` skill: it sweeps the session for uncaptured durable knowledge, routes it with this table, files undone next steps to the backlog, and reports whether the session is safe to reset.

**Delivery mode (choose at add).**
`<mode>` is how a finished change reaches `main` (parsed by `fm-project-mode.sh`, recorded into each task's meta):

- `no-mistakes` (default; `[...]` may be omitted) - full pipeline -> PR -> captain merge. Highest assurance.
- `direct-PR` - push + open a PR via `gh-axi`, no pipeline -> captain merge.
- `local-only` - local branch, no remote, no PR; firstmate reviews the diff, the captain approves, firstmate merges to local `main` (section 7).

Orthogonal optional `+yolo` (`[direct-PR +yolo]`), default off and not recommended: firstmate makes the approval decisions itself (section 7).
Default a new project to `no-mistakes` with yolo off; set a faster mode or `+yolo` only on the captain's explicit say-so.

**Clone existing:** `git clone <url> projects/<name>`, add the registry line, then initialize only if `no-mistakes`.
**Create new:** `no-mistakes` and `direct-PR` need a GitHub repo first (they push to `origin`); `local-only` needs no remote.
Creating a GitHub repo is outward-facing - get the captain's consent (propose name, owner/org, visibility default private, mode) and create with `gh-axi` only after confirmation, then clone and initialize if `no-mistakes`.
For `local-only`, create the local repo under `projects/<name>` and skip GitHub.
**Initialize (`no-mistakes` only):**

```sh
cd projects/<name> && no-mistakes init && no-mistakes doctor
```

`no-mistakes init` sets up the local gate (a bare repo plus post-receive hook, the `no-mistakes` remote, and a DB record; it needs an `origin` remote).
It vendors no skill and produces nothing to commit - a sanctioned exception to rule #1 only in that it runs git remote/config setup inside the project; touch nothing else.
`direct-PR` and `local-only` skip init entirely.
If `no-mistakes doctor` reports problems, fix the environment before dispatching work there.

## 7. Task lifecycle

### Intake

**Resolve the project first.**
The captain rarely names it and may juggle several across messages; resolve each message independently, never assuming the last-discussed one.
Signals in order: (1) an explicit name wins; (2) a clear follow-up inherits its referent's project; (3) else match content against `projects/` names, in-flight tasks, and the projects' own code/READMEs (read them - a feature, file, stack trace, or technology usually points at one); (4) one confident match - proceed but state the project in plain language so a wrong guess costs one correction; (5) more than one or none - ask a one-line question (a misdirected dispatch is recoverable but expensive; a question is cheap).

**Then resolve the secondmate scope.**
Compare the request to each `data/secondmates.md` `scope:` and route by the nature of the task, not the project name (a project may appear in several clone lists).
If the project is `local-only`, keep the work with the main firstmate even when a scope sounds relevant.
If a scope fits, steer that secondmate with one instruction via `FM_HOME=<this-home> bin/fm-send.sh <id> '<request>'` (unless `FM_HOME` is already this home) and let it run its own lifecycle.
`fm-send` is fail-closed (`FM_HOME` must be set; an unresolvable target exits non-zero rather than guessing): ids resolve first through this home's `state/<id>.meta`, and you pass an explicit backend target containing `:` only when intentionally addressing an endpoint outside this home.
A send to a `kind=secondmate` target auto-prepends a from-firstmate marker.
A marked request is returned via the secondmate's status file, or a doc under its home plus a status pointer, never only in chat - read it there as an ordinary status signal, do not peek its chat.
A captain typing directly into a secondmate window is unmarked and stays a conversational intervention.
Do not spawn a direct crewmate for secondmate-scope work unless the secondmate is blocked or the captain redirects.
If no scope fits, proceed in the main firstmate, or create a new secondmate with the captain when the domain should become persistent - then hand its in-scope queued items off with `bin/fm-backlog-handoff.sh` (section 6).

**Then classify the shape:**

- **Ship** (default): the deliverable is a change, shipped through the project's mode.
- **Scout:** the deliverable is knowledge - an investigation, plan, repro, or audit - ending in `data/<id>/report.md`, never a PR. "What's wrong", "how would we", "find out why" is a scout task; dispatch it, do not dig yourself.

**Then classify readiness:**

- **Dispatchable:** no overlap with in-flight tasks - dispatch now (no concurrency cap).
- **Blocked:** same files/subsystem as an in-flight task, or depends on an unmerged PR - record in `data/backlog.md` with `blocked-by: <id>` and tell the captain what is waiting and why. Scouts are read-mostly and rarely block.

Keep dependency judgment coarse: same repo plus overlapping area means serialize, else parallel.
For `no-mistakes` the pipeline rebase absorbs mild overlaps; other modes rebase before review or merge if needed.
Write the brief per section 11.

### Spawn

Load `harness-adapters` before spawning or recovering any direct report.

```sh
bin/fm-spawn.sh <id> projects/<repo>                       # active crew harness (when no crew-dispatch.json)
bin/fm-spawn.sh <id> projects/<repo> --harness codex [--model gpt-5.5] [--effort high]
bin/fm-spawn.sh <id> projects/<repo> codex                 # positional harness override
bin/fm-spawn.sh <id> projects/<repo> --backend tmux        # tmux is the verified reference backend (docs/tmux-backend.md)
bin/fm-spawn.sh <id> projects/<repo> --backend herdr|zellij|orca|cmux   # experimental; version/setup-gated (docs/<backend>-backend.md)
bin/fm-spawn.sh <id> projects/<repo> --scout               # scout task (kind=scout)
bin/fm-spawn.sh <id> [--secondmate | <firstmate-home> --secondmate]     # launch/recover a secondmate
bin/fm-spawn.sh <id1>=projects/<repo1> <id2>=projects/<repo2> [--scout] # batch
```

(codex-app is not a selectable backend; see docs/codex-app-backend.md.)
Batch by passing `id=repo` pairs; shared `--scout`/`--harness`/`--model`/`--effort`/`--backend` apply to all, looping is internal, and one failing pair still runs the rest and exits non-zero.
With `crew-dispatch.json` present, include a shared `--harness` after consulting the rules.

The script resolves harness and backend, records `state/<id>.meta`, and launches with the brief; resolution order, meta fields, workspace rules, the grok hook, and secondmate fast-forward/config propagation live in the `bin/fm-spawn.sh` header and docs/configuration.md.
Two facts stay here.
It asserts the worktree is a genuine isolated worktree distinct from the primary checkout, aborting otherwise (prevents the section 8 tangle); project worktrees start at detached HEAD on a clean default branch, so ship briefs tell the crewmate to create its branch while scout briefs keep the worktree scratch.
A backend spawn refusal (missing dependency, unauthenticated socket, version gate) is a blocker to surface - never silently retry on another backend.

After spawning, peek the endpoint to confirm the brief is processing and handle any trust dialog with `harness-adapters`.
Add the task to `data/backlog.md` under In flight.

### Supervise

Covered by section 8.
Steer with short single lines via `FM_HOME=<this-home> bin/fm-send.sh` (unless `FM_HOME` is already this home); anything long belongs in a file the crewmate reads.
Steer a secondmate the same way - its charter retargets escalation to the main firstmate's status file, so only `done`, `blocked`, `needs-decision`, `failed`, or captain-relevant phase changes wake you, and its answer comes back on that status/doc path (do not peek its chat).
A secondmate-reported merged PR is exactly the fleet-sync-on-merge case (section 8), since its own teardown never touches this home's separate clone.

### Delivery modes and yolo

A ship task's path from `done` to landed is set by `mode`; `yolo` decides who approves.
The Validate / PR-ready / Teardown stages below are the `no-mistakes` path; others diverge:

- **no-mistakes** - the stages as written: pipeline -> PR -> captain merge.
- **direct-PR** - no pipeline; the crewmate pushes and opens the PR itself and reports `done: PR <url>`. Skip Validate, go to PR ready; normal teardown check.
- **local-only** - no remote or PR; the crewmate stops at `done: ready in branch fm/<id>`. Review with `bin/fm-review-diff.sh <id>`, relay a one-paragraph summary, and on approval run `bin/fm-merge-local.sh <id>` (clean fast-forward only - else have the crewmate rebase). No `fm-pr-check`. Teardown then requires the branch merged into local `main` OR pushed to any remote (a fork counts).

Review any crewmate branch diff with `bin/fm-review-diff.sh <id>`, not raw `git diff`: pooled clones lag `origin`, so the helper compares against the authoritative base, and when meta records `pr=` also against the PR head (`pr_head=` or a fresh `refs/pull/<n>/head`) so fix rounds pushed to the PR are included (it warns and falls back to the local branch if the PR head cannot resolve).
In target projects, `.no-mistakes/evidence/` commits in a crew branch are the pipeline's own PR-viewable evidence, committed by design - do not strip, count against the change, or rebase them away.
Firstmate's own repo is the exception: its `.no-mistakes/` stays gitignored and CI rejects tracked `.no-mistakes` paths.

**yolo (orthogonal).**
`yolo=off` (default): every approval is the captain's - ask-user findings, PR merges, the local-only merge.
`yolo=on`: firstmate decides and merges green/approved work itself via `bin/fm-pr-merge.sh <id> <full PR URL>` / `bin/fm-merge-local.sh` - EXCEPT anything destructive, irreversible, or security-sensitive, which still escalates; never merge a red PR.
`bin/fm-pr-merge.sh` records `pr=`/`pr_head=` before merging, parses the full URL, and defaults to `--squash` (override after `--`) - always use it, never raw `gh-axi pr merge`, or teardown loses its merge-verification anchor.
After any merge you do without asking, post a one-line "merged <full PR URL or local main> after checks passed" FYI.

### Validate (`no-mistakes` ship tasks)

When the crewmate reports `done`, trigger validation using the crew harness from `state/<id>.meta` (load `harness-adapters` for the skill invocation form; natural language works too).
The crewmate drives the whole no-mistakes pipeline (review, test, document, lint, push, PR, CI) itself; the brief points to the version-matched SKILL.md via `/no-mistakes`, `no-mistakes axi run --help`, and per-response `help`, not restated mechanics.
Firstmate's wrapper stays narrow: `ask-user` findings return through `needs-decision`, captain decisions go back via `no-mistakes axi respond`, validation avoids `--yes`, and CI-green is reported as `done: PR {url} checks green` (owed when `/no-mistakes` first reports CI green, not after the merge loop).
Use chat for yes/no; lavish-axi for multiple findings.
Judge a validating crewmate by run-step status, not whether its shell runs: `bin/fm-crew-state.sh <id>` takes the matching run-step as truth and flags a stale status line superseded - never `tail` the status log as current state.
For the state-by-state reading and the self-fix red flag, load `stuck-crewmate-recovery`; `no-mistakes axi status` gives full findings.

### PR ready

Ready signal by mode: `no-mistakes` -> `done: PR <url> checks green`; `direct-PR` -> `done: PR <url>`.
Run `bin/fm-pr-check.sh <id> <PR url>` (records `pr=`/`pr_head=`, arms the merge poll).
Tell the captain the full `https://...` URL (never a bare `#number` - the captain's terminal makes a full URL clickable), a one-paragraph summary, and for `no-mistakes` the risk level.
(Any custom `state/<id>.check.sh` you write: print one line only when firstmate should wake, else nothing, and finish before `FM_CHECK_TIMEOUT`.)
If the captain says "merge it", run `bin/fm-pr-merge.sh <id> <full PR URL>` (that instruction is the approval); under `yolo=on`, merge green/approved work yourself the same way and post the FYI.
The helper defaults to `--squash`, accepts `-- --merge`/`-- --rebase`/`-- --method=merge`, and refuses `--repo`/`-R` (the repo is derived from the URL).

### Ship teardown (only after merge is confirmed)

```sh
bin/fm-teardown.sh <id>
```

The script refuses on uncommitted changes or committed work that has not landed; treat a refusal as stop-and-investigate.
"Landed" is broader than remote-reachable: for a normal ship task it also accepts a merged PR whose head contains the local work (local `HEAD` is the PR head, an ancestor of it, or has matching patch IDs after no-mistakes replayed the branch), or content already in the up-to-date default branch - so the common squash-merge-then-delete-branch flow tears down cleanly.
The PR comes from the recorded `pr=`, or, when none was recorded, by matching the worktree branch to a merged PR and fetching `refs/pull/<n>/head` if the branch is gone (covers a yolo merge that skipped `fm-pr-check`).
Genuinely unlanded work and dirty worktrees still refuse, and a gh lookup error falls back to the content check.
Benign external-PR case: commits reachable only on the contributor's fork - add the fork as a remote and fetch, then retry; never `--force`.
After a PR-based teardown it runs `bin/fm-fleet-sync.sh` for that project (safe clones catch up, the merged branch is pruned; unsafe drift reports `STUCK:` and is left untouched).
Then update the backlog per the teardown reminder (`tasks-axi done` when the default backend is active and compatible, else hand-edit Done with the full PR URL or local-merge note and date, keeping Done to 10).
Re-evaluate the queue and dispatch only work whose blockers are gone and whose date gate, if any, has arrived.

### Secondmate teardown (explicit only)

A secondmate is persistent; an empty queue does not trigger teardown.
Run `bin/fm-teardown.sh <id>` for `kind=secondmate` only when the captain or main firstmate explicitly retires it (load `secondmate-provisioning`).
The safety check is its own home: teardown refuses while its `state/*.meta` holds in-flight work.
`--force` is the explicit discard path for its windows, work, state, route, lease, and home - only on the captain's explicit say-so.

### Scout tasks (report instead of PR)

Scout follows Intake, Spawn, and Supervise as above (scaffold `bin/fm-brief.sh <id> <repo> --scout`, spawn `--scout`), then diverges:

- No Validate or PR-ready. On `done`, read `data/<id>/report.md`.
- Relay the findings (chat for a focused answer, lavish-axi for structure worth a visual).
- Tear down immediately: `bin/fm-teardown.sh` allows a scout worktree's scratch commits and dirty files once the report exists, and refuses if the report is missing (the findings are the product).
- Record in Done with the report path (`tasks-axi done` or hand-edit, keep 10), then re-evaluate the queue.

**Promotion.**
When a scout reveals shippable work and the captain wants it shipped, promote in place: `bin/fm-promote.sh <id>` (flips `kind=` to ship, restoring teardown protection), then steer the crewmate with `FM_HOME=<this-home> bin/fm-send.sh` to inventory scratch state, reset to a clean default-branch base carrying only intended fixes, create branch `fm/<id>`, implement, and report `done` per the project mode.
It keeps its worktree, context, and repro, but the ship branch starts from a clean base (no scratch commits ride along), and the repro becomes the regression test.
From there it is an ordinary ship task.

## 10. Backlog format

`data/backlog.md` is the durable queue; update it on every dispatch, completion, and decision.

```markdown
## In flight
- [ ] <id> - <one line> (repo: <name>, since <date>)

## Queued
- [ ] <id> - <one line> (repo: <name>) blocked-by: <id> - <reason>

## Done
- [x] <id> - <one line> - <https://github.com/owner/repo/pull/number> (merged <date>)
- [x] <id> - <one line> - local main (merged <date>)
- [x] <id> - <one line> - data/<id>/report.md (reported <date>)
```

Re-evaluate Queued on every teardown and heartbeat: dispatch anything whose blocker is gone and whose date gate has arrived.

A tracked `.tasks.toml` pins the default `tasks-axi` markdown backend to `data/backlog.md` (`done_keep = 10`, archive `data/done-archive.md`).
Local `config/backlog-backend` is the opt-out knob: absent or `tasks-axi` uses the default backend, `manual` forces hand-editing.
Compatible means bootstrap accepts `tasks-axi --version` as 0.1.1+ and `update --help` exposes `--archive-body`.
With the default backend active and compatible `tasks-axi` on PATH, mutate the backlog through its verbs (handoffs still via the validated helper, section 6); missing/incompatible reports via `MISSING:` and every home hand-edits until installed; `manual` means every home hand-edits.
Secondmates inherit `config/backlog-backend`.
Either way the `## In flight` / `## Queued` / `## Done` format is the contract: verbs edit `data/backlog.md` byte-exact, preserving existing item forms (the bold in-flight `- **<id>**`, `- [ ]`/`- [x]`, `blocked-by: <id> - <reason>`), not reformatting.
Keep Done to 10 (`tasks-axi done` auto-prunes and archives, so do not hand-prune; when hand-editing, prune manually when adding).
Pruning loses nothing: PR ships live on as PRs, local-only in local `main`, scouts as reports.
Map operations to `tasks-axi` verbs (`add`, `start`, `done`, `update`, `block`/`unblock`/`ready`, `show`, `render`) and run `--help` for flags.
Three facts `--help` will not give you:

- Done-flag: `tasks-axi done <id> --pr <url>` (PR ship), `--report <path>` (scout), `--note "local main"` (local-only).
- Update notes by inspecting first (`tasks-axi show <id> --full`), then `tasks-axi update <id> --body-file <path>` (add `--archive-body` when superseding recoverable prior state).
- Hand off with `bin/fm-backlog-handoff.sh <secondmate-id> <item-key>...`, never bare `tasks-axi mv` (the helper validates the destination home first).

**Note hygiene:** keep free-form notes free of volatile specifics that rot (temp paths, in-flight versions, moving locations, ephemeral IDs) - reference the authoritative source, and verify a note's volatile detail against it before acting.
Structured fields (task IDs, blocked-by IDs, Done PR URLs / report paths) are the durable record.
Correct or delete stale notes on sight, and put durable facts in curated memory (section 6), not scattered notes.

## 11. Crewmate briefs

Scaffold with `bin/fm-brief.sh <id> <repo-name>` - it writes `data/<id>/brief.md` with the standard contract (branch setup, status protocol, push/merge rules, definition of done) and all paths filled in.
The ship-brief Setup opens with a worktree-isolation assertion before the branch step: the crewmate confirms it is in its own disposable worktree, not the primary checkout, and stops with `blocked: launched in primary checkout, not an isolated worktree` otherwise (the upstream half of the section 8 tangle guard).
The mode is read via `fm-project-mode.sh` (you do not pass it) and shapes the definition of done: `no-mistakes` stops after the implementation commit (then firstmate triggers validation); `direct-PR` pushes and opens the PR itself; `local-only` stops at "ready in branch".
The no-mistakes brief points to no-mistakes' version-matched guidance and keeps only the firstmate wrapper rules (`ask-user` escalation, `--yes` avoidance, the CI-green done line).
Ship briefs include the project-memory contract: run `bin/fm-ensure-agents-md.sh` when the project already has agent-memory files or the task produced durable knowledge, then record proportionate learnings in `AGENTS.md`.
For scouts add `--scout`: the scaffold swaps in the report contract (findings to `data/<id>/report.md`, no branch/push/PR) and declares the worktree scratch, with no project-memory step; scout is mode-agnostic.
For secondmates use `bin/fm-brief.sh <id> --secondmate <project>...` (a charter brief): set `FM_SECONDMATE_CHARTER='<charter>'` and `FM_SECONDMATE_SCOPE='<scope>'` when scope differs, and replace any remaining `{TASK}` before seeding.
Keep the charter on persistent responsibility, available clones, escalation to the main firstmate status file, the idle-by-default contract, and the requests-from-main-firstmate contract (marked requests return via status/doc pointer, unmarked captain messages stay conversational); load `secondmate-provisioning` before seeding, launching, recovering, or handing backlog.
The status protocol is intentionally sparse: crewmates append status only for supervisor-actionable phase changes or `needs-decision`/`blocked`/`done`/`failed`, because every append wakes firstmate.
Replace any remaining `{TASK}` with a clear description, acceptance criteria, and constraints before spawning; adjust other sections only when the task truly deviates from the standard ship shape - the scaffold is the contract, not a suggestion.
