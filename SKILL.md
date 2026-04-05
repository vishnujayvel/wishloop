---
name: wishloop
description: |
  Universal SDLC orchestrator for projects using OpenSpec CLI + Loki Mode.
  Closed-loop: spec -> execute -> verify -> file bugs -> loop. Includes gardening
  agent for monitoring, institutional learning accumulation across runs, and
  autonomous issue fixing with intelligent batching.

  Triggers on: "openspec", "loki", "SDLC", "run the loop", "wishloop", "worktrunk" + parallel context, "fix these bugs" + loki context,
  "build X from scratch" + openspec context, "continue where we left off" with openspec/changes/,
  greenfield projects with openspec/ directory, "archive the change", "verify and triage".

  DO NOT USE FOR one-off brainstorming (use superpowers:brainstorming),
  web/topic research (use deep-research), Kiro-based SDLC (use pdlc-autopilot),
  day planning (use daily-copilot), practice tracking (use practice-tracker),
  or generic "fix this bug" without openspec/loki context.
---

# Wishloop

Classify work, spec it via OpenSpec CLI, execute via Loki Mode, monitor with gardening agent, capture run data and learnings, verify, file bugs, loop.

### Prerequisites

- **openspec CLI** — `openspec` (spec generation)
- **loki CLI** — `loki start` (autonomous execution, requires `--dangerously-skip-permissions`)
- **gh CLI** — `gh issue create` / `gh issue list` (bug filing and feedback loop)
- **Worktrunk** *(recommended)* — `brew install worktrunk && wt config shell install` (worktree lifecycle, merge automation, parallel agents). Optional — the skill falls back to manual git worktrees when not installed.

---

## Phase 1: Classify Work

Map the request to exactly one work type:

| Signal | Work Type | Spec? | Loki? |
|--------|-----------|-------|-------|
| "build X from scratch", greenfield | **Greenfield** | Full init | Full 9-phase |
| "add X", "integrate Y", new feature | **Feature** | `openspec new change` | Targeted |
| "fix #N", "fix these bugs", bug list | **Bug Batch** | Batched changes | Per-wave |
| "design X", "architecture for Y" | **Architecture** | Proposal + design only | No |
| "refactor", "migrate from X to Y" | **Refactor** | `openspec new change` (MODIFIED) | Full |
| "research", "spike", "evaluate" | **Research** | No | No |
| "rethink the X", "brainstorm" | **Product Thinking** | No | No |
| "add tests", "E2E coverage" | **Testing** | Test-focused change | Testing phase only |
| "write docs", "API docs" | **Documentation** | No | No |

**Distinguish UI tasks from integration tasks.** "Rewrite WritersRoomView" and "Wire Claude subprocess into WritersRoom" are separate tasks with different files and risk. Never combine them.

---

## Phase 2: Intake

```
1. Check if openspec/ exists — if not: openspec init --tools claude
2. Read existing specs: openspec list --specs
3. Read active changes: openspec list
4. Check codebase state: git status, git log --oneline -5
5. Read CLAUDE.md if it exists
6. Detect build system: package.json | Makefile | Cargo.toml | go.mod | pyproject.toml
```

**Greenfield:** Ask product context questions ONE AT A TIME. Generate UI mockups (HTML in docs/mockups/) if the project has a UI. Let user choose direction before proceeding.

**Feature:** Read relevant spec files. Identify which specs will be MODIFIED vs ADDED.

**Bug Batch:** Pull issues via `gh issue list --state open --json number,title,body,labels`. Run the Intelligent Batching Algorithm (see `references/batching-algorithm.md`).

**Research / Product Thinking / Documentation:** Skip to Phase 5 (non-code paths).

---

## Phase 3: Spec

Always use `openspec` CLI (`openspec`), never Kiro skills. OpenSpec produces delta specs (ADDED/MODIFIED/REMOVED) that Loki's adapter needs.

```bash
# Greenfield
openspec init --tools claude && openspec new change <project-name>

# Feature / Refactor / Testing / Bug Batch
openspec new change <name>
```

Write artifacts in `openspec/changes/<name>/`:
1. `proposal.md` — problem, goals, scope, non-goals, testing strategy
2. `design.md` — architecture, components, data flow, API contracts
3. `specs/<domain>/spec.md` — delta specs with GIVEN/WHEN/THEN scenarios
4. `tasks.md` — ordered task groups with dependencies and acceptance criteria

**Loki can start from just a proposal.** If the proposal has clear requirements, technology choices, and testing strategy, skip writing design/specs/tasks — Loki handles the rest. Only generate full OpenSpec artifacts for brownfield modifications needing structured delta context.

**Architecture work type:** Write `proposal.md` and `design.md` only. No tasks. Output is the design.

