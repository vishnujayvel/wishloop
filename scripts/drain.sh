#!/usr/bin/env bash
# Drain mode orchestrator for Wishloop v2.
# Autonomously processes ALL open GitHub issues until the backlog is empty.
# Uses only Loki's public CLI (P6: External Interface Only).
#
# Delegates to existing scripts:
#   - gardening-check.sh for session monitoring
#   - pr-babysitter.sh for PR lifecycle
#
# Usage:
#   bash drain.sh [--label <label>] [--max-iterations <N>] [--cooldown <seconds>]
#
# Examples:
#   bash drain.sh                          # drain all open issues
#   bash drain.sh --label bug              # drain only bugs
#   bash drain.sh --label refactor --max-iterations 3

set -euo pipefail

# --- Configuration ---
LABEL_FILTER=""
MAX_ITERATIONS=5
COOLDOWN_SECONDS=120
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$PROJECT_DIR/.wishloop/state.json"
ENV_FILE="$PROJECT_DIR/.wishloop/loki.env"
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_EPOCH=$(date +%s)

# Counters for cumulative summary
ISSUES_AT_START=0
ISSUES_RESOLVED=0
ISSUES_FILED=0
SESSIONS_LAUNCHED=0
PRS_MERGED=0
QUICK_FIXES=0
ITERATION=0

# --- Parse arguments ---
while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      LABEL_FILTER="${2:?--label requires a value}"
      shift 2
      ;;
    --max-iterations)
      MAX_ITERATIONS="${2:?--max-iterations requires a value}"
      shift 2
      ;;
    --cooldown)
      COOLDOWN_SECONDS="${2:?--cooldown requires a value}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash drain.sh [--label <label>] [--max-iterations <N>] [--cooldown <seconds>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validate numeric arguments ---
if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Error: --max-iterations must be a positive integer, got: $MAX_ITERATIONS" >&2
  exit 1
