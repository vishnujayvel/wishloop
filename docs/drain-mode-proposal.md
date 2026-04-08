# Proposal: Wishloop `--drain` Mode

**Date:** 2026-04-07 (revised for v2 architecture)
**Status:** Proposed

## Motivation

Wishloop v2 operates as a thin session manager — it classifies work, enriches proposals, launches Loki sessions, babysits PRs, and loops. But today each invocation handles one task. The user must manually re-invoke for the next issue.

`--drain` makes the loop automatic: fetch issues, launch Loki sessions, babysit PRs, merge, repeat until the backlog is empty.

## What `--drain` Does

```
wishloop --drain                    # drain all open issues
wishloop --drain --label bug        # drain only bugs
wishloop --drain --label refactor   # drain only refactors
```

### Key Design Decision: GitHub Issues ARE the State

The drain loop uses **no local state file** for backlog tracking. GitHub Issues are the single source of truth:

- Open issues = work remaining
- Closed issues = work done
- Issue labels = priority and filtering
- PR state = current work-in-progress

If the session dies and restarts, `wishloop --drain` re-reads `gh issue list --state open` and picks up where it left off. No `.wishloop/backlog.json` to go stale.

**Exception:** `.wishloop/state.json` tracks which Step the pipeline is in (session, post-session, babysitter, loop) for mid-cycle resumption. This is pipeline state, not backlog state.

### The Drain Cycle

Each cycle maps directly to Wishloop v2's Steps:

```
1. FETCH:     gh issue list --state open --label <filter> --json number,title,body,labels
2. STOP?:     If zero issues → print summary, exit
3. PRIORITIZE: critical > bug > auto-detected > refactor > enhancement > docs
               Within same tier: smaller effort first (body length heuristic)
4. RESUME?:   gh pr list --state open → if PR exists, skip to BABYSIT
              loki status --json → if session running, skip to MONITOR
5. PICK:      Select top-priority issue not already in-progress
6. CLASSIFY:  Single issue → loki run #N --pr
              Multiple related → batch into wave → loki start --parallel
7. ENRICH:    enrich-proposal.sh (if using loki start, not loki run)
8. CONFIGURE: source .wishloop/loki.env
9. LAUNCH:    loki run #N --pr  OR  loki start --parallel --openspec ...
10. MONITOR:  Poll loki status --json every 5 min until completed/stopped/crashed
11. POST:     loki docs check, verify learnings, capture-run.sh
12. BABYSIT:  Wait CodeRabbit → loki quick (fix comments) → loki ci --pr → merge
13. LOOP:     Go to step 1
```

### How It Maps to v2 Steps

| Drain Cycle Step | v2 Step | Notes |
|---|---|---|
| FETCH, STOP, PRIORITIZE | Step 1 (Intake) | Work type classification + batching |
| PICK, CLASSIFY | Step 1 (Intake) | Route to `loki run` or `loki start --parallel` |
| ENRICH | Step 2 (Spec + Enrich) | Only for `loki start` path |
| CONFIGURE, LAUNCH | Step 3 (Configure) | Source env file, checkpoint, launch |
| MONITOR | Step 3.5 (Monitor) | `loki status --json` polling |
| POST | Step 4 (Post-Session) | Docs check, learnings verification, archival |
| BABYSIT | Step 5 (PR Babysitter) | CodeRabbit wait, comment fixing, merge |
| LOOP | Step 6 (Loop) | Archive, prune, re-fetch |

`--drain` is NOT a new Step. It's a **loop wrapper** around the existing v2 Steps.

### Session Resumption

When a new Claude Code session starts and the user invokes `wishloop --drain`:

1. Read `.wishloop/state.json` — what step were we in?
2. Check for open PRs (`gh pr list --state open`) → if any, resume at BABYSIT
3. Check for running Loki sessions (`loki status --json`) → if running, resume at MONITOR
4. If neither, fetch open issues and start fresh at FETCH

No special recovery logic. GitHub state + `loki status --json` + `.wishloop/state.json` provide full resumption.

### Interface Contract

Drain mode uses only Loki's public CLI (per P6):

| Action | Command |
|---|---|
| Launch single issue | `loki run #N --pr` |
| Launch batch | `loki start --parallel --openspec ...` |
| Monitor | `loki status --json` |
| Fix review comments | `loki quick "fix comments on PR #N"` |
| Quality gate | `loki ci --pr --fail-on critical,high` |
| Post-session docs | `loki docs check`, `loki docs generate` |
| Emergency stop | `loki stop` |

No `.loki/` file reads. No internal function calls.

### Single Issue vs Batch Decision

```
if (open_issues == 1):
    loki run #N --pr                    # lightweight, no worktree
elif (open_issues <= 3 && no file conflicts):
    batch all → loki start --parallel   # one session handles all
else:
    batch into waves → sequential loki start --parallel per wave
```

The batching algorithm (from `references/batching-algorithm.md`) groups issues by file conflict, effort, and priority. Each wave is a separate Loki session.

## Architecture

```
┌─────────────────────────────────────────┐
│  DRAIN LOOP                            │
│                                         │
│  while (open issues > 0):              │
│    issues = gh issue list              │
│    batch = prioritize + group          │
│                                         │
│    ┌─── v2 Steps 1-6 ───┐             │
│    │ Intake → Spec →     │             │
│    │ Configure → Launch → │             │
│    │ Monitor → Post →     │             │
│    │ Babysit → Merge     │             │
│    └─────────────────────┘             │
│                                         │
│    if new bugs filed during session:   │
│      continue (they join the backlog)  │
│                                         │
│  print cumulative summary              │
└─────────────────────────────────────────┘
```

## Cumulative Summary (on exit)

```
=== Drain Complete ===
Issues at start: 5 | Resolved: 4 | New bugs filed: 1 | Remaining: 2
Loki sessions: 3 | PRs merged: 4 | loki quick fixes: 2
Duration: 47 min
```

## Non-Goals

- **Cross-repo drain** — only the current repo
- **Parallel Loki sessions** — one session at a time (Loki parallelizes internally via `--parallel`)
- **Durable daemon** — session-bound; resumption from GitHub state + `loki status --json`
- **Custom priority logic** — uses fixed priority tiers; user can filter by `--label`

## Success Criteria

- [ ] `wishloop --drain` processes 3+ issues end-to-end without manual intervention
- [ ] Session restart + re-invoke resumes correctly (no duplicate work)
- [ ] Cumulative summary printed on exit
- [ ] `--label` filtering works
- [ ] Uses only Loki's public CLI (P6 compliant)
- [ ] `loki status --json` is the sole monitoring mechanism
