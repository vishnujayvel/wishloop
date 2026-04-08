#!/usr/bin/env bash
# Lightweight session monitor for Wishloop v2.
# Uses `loki status --json` for health checks (P6: External Interface Only).
# No direct .loki/ file access — all interaction through Loki's public CLI.
#
# Usage: bash gardening-check.sh [project-dir] [change-name]
# Integration: /loop 5m bash <skill-path>/scripts/gardening-check.sh /path/to/project my-change

set -euo pipefail

PROJECT_DIR="${1:-.}"
CHANGE_NAME="${2:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M UTC")
STATE_FILE="$PROJECT_DIR/.wishloop/state.json"

# Track stall detection across polls (file-based counter)
STALL_FILE="$PROJECT_DIR/.wishloop/.stall-tracker"

cd "$PROJECT_DIR"

# --- Query Loki session status via public CLI ---
STATUS_JSON=""
SESSION_STATUS="unknown"
ITERATION="0"
TASKS_DONE="0"
TASKS_PENDING="0"

if command -v loki &>/dev/null; then
  STATUS_JSON=$(loki status --json 2>/dev/null || echo '{}')
  SESSION_STATUS=$(echo "$STATUS_JSON" | jq -r '.status // "unknown"')
  ITERATION=$(echo "$STATUS_JSON" | jq -r '.iteration // "0"')
  TASKS_DONE=$(echo "$STATUS_JSON" | jq -r '.task_counts.completed // "0"')
  TASKS_PENDING=$(echo "$STATUS_JSON" | jq -r '.task_counts.pending // "0"')
else
  echo "WARNING: loki CLI not found on PATH. Cannot monitor session."
  SESSION_STATUS="unknown"
fi

# --- Worktrunk status (additive) ---
if command -v wt &>/dev/null; then
  echo "=== Worktrunk Status ==="
  wt list 2>/dev/null || true
  echo ""
fi

# --- Recent commits (lightweight progress indicator) ---
RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || echo "No git repo")

# --- Output structured report ---
echo "=== Session Monitor: $TIMESTAMP ==="
echo "Change: $CHANGE_NAME"
echo ""
echo "Loki status: $SESSION_STATUS"
echo "Iteration: $ITERATION"
echo "Tasks: $TASKS_DONE completed, $TASKS_PENDING pending"
echo ""
echo "Recent commits:"
echo "$RECENT_COMMITS"
echo ""

# --- Stall detection ---
if [ "$SESSION_STATUS" = "running" ]; then
  LAST_ITERATION="0"
  STALL_COUNT=0

  if [ -f "$STALL_FILE" ]; then
    LAST_ITERATION=$(jq -r '.iteration // "0"' "$STALL_FILE" 2>/dev/null || echo "0")
    STALL_COUNT=$(jq -r '.count // 0' "$STALL_FILE" 2>/dev/null || echo "0")
  fi

  if [ "$ITERATION" = "$LAST_ITERATION" ]; then
    STALL_COUNT=$((STALL_COUNT + 1))
  else
    STALL_COUNT=0
  fi

  mkdir -p "$(dirname "$STALL_FILE")"
  echo "{\"iteration\": \"$ITERATION\", \"count\": $STALL_COUNT, \"checkedAt\": \"$TIMESTAMP\"}" > "$STALL_FILE"

  if [ "$STALL_COUNT" -ge 3 ]; then
    echo "WARNING: Session stalled — iteration $ITERATION unchanged for $((STALL_COUNT * 5)) minutes"
    echo ""
    echo "ACTION: SESSION_STALLED"
    echo "Session has not progressed for 15+ minutes. Consider: loki stop && loki resume"
  fi
fi

# --- Completion detection ---
if [ "$SESSION_STATUS" = "completed" ]; then
  echo "SESSION COMPLETE"
  echo ""
  echo "ACTION: SESSION_COMPLETE"
  echo "Loki session completed. Proceed to Step 4 (Post-Session)."

  # Update state file
  if [ -d "$PROJECT_DIR/.wishloop" ]; then
    jq -n \
      --arg change "$CHANGE_NAME" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{"step": "post-session", "change": $change, "completedAt": $ts}' \
      > "$STATE_FILE"
  fi

  # Clean up stall tracker
  rm -f "$STALL_FILE"
fi

# --- Crash detection ---
if [ "$SESSION_STATUS" = "stopped" ] || [ "$SESSION_STATUS" = "unknown" ]; then
  # Check if this was expected (user-initiated stop) or a crash
  if [ "$SESSION_STATUS" = "unknown" ]; then
    echo "WARNING: No active Loki session found — may have crashed"
    echo ""
    echo "ACTION: SESSION_CRASHED"
    echo "Session may have crashed. Check logs. Suggest: loki resume"

    if [ -d "$PROJECT_DIR/.wishloop" ]; then
      jq -n \
        --arg change "$CHANGE_NAME" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{"step": "post-session", "change": $change, "status": "crashed", "completedAt": $ts}' \
        > "$STATE_FILE"
    fi
  else
    echo "Session stopped."
    echo ""
    echo "ACTION: SESSION_COMPLETE"
    echo "Loki session stopped. Proceed to Step 4 (Post-Session)."

    if [ -d "$PROJECT_DIR/.wishloop" ]; then
      jq -n \
        --arg change "$CHANGE_NAME" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{"step": "post-session", "change": $change, "completedAt": $ts}' \
        > "$STATE_FILE"
    fi
  fi

  rm -f "$STALL_FILE"
fi
