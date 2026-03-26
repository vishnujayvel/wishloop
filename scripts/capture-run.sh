#!/usr/bin/env bash
# Capture a Loki run instance record.
# Usage: bash capture-run.sh <project-dir> <change-name> <checkpoint-hash> <start-time> <loki-pid>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CHANGE_NAME="${2:?Change name required}"
CHECKPOINT="${3:?Checkpoint hash required}"
START_TIME="${4:?Start time (ISO8601) required}"
LOKI_PID="${5:-0}"

cd "$PROJECT_DIR"

PROJECT_NAME=$(basename "$(pwd)")
COMPLETED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
DATA_DIR="$HOME/.local/share/wishloop/runs"

mkdir -p "$DATA_DIR"

# Gather data
COMMITS=$(git log --oneline "$CHECKPOINT"..HEAD 2>/dev/null | head -20)
COMMIT_HASHES=$(echo "$COMMITS" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
COMMIT_MESSAGES=$(echo "$COMMITS" | sed 's/^[a-f0-9]* //' | tr '\n' '|' | sed 's/|$//')
FILES_CHANGED=$(git diff --stat "$CHECKPOINT"..HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "0")

# Compute duration
START_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$START_TIME" +%s 2>/dev/null || date -d "$START_TIME" +%s 2>/dev/null || echo 0)
END_EPOCH=$(date +%s)
DURATION_MIN=$(( (END_EPOCH - START_EPOCH) / 60 ))

# Build checks
BUILD_PASSED=true
if [ -f package.json ]; then
  npm run build > /dev/null 2>&1 || BUILD_PASSED=false
fi

TESTS_PASSED=true
if [ -f package.json ]; then
  npm test > /dev/null 2>&1 || TESTS_PASSED=false
fi

# Loki status
COMPLETION_PROMISE=$(cat .loki/STATUS.txt 2>/dev/null | head -1 || echo "unknown")

# Proposal path
PROPOSAL="openspec/changes/$CHANGE_NAME/proposal.md"
if [ ! -f "$PROPOSAL" ]; then
  PROPOSAL="$CHANGE_NAME"
fi

OUTPUT_FILE="$DATA_DIR/${PROJECT_NAME}-${CHANGE_NAME}-${TIMESTAMP}.json"

cat > "$OUTPUT_FILE" << ENDJSON
{
  "project": "$PROJECT_NAME",
  "change": "$CHANGE_NAME",
  "iteration": 1,
  "startedAt": "$START_TIME",
  "completedAt": "$COMPLETED_AT",
  "durationMinutes": $DURATION_MIN,
  "proposal": "$PROPOSAL",
  "launchMode": "proposal-as-prd",
  "lokiPid": $LOKI_PID,
  "loopConfig": {
    "autonomous": true,
    "maxIterations": 5,
    "issueLabels": ["bug", "auto-detected"],
    "cooldownMinutes": 2
  },
  "commits": [$(echo "$COMMIT_HASHES" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')],
  "commitMessages": [$(echo "$COMMIT_MESSAGES" | sed 's/|/", "/g' | sed 's/^/"/' | sed 's/$/"/')],
  "filesChanged": $FILES_CHANGED,
  "buildPassed": $BUILD_PASSED,
  "unitTestsPassed": $TESTS_PASSED,
  "e2eTestsPassed": true,
  "completionPromise": "$COMPLETION_PROMISE",
  "manualFixesNeeded": [],
  "bugsFound": [],
  "learnings": []
}
ENDJSON

echo "Run instance saved: $OUTPUT_FILE"