fi
if ! [[ "$COOLDOWN_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "Error: --cooldown must be a positive integer, got: $COOLDOWN_SECONDS" >&2
  exit 1
fi

cd "$PROJECT_DIR"

# --- Helper: fetch open issues ---
fetch_issues() {
  local args=("--state" "open" "--limit" "9999" "--json" "number,title,body,labels,createdAt")
  if [ -n "$LABEL_FILTER" ]; then
    args+=("--label" "$LABEL_FILTER")
  fi
  gh issue list "${args[@]}" 2>/dev/null || echo "[]"
}

# --- Helper: prioritize issues ---
# Returns issue numbers in priority order.
# Priority tiers: critical > bug > auto-detected > refactor > enhancement > documentation
# Within same tier: smaller effort first (body length heuristic)
prioritize_issues() {
  local issues_json="$1"
  echo "$issues_json" | jq -r '
    def priority_score:
      (.labels // []) as $labels |
      if ($labels | map(.name) | any(. == "critical")) then 0
      elif ($labels | map(.name) | any(. == "bug")) then 1
      elif ($labels | map(.name) | any(. == "auto-detected")) then 2
      elif ($labels | map(.name) | any(. == "refactor")) then 3
      elif ($labels | map(.name) | any(. == "enhancement")) then 4
      elif ($labels | map(.name) | any(. == "documentation")) then 5
      else 6 end;
    def effort_score:
      ((.body // "") | length) ;
    sort_by([priority_score, effort_score]) | .[].number
  '
}

# --- Helper: check for open PRs from current session ---
# Scopes to the current issue by checking PR body for "Closes #N" or "Fixes #N".
# Falls back to first open PR if no issue context is available.
check_open_prs() {
  local issue_num="${1:-}"
  if [ -n "$issue_num" ]; then
    # Search for PR linked to this specific issue
    local pr
    pr=$(gh pr list --state open --search "closes #$issue_num OR fixes #$issue_num" --json number --jq '.[0].number // empty' 2>/dev/null || true)
    if [ -n "$pr" ]; then
      echo "$pr"
      return
    fi
  fi
  # Fallback: check state file for persisted PR number
  if [ -f "$STATE_FILE" ]; then
    local state_pr
    state_pr=$(jq -r '.pr // empty' "$STATE_FILE" 2>/dev/null || true)
    if [ -n "$state_pr" ] && [ "$state_pr" != "null" ]; then
      # Verify PR is still open
      local pr_state
      pr_state=$(gh pr view "$state_pr" --json state --jq '.state' 2>/dev/null || echo "CLOSED")
      if [ "$pr_state" = "OPEN" ]; then
        echo "$state_pr"
        return
      fi
    fi
  fi
  # Last resort: first open PR (may be unrelated, but acceptable for single-PR repos)
  gh pr list --state open --json number --jq '.[0].number // empty' 2>/dev/null || true
}

# --- Helper: check loki session status ---
check_loki_status() {
  if command -v loki &>/dev/null; then
    loki status --json 2>/dev/null || echo '{"status": "unknown"}'
  else
    echo '{"status": "unknown"}'
  fi
}

# --- Helper: monitor loki session until completion ---
# Delegates to gardening-check.sh for each poll (reuses stall detection, dashboard).
# Uses loki status --json as the sole monitoring mechanism (prd-001).
monitor_session() {
  local change_name="$1"
  local max_polls=60  # 60 * 5min = 5 hours max
  local poll_count=0

  echo "Monitoring session: $change_name"

  while [ "$poll_count" -lt "$max_polls" ]; do
    poll_count=$((poll_count + 1))

    # Delegate monitoring check to gardening-check.sh
    local check_output
    check_output=$(bash "$SCRIPT_DIR/gardening-check.sh" "$PROJECT_DIR" "$change_name" 2>&1 || true)
    echo "$check_output"

    # Parse action directives from gardening-check.sh
    if echo "$check_output" | grep -q "ACTION: SESSION_COMPLETE"; then
      echo "  Session completed."
      update_state "post-session" "$change_name"
      return 0
    fi

    if echo "$check_output" | grep -q "ACTION: SESSION_CRASHED"; then
      echo "  Session crashed. Attempting loki resume..."
      loki_resume
      sleep 30
      local retry_status
      retry_status=$(check_loki_status | jq -r '.status // "unknown"')
      if [ "$retry_status" = "unknown" ]; then
        echo "  Resume failed."
        update_state "post-session" "$change_name"
        return 1
      fi
    fi

    if echo "$check_output" | grep -q "ACTION: SESSION_STALLED"; then
      echo "  Session stalled. Stopping and resuming..."
      loki_stop
      sleep 10
      loki_resume
      sleep 30
      local stall_retry
      stall_retry=$(check_loki_status | jq -r '.status // "unknown"')
      if [ "$stall_retry" = "unknown" ]; then
        echo "  Recovery failed."
        update_state "post-session" "$change_name"
        return 1
      fi
    fi

    sleep 300  # Poll every 5 minutes
  done

  echo "  Monitoring timeout reached. Stopping session."
  loki_stop
  update_state "post-session" "$change_name"
  return 1
}

# --- Helper: stop a loki session (prd-002) ---
# Uses `loki stop` — the public CLI for emergency stops.
loki_stop() {
  if command -v loki &>/dev/null; then
    echo "  Executing: loki stop"
    loki stop 2>/dev/null || true
  else
    echo "  WARNING: loki CLI not found. Cannot stop session."
  fi
}

# --- Helper: resume a loki session (prd-003) ---
# Uses `loki resume` — the public CLI for checkpoint recovery.
loki_resume() {
  if command -v loki &>/dev/null; then
    echo "  Executing: loki resume"
    loki resume 2>/dev/null || true
  else
    echo "  WARNING: loki CLI not found. Cannot resume session."
  fi
}

# --- Helper: update state file (uses jq for safe JSON construction) ---
update_state() {
  local step="$1"
  local change="${2:-}"

  mkdir -p "$(dirname "$STATE_FILE")"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  case "$step" in
    session)
      jq -n --arg step "$step" --arg change "$change" --arg mode "drain" \
        --argjson iteration "$ITERATION" --arg startedAt "$ts" \
        '{step: $step, change: $change, mode: $mode, iteration: $iteration, startedAt: $startedAt}' \
        > "$STATE_FILE"
      ;;
    post-session)
      jq -n --arg step "$step" --arg change "$change" --arg mode "drain" \
        --argjson iteration "$ITERATION" --arg completedAt "$ts" \
        '{step: $step, change: $change, mode: $mode, iteration: $iteration, completedAt: $completedAt}' \
        > "$STATE_FILE"
      ;;
    babysitter)
      jq -n --arg step "$step" --argjson pr "$change" --arg mode "drain" \
        --argjson iteration "$ITERATION" \
        '{step: $step, pr: $pr, mode: $mode, iteration: $iteration}' \
        > "$STATE_FILE"
      ;;
    loop)
      jq -n --arg step "$step" --arg mode "drain" --argjson iteration "$ITERATION" \
        '{step: $step, mode: $mode, iteration: $iteration}' \
        > "$STATE_FILE"
      ;;
    done)
      jq -n --arg step "$step" --arg mode "drain" --argjson iteration "$ITERATION" \
        --arg completedAt "$ts" \
        '{step: $step, mode: $mode, iteration: $iteration, completedAt: $completedAt}' \
        > "$STATE_FILE"
      ;;
  esac
}

