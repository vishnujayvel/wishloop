# wishloop

A Claude Code skill that orchestrates the full continuous development loop: propose an OpenSpec change, generate delta specs (ADDED/MODIFIED/REMOVED with GIVEN/WHEN/THEN scenarios), launch Loki Mode for autonomous execution, verify the results, file bugs as GitHub Issues, archive the completed change to update canonical specs, and loop back for the next iteration. This skill was born from a real failure mode where Loki shipped 9 bugs because the spec pipeline had no feedback loop from issues back into specs.

## When to use this skill vs others

| Skill | When to use |
|-------|-------------|
| **wishloop** | You have a project with both `openspec/` and `.loki/` directories, and you want the full propose -> spec -> build -> verify -> fix cycle. This is the closed-loop workflow. |
| **pdlc-autopilot** | You want SDLC/PDLC orchestration using Kiro skills (kiro:spec-*) with product phases (P0-P3). Use this when you do NOT need Loki Mode execution and prefer manual or subagent-based implementation. |
| **loki-mode** | You want raw autonomous execution from a PRD or issue. Loki Mode alone does not manage spec generation, verification feedback, or bug triage -- it just executes tasks. |
| **kiro:spec-*** | You want to generate individual spec artifacts (requirements, design, tasks) without the full loop. These are low-level building blocks that pdlc-autopilot orchestrates. wishloop uses the `openspec` CLI instead of Kiro skills. |

**Rule of thumb:** If the project uses `openspec/` for specs and `.loki/` for execution, use wishloop. If the project uses `.claude/specs/` (Kiro format), use pdlc-autopilot.

## Prerequisites

1. **openspec CLI** -- Install with `npm install -g openspec`. Verify: `openspec --version`. The project must be initialized with `openspec init`.

2. **loki CLI** -- Install with `npm install -g loki-mode`. Verify: `loki version`. Loki must be launched from a separate terminal (never from within a Claude Code session) because it spawns `claude --dangerously-skip-permissions` as a child process.

3. **gh CLI** -- Install with `brew install gh`. Verify: `gh auth status`. Must be authenticated. Used for filing bugs (`gh issue create`) and pulling open issues (`gh issue list`) to feed back into the loop.

## Quick start examples

### Start a new feature from scratch
```
> /wishloop
> "I want to add dark mode support to the app"
```
The skill will run `openspec new change dark-mode`, guide you through proposal/design/specs/tasks, copy context to `.loki/`, and tell you to run `loki start --openspec openspec/changes/dark-mode` from a separate terminal.

### Fix bugs from a previous Loki run
```
> /wishloop
> "Pull open issues and fix them"
```
The skill will run `gh issue list --state open`, create a new OpenSpec change from the bugs, generate delta specs with MODIFIED sections, and prepare for another Loki run.

### Archive a completed change and check for remaining work
```
> /wishloop
> "Archive the dark-mode change and see what's left"
```
The skill will run `openspec archive dark-mode`, update canonical specs, check `gh issue list` for remaining bugs, and propose next steps.

### Resume a loop mid-cycle
```
> /wishloop
> "Loki finished, let's verify and triage"
```
The skill will check build/test status, guide manual verification, help file bugs for anything broken, and set up the next loop iteration.