Validate: `openspec validate <name>` — all artifacts must pass before proceeding.

**If validation fails:** Show errors, ask user to fix, retry. Do not proceed with invalid specs.

---

## Phase 4: Context Prep + Learnings Injection

**Update CLAUDE.md BEFORE Loki runs.** Loki reads it at start — wrong rules mean wrong implementation.

### 4a. Inject learnings from prior runs

Run `scripts/inject-learnings.sh <project-dir>` or manually:
1. Read `~/.local/share/wishloop/learnings.json`
2. Filter by project's tech stack (always include loki, workflow, testing categories)
3. Append relevant warnings to CLAUDE.md as `## Known Pitfalls`

See `references/learnings-schema.md` for filtering logic and injection format.

### 4b. Generate .worktrunk.toml (if Worktrunk is available)

If `wt` is on PATH and the project has no `.worktrunk.toml`, generate one with hooks:

```toml
[hooks]
post-start = ["<deps-install-command>"]    # e.g., "npm install", "cargo build"
pre-merge = ["<build-command>", "<test-command>"]  # e.g., "npm run build", "npm test"
post-merge = ["openspec archive $(git branch --show-current)"]
```

Detect the build system from Phase 2 intake (package.json → npm, Cargo.toml → cargo, go.mod → go, pyproject.toml → pip/pytest, Makefile → make). If `.worktrunk.toml` already exists, merge Wishloop hooks with existing configuration — do not overwrite.

### 4c. Discover and inject ADRs

Scan the target project for ADRs in common locations: `docs/adrs/`, `docs/decisions/`, `architecture/decisions/`, and files matching `ADR-*.md` or `adr-*.md` in the repo root.

For each ADR found:
1. Extract title, status (`accepted`, `proposed`, `superseded`, `deprecated`), and a one-line summary from the document
2. Check if the ADR's topic overlaps with files or domains in the current OpenSpec change — match by keywords in the ADR title/context against changed file paths, spec domains, and proposal scope
3. If relevant, append to the project's CLAUDE.md under a `## Relevant ADRs` section (create the section if absent; never overwrite existing CLAUDE.md content)

Injection format:
```markdown
- **ADR-NNN: Title** (status) — summary. Applies because: [reason]
```

If no ADRs are found or none are relevant, skip silently.

See `references/adr-integration.md` for discovery patterns and relevance matching.

### 4d. Checkpoint commit

```bash
git add -A && git commit -m "checkpoint: prep for loki run (<change-name>)"
loki doctor  # validate prerequisites
```

**Always commit before Loki.** Clean git state is your recovery point if Loki breaks things. The checkpoint captures ADR injections from 4c, learnings from 4a, and any `.worktrunk.toml` from 4b.

**If `loki doctor` fails:** Print diagnostic output. Common fixes: install missing deps, clear stale `.loki/` state, ensure `claude` CLI is available with `--dangerously-skip-permissions`.

---

## Phase 5: Execute

### Code work (Greenfield, Feature, Bug Batch, Refactor, Testing)

**If Worktrunk (`wt`) is available** (preferred — handles worktree creation, isolation, and cleanup):

```bash
wt switch -c -x "loki start --parallel --openspec openspec/changes/<change-name>" <change-name>
```

For focused changes (plain PRD path, no OpenSpec adapter needed):

```bash
wt switch -c -x "loki start ./proposal.md --parallel --yes" <change-name>
```

**If Worktrunk is not installed,** fall back to direct invocation:

