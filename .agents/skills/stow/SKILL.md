---
name: stow
description: Sweep the current session for uncaptured durable knowledge and file it to disk before a context reset. Use when the captain invokes /stow (e.g. "/stow", "stow what you've learned"), before a session reset or context compaction, or periodically to keep operational memory current.
user-invocable: true
metadata:
  internal: true
---

<!-- maintainers: this is the firstmate-internal skill. The public, installer-facing counterpart lives at skills/stow/SKILL.md - deliberately a separate file with no shared code or environment branching. Keep them independent. -->

# stow

Sweep this session for durable knowledge that only exists in conversation right now, and write it to its authoritative disk location.
The goal is a session that is safe to reset or destroy because everything durable has already been captured.

## What it does

1. **Sweep the session for uncaptured durable knowledge.**
   Read back over this conversation and look for:
   - Operational learnings: fleet-local facts discovered while operating firstmate (a home-specific mode, a harness state, a recurring false alarm and its real cause).
   - Captain preferences expressed in passing: a working-style or approval preference the captain stated conversationally rather than through `data/captain.md` directly.
   - Project-wide working rules discovered: build, test, release, or architecture conventions that belong in that project's own `AGENTS.md`.
   - Decisions made: a standing choice the captain made this session that should outlive it.
   - Undone next steps: anything left open that has not yet been filed as backlog work.

2. **Route each finding using AGENTS.md's knowledge-routing table.**
   AGENTS.md (section 6, "Knowledge routing") is the single source of truth for where each kind of knowledge belongs.
   Read that table and route each finding there instead of re-deriving the mapping here.

3. **Write within firstmate's existing write boundaries.**
   This skill does not grant any new write permission; it only prompts firstmate to use the boundaries that already exist (AGENTS.md section 1):
   - Captain preferences and fleet-local operational facts that are not code-specific: hand-write directly, to `data/captain.md` and `data/learnings.md` respectively, using inspect-then-update every time.
     Before writing, inspect the destination, find the existing bullet or section the finding duplicates or supersedes, and rewrite it in place rather than adding a new trailing entry.
     `data/learnings.md` may not exist yet; create it on first learning, in the same dated, evidence-backed, curated style as `data/captain.md`.
   - Project code and project-wide working rules: never hand-write a project's `AGENTS.md` or code.
     Route them through a normal ship task: a gotcha about one piece of code becomes a comment at that line (the reason and the date), a lint rule or a test; a project-wide working rule is recorded via `bin/fm-ensure-agents-md.sh`.
     The crewmate commits either through that project's delivery pipeline, exactly as section 6 describes.
     If the fleet is live, delegate this to a crewmate rather than doing it inline.
   - Knowledge generalizable to every firstmate user: this repo's own `AGENTS.md` (or other shared, tracked material), shipped through the normal branch -> no-mistakes -> PR -> captain-merge pipeline for this repo (section 1), never hand-committed straight to `main`.
   - Task-scoped notes: inspect the relevant backlog item with `tasks-axi show <id> --full`, judge whether the new note is new, duplicate, superseding, or obsolete, then write a considered replacement body with `tasks-axi update <id> --body-file <path>`.
     When the replacement intentionally supersedes prior state that should remain recoverable, add `--archive-body` to that update command so the prior body stays recoverable without copying it into the replacement.
     Never append.
     If hand-editing `data/backlog.md` per the active backend, make the same inspect-then-update edit in place.
   - Undone next steps: file each as a queued backlog item (section 10), with `blocked-by` recorded if it genuinely depends on something else.

4. **Curate with inspect-then-update.**
   Every write starts by reading the current destination and deciding how the finding changes what is already there.
   Use this checklist before writing:
   - Which existing bullet, section, or task body does this supersede?
   - Can this be a one-sentence rewrite instead of a new entry?
   - Should an older bullet or note be deleted, retired, or archived because it is now obsolete?
   When a finding overlaps or supersedes something already on disk, rewrite or prune the existing entry instead of piling on a new one.
   Graduation moves are limited to exactly three: promote a fleet-wide operating rule to the shared `AGENTS.md` via PR, fold it into `data/captain.md`, or delete a stale entry.
   Do not invent other graduation paths.

5. **Report to the captain.**
   Summarize, in plain outcome language (section 9): what was stowed and where, what was filed to the backlog, and whether the session is now safe to reset or destroy - i.e. whether every durable finding from this sweep now lives on disk rather than only in this conversation.
   If something could not be captured yet (for example, a project code change or working rule waiting on a crewmate to land it), say so explicitly rather than reporting the session fully safe.

## Scope exclusion: no skill storage

`/stow` must **never** store, create, or edit a skill as a destination for any finding.
There is no "graduate this to a skill" move in this skill's routing.
This is a deliberate, standing exclusion, not an oversight: even with the two-tier skill layout, a stow sweep is a memory-routing operation, not a way to author or mutate skills.
Writing learnings into either `.agents/skills/` or public `skills/` would still risk mixing fleet-local material with shared firstmate behavior or standalone installer-facing behavior.
Until a human deliberately scopes a skill change as firstmate repo work, route generalizable operating rules to the shared `AGENTS.md` (or other shared, tracked material) via the pipeline, and fleet-local operational facts to `data/`, never to a skill.