# --- Helper: post-session tasks ---
run_post_session() {
  local change_name="$1"
  local session_ok="${2:-true}"

  echo "Running post-session tasks..."

  # Docs check
  if command -v loki &>/dev/null; then
    loki docs check 2>/dev/null || true
  fi

  # Capture run
  local checkpoint
  checkpoint=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  if [ -f "$SCRIPT_DIR/capture-run.sh" ]; then
    bash "$SCRIPT_DIR/capture-run.sh" "$PROJECT_DIR" "$change_name" "$checkpoint" "$START_TIME" "0" 2>/dev/null || true
  fi
}

# --- Helper: babysit PR through merge ---
# Delegates to pr-babysitter.sh for PR state checking, handles loki quick for fixes.
babysit_pr() {
  local pr_number="$1"
  local max_babysit_cycles=20
  local cycle=0
  local escalation_count=0

  echo "Babysitting PR #$pr_number..."
  update_state "babysitter" "$pr_number"

  while [ "$cycle" -lt "$max_babysit_cycles" ]; do
    cycle=$((cycle + 1))

    # Delegate PR state check to pr-babysitter.sh
    local babysitter_output
    babysitter_output=$(bash "$SCRIPT_DIR/pr-babysitter.sh" once 2>&1 || true)
    echo "$babysitter_output"

    # Parse action directives from pr-babysitter.sh, scoped to our PR
    if echo "$babysitter_output" | grep -q "ACTION: ALL_PRS_MERGED"; then
      echo "  All PRs merged!"
      PRS_MERGED=$((PRS_MERGED + 1))
      return 0
    fi

    # Verify the action targets our specific PR before acting
    if echo "$babysitter_output" | grep -q "ACTION: MERGE_PR" && echo "$babysitter_output" | grep -q "PR #$pr_number"; then
      echo "  Merging PR #$pr_number..."
      if gh pr merge "$pr_number" --squash --delete-branch 2>/dev/null; then
        PRS_MERGED=$((PRS_MERGED + 1))
        return 0
      else
        echo "  Merge failed for PR #$pr_number."
        return 1
      fi
    fi

    if echo "$babysitter_output" | grep -q "ACTION: FIX_REVIEW_COMMENTS" && echo "$babysitter_output" | grep -q "PR #$pr_number"; then
      echo "  Unresolved review threads on PR #$pr_number. Dispatching loki quick..."
      if command -v loki &>/dev/null; then
        loki quick "Read and address all review comments on PR #$pr_number. Run 'gh pr view $pr_number --comments' to see them. Fix each issue, commit, and push." 2>/dev/null || true
        QUICK_FIXES=$((QUICK_FIXES + 1))
        escalation_count=$((escalation_count + 1))
      fi

      # Circuit breaker: after 3 escalations, bail
      if [ "$escalation_count" -ge 3 ]; then
        echo "  Circuit breaker: 3 escalations for PR #$pr_number. Skipping."
        return 1
      fi

      sleep 90
      continue
    fi

    if echo "$babysitter_output" | grep -q "ACTION: FIX_CI_FAILURE" && echo "$babysitter_output" | grep -q "PR #$pr_number"; then
      echo "  CI failing on PR #$pr_number. Dispatching loki quick to fix..."
      if command -v loki &>/dev/null; then
        loki quick "CI checks are failing on PR #$pr_number. Investigate and fix the failures." 2>/dev/null || true
        QUICK_FIXES=$((QUICK_FIXES + 1))
        escalation_count=$((escalation_count + 1))
      fi

      if [ "$escalation_count" -ge 3 ]; then
        echo "  Circuit breaker: 3 escalations for PR #$pr_number. Skipping."
        return 1
      fi

      sleep 90
      continue
    fi

    if echo "$babysitter_output" | grep -q "ACTION: REBASE_PR" && echo "$babysitter_output" | grep -q "PR #$pr_number"; then
      echo "  Merge conflict on PR #$pr_number. Attempting rebase..."
      local pr_branch
      pr_branch=$(gh pr view "$pr_number" --json headRefName --jq '.headRefName' 2>/dev/null || echo "")
      if [ -n "$pr_branch" ]; then
        git fetch origin 2>/dev/null || true
        git checkout -- "$pr_branch" 2>/dev/null || git checkout "$pr_branch" 2>/dev/null || true
        git rebase origin/main 2>/dev/null || true
        git push --force-with-lease 2>/dev/null || true
      fi
      sleep 90
      continue
    fi

    # No actionable directive — still processing or checks pending
    echo "  PR #$pr_number: waiting for state change..."
    sleep 90
  done

  echo "  Babysitter timeout for PR #$pr_number."
  return 1
}