```bash
nohup loki start --parallel --openspec openspec/changes/<change-name> > /tmp/loki-<change>.log 2>&1 &
LOKI_PID=$!
echo "Loki PID: $LOKI_PID, started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

For focused changes: `loki start ./proposal.md --parallel --yes`

> **Note:** If Worktrunk is not installed, install with: `brew install worktrunk && wt config shell install`

**Always use `nohup ... > logfile 2>&1 &` for the fallback path.** Without proper detachment, the Bash tool's FD closure causes Loki's child `claude` process to hang on broken stdout pipes.

**If launch fails:** Check `/tmp/loki-<change>.log` for errors. Suggest user launch from separate terminal.

**If another Loki is running:** See `references/worktree-isolation.md` for concurrent session handling via git worktrees.

### Parallel Bug Batch waves

When running multiple bug-batch waves concurrently, Worktrunk isolates each wave in its own worktree:

```bash
wt switch -c -x "loki start --parallel --openspec openspec/changes/wave-1" wave-1
wt switch -c -x "loki start --parallel --openspec openspec/changes/wave-2" wave-2
```

Each wave runs in a separate worktree, so they do not conflict. Without Worktrunk, waves must run sequentially or use manual `git worktree add` (see `references/worktree-isolation.md`).

### Non-code work types

- **Architecture:** Present design document from Phase 3.
- **Research:** Use subagents for deep research. Output to `docs/plans/<topic>.md`.
- **Product Thinking:** Brainstorm with user, ONE question at a time. Output to `product-context.md`.
- **Documentation:** Read code, generate docs directly.

**Initialize phase state before launch:**
```bash
mkdir -p .wishloop
echo "{\"phase\": 5, \"phaseLabel\": \"Execute\", \"change\": \"<change-name>\", \"startedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > .wishloop/state.json
```

**After launching Loki, immediately start Phase 6 monitoring.** When monitoring detects completion (`ACTION: ADVANCE_TO_PHASE_7`), proceed directly to Phase 7 → Phase 8 → Phase 9 without pausing for user input.

---

## Phase 6: Monitor (Gardening Loop)

Run monitoring every 5 minutes while Loki executes. Use:
```bash
bash <skill-path>/scripts/gardening-check.sh <project-dir> <change-name>
# Or via /loop: /loop 5m bash scripts/gardening-check.sh . my-change
```

The script runs 5 checks (commits, STATUS.txt, active agents, build, conflicts), detects anomalies (stalls, crashes, build breaks, completion), and appends journal entries to `docs/plans/pipeline-journal.md`.

When Worktrunk is available, `wt list` provides structured status for all active worktrees — branch name, commit count, ahead/behind tracking, and CI status — instead of raw git parsing. The gardening script auto-detects Worktrunk and falls back to git-based checks when `wt` is not on PATH.

See `references/gardening-checks.md` for anomaly thresholds and steering commands (PAUSE/STOP/HUMAN_INPUT).

**Loki's first iteration takes 5-10 minutes** (reading context, planning). No commits in this window is normal. Loki often does everything in ONE atomic commit.

**Loki queue is stale between runs.** `queue/pending.json` is never cleaned up. Trust `git log` for progress.

Dashboard: `http://localhost:57374/`

### Phase Continuation Triggers

The gardening script outputs ACTION directives. **You MUST act on them immediately:**

| Directive | Meaning | Action |
|-----------|---------|--------|
| `ACTION: ADVANCE_TO_PHASE_7` | Loki completed successfully | Stop monitoring loop. Run Phase 7 immediately. Then Phase 8. Then Phase 9 if autonomous. |
| `ACTION: INVESTIGATE_EXIT` | Loki agents exited without completion signal | Check Loki logs. If work is done, advance to Phase 7. If crashed, file bug and retry. |

**Do NOT treat gardening output as a status update.** When you see `ACTION: ADVANCE_TO_PHASE_7`, stop monitoring and proceed. The pipeline is autonomous — waiting for human input between phases is a bug.

### Phase State Tracking

Before launching Loki (Phase 5), initialize state:
```bash
mkdir -p .wishloop
echo '{"phase": 5, "phaseLabel": "Execute", "change": "<name>", "startedAt": "<ISO>"}' > .wishloop/state.json
```

The gardening script updates `.wishloop/state.json` when it detects completion. You can also read it to know where the pipeline is:
```bash
cat .wishloop/state.json  # → {"phase": 7, ...} means proceed to Phase 7
```

Update state at each phase transition:
```bash
echo '{"phase": N, "phaseLabel": "<label>", "change": "<name>", "advancedAt": "<ISO>"}' > .wishloop/state.json
```

---

## Phase 7: Post-Run Capture

> **Trigger:** Entered automatically when gardening detects completion (`ACTION: ADVANCE_TO_PHASE_7`) or when you confirm Loki has finished. Do NOT wait for user prompt.

Every Loki run MUST produce a run instance record. No exceptions.

### 7a. Auto-generate run instance JSON

Run `scripts/capture-run.sh <project-dir> <change> <checkpoint-hash> <start-time> <pid>` or manually collect: commits since checkpoint, files changed, build/test results, STATUS.txt.

See `references/run-instance-schema.md` for the full JSON schema and field population guide.

### 7b. Extract learnings interactively

Prompt user with 3 questions: What surprised you? What did Loki get wrong? New patterns to remember?

### 7c. Update accumulated learnings

Categorize learnings (by technology, loki, workflow, or testing). Deduplicate against existing entries. Write to `~/.local/share/wishloop/learnings.json`.

See `references/learnings-schema.md` for categorization logic and deduplication rules.

### 7d. Update ADRs with implementation consequences

Check if any ADRs were injected into CLAUDE.md in Phase 4c. For each relevant ADR:

1. Ask: "Did implementation reveal anything this ADR didn't anticipate?"
2. If yes, append a dated entry to the ADR's `## Consequences` section:
   ```markdown
   ### Implementation feedback — YYYY-MM-DD (<change-name>)
   <what was discovered>
   ```
