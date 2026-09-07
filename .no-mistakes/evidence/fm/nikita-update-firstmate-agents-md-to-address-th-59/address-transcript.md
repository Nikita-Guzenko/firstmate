# Firstmate direct-address development evaluation

Actual Pi-generated messages using the full AGENTS.md from each commit. Runtime: openai-codex / gpt-5.6-sol, medium thinking. Tools, extensions, context discovery, and session persistence disabled. The contract was explicitly supplied as an appended system prompt. This is a bounded model-interpretation evaluation, not a native discovery/restart test or a universal compliance guarantee.

The same scenario request was used for base and target; it specified no name or expected wording.

## Scenario request

Development-only conversation evaluation. Follow the supplied Firstmate contract. For each independent scenario below, generate the exact message you would send the user. Do not perform any operations. Return only a JSON object mapping each scenario ID to its user-facing message.
normal: The user asks what a scout does. Answer in one sentence.
failure: Verified result: the build failed because a required dependency is missing. Tell the user the result and consequence in one sentence.
routine: A routine operational update requires no action, but a response must be sent. There are no other decisions or issues to report.

## Base (d4eb22801f7509c1c7942ea047db78bcb5389ea0)

### normal

Captain, a scout investigates, diagnoses, or plans and delivers findings without changing the project.

### failure

Captain, the build failed because a required dependency is missing, so the change cannot proceed until that dependency is installed.

### routine

Captain, shipshape.

## Target (b65a2aaeff3025ccdd3a5583fbf5618bfdb4708a)

### normal

Nikita, a scout investigates a question and produces a self-contained report without changing the project.

### failure

Nikita, the build failed because a required dependency is missing, so development cannot proceed until it is installed.

### routine

Nikita, shipshape.

## Assessment

All three target replies address Nikita; all three baseline replies address Captain. The routine reply preserves shipshape. Both failure replies omit nautical seasoning. Manual diff review confirms only AGENTS.md changed and the two nautical-guidance lines remain unchanged.

Local Ollama availability check failed (connection refused); the installed authenticated Pi runtime completed the evaluation instead. No browser/UI surface changed, so the generated CLI conversation is the product evidence.
