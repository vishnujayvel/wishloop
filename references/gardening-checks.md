# Gardening Agent — Monitoring Protocol

The gardening agent runs every 5 minutes while Loki executes. Its job is to monitor, detect anomalies, and journal findings. Use `scripts/gardening-check.sh` or the `/loop` skill for automation.

## The 5 Checks

Run all of these each iteration:

```bash
# 1. Check for new commits
git log --oneline -5

# 2. Check Loki task progress
cat .loki/STATUS.txt 2>/dev/null || echo "No STATUS.txt"

# 3. Check for active agents
ps aux | grep "claude.*dangerously" | grep -v grep | wc -l

# 4. Verify build still passes
<project build command> 2>&1 | tail -5

# 5. Check for file conflicts
git status --short
```

## Journal Entry Format

Append timestamped entries to `docs/plans/pipeline-journal.md`:

```markdown
## YYYY-MM-DD HH:MM UTC — Gardening Check

| Metric | Value |
|--------|-------|
| Commits since last check | N (list hashes) |
| Active agents | N |
| STATUS.txt summary | <first line of STATUS.txt> |
| Build status | PASS / FAIL (error summary) |
| Git conflicts | NONE / list of conflicted files |

**Observations:** <notable patterns, progress, or concerns>
```

## Anomaly Detection

### Stall detection (no commits for 15+ minutes)
```
IF last_commit_time > 15 minutes ago AND active_agents > 0:
  -> Log WARNING: "Potential stall — N agents active but no commits for M minutes"
  -> Check loki status for stuck tasks
  -> Check /tmp/loki-<change>.log for errors
  -> If stuck > 30 minutes: notify user "Loki appears stalled. Consider: loki resume or touch .loki/STOP"
```

### Build breakage
```
IF build fails:
  -> Log ERROR with build output
  -> Check which commit broke it (git log --oneline -3)
  -> Do NOT auto-fix — Loki should self-correct. Log and continue.
  -> If broken for 2+ consecutive checks (10+ minutes): warn user
```

### Completion detection
```
IF active_agents == 0 AND (STATUS.txt contains "complete" OR no new commits for 10 minutes):
  -> Log "COMPLETION DETECTED"
  -> Record final commit hash and timestamp
  -> Trigger transition to Phase 7 (Post-Run Capture)
```

### Agent crash
```
IF active_agents drops to 0 BUT STATUS.txt does NOT show completion:
  -> Log WARNING: "All agents exited but completion not confirmed"
  -> Check /tmp/loki-<change>.log for crash output
  -> Suggest: loki resume
```

## Mid-run issue filing

If the gardening agent detects persistent issues:
- **Build failures:** File as GitHub issue immediately with `--label "bug" --label "auto-detected"`
- **Test failures:** Same — file immediately
- **Stalls:** Do NOT file as issues (operational, not bugs)

Mid-run issues get picked up in the next autonomous loop iteration automatically.

## Steering mid-run

```bash
touch .loki/PAUSE          # Pause gracefully
touch .loki/STOP           # Stop immediately
echo "guidance" > .loki/HUMAN_INPUT.md  # Inject human guidance (requires LOKI_PROMPT_INJECTION=true)
```

## Dashboard

Direct user to `http://localhost:57374/` for the visual dashboard.
