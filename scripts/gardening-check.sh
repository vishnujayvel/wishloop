#!/usr/bin/env bash
# Gardening check for OpenSpec Loki Loop
# Run every 5 minutes during Loki execution to monitor progress.
# Usage: bash gardening-check.sh [project-dir] [change-name]
# Integration: /loop 5m bash <skill-path>/scripts/gardening-check.sh /path/to/project my-change

set -euo pipefail

PROJECT_DIR="${1:-.}"
CHANGE_NAME="${2:-unknown}"
JOURNAL="$PROJECT_DIR/docs/plans/pipeline-journal.md"
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M UTC")

# Detect Worktrunk
WT_AVAILABLE=false
if command -v wt &>/dev/null; then
  WT_AVAILABLE=true
fi

cd "$PROJECT_DIR"

# Worktrunk-enhanced status check
check_wt_status() {
  if [ "$WT_AVAILABLE" = true ]; then
    echo "=== Worktrunk Status ==="
    wt list 2>/dev/null || true
    echo ""
  fi
}

# --- Worktrunk status (additive, before git checks) ---
check_wt_status

# --- Check 1: Recent commits ---
RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No git repo")

# --- Check 2: Loki task progress ---
STATUS=$(cat .loki/STATUS.txt 2>/dev/null | head -1 || echo "No STATUS.txt")

# --- Check 3: Active agents ---
AGENT_COUNT=$(ps aux | grep "claude.*dangerously" | grep -v grep | wc -l | tr -d ' ')

# --- Check 4: Build status ---
BUILD_STATUS=0
BUILD_OUTPUT="No build system detected"
if [ -f package.json ]; then
  BUILD_OUTPUT=$(npm run build 2>&1 | tail -5) || BUILD_STATUS=$?
elif [ -f Makefile ]; then
  BUILD_OUTPUT=$(make build 2>&1 | tail -5) || BUILD_STATUS=$?
elif [ -f Cargo.toml ]; then
  BUILD_OUTPUT=$(cargo build 2>&1 | tail -5) || BUILD_STATUS=$?
elif [ -f go.mod ]; then
  BUILD_OUTPUT=$(go build ./... 2>&1 | tail -5) || BUILD_STATUS=$?
fi

if [ "$BUILD_STATUS" -eq 0 ]; then
  BUILD_RESULT="PASS"
else
  BUILD_RESULT="FAIL"
fi

# --- Check 5: Git conflicts ---
GIT_STATUS=$(git status --short 2>/dev/null || echo "No git repo")
if echo "$GIT_STATUS" | grep -q "^UU\|^AA\|^DD"; then
  CONFLICTS=$(echo "$GIT_STATUS" | grep "^UU\|^AA\|^DD")
else
  CONFLICTS="NONE"
fi

# --- Output structured report ---
echo "=== Gardening Check: $TIMESTAMP ==="
echo "Change: $CHANGE_NAME"
echo ""
echo "Recent commits:"
echo "$RECENT_COMMITS"
echo ""
echo "STATUS.txt: $STATUS"
echo "Active agents: $AGENT_COUNT"
echo "Build: $BUILD_RESULT"
echo "Conflicts: $CONFLICTS"
echo ""

# --- Anomaly detection ---
LAST_COMMIT_TIME=$(git log -1 --format=%ct 2>/dev/null || echo 0)
NOW=$(date +%s)
MINUTES_SINCE_COMMIT=$(( (NOW - LAST_COMMIT_TIME) / 60 ))

if [ "$AGENT_COUNT" -gt 0 ] && [ "$MINUTES_SINCE_COMMIT" -gt 15 ]; then
  echo "WARNING: Potential stall — $AGENT_COUNT agents active but no commits for ${MINUTES_SINCE_COMMIT} minutes"
fi

if [ "$AGENT_COUNT" -eq 0 ] && echo "$STATUS" | grep -qi "complete"; then
  echo "COMPLETION DETECTED"
  echo ""
  echo "ACTION: ADVANCE_TO_PHASE_7"
  echo "Loki has completed. Proceed immediately to Phase 7 (Post-Run Capture) then Phase 8 (Verification)."
  echo "Do NOT wait for user input. The pipeline must continue autonomously."

  # Update state file if it exists
  STATE_FILE="$PROJECT_DIR/.wishloop/state.json"
  if [ -d "$PROJECT_DIR/.wishloop" ]; then
    cat > "$STATE_FILE" << STATEJSON
{"phase": 7, "phaseLabel": "Post-Run Capture", "advancedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "reason": "Loki completion detected by gardening check", "change": "$CHANGE_NAME"}
STATEJSON
  fi
fi

if [ "$AGENT_COUNT" -eq 0 ] && ! echo "$STATUS" | grep -qi "complete" && [ "$STATUS" != "No STATUS.txt" ]; then
  echo "WARNING: All agents exited but completion not confirmed"
  echo ""
  echo "ACTION: INVESTIGATE_EXIT"
  echo "All Loki agents exited without completion signal. Check logs for errors."
fi

# --- Append journal entry ---
mkdir -p "$(dirname "$JOURNAL")"

# Include branch name for worktree disambiguation when Worktrunk is available
BRANCH_LABEL=""
if [ "$WT_AVAILABLE" = true ]; then
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  BRANCH_LABEL=" [branch: $CURRENT_BRANCH]"
fi

cat >> "$JOURNAL" << EOF

## $TIMESTAMP — Gardening Check${BRANCH_LABEL}

| Metric | Value |
|--------|-------|
| Commits since last check | $(echo "$RECENT_COMMITS" | head -3) |
| Active agents | $AGENT_COUNT |
| STATUS.txt summary | $STATUS |
| Build status | $BUILD_RESULT |
| Git conflicts | $CONFLICTS |

**Observations:** Auto-check. ${MINUTES_SINCE_COMMIT}m since last commit. ${AGENT_COUNT} agents active.
EOF

echo "Journal entry appended to $JOURNAL"