# --- Helper: compose dynamic completion promise ---
compose_completion_promise() {
  local issue_number="$1"
  local issue_title="$2"

  local task_criteria="Issue #$issue_number ($issue_title) resolved with passing tests"
  local process_bar="${WISHLOOP_PROCESS_BAR:-PR created, all CI checks passing, CodeRabbit review received, all comments fixed and responded to, no unresolved review threads}"

  export LOKI_COMPLETION_PROMISE="$task_criteria. THEN: $process_bar"
}

# --- Helper: display Wishloop Status Dashboard ---
display_dashboard() {
  local status_json
  status_json=$(check_loki_status)
  local state_json
  state_json=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')

  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  WISHLOOP DRAIN STATUS                                  ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  Iteration: %d / %d                                     ║\n" "$ITERATION" "$MAX_ITERATIONS"
  printf "║  Label:     %-43s ║\n" "${LABEL_FILTER:-all}"
  printf "║  Step:      %-43s ║\n" "$(echo "$state_json" | jq -r '.step // "unknown"')"
  printf "║  Started:   %-43s ║\n" "$START_TIME"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║  LOKI SESSION                                           ║"
  printf "║  Status:    %-43s ║\n" "$(echo "$status_json" | jq -r '.status // "none"')"
  printf "║  Phase:     %-43s ║\n" "$(echo "$status_json" | jq -r '.phase // "N/A"')"
  printf "║  Iteration: %-43s ║\n" "$(echo "$status_json" | jq -r '.iteration // "N/A"')"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║  CUMULATIVE                                             ║"
  printf "║  Issues at start: %d | Resolved: %d | Filed: %d          ║\n" "$ISSUES_AT_START" "$ISSUES_RESOLVED" "$ISSUES_FILED"
  printf "║  Sessions: %d | PRs merged: %d | Quick fixes: %d         ║\n" "$SESSIONS_LAUNCHED" "$PRS_MERGED" "$QUICK_FIXES"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║  PR STATUS                                              ║"
  printf "║  %-53s ║\n" "$(gh pr list --json number,title,state --jq '.[0] | "#\(.number) \(.title) [\(.state)]"' 2>/dev/null || echo 'No open PR')"
  echo "╚══════════════════════════════════════════════════════════╝"
}

