---
name: whytask
description: Explain a task's purpose, the value created by completing it, and the concrete conditions for successful completion. Use when the user invokes /whytask, names $whytask, or asks what a task is for, what completing it gives them, or what counts as done. Reads the task brief, backlog record, and live status without mutating task or fleet state.
user-invocable: true
metadata:
  internal: true
---

# whytask

Explain why one task exists and what completion means.
Keep the answer short, concrete, and grounded in the task's actual brief and current state.
Do not repeat implementation detail unless it changes the value or success criteria.

## Select the task

1. If the invocation includes a task ID, use that task.
2. Otherwise, use the task explicitly discussed in the user's message or the immediately preceding conversation.
3. Otherwise, list in-flight tasks with `tasks-axi list --state in_flight` when the default backend is active and compatible.
   If the home uses the manual backend or `tasks-axi` is unavailable or incompatible, read the `## In flight` section of `data/backlog.md` instead.
4. If exactly one task is in flight, use it.
5. If the target is still ambiguous, ask one concise question naming the candidate task IDs.

Never guess between multiple plausible tasks.

## Read the evidence

Read the minimum evidence needed in this order:

1. `tasks-axi show <id> --full` for the durable backlog record when the default backend is active and compatible, or the matching item in `data/backlog.md` otherwise.
   If the active backlog does not contain the task, search `data/done-archive.md` before treating its ID as missing.
2. `data/<id>/brief.md` when it exists for the goal, constraints, and acceptance criteria.
3. `bin/fm-crew-state.sh <id>` only when current progress changes what remains for success.
4. `data/<id>/report.md` or a recorded PR only when the task is already complete or awaiting acceptance.

Treat `state/<id>.status` as historical event evidence only, never as current state or current blocker evidence.
Do not infer purpose from the task title alone when a brief or backlog body exists.
Do not run project code, inspect broad diffs, dispatch work, steer a crewmate, merge a PR, or mutate backlog, task, fleet, provider, or project state.

## Answer contract

Answer in the user's language and identify the task ID and title first.
Then answer exactly these three questions with concrete task-specific statements:

1. **Предназначение / Purpose** - What problem this task exists to solve and why it is being done now.
2. **Что даёт успех / Value of success** - What capability, risk reduction, decision, or user outcome becomes available when it succeeds.
3. **Что считается успехом / Success criteria** - Observable conditions that prove the task is complete, including required validation or delivery state.

Distinguish code readiness from deployed or live-product readiness when the task evidence makes that distinction material.
If the brief lacks a measurable success condition, say what is missing instead of inventing one.
If the task is blocked, add one final sentence naming the blocker after the three answers.

## Read-only boundary

`/whytask` is strictly read-only.
It may explain or expose ambiguity, but it never changes task state or starts follow-up work as a side effect.
