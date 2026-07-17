# Repos: Recursive Agent Trajectory Analysis & Optimization Systems

A curated, verified collection of 12 repositories implementing recursive self-improvement loops, agent trajectory trace analyzers, and prompt/code optimization systems that can be evaluated on standard benchmarks.

Date: 2026-07-17

---

## Inclusion / Exclusion criteria

To ensure high-quality, actionable results rather than a generic keyword dump, every repository has been graded against the following strict criteria:

### Inclusion Criteria (MUST meet all)
1. **Activity/Trace Capture**: The repository contains code/documentation for recording, saving, or parsing LLM/agent interactions, execution traces, or session transcripts.
2. **Analysis & Feedback Loop**: The repository implements a process to analyze these trajectories (using LLM critique, numerical/textual rewards, or compiler feedback) to identify errors or inefficiencies.
3. **Execution Improvement (Self-Optimization)**: The repository provides automated code/prompt optimization, skill updates, or memory distillation to recursively improve the agent's performance.
4. **Decidability**: Verified directly from the README, code tree, or documentation.

### Exclusion Criteria (Must NOT meet any)
1. **Pure Observability/Monitoring UIs**: The repository is only a telemetry log collector or dashboard (e.g., Langfuse) without a closed-loop self-optimization step.
2. **Standard Agent Frameworks**: The repository is a generic agent runner (e.g., AutoGen, CrewAI) that does not compile/optimize its own prompt/code parameters.
3. **Static Benchmark Lists**: The repository is a static paper bibliography or benchmark dataset without runnable optimization code.

---

## Ranked repos