# --- Helper: print cumulative summary ---
print_summary() {
  local end_epoch
  end_epoch=$(date +%s)
  local duration_min=$(( (end_epoch - START_EPOCH) / 60 ))
  local remaining
  remaining=$(fetch_issues | jq 'length')
  local commits
  commits=$(git log --oneline --since="$START_TIME" 2>/dev/null | wc -l | tr -d ' ')

  echo ""
  echo "=== Drain Complete ==="
  echo "Iterations: $ITERATION | Duration: ${duration_min} min | Commits: $commits"
  echo "Issues at start: $ISSUES_AT_START | Resolved: $ISSUES_RESOLVED | Filed: $ISSUES_FILED | Remaining: $remaining"
  echo "Loki sessions: $SESSIONS_LAUNCHED | PRs merged: $PRS_MERGED | Quick fixes: $QUICK_FIXES"
}

# ====================================================================
# MAIN: Drain Loop
# ====================================================================

echo "=== Wishloop Drain Mode ==="
echo "Label filter: ${LABEL_FILTER:-all}"
echo "Max iterations: $MAX_ITERATIONS"
echo "Cooldown: ${COOLDOWN_SECONDS}s"
echo ""

# Source environment if available
if [ -f "$ENV_FILE" ]; then
  set -a && source "$ENV_FILE" && set +a
fi

# --- Count initial issues (before resumption, for accurate summary) ---
INITIAL_ISSUES_JSON=$(fetch_issues)
ISSUES_AT_START=$(echo "$INITIAL_ISSUES_JSON" | jq 'length')
echo "Open issues: $ISSUES_AT_START"

# --- Step 0: Resumption check (prd-003) ---
# Check if we're resuming from a previous drain session
if [ -f "$STATE_FILE" ]; then
  PREV_STEP=$(jq -r '.step // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  PREV_MODE=$(jq -r '.mode // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")

  if [ "$PREV_MODE" = "drain" ]; then
    echo "Resuming drain session from step: $PREV_STEP"

    case "$PREV_STEP" in
      babysitter)
        PREV_PR=$(jq -r '.pr // empty' "$STATE_FILE" 2>/dev/null || true)
        if [ -n "$PREV_PR" ]; then
          echo "Resuming PR babysitter for #$PREV_PR..."
          if babysit_pr "$PREV_PR"; then
            ISSUES_RESOLVED=$((ISSUES_RESOLVED + 1))
          fi
        fi
        ;;
      session)
        PREV_CHANGE=$(jq -r '.change // empty' "$STATE_FILE" 2>/dev/null || true)
        SESSION_STATUS=$(check_loki_status | jq -r '.status // "unknown"')
        if [ "$SESSION_STATUS" = "running" ]; then
          echo "Active Loki session found. Resuming monitoring..."
          monitor_session "${PREV_CHANGE:-unknown}" || true
          run_post_session "${PREV_CHANGE:-unknown}"
          OPEN_PR=$(check_open_prs)
          if [ -n "$OPEN_PR" ]; then
            if babysit_pr "$OPEN_PR"; then
              ISSUES_RESOLVED=$((ISSUES_RESOLVED + 1))
            fi
          fi
        elif [ "$SESSION_STATUS" = "unknown" ]; then
          echo "No active session. Attempting loki resume..."
          loki_resume
          sleep 30
          RETRY_STATUS=$(check_loki_status | jq -r '.status // "unknown"')
          if [ "$RETRY_STATUS" = "running" ]; then
            monitor_session "${PREV_CHANGE:-unknown}" || true
            run_post_session "${PREV_CHANGE:-unknown}"
            OPEN_PR=$(check_open_prs)
            if [ -n "$OPEN_PR" ]; then
              if babysit_pr "$OPEN_PR"; then
                ISSUES_RESOLVED=$((ISSUES_RESOLVED + 1))
              fi
            fi
          fi
        fi
        ;;
      post-session)
        OPEN_PR=$(check_open_prs)
        if [ -n "$OPEN_PR" ]; then
          echo "Open PR found: #$OPEN_PR. Resuming babysitter..."
          if babysit_pr "$OPEN_PR"; then
            ISSUES_RESOLVED=$((ISSUES_RESOLVED + 1))
          fi
        fi
        ;;
    esac
  fi
