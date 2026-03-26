# Run Instance Data Schema

Every Loki run produces a JSON record for institutional knowledge accumulation.

## Directory Convention (XDG-compliant)

All skill data lives outside the project repository:

```
~/.local/share/wishloop/
  learnings.json              # Accumulated cross-run learnings (categories -> entries)
  runs/
    {project}-{change}-{timestamp}.json   # One record per Loki run
```

On first use, ensure the directory exists:
```bash
mkdir -p ~/.local/share/wishloop/runs/
```

## Run Instance JSON Schema

**Filename:** `{project}-{change}-{YYYYMMDD-HHmmss}.json`

```json
{
  "project": "<project-name>",
  "change": "<change-name>",
  "iteration": 1,
  "startedAt": "<ISO8601 from launch>",
  "completedAt": "<ISO8601 from completion detection>",
  "durationMinutes": "<computed from start/end>",
  "proposal": "openspec/changes/<name>/proposal.md",
  "launchMode": "openspec-adapter | proposal-as-prd",
  "lokiPid": "<PID captured at launch>",
  "loopConfig": {
    "autonomous": true,
    "maxIterations": 5,
    "issueLabels": ["bug", "auto-detected"],
    "cooldownMinutes": 2
  },
  "commits": ["<hash1>", "<hash2>"],
  "commitMessages": ["<msg1>", "<msg2>"],
  "filesChanged": "<count>",
  "buildPassed": true,
  "unitTestsPassed": true,
  "e2eTestsPassed": true,
  "completionPromise": "<what Loki claimed it completed>",
  "manualFixesNeeded": [
    {"issue": "<description>", "commit": "<fix-commit-hash>"}
  ],
  "bugsFound": ["#N <title>"],
  "learnings": ["<learning-1>", "<learning-2>"]
}
```

## How to populate each field

| Field | Source |
|-------|--------|
| `commits` / `commitMessages` | `git log --oneline <checkpoint>..HEAD` |
| `filesChanged` | `git diff --stat <checkpoint>..HEAD \| tail -1` (parse the number) |
| `buildPassed` / `unitTestsPassed` / `e2eTestsPassed` | Run the project's verification suite |
| `completionPromise` | `.loki/STATUS.txt` or last lines of the Loki log |
| `manualFixesNeeded` | Populated in Phase 8 if user applies manual fixes |
| `bugsFound` | Populated in Phase 8 after filing GitHub issues |
| `learnings` | Populated interactively in Phase 7 (learning extraction) |

## Lifecycle

1. **Created** in Phase 7 (Post-Run Capture) with auto-detected data
2. **Updated** in Phase 8 (Verification) with bugs found and manual fixes
3. **Finalized** after Phase 8 — record is immutable after this point

## Querying run data

```bash
# List all runs for a project
ls ~/.local/share/wishloop/runs/ | grep "^<project>-"

# Read a specific run
cat ~/.local/share/wishloop/runs/<filename>.json
```