| # | Repo | ⭐ | Last push | Lang | Why it qualifies (evidence) |
|---|---|---|---|---|---|
| 1 | [microsoft/SkillOpt](https://github.com/microsoft/SkillOpt) | 12,983 | 2026-07-17 | Python | Tracks agent trajectories, edits natural-language skills, and runs validation-gated updates. Shipped with integration shells for **Claude Code**, **Codex**, and OpenClaw. |
| 2 | [stanfordnlp/dspy](https://github.com/stanfordnlp/dspy) | 36,185 | 2026-07-17 | Python | The standard framework for programming and optimizing LLM pipelines. Trace-records pipeline steps and runs compilers (e.g. MIPRO) to optimize prompts. |
| 3 | [NousResearch/hermes-agent-self-evolution](https://github.com/NousResearch/hermes-agent-self-evolution) | 4,712 | 2026-07-17 | Python | Evolutionary self-improvement loop for Hermes Agent. Uses DSPy + genetic prompt evolution (GEPA) over execution traces to optimize agent skills, prompts, and code. |
| 4 | [zou-group/textgrad](https://github.com/zou-group/textgrad) | 3,654 | 2026-07-16 | Python | Implements automatic differentiation via text. Constructs execution graphs, analyzes outputs, and backpropagates LLM critique to recursively refine prompts/code. |
| 5 | [noahshinn/reflexion](https://github.com/noahshinn/reflexion) | 3,205 | 2026-07-16 | Python | Evaluates agent trajectories, generates verbal self-reflection on errors, and recursively injects feedback into the prompt context for subsequent runs. |
| 6 | [withkynam/vibecode-pro-max-kit](https://github.com/withkynam/vibecode-pro-max-kit) | 1,043 | 2026-07-17 | JS | Spec-driven coding harness for **Claude Code** and **Codex** with self-improving context memory and autopilot loops to prevent context rot. |
| 7 | [Kulaxyz/self-learning-skills](https://github.com/Kulaxyz/self-learning-skills) | 880 | 2026-07-17 | Markdown | A self-improving meta-skill for **Claude Code** and Cursor that analyzes session transcripts to extract "golden paths" and write them into the instruction files. |
| 8 | [lapisrocks/LanguageAgentTreeSearch](https://github.com/lapisrocks/LanguageAgentTreeSearch) | 844 | 2026-07-10 | Python | Logs agent decision branches, scores execution states via environment evaluations, and recursively optimizes search trajectories via Monte Carlo Tree Search. |
| 9 | [madaan/self-refine](https://github.com/madaan/self-refine) | 812 | 2026-07-16 | Python | Implements a recursive loop where LLMs generate, critique, and self-correct their outputs (including code readability and math problems). |
| 10 | [microsoft/Trace](https://github.com/microsoft/Trace) | 748 | 2026-07-16 | Python | AutoDiff-like Python library for AI agents. Records execution traces and backpropagates general feedback (compiler errors, textual losses) to optimize agent parameters. |
| 11 | [ascorbic/macrodata](https://github.com/ascorbic/macrodata) | 119 | 2026-06-15 | TS | Gives **Claude Code** and OpenCode persistent self-refining memory, consolidates learnings, and runs background "dream time" reflection. |
| 12 | [jo-inc/pi-reflect](https://github.com/jo-inc/pi-reflect) | 38 | 2026-07-16 | TS | Specifically designed for pi coding agents. Reads session logs, compares behavior to a target, and makes surgical edits to instructions (`AGENTS.md`) to close the gap. |

---

## Notable but excluded

- **princeton-nlp/SWE-agent** (12,305 ⭐): Excluded because it is a runner framework for SWE-bench; it logs trajectories but does not possess an autonomous prompt compilation or recursive self-optimization loop.
- **cursor/agent-trace** (771 ⭐): Excluded because it defines a schema and telemetry format for agent traces but does not implement optimization, replay, or self-correction algorithms.
- **invariantlabs-ai/invariant** (434 ⭐): Excluded because it is a security/monitoring guardrails platform for MCP and agent traces; it flags policy violations but does not autonomously rewrite prompts or skills to optimize performance.
- **EvoAgentX/Awesome-Self-Evolving-Agents** (2,356 ⭐): Excluded because it is a curated list of research papers and does not contain runnable agent optimization code or benchmark tests.

---

## Search angles run

1. **GitHub search (gh CLI)**:
   - `gh search repos "textgrad" --limit 5` (Found `zou-group/textgrad`)
   - `gh search repos "Reflexion" --limit 10` (Found `noahshinn/reflexion`, `FareedKhan-dev/all-agentic-architectures`)
   - `gh search repos "dspy" --limit 5` (Found `stanfordnlp/dspy`, `NousResearch/hermes-agent-self-evolution`)
   - `gh search repos "LATS" --limit 5` (Found `lapisrocks/LanguageAgentTreeSearch`)
   - `gh search repos "Self-Refine" --limit 5` (Found `madaan/self-refine`, `ascorbic/macrodata`)
   - `gh search repos "Trace" --owner "microsoft"` (Found `microsoft/Trace`)
   - `gh search repos "SkillOpt"` (Found `microsoft/SkillOpt`)
   - `gh search repos "AgentJet"` (Found `modelscope/AgentJet`)
   - `gh search repos "reflexio"` (Found `ReflexioAI/reflexio`)
   - `gh search repos "Self-Evolving"` (Found `EvoAgentX/Awesome-Self-Evolving-Agents`)
   - `gh search repos "self_improving_coding_agent"` (Found `MaximeRobeyns/self_improving_coding_agent`, `withkynam/vibecode-pro-max-kit`, `Kulaxyz/self-learning-skills`)
   - `gh search repos "agent trace"` (Found `jo-inc/pi-reflect`, `invariantlabs-ai/invariant`)
2. **Web search**:
   - Query: `"agent trajectory" optimization github OR "self-improvement" LLM agent github` (Surfaced MADER, GPU-Multi-Agent-Traj-Opt, Reflect MCP, and AgentEvals).
3. **Repository Skims**:
   - Skimmed READMEs for 12 candidate repos using the GitHub API to extract exact behavior descriptions.
