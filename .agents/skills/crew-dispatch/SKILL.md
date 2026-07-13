---
name: crew-dispatch
description: Agent-only reference for the config/crew-dispatch.json dispatch-profile schema and the quota-balanced selector. Use before editing config/crew-dispatch.json, and when a chosen dispatch rule uses select quota-balanced. Owns the canonical schema, the array-use form, and the quota-balanced algorithm.
user-invocable: false
metadata:
  internal: true
---

# crew-dispatch

Load this before editing `config/crew-dispatch.json`, or when a chosen rule's `use` is an array with `select: "quota-balanced"`.
This skill is the one owner of the dispatch-profile schema and the `quota-balanced` selector contract.
AGENTS.md section 4 keeps only the intake precedence and the "consult rules, pass explicit flags" contract; `docs/configuration.md` "Crew dispatch profiles" cross-references here.

`config/crew-dispatch.json` is an optional local dispatch profile file.
It is firstmate-maintained but human-editable.
When the captain expresses a standing preference such as "use grok for news-dependent work", firstmate codifies it into this file; the captain may also hand-edit it.
The file is JSON so firstmate can read the natural-language rules and bootstrap can validate it with `jq`.
When the file is valid, bootstrap prints a concise `CREW_DISPATCH: active config/crew-dispatch.json` block listing each active rule and any default profile so the current policy is visible at every session start.
See `docs/examples/crew-dispatch.json` for a documented starting point to copy into local `config/crew-dispatch.json`.

## Schema

```json
{
  "rules": [
    {
      "when": "<natural-language condition describing a kind of task>",
      "use": [
        { "harness": "<adapter>", "model": "<optional model>", "effort": "<low|medium|high|xhigh|max, optional>" }
      ],
      "select": "<optional strategy>",
      "why": "<optional rationale that helps firstmate choose>"
    }
  ],
  "default": { "harness": "<adapter>", "model": "<optional model>", "effort": "<optional effort>" }
}
```

Per rule, `when` and `use` are required.
A single-object `use` needs `harness`, and every array profile needs `harness`.
`use` may be a single profile object or an ordered array of profile objects.
The single-object form stays fully backward-compatible.
`use.model`, `use.effort`, and `why` are optional.
`select` is optional and currently supports `quota-balanced`.
Absent `select` means use the first array element, or the only object in the single-object form.
The first array element is the deterministic tie-break and the ultimate fallback.
`default` is optional.
An omitted model or effort means the selected harness uses its own default for that axis.

## Resolving a rule at intake

When `config/crew-dispatch.json` is present, read it during intake before every crewmate or scout dispatch.
Pick the single best-fit rule using your own judgment.
This is explicitly not first-match: weigh all rules, their `when` text, and their `why` rationales against the actual task.
For a chosen rule with a single-object `use`, or an array `use` with no `select`, resolve the first profile directly.
For a chosen rule with `select: "quota-balanced"`, pipe the full rule JSON to `bin/fm-dispatch-select.sh` and use the compact JSON profile it prints.
Extract that chosen concrete profile `(harness, model, effort)` and pass it to `bin/fm-spawn.sh` with explicit `--harness`, `--model`, and `--effort` flags for the axes that are set.
If no rule fits, use `default`.
If `default` is absent, fall back to `config/crew-harness` through `bin/fm-harness.sh crew`, exactly as the static path did before dispatch profiles, but still pass that resolved harness explicitly.
This is enforced: when `config/crew-dispatch.json` exists, `bin/fm-spawn.sh` refuses crewmate and scout launches that do not include an explicit harness (`--harness <name>`, a positional adapter name, or a raw launch command).
That refusal is the consultation backstop, so the rules are never silently skipped.
The requirement is gated only on the file's presence; when the file is absent, `fm-spawn.sh` keeps resolving the crewmate harness from `config/crew-harness` as before.
Secondmate launches are exempt because they resolve through `fm-harness.sh secondmate`, not the crewmate dispatch-profile rules.

Never select an unverified harness (verified adapters: `claude`, `codex`, `opencode`, `pi`, `grok`).
Validate every selected harness name against that list.
If a dispatch rule or default names an unverified harness, ignore that profile, fall back to the next valid source, and note the problem when it affects the dispatch.
The shell scripts never parse or match the natural-language rules; firstmate does the matching and passes only concrete flags to `fm-spawn`.
`fm-spawn` only checks whether the file exists so it can enforce the explicit-harness backstop for crewmate and scout dispatches.

If the selected profile asks for an effort value the selected harness does not accept, `fm-spawn` records the requested `effort=` in meta for traceability but omits the launch flag so the harness starts successfully.
Bootstrap reports this as a `CREW_DISPATCH` diagnostic when it can see the invalid harness/effort pair in `config/crew-dispatch.json`.

## quota-balanced selector

`quota-balanced` is deterministic.
It runs `quota-axi --json`.
For each candidate vendor, it uses the minimum `percentRemaining` across that vendor's general windows only: Claude `five_hour` and `seven_day`, Codex `five_hour` and `weekly`.
It ignores model-scoped windows such as `model:fable` and `model:codex_bengalfox:*`.
The vendor with the higher minimum remaining quota wins.
An exact tie between candidates with equally trusted freshness uses the first array element.
If one candidate is fresh and another is stale but still has cached general-window numbers, the stale numbers are usable, but the fresh candidate wins unless the stale candidate's minimum is at least 20 percentage points higher.
That 20 point stale-clear margin is the documented definition of "clearly less constrained".
If `quota-axi` is missing, exits non-zero, or returns unparseable JSON, `bin/fm-dispatch-select.sh` logs the reason to stderr and prints the first array element.
If a candidate vendor is absent from quota output, or has no usable general windows, that vendor is unavailable.
If at least one candidate is available, choose among the available candidates.
If no candidate is usable, `bin/fm-dispatch-select.sh` logs the reason and prints the first array element.
Quota trouble must never block dispatch.
