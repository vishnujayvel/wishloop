#!/usr/bin/env bash
# Test suite for Wishloop v2 scripts
# Usage: bash tests/test-scripts.sh
# Exit code: 0 = all pass, 1 = failures

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC}: $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $test_name"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo -e "  ${GREEN}PASS${NC}: $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $test_name"
    echo "    Expected to contain: $expected"
    echo "    Actual: $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" not_expected="$2" actual="$3"
  if echo "$actual" | grep -q "$not_expected"; then
    echo -e "  ${RED}FAIL${NC}: $test_name"
    echo "    Should NOT contain: $not_expected"
    FAIL=$((FAIL + 1))
  else
    echo -e "  ${GREEN}PASS${NC}: $test_name"
    PASS=$((PASS + 1))
  fi
}

assert_file_exists() {
  local test_name="$1" filepath="$2"
  if [ -f "$filepath" ]; then
    echo -e "  ${GREEN}PASS${NC}: $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $test_name — file not found: $filepath"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local test_name="$1" filepath="$2"
  if [ ! -f "$filepath" ]; then
    echo -e "  ${GREEN}PASS${NC}: $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $test_name — file should not exist: $filepath"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  ${GREEN}PASS${NC}: $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $test_name — expected exit $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# Setup: Create a temporary git repo for integration tests
# ============================================================
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

setup_mock_repo() {
  local repo="$TEMP_DIR/mock-repo"
  rm -rf "$repo"
  mkdir -p "$repo/src" "$repo/tests" "$repo/.wishloop" "$repo/docs/plans"

  cd "$repo"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create mock source files
  echo 'export function hello() { return "world"; }' > src/index.ts
  echo 'import { hello } from "./index"; test("hello", () => expect(hello()).toBe("world"));' > tests/index.test.ts
  echo '{"scripts":{"build":"tsc","test":"vitest run","lint":"eslint ."}, "dependencies":{"vitest":"^1.0.0"}}' > package.json
  echo '# My Project' > README.md
  cat > CLAUDE.md << 'CLAUDEMD'
## Known Pitfalls
- Always use localToday() — never toISOString().slice(0,10)
## Mandatory Rules
- Never use inline styles — use Tailwind classes
CLAUDEMD

  git add -A
  git commit -q -m "initial commit"

  echo "$repo"
}

echo "============================================"
echo "  Wishloop v2 Test Suite"
echo "============================================"
echo ""

# ============================================================
# UNIT TESTS: Script syntax validation
# ============================================================
echo -e "${YELLOW}--- Unit Tests: Syntax Validation ---${NC}"

for script in gardening-check.sh enrich-proposal.sh pr-babysitter.sh capture-run.sh; do
  SCRIPT_PATH="$SCRIPT_DIR/scripts/$script"
  if [ -f "$SCRIPT_PATH" ]; then
    if bash -n "$SCRIPT_PATH" 2>/dev/null; then
      assert_exit_code "syntax: $script" "0" "0"
    else
      assert_exit_code "syntax: $script" "0" "1"
    fi
  else
    echo -e "  ${YELLOW}SKIP${NC}: $script not found"
  fi
done

echo ""

# ============================================================
# UNIT TESTS: Removed scripts should not exist
# ============================================================
echo -e "${YELLOW}--- Unit Tests: Removed Scripts ---${NC}"

assert_file_not_exists "inject-learnings.sh removed (replaced by Loki native injection)" "$SCRIPT_DIR/scripts/inject-learnings.sh"

echo ""

# ============================================================
# UNIT TESTS: Script argument validation
# ============================================================
echo -e "${YELLOW}--- Unit Tests: Argument Validation ---${NC}"

# enrich-proposal.sh should fail with no args
OUTPUT=$(bash "$SCRIPT_DIR/scripts/enrich-proposal.sh" 2>&1 || true)
assert_contains "enrich-proposal.sh rejects missing proposal" "Usage" "$OUTPUT"

# enrich-proposal.sh should fail with nonexistent file
OUTPUT=$(bash "$SCRIPT_DIR/scripts/enrich-proposal.sh" /tmp /tmp/nonexistent-proposal-xyz.md 2>&1 || true)
assert_contains "enrich-proposal.sh rejects missing file" "not found" "$OUTPUT"

echo ""

# ============================================================
# INTEGRATION TESTS: gardening-check.sh (v2 — loki status --json)
# ============================================================
echo -e "${YELLOW}--- Integration Tests: gardening-check.sh ---${NC}"

REPO=$(setup_mock_repo)

# Test basic check on a repo (loki may not be installed, but script should handle gracefully)
OUTPUT=$(bash "$SCRIPT_DIR/scripts/gardening-check.sh" "$REPO" "test-change" 2>&1 || true)
assert_contains "gardening: outputs session monitor header" "Session Monitor" "$OUTPUT"
assert_contains "gardening: shows change name" "test-change" "$OUTPUT"
assert_contains "gardening: shows loki status field" "Loki status" "$OUTPUT"
assert_contains "gardening: shows iteration field" "Iteration" "$OUTPUT"
assert_contains "gardening: shows tasks field" "Tasks" "$OUTPUT"
assert_contains "gardening: shows recent commits" "initial commit" "$OUTPUT"

# Test P6 compliance: script should NOT reference .loki/ internal files
SCRIPT_CONTENT=$(cat "$SCRIPT_DIR/scripts/gardening-check.sh")
assert_not_contains "gardening: no STATUS.txt access (P6)" "STATUS.txt" "$SCRIPT_CONTENT"
assert_not_contains "gardening: no .loki/ file reads (P6)" "cat.*\.loki/" "$SCRIPT_CONTENT"
assert_contains "gardening: uses loki status --json (P6)" "loki status --json" "$SCRIPT_CONTENT"

# Test action directive names (v2 uses SESSION_COMPLETE, not ADVANCE_TO_PHASE_7)
assert_contains "gardening: has SESSION_COMPLETE action" "ACTION: SESSION_COMPLETE" "$SCRIPT_CONTENT"
assert_contains "gardening: has SESSION_STALLED action" "ACTION: SESSION_STALLED" "$SCRIPT_CONTENT"
assert_contains "gardening: has SESSION_CRASHED action" "ACTION: SESSION_CRASHED" "$SCRIPT_CONTENT"
assert_not_contains "gardening: no v1 ADVANCE_TO_PHASE_7 reference" "ADVANCE_TO_PHASE_7" "$SCRIPT_CONTENT"

# Test state.json update on completion
assert_contains "gardening: updates state.json" "state.json" "$SCRIPT_CONTENT"

# Test stall detection logic
assert_contains "gardening: has stall detection" "stall" "$SCRIPT_CONTENT"

# Test loki stop/resume references (emergency controls)
assert_contains "gardening: references loki stop" "loki stop" "$SCRIPT_CONTENT"
assert_contains "gardening: references loki resume" "loki resume" "$SCRIPT_CONTENT"

echo ""

# ============================================================
# INTEGRATION TESTS: enrich-proposal.sh
# ============================================================
echo -e "${YELLOW}--- Integration Tests: enrich-proposal.sh ---${NC}"

REPO=$(setup_mock_repo)

# Create a proposal file
cat > "$REPO/proposal.md" << 'PROPOSAL'
# Fix: Hello World Bug
## Problem
The hello function returns wrong value.
## Fix
Update the return value.
## Acceptance Criteria
- [ ] hello() returns correct value
PROPOSAL

OUTPUT=$(bash "$SCRIPT_DIR/scripts/enrich-proposal.sh" "$REPO" "$REPO/proposal.md" 2>&1 || true)
assert_contains "enrich: reports success" "enriched successfully" "$OUTPUT"

# Check the proposal was enriched
ENRICHED=$(cat "$REPO/proposal.md")
assert_contains "enrich: adds Context section" "## Context (auto-generated)" "$ENRICHED"
assert_contains "enrich: adds build commands section" "### Build commands" "$ENRICHED"
assert_contains "enrich: adds test patterns section" "### Test patterns" "$ENRICHED"
assert_contains "enrich: includes project rules" "### Project rules" "$ENRICHED"

# Test idempotency — running again should skip
OUTPUT=$(bash "$SCRIPT_DIR/scripts/enrich-proposal.sh" "$REPO" "$REPO/proposal.md" 2>&1 || true)
assert_contains "enrich: skips already-enriched proposal" "already enriched" "$OUTPUT"

echo ""

# ============================================================
# INTEGRATION TESTS: pr-babysitter.sh
# ============================================================
echo -e "${YELLOW}--- Integration Tests: pr-babysitter.sh ---${NC}"

OUTPUT=$(bash -n "$SCRIPT_DIR/scripts/pr-babysitter.sh" 2>&1)
assert_exit_code "pr-babysitter: syntax valid" "0" "$?"

echo ""

# ============================================================
# COHERENCE TESTS: SKILL.md v2 validation
# ============================================================
echo -e "${YELLOW}--- Coherence Tests: SKILL.md v2 ---${NC}"

SKILLMD="$SCRIPT_DIR/SKILL.md"

# Check all referenced scripts exist
for script in gardening-check.sh capture-run.sh enrich-proposal.sh pr-babysitter.sh; do
  if grep -q "$script" "$SKILLMD"; then
    assert_file_exists "SKILL.md references existing script: $script" "$SCRIPT_DIR/scripts/$script"
  fi
done

# Verify inject-learnings.sh is NOT referenced in SKILL.md
assert_not_contains "SKILL.md does not reference inject-learnings.sh" "inject-learnings" "$(cat "$SKILLMD")"

# Check all referenced templates exist
for template in audit.md lld.md hld.md research.md docs.md; do
  if grep -q "templates/$template" "$SKILLMD"; then
    assert_file_exists "SKILL.md references existing template: $template" "$SCRIPT_DIR/templates/$template"
  fi
done

# Check v2 step ordering — steps should appear in order
STEP_LINES=$(grep -n "^## Step" "$SKILLMD" | head -20)
PREV_STEP=0
STEP_ORDER_OK=true
while IFS=: read -r _ line_text; do
  STEP_NUM=$(echo "$line_text" | grep -oE '[0-9]+' | head -1)
  if [ -n "$STEP_NUM" ] && [ "$STEP_NUM" -lt "$PREV_STEP" ]; then
    STEP_ORDER_OK=false
  fi
  PREV_STEP="${STEP_NUM:-$PREV_STEP}"
done <<< "$STEP_LINES"
if [ "$STEP_ORDER_OK" = true ]; then
  echo -e "  ${GREEN}PASS${NC}: SKILL.md steps are in sequential order"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: SKILL.md steps are out of order"
  FAIL=$((FAIL + 1))
fi

# v2 uses Steps, not Phases — verify no Phase references remain
assert_not_contains "SKILL.md uses Steps not Phases (v2)" "^## Phase" "$(cat "$SKILLMD")"

# Check Step 2b has enrichment
assert_contains "SKILL.md Step 2 has enrichment" "enrich-proposal" "$(cat "$SKILLMD")"

# Check Step 3.5 has monitoring via loki status
assert_contains "SKILL.md Step 3.5 uses loki status --json" "loki status --json" "$(cat "$SKILLMD")"

# Check Step 5 has PR babysitter
assert_contains "SKILL.md Step 5 has PR babysitter" "pr-babysitter" "$(cat "$SKILLMD")"

# Check Step 2c has proposal quality gate
assert_contains "SKILL.md has proposal quality gate" "quality gate" "$(cat "$SKILLMD")"

# Check P6 principle is documented
assert_contains "SKILL.md documents P6: External Interface Only" "External Interface Only" "$(cat "$SKILLMD")"

# Check Loki Commands table exists
assert_contains "SKILL.md has Loki Commands table" "Loki Commands Used" "$(cat "$SKILLMD")"

# Verify all required loki commands are documented
for cmd in "loki doctor" "loki start" "loki run" "loki quick" "loki status --json" "loki resume" "loki ci" "loki docs check" "loki docs generate" "loki stop"; do
  assert_contains "SKILL.md documents: $cmd" "$cmd" "$(cat "$SKILLMD")"
done

echo ""

# ============================================================
# TEMPLATE TESTS: Validate template structure
# ============================================================
echo -e "${YELLOW}--- Template Tests: Structure Validation ---${NC}"

for template in audit lld hld research docs; do
  TPATH="$SCRIPT_DIR/templates/$template.md"
  if [ -f "$TPATH" ]; then
    CONTENT=$(cat "$TPATH")
    assert_contains "template/$template.md has Required Inputs" "Required Inputs" "$CONTENT"
    assert_contains "template/$template.md has Workflow" "Workflow" "$CONTENT"
    assert_contains "template/$template.md has Output Artifacts" "Output Artifacts" "$CONTENT"
    assert_contains "template/$template.md has Quality Gates" "Quality Gates" "$CONTENT"
    assert_contains "template/$template.md has Exit Criteria" "Exit Criteria" "$CONTENT"
  fi
done

echo ""

# ============================================================
# P6 COMPLIANCE TESTS: No internal .loki/ file access
# ============================================================
echo -e "${YELLOW}--- P6 Compliance Tests ---${NC}"

# SKILL.md should not reference internal Loki functions
SKILL_CONTENT=$(cat "$SKILLMD")
for func in "extract_learnings_from_session" "compound_session_to_solutions" "init_loki_dir" "update_continuity" "load_startup_learnings" "check_completion_promise"; do
  assert_not_contains "SKILL.md does not call internal: $func" "$func" "$SKILL_CONTENT"
done

# gardening-check.sh should not read .loki/ files
GARDENING_CONTENT=$(cat "$SCRIPT_DIR/scripts/gardening-check.sh")
assert_not_contains "gardening: no .loki/STATUS.txt reads" ".loki/STATUS.txt" "$GARDENING_CONTENT"
assert_not_contains "gardening: no .loki/queue reads" ".loki/queue" "$GARDENING_CONTENT"
assert_not_contains "gardening: no .loki/state reads" ".loki/state" "$GARDENING_CONTENT"

echo ""

# ============================================================
# UNIT TESTS: drain.sh syntax and arguments
# ============================================================
echo -e "${YELLOW}--- Unit Tests: drain.sh ---${NC}"

DRAIN_PATH="$SCRIPT_DIR/scripts/drain.sh"

assert_file_exists "drain.sh exists" "$DRAIN_PATH"

if [ -f "$DRAIN_PATH" ]; then
  if bash -n "$DRAIN_PATH" 2>/dev/null; then
    assert_exit_code "drain.sh: syntax valid" "0" "0"
  else
    assert_exit_code "drain.sh: syntax valid" "0" "1"
  fi

  # Test --help flag
  OUTPUT=$(bash "$DRAIN_PATH" --help 2>&1 || true)
  assert_contains "drain.sh: --help shows usage" "Usage" "$OUTPUT"

  # Test unknown argument rejection
  OUTPUT=$(bash "$DRAIN_PATH" --bogus 2>&1 || true)
  assert_contains "drain.sh: rejects unknown args" "Unknown argument" "$OUTPUT"
fi

echo ""

# ============================================================
# CONTENT TESTS: drain.sh P6 compliance and feature coverage
# ============================================================
echo -e "${YELLOW}--- Content Tests: drain.sh ---${NC}"

if [ -f "$DRAIN_PATH" ]; then
  DRAIN_CONTENT=$(cat "$DRAIN_PATH")

  # P6 compliance: no direct .loki/ file access
  assert_not_contains "drain: no .loki/ file reads (P6)" "cat.*\.loki/" "$DRAIN_CONTENT"
  assert_not_contains "drain: no .loki/queue reads (P6)" ".loki/queue" "$DRAIN_CONTENT"
  assert_not_contains "drain: no .loki/state reads (P6)" ".loki/state/" "$DRAIN_CONTENT"

  # prd-001: Monitoring via loki status --json
  assert_contains "drain: uses loki status --json for monitoring (prd-001)" "loki status --json" "$DRAIN_CONTENT"
  assert_contains "drain: has monitor_session function" "monitor_session" "$DRAIN_CONTENT"
  assert_contains "drain: delegates to gardening-check.sh" "gardening-check.sh" "$DRAIN_CONTENT"

  # prd-002: Stopping via loki stop
  assert_contains "drain: uses loki stop for emergency stop (prd-002)" "loki stop" "$DRAIN_CONTENT"
  assert_contains "drain: has separate loki_stop function" "loki_stop" "$DRAIN_CONTENT"

  # prd-003: Resuming via loki resume
  assert_contains "drain: uses loki resume for recovery (prd-003)" "loki resume" "$DRAIN_CONTENT"
  assert_contains "drain: has separate loki_resume function" "loki_resume" "$DRAIN_CONTENT"
  assert_contains "drain: checks state.json for resumption" "state.json" "$DRAIN_CONTENT"

  # Core drain features
  assert_contains "drain: fetches issues via gh issue list" "gh issue list" "$DRAIN_CONTENT"
  assert_contains "drain: has priority sorting" "priority_score" "$DRAIN_CONTENT"
  assert_contains "drain: has --label filter support" "LABEL_FILTER" "$DRAIN_CONTENT"
  assert_contains "drain: uses loki run for single issues" "loki run" "$DRAIN_CONTENT"
  assert_contains "drain: delegates to pr-babysitter.sh" "pr-babysitter.sh" "$DRAIN_CONTENT"
  assert_contains "drain: has cumulative summary" "Drain Complete" "$DRAIN_CONTENT"
  assert_contains "drain: has max iterations limit" "MAX_ITERATIONS" "$DRAIN_CONTENT"
  assert_contains "drain: has cooldown between iterations" "COOLDOWN" "$DRAIN_CONTENT"
  assert_contains "drain: displays dashboard" "display_dashboard" "$DRAIN_CONTENT"
  assert_contains "drain: has loki quick for review fixes" "loki quick" "$DRAIN_CONTENT"
  assert_contains "drain: has circuit breaker" "Circuit breaker" "$DRAIN_CONTENT"
  assert_contains "drain: merges PRs via gh pr merge" "gh pr merge" "$DRAIN_CONTENT"
  assert_contains "drain: composes dynamic completion promise" "compose_completion_promise" "$DRAIN_CONTENT"
  assert_contains "drain: uses jq for safe JSON in update_state" "jq -n" "$DRAIN_CONTENT"
  assert_contains "drain: uses --argjson for safe jq queries" "argjson" "$DRAIN_CONTENT"
  assert_contains "drain: validates numeric arguments" "must be a positive integer" "$DRAIN_CONTENT"
  assert_contains "drain: unknown labels get lowest priority (tier 6)" "else 6 end" "$DRAIN_CONTENT"
  assert_contains "drain: only counts resolved on babysit success" "if babysit_pr" "$DRAIN_CONTENT"
fi

echo ""

# ============================================================
# BEHAVIORAL TESTS: drain.sh argument validation
# ============================================================
echo -e "${YELLOW}--- Behavioral Tests: drain.sh argument validation ---${NC}"

if [ -f "$DRAIN_PATH" ]; then
  # Non-numeric --max-iterations rejected
  OUTPUT=$(bash "$DRAIN_PATH" --max-iterations abc 2>&1 || true)
  assert_contains "drain: rejects non-numeric max-iterations" "must be a positive integer" "$OUTPUT"

  # Non-numeric --cooldown rejected
  OUTPUT=$(bash "$DRAIN_PATH" --cooldown xyz 2>&1 || true)
  assert_contains "drain: rejects non-numeric cooldown" "must be a positive integer" "$OUTPUT"

  # Missing --label value
  OUTPUT=$(bash "$DRAIN_PATH" --label 2>&1 || true)
  assert_contains "drain: rejects --label with no value" "requires a value" "$OUTPUT"
fi

echo ""

# ============================================================
# BEHAVIORAL TESTS: priority ordering (via jq function)
# ============================================================
echo -e "${YELLOW}--- Behavioral Tests: priority ordering ---${NC}"

# Test the prioritize_issues jq logic directly with mock data
MOCK_ISSUES='[
  {"number":1,"title":"docs update","body":"short","labels":[{"name":"documentation"}]},
  {"number":2,"title":"critical crash","body":"x","labels":[{"name":"critical"}]},
  {"number":3,"title":"fix login","body":"xx","labels":[{"name":"bug"}]},
  {"number":4,"title":"refactor auth","body":"long body here for effort","labels":[{"name":"refactor"}]},
  {"number":5,"title":"no labels","body":"y","labels":[]}
]'

