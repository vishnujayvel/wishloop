# Wishloop

You wish it, it loops until it's done.

Wishloop is a Claude Code skill that turns a single wish — "build this", "fix these bugs", "refactor that" — into a closed-loop autonomous pipeline. It specs the work, executes it, verifies the results, files bugs for anything broken, learns from the run, and loops back to fix what's left. No manual glue. No forgotten steps. Just the loop.

## Philosophy

### The problem Wishloop was born to solve

AI coding agents are good at executing. Give them a task, they'll write code. But they have no memory of failure. They don't know that the last three runs broke the same test. They don't know that `frame:false` and `titleBarStyle:'hiddenInset'` are mutually exclusive in Electron. They don't file bugs for what they missed. They don't come back to fix what they broke.

Wishloop exists because **Loki shipped 9 bugs in a single run** and there was no mechanism to feed those failures back into the next iteration. The spec pipeline was open-ended — it went in one direction and never turned around.

### The closed loop

Wishloop closes the loop. Every run produces three things:

1. **Verified output** — did the code actually work?
2. **Filed issues** — what broke, as GitHub Issues with `auto-detected` labels
3. **Accumulated learnings** — what should we never do again?

Those issues and learnings feed directly into the next iteration. The loop continues until the pipeline is clean or you tell it to stop.

```
         wish
          |
    [1. Classify] ──> what kind of work is this?
          |
    [2. Intake] ────> read specs, git state, build system
          |
    [3. Spec] ──────> OpenSpec CLI: proposal, design, tasks
          |
    [4. Context] ───> inject learnings, prep CLAUDE.md, generate .worktrunk.toml
          |
    [5. Execute] ───> Worktrunk creates worktree, Loki builds autonomously
          |
    [6. Monitor] ───> gardening agent watches every 5 minutes
          |
    [7. Capture] ───> run instance JSON + extract learnings
          |
    [8. Verify] ────> build, test, type-check, file bugs, merge via wt merge
          |
    [9. Loop] ──────> re-fetch issues, re-batch, repeat until clean
          |
        done (or "stop")
```

### Institutional memory

Most AI workflows are stateless — each run starts from zero. Wishloop accumulates knowledge across runs in `~/.local/share/wishloop/learnings.json`. Before every Loki execution, relevant learnings are injected into the project's CLAUDE.md as "Known Pitfalls." This means the agent that builds your Electron app today knows about the bug that burned you last month.

### Worktrunk integration

Worktree management was the weakest link — a reference doc with manual `git worktree add` commands. Wishloop now integrates [Worktrunk](https://worktrunk.dev) as the execution substrate:

- `wt switch -c -x loki <change>` — one command creates a worktree and launches the agent
- `wt list` — structured monitoring data for the gardening agent
- `wt merge main` — squash, rebase, fast-forward, and cleanup in one shot
- Hooks — `post-start` installs deps, `pre-merge` runs tests, `post-merge` archives the change

Worktrunk is optional. Everything falls back gracefully to manual git when it's not installed.

### Design principles

- **Closed-loop feedback.** Bugs feed back. Learnings accumulate. Nothing is forgotten.
- **Async execution.** Loki runs detached. You monitor from the main session.
- **Delta-aware specs.** OpenSpec produces ADDED/MODIFIED/REMOVED, not full rewrites.
- **Work type classification.** One request maps to one type, one path through the phases.
- **Parallel safety.** The batching algorithm prevents file conflicts in concurrent agents.
- **Graceful degradation.** Each phase outputs clear artifacts. You can resume mid-cycle.
- **XDG compliance.** Skill data lives in `~/.local/share/wishloop/`, not project repos.

## Visual Guide

<p align="center">
  <img src="./the-loop.svg" alt="The 9-Phase Closed Loop" width="100%"/>
</p>

<p align="center">
  <img src="./the-swarm.svg" alt="Parallel Wave Execution" width="100%"/>
</p>

<p align="center">
  <img src="./the-gardener.svg" alt="Autonomous Monitoring" width="100%"/>
</p>

<p align="center">
  <img src="./the-memory.svg" alt="Compound Learning" width="100%"/>
</p>

<p align="center">
  <img src="./rarv.svg" alt="RARV Agent Inner Loop" width="100%"/>
</p>

---

## Architecture

```
 ┌────────────────────────────────────────────────────────┐
 │                    SKILL.md (9 phases)                  │
 │  Classify → Intake → Spec → Context → Execute →        │
 │  Monitor → Capture → Verify → Loop                     │
 ├────────────────────────────────────────────────────────┤
 │  OpenSpec CLI          │  Loki Mode        │ Worktrunk │
 │  - proposal.md         │  - --parallel     │ - wt switch│
 │  - design.md           │  - --openspec     │ - wt merge │
 │  - specs/              │  - dashboard      │ - hooks    │
 │  - tasks.md            │    :57374         │ - wt list  │
 ├────────────────────────────────────────────────────────┤
 │  Gardening Agent       │  Learnings Store  │ GitHub CLI │
 │  - 5-min polling       │  - learnings.json │ - gh issue │
 │  - anomaly detection   │  - run instances  │   create   │
 │  - steering commands   │  - CLAUDE.md      │ - gh issue │
 │  - pipeline journal    │    injection      │   list     │
 └────────────────────────────────────────────────────────┘
```

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/gardening-check.sh` | 5-minute monitoring loop with anomaly detection |
| `scripts/capture-run.sh` | Generate run instance JSON after Loki completes |
| `scripts/inject-learnings.sh` | Filter and inject learnings into CLAUDE.md |

### Reference docs

| Reference | When to read |
|-----------|-------------|
| `references/batching-algorithm.md` | Bug Batch classification or Phase 9 wave planning |
| `references/run-instance-schema.md` | Run capture or querying historical runs |
| `references/learnings-schema.md` | Learnings injection or extraction |
| `references/worktree-isolation.md` | Concurrent Loki sessions (Worktrunk + fallback) |
| `references/gardening-checks.md` | Anomaly detection and steering commands |

## Prerequisites

| Tool | Install | Purpose |
|------|---------|---------|
| openspec | `npm install -g openspec` | Spec generation (delta specs) |
| loki | `npm install -g loki-mode` | Autonomous execution |
| gh | `brew install gh` | Bug filing and issue feedback |
| worktrunk | `brew install worktrunk` | Worktree lifecycle (optional) |

## Quick start

```bash
# Start a new feature
> wishloop
> "I want to add dark mode support to the app"

# Fix bugs from a previous run
> wishloop
> "Pull open issues and fix them"

# Verify and triage after Loki finishes
> wishloop
> "Loki finished, let's verify and triage"

# Archive and check what's left
> wishloop
> "Archive the dark-mode change and see what's left"
```

## The name

Vish + Loop. You wish it, it loops. Your name is hiding in plain sight.

## License

MIT
