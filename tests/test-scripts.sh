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
