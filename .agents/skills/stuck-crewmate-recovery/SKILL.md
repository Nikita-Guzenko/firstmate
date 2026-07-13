---
name: stuck-crewmate-recovery
description: Agent-only playbook for stuck firstmate direct reports. Use after a stale wake, looping pane, repeated confusion, an answered-by-brief question, an unresponsive crewmate, or a failed steer. Escalates from peek, to one-line steer, to harness-specific interrupt, to relaunch with progress, to failed status.
user-invocable: false
metadata:
  internal: true
---

# stuck-crewmate-recovery

Use this playbook when a direct report is stale, looping, repeatedly confused, asking a question its brief already answers, unresponsive, or when a steer failed to land.

Load `harness-adapters` before sending an interrupt, exit command, resume command, or harness-specific skill invocation.
The target window's harness is recorded as `harness=` in `state/<id>.meta`.

Escalate in order:

1. Peek the pane.
2. If the crewmate is waiting on a question its brief already answers, answer in one line via `FM_HOME=<this-firstmate-home> bin/fm-send.sh` from an active firstmate session unless `FM_HOME` is already set to the active firstmate home.
3. If the crewmate is confused or looping, interrupt with the adapter's interrupt key, then redirect with one corrective line.
   For example, for a single-Escape adapter: `FM_HOME=<this-firstmate-home> bin/fm-send.sh <window> --key Escape`.
4. If the crewmate is genuinely wedged after redirection, exit the agent with the adapter's exit command and relaunch with the same brief plus a `progress so far` note appended to it.
   Genuine wedging means looping, unresponsive, repeating the same obstacle, or truly dead.
   A low context reading is not wedging; modern harnesses auto-compact and keep going.
   The worktree and commits persist, so relaunch is cheap.
5. If a second relaunch fails too, write `failed` to the backlog and tell the captain with evidence.

## Reading a validating no-mistakes crewmate

Judge a validating crewmate by the run's step status, never by whether its shell is still running.
Read its current state with `bin/fm-crew-state.sh <id>`: a deterministic, token-tight one-line read that takes the matching no-mistakes run-step as the source of truth and reconciles it against the crewmate's `state/<id>.status` log.
Because the run-step is authoritative before pane liveness, a crewmate whose window closed after or during validation can still report `done` or `working` from its run; a missing pane becomes `unknown` only when no matching run exists.
That log is an append-only wake-*event* log, not a current-state field, and it goes stale the moment a resolved gate lets the run resume: after you answer a `needs-decision`/`blocked` and the crewmate silently resumes (responds to the gate, the pipeline fixes, it re-validates), the log's last line still reads `needs-decision`/`blocked` while the run-step has moved on.
So never infer current state from a `tail` of that log; `bin/fm-crew-state.sh` reports the live run-step state and explicitly flags the stale log line superseded, where a raw `tail` would mislead you into re-escalating settled work.
The fields below name the run-step states and outcomes it reads from `no-mistakes axi status`; run that command directly when you want the full gate findings.
During the `ci` monitor phase, `bin/fm-crew-state.sh` also reads the ci step log tail because `axi status` reports both "still waiting on checks" and "checks green, waiting on merge" as `ci,running`.

- `running`/`fixing`/`ci` - the pipeline is working (a fix round, a test, or CI monitoring); `ci` stays working until the ci log's most recent recognized marker says checks passed or no checks are terminally ready, and a later re-arm or issue marker returns it to working.
- `awaiting_approval`/`fix_review` - the run is parked waiting on the agent, surfaced as a top-level `awaiting_agent: parked <duration>` line right after `status:` in `axi status`.
  The crewmate owes a response; if it is idle-waiting for the run to advance on its own, steer it to follow no-mistakes' active-gate help.
- `outcome: passed` or `checks-passed` - the helper reports `done`; `passed` means the PR is already merged or closed, while `checks-passed` means it is ready for PR review.
- `outcome: failed` or `cancelled` - the helper reports `failed`; inspect the run details and recover or report failure with evidence.
- Red flag - self-fix duplication: a validating crewmate making fresh hand-commits, aborting the run, or re-running it mid-validation is re-doing work the pipeline already owns.
  Steer it back to no-mistakes' respond flow; the pipeline, not the crewmate, applies validation fixes.