fi

echo ""

# --- Main drain loop ---
while [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; do
  ITERATION=$((ITERATION + 1))
  update_state "loop"

  echo ""
  echo "=== Drain Iteration $ITERATION / $MAX_ITERATIONS ==="

  # Display dashboard at each iteration
  display_dashboard
  echo ""

  # Step 1: FETCH
  ISSUES_JSON=$(fetch_issues)
  ISSUE_COUNT=$(echo "$ISSUES_JSON" | jq 'length')

  # Step 2: STOP if no issues
  if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo "No open issues remaining. Drain complete."
    break
  fi

  echo "Open issues: $ISSUE_COUNT"

  # Step 3: Check for in-progress work (open PRs, running sessions)
  OPEN_PR=$(check_open_prs)
  if [ -n "$OPEN_PR" ]; then
    echo "Open PR #$OPEN_PR found. Babysitting..."
    if babysit_pr "$OPEN_PR"; then
      ISSUES_RESOLVED=$((ISSUES_RESOLVED + 1))
    fi

    if [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; then
      echo "Cooldown: ${COOLDOWN_SECONDS}s..."
      sleep "$COOLDOWN_SECONDS"
    fi
    continue
  fi

  LOKI_STATUS=$(check_loki_status | jq -r '.status // "unknown"')
  if [ "$LOKI_STATUS" = "running" ]; then
    echo "Loki session already running. Monitoring..."
    monitor_session "drain-iter-$ITERATION" || true
    OPEN_PR=$(check_open_prs)
    if [ -n "$OPEN_PR" ]; then
      if babysit_pr "$OPEN_PR"; then
        ISSUES_RESOLVED=$((ISSUES_RESOLVED + 1))
      fi
    fi

    if [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; then
      echo "Cooldown: ${COOLDOWN_SECONDS}s..."
      sleep "$COOLDOWN_SECONDS"
    fi
    continue
  fi

  # Step 4: PRIORITIZE and PICK
  ISSUE_NUMBER=$(prioritize_issues "$ISSUES_JSON" | head -1)
  if [ -z "$ISSUE_NUMBER" ]; then
    echo "No issues to process. Exiting."
    break
  fi

  ISSUE_TITLE=$(echo "$ISSUES_JSON" | jq -r --argjson n "$ISSUE_NUMBER" '.[] | select(.number == $n) | .title')
  echo "Selected: #$ISSUE_NUMBER — $ISSUE_TITLE"

  # Step 5: CONFIGURE and LAUNCH
  update_state "session" "issue-$ISSUE_NUMBER"

  # Compose dynamic completion promise per issue
  compose_completion_promise "$ISSUE_NUMBER" "$ISSUE_TITLE"

  echo "Launching: loki run #$ISSUE_NUMBER --pr"
  SESSIONS_LAUNCHED=$((SESSIONS_LAUNCHED + 1))

  if command -v loki &>/dev/null; then
    loki run "#$ISSUE_NUMBER" --pr 2>&1 || true
  else
    echo "WARNING: loki CLI not found. Simulating session for issue #$ISSUE_NUMBER."
  fi

  # Step 6: MONITOR
  monitor_session "issue-$ISSUE_NUMBER" || true

  # Step 7: POST-SESSION
  run_post_session "issue-$ISSUE_NUMBER"

  # Step 8: BABYSIT PR (scoped to current issue)
  OPEN_PR=$(check_open_prs "$ISSUE_NUMBER")
  if [ -n "$OPEN_PR" ]; then
    if babysit_pr "$OPEN_PR"; then
      ISSUES_RESOLVED=$((ISSUES_RESOLVED + 1))
    fi
  fi

  # Step 9: Archive and clean
  git worktree prune 2>/dev/null || true

  # Cooldown between iterations
  if [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; then
    echo "Cooldown: ${COOLDOWN_SECONDS}s..."
    sleep "$COOLDOWN_SECONDS"
  fi
done

# --- Print cumulative summary ---
update_state "done"
print_summary
