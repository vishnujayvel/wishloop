#!/usr/bin/env bash
# Persistent PR Babysitter — monitors ALL open PRs through merge.
# Single loop, handles multiple PRs, merges in dependency order.
#
# Usage: bash pr-babysitter.sh [poll-interval-seconds] [max-cycles]
# Integration: /loop 3m bash <skill-path>/scripts/pr-babysitter.sh
#
# Outputs structured status + ACTION directives for the orchestrating agent.

set -euo pipefail

POLL_INTERVAL="${1:-180}"  # Default: 3 minutes
MAX_CYCLES="${2:-100}"     # Default: 100 cycles (~5 hours at 3min)
CYCLE=0

echo "=== PR Babysitter Started ==="
echo "Poll interval: ${POLL_INTERVAL}s | Max cycles: $MAX_CYCLES"
echo ""

check_prs() {
  CYCLE=$((CYCLE + 1))
  TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M UTC")

  echo "--- Cycle $CYCLE / $MAX_CYCLES — $TIMESTAMP ---"

  # Fetch all open PRs
  PRS=$(gh pr list --state open --json number,title,headRefName,statusCheckRollup,reviewDecision,mergeable,createdAt --jq '
    sort_by(.createdAt) | .[] |
    {
      number: .number,
      title: .title,
      branch: .headRefName,
      checks: (if (.statusCheckRollup | length) == 0 then "none"
               elif (.statusCheckRollup | all(.conclusion == "SUCCESS")) then "pass"
               elif (.statusCheckRollup | any(.conclusion == "FAILURE")) then "fail"
               elif (.statusCheckRollup | any(.status == "IN_PROGRESS" or .status == "QUEUED")) then "pending"
               else "unknown" end),
      review: (.reviewDecision // "none"),
      mergeable: (.mergeable // "UNKNOWN"),
      created: .createdAt
    }
  ' 2>/dev/null)

  if [ -z "$PRS" ] || [ "$PRS" = "null" ]; then
    echo "No open PRs found."
    echo ""
    echo "ACTION: ALL_PRS_MERGED"
    echo "All PRs have been merged. PR babysitter can exit."
    return 1  # Signal to stop
  fi

  echo "Open PRs:"
  echo "$PRS" | jq -r '"  #\(.number) [\(.checks)] [\(.review)] [\(.mergeable)] — \(.title)"'
  echo ""

  # Process each PR (oldest first for correct merge order)
  echo "$PRS" | jq -c '.' | while IFS= read -r pr; do
    NUMBER=$(echo "$pr" | jq -r '.number')
    TITLE=$(echo "$pr" | jq -r '.title')
    CHECKS=$(echo "$pr" | jq -r '.checks')
    REVIEW=$(echo "$pr" | jq -r '.review')
    MERGEABLE=$(echo "$pr" | jq -r '.mergeable')

    # --- Check for CodeRabbit "Currently processing" ---
    LATEST_COMMENTS=$(gh pr view "$NUMBER" --json comments --jq '.comments[-3:][].body' 2>/dev/null || echo "")
    if echo "$LATEST_COMMENTS" | grep -qi "currently processing\|generating review"; then
      echo "  PR #$NUMBER: CodeRabbit still processing. Waiting."
      continue
    fi

    # --- Check for unresolved review comments ---
    REVIEW_COMMENTS=$(gh api "repos/{owner}/{repo}/pulls/$NUMBER/comments" --jq '[.[] | select(.in_reply_to_id == null)] | length' 2>/dev/null || echo "0")
    RESOLVED_THREADS=$(gh pr view "$NUMBER" --json reviewThreads --jq '[.reviewThreads[] | select(.isResolved)] | length' 2>/dev/null || echo "0")
    UNRESOLVED_THREADS=$(gh pr view "$NUMBER" --json reviewThreads --jq '[.reviewThreads[] | select(.isResolved | not)] | length' 2>/dev/null || echo "0")

    if [ "$UNRESOLVED_THREADS" -gt 0 ]; then
      echo "  PR #$NUMBER: $UNRESOLVED_THREADS unresolved review threads."
      echo ""
      echo "  ACTION: FIX_REVIEW_COMMENTS"
      echo "  PR #$NUMBER has $UNRESOLVED_THREADS unresolved review comments."
      echo "  Dispatch a subagent to address them: gh pr view $NUMBER --comments"
      continue
    fi

    # --- Ready to merge? ---
    if [ "$CHECKS" = "pass" ] && [ "$MERGEABLE" = "MERGEABLE" ] && { [ "$REVIEW" = "APPROVED" ] || [ "$REVIEW" = "none" ]; }; then
      echo "  PR #$NUMBER: All checks pass, mergeable, no blocking comments."
      echo ""
      echo "  ACTION: MERGE_PR"
      echo "  PR #$NUMBER is ready to merge. Run: gh pr merge $NUMBER --squash --delete-branch"
      continue
    fi

    # --- Checks failing ---
    if [ "$CHECKS" = "fail" ]; then
      echo "  PR #$NUMBER: CI checks failing."
      echo ""
      echo "  ACTION: FIX_CI_FAILURE"
      echo "  PR #$NUMBER has failing CI. Investigate and fix."
      continue
    fi

    # --- Checks pending ---
    if [ "$CHECKS" = "pending" ]; then
      echo "  PR #$NUMBER: Checks still running. Waiting."
      continue
    fi

    # --- Merge conflict ---
    if [ "$MERGEABLE" = "CONFLICTING" ]; then
      echo "  PR #$NUMBER: Merge conflict detected."
      echo ""
      echo "  ACTION: REBASE_PR"
      echo "  PR #$NUMBER has conflicts. Rebase onto main: git rebase main"
      continue
    fi

    echo "  PR #$NUMBER: Status unclear (checks=$CHECKS, review=$REVIEW, mergeable=$MERGEABLE). Monitoring."
  done

  echo ""
  return 0  # Continue monitoring
}

# Single check mode (for /loop integration)
if [ "${POLL_INTERVAL}" = "once" ]; then
  check_prs
  exit $?
fi

# Continuous loop mode
while [ "$CYCLE" -lt "$MAX_CYCLES" ]; do
  if ! check_prs; then
    echo ""
    echo "=== PR Babysitter Complete — all PRs merged ==="
    exit 0
  fi

  echo "Next check in ${POLL_INTERVAL}s..."
  sleep "$POLL_INTERVAL"
done

echo ""
echo "=== PR Babysitter stopped — max cycles ($MAX_CYCLES) reached ==="
echo "Open PRs may still need attention."