3. If an ADR is discovered to be wrong or outdated, change its status to `**Status:** superseded` and note the reason inline

If no ADRs were injected, skip this phase.

See `references/adr-integration.md` for update format.

---

## Phase 8: Verification & Issue Filing

> **Trigger:** Entered automatically after Phase 7 completes. Do NOT wait for user prompt.

### Verify build and tests

Run the project's build, unit test, and E2E commands (detected in Phase 2). Also run type checking if applicable (e.g., `npx tsc --noEmit`).

**Loki declares completion based on its own assessment.** It won't test dragging, native window chrome, or visual aesthetics. Always do a manual spot-check.

### File issues immediately

```bash
gh issue create --title "<description>" --body "<details>" --label "bug" --label "auto-detected"
```

All issues MUST have `auto-detected` label — this enables the autonomous loop to distinguish machine-detected from human-filed issues. File bugs as soon as confirmed, not in a batch later.

Update the run instance JSON with `bugsFound` and any `manualFixesNeeded`.

### Archive

```bash
openspec archive <change-name>
git add -A && git commit -m "post-loki: archive <change-name>, update specs"
```

### Merge

**If Worktrunk (`wt`) is available** (preferred — squash + rebase + fast-forward + worktree cleanup in one command):

```bash
wt merge main
```

Pre-merge hooks run tests automatically before the merge is allowed. No manual test step needed.

**If Worktrunk is not installed,** merge manually:

```bash
git checkout main
git merge --squash <change-branch>
git commit -m "feat: <change-name>"
openspec archive <change-name>
```

### Auto-merge criteria

When ALL of the following are true, **merge immediately without asking the user:**

- CI checks pass (build + tests green)
- Code review (e.g., CodeRabbit) has no unresolved blocking inline comments
- No merge conflicts

**Only pause for user input** when blocking review comments require design decisions that the agent cannot resolve autonomously.

### Merge error handling

- **Conflicts:** Report the conflicting files to the user and pause the autonomous loop for manual resolution. Do not attempt automatic conflict resolution.
- **Pre-merge hook failure (tests fail):** File a GitHub issue with the test failure details (`gh issue create --title "Pre-merge test failure: <change>" --body "<details>" --label "bug" --label "auto-detected"`), then continue the loop to attempt a fix in the next iteration.

---

## Phase 9: Autonomous Issue Loop

The loop is the DEFAULT behavior — the user opts OUT, not in.

### Configuration (defaults)
```
autonomous: true | max_iterations: 5 | cooldown_minutes: 2
issue_labels: ["bug", "auto-detected"]
```

### Each iteration:
1. **Re-fetch** ALL open issues: `gh issue list --state open --json number,title,body,labels`
2. **Re-prioritize:** critical > bug > auto-detected > enhancement. Dependencies first. Smaller effort first within same tier.
3. **Batch into waves** using the Intelligent Batching Algorithm (see `references/batching-algorithm.md`)
4. **Cooldown:** Print run summary + next wave plan. Wait `cooldown_minutes`. User can type "stop", "skip", or steering input.
5. **Auto-continue:** Generate minimal proposal from Wave 1 issues -> Phase 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9

### Exit conditions:
- Zero open issues -> "Pipeline clean"
- Max iterations reached -> print cumulative summary
- User types "stop"

### Cumulative summary (on exit):
```
=== Autonomous Loop Complete ===
Iterations: {N} | Duration: {M} min | Commits: {C} | Files: {F}
Issues at start: {N} | Filed: {N} | Resolved: {N} | Remaining: {N}
Learnings captured: {N}
Run records: {list of JSON paths}
```

---

## Reference Documents

Read these as needed — they contain detailed schemas, algorithms, and guides:

| Reference | When to read |
|-----------|-------------|
| `references/batching-algorithm.md` | Bug Batch classification or Phase 9 wave planning |
| `references/run-instance-schema.md` | Phase 7 run capture or querying historical runs |
| `references/learnings-schema.md` | Phase 4 learnings injection or Phase 7 extraction |
| `references/worktree-isolation.md` | Phase 5 when another Loki session is already running |
| `references/gardening-checks.md` | Phase 6 anomaly detection details or steering commands |
| `references/adr-integration.md` | Phase 4 ADR discovery or Phase 7 ADR consequence updates |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/gardening-check.sh <dir> <change>` | Run the 5 monitoring checks + journal append |
| `scripts/capture-run.sh <dir> <change> <hash> <time> <pid>` | Generate run instance JSON |
| `scripts/inject-learnings.sh <dir> [tech-csv]` | Filter and inject learnings into CLAUDE.md |

## Canonical data location

Run records and learnings live at `~/.local/share/wishloop/` (XDG-compliant, outside project repos).