PRIORITY_ORDER=$(echo "$MOCK_ISSUES" | jq -r '
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
' | tr '\n' ',')

FIRST_ISSUE=$(echo "$PRIORITY_ORDER" | cut -d, -f1)
assert_eq "priority: critical issue (#2) is first" "2" "$FIRST_ISSUE"

SECOND_ISSUE=$(echo "$PRIORITY_ORDER" | cut -d, -f2)
assert_eq "priority: bug issue (#3) is second" "3" "$SECOND_ISSUE"

LAST_ISSUE=$(echo "$PRIORITY_ORDER" | cut -d, -f5)
assert_eq "priority: unlabeled issue (#5) gets lowest tier (6), last" "5" "$LAST_ISSUE"

echo ""

# ============================================================
# BEHAVIORAL TESTS: update_state JSON safety
# ============================================================
echo -e "${YELLOW}--- Behavioral Tests: update_state JSON safety ---${NC}"

# Verify that update_state uses jq -n (not echo with string interpolation)
if [ -f "$DRAIN_PATH" ]; then
  # Count jq -n calls in update_state function
  JQ_SAFE_COUNT=$(sed -n '/^update_state/,/^[^ ]/p' "$DRAIN_PATH" | grep -c 'jq -n' || echo "0")
  if [ "$JQ_SAFE_COUNT" -ge 5 ]; then
    echo -e "  ${GREEN}PASS${NC}: update_state uses jq -n for all 5 state types"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: update_state should use jq -n for all 5 state types (found $JQ_SAFE_COUNT)"
    FAIL=$((FAIL + 1))
  fi

  # Verify no raw echo JSON construction in update_state
  RAW_JSON="0"
  if sed -n '/^update_state/,/^[^ ]/p' "$DRAIN_PATH" | grep -q 'echo.*{.*step'; then
    RAW_JSON="1"
  fi
  assert_eq "update_state: no raw echo JSON construction" "0" "$RAW_JSON"
fi

echo ""

# ============================================================
# COHERENCE TESTS: SKILL.md drain mode section
# ============================================================
echo -e "${YELLOW}--- Coherence Tests: SKILL.md drain mode ---${NC}"

SKILLMD_CONTENT=$(cat "$SKILLMD")

# Drain mode section exists
assert_contains "SKILL.md has Drain Mode section" "## Drain Mode" "$SKILLMD_CONTENT"

# Drain mode references the script
assert_contains "SKILL.md references drain.sh in scripts table" "drain.sh" "$SKILLMD_CONTENT"

# Drain mode documents key features
assert_contains "SKILL.md drain: documents --label filter" "\-\-label" "$SKILLMD_CONTENT"
assert_contains "SKILL.md drain: documents loki status --json monitoring" "loki status --json" "$SKILLMD_CONTENT"
assert_contains "SKILL.md drain: documents loki stop" "loki stop" "$SKILLMD_CONTENT"
assert_contains "SKILL.md drain: documents loki resume" "loki resume" "$SKILLMD_CONTENT"
assert_contains "SKILL.md drain: documents priority tiers" "critical > bug" "$SKILLMD_CONTENT"
assert_contains "SKILL.md drain: documents cumulative summary" "Drain Complete" "$SKILLMD_CONTENT"
assert_contains "SKILL.md drain: documents session resumption" "Session Resumption" "$SKILLMD_CONTENT"
assert_contains "SKILL.md drain: triggers include drain" "drain" "$(head -20 "$SKILLMD")"

echo ""

# ============================================================
# P6 COMPLIANCE TESTS: drain.sh
# ============================================================
echo -e "${YELLOW}--- P6 Compliance Tests: drain.sh ---${NC}"

if [ -f "$DRAIN_PATH" ]; then
  DRAIN_CONTENT=$(cat "$DRAIN_PATH")

  # Should NOT reference internal Loki functions
  for func in "extract_learnings_from_session" "compound_session_to_solutions" "init_loki_dir" "update_continuity"; do
    assert_not_contains "drain: does not call internal: $func" "$func" "$DRAIN_CONTENT"
  done

  # Should NOT read .loki/ internal files
  assert_not_contains "drain: no .loki/STATUS.txt reads" ".loki/STATUS.txt" "$DRAIN_CONTENT"
  assert_not_contains "drain: no .loki/session.json reads" ".loki/session.json" "$DRAIN_CONTENT"
  assert_not_contains "drain: no .loki/CONTINUITY.md reads" ".loki/CONTINUITY" "$DRAIN_CONTENT"
fi

echo ""

# ============================================================
# Summary
# ============================================================
TOTAL=$((PASS + FAIL))
echo "============================================"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, $TOTAL total"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
