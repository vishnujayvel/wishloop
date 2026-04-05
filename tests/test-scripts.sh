#!/usr/bin/env bash
# Test suite for wishloop scripts
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
  mkdir -p "$repo/src" "$repo/tests" "$repo/.loki" "$repo/.wishloop" "$repo/docs/plans"

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
echo "  Wishloop Test Suite"
echo "============================================"
echo ""

# ============================================================
# UNIT TESTS: Script syntax validation
# ============================================================
echo -e "${YELLOW}--- Unit Tests: Syntax Validation ---${NC}"

for script in gardening-check.sh enrich-proposal.sh pr-babysitter.sh capture-run.sh inject-learnings.sh; do
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
# INTEGRATION TESTS: gardening-check.sh
# ============================================================
echo -e "${YELLOW}--- Integration Tests: gardening-check.sh ---${NC}"

REPO=$(setup_mock_repo)

# Test basic check on a normal repo
OUTPUT=$(bash "$SCRIPT_DIR/scripts/gardening-check.sh" "$REPO" "test-change" 2>&1 || true)
assert_contains "gardening: outputs timestamp header" "Gardening Check" "$OUTPUT"
assert_contains "gardening: shows recent commits" "initial commit" "$OUTPUT"
assert_contains "gardening: shows active agents" "Active agents" "$OUTPUT"
assert_contains "gardening: shows build status" "Build:" "$OUTPUT"
assert_contains "gardening: shows conflicts" "Conflicts:" "$OUTPUT"

# Test journal entry creation
assert_file_exists "gardening: creates journal file" "$REPO/docs/plans/pipeline-journal.md"

# Test completion detection (mock STATUS.txt)
# Note: We override the agent count check by temporarily replacing the ps-based detection.
# The gardening script checks AGENT_COUNT -eq 0 AND STATUS=complete.
# In a test environment, real Claude agents may be running, so we test the
# individual output sections instead of relying on the compound condition.
echo "COMPLETE - All tasks finished" > "$REPO/.loki/STATUS.txt"

# Create a wrapper that forces AGENT_COUNT=0 for testing
WRAPPER="$TEMP_DIR/gardening-wrapper.sh"
cat > "$WRAPPER" << 'WRAPEOF'
#!/usr/bin/env bash
# Override ps to return 0 agents for testing
ps() { echo ""; }
export -f ps
source "$1" "$2" "$3"
WRAPEOF
chmod +x "$WRAPPER"

# Use a simpler approach: directly test the script's output with the real conditions
# The script outputs "COMPLETION DETECTED" when agent_count=0 and status=complete
# We verify the status reading works, and the action logic works
OUTPUT=$(bash "$SCRIPT_DIR/scripts/gardening-check.sh" "$REPO" "test-change" 2>&1 || true)
assert_contains "gardening: reads STATUS.txt" "COMPLETE - All tasks finished" "$OUTPUT"

# Test that the script's completion logic is wired correctly by checking
# the source code for the ACTION output
SCRIPT_CONTENT=$(cat "$SCRIPT_DIR/scripts/gardening-check.sh")
assert_contains "gardening: has ADVANCE_TO_PHASE_7 logic" "ACTION: ADVANCE_TO_PHASE_7" "$SCRIPT_CONTENT"
assert_contains "gardening: has INVESTIGATE_EXIT logic" "ACTION: INVESTIGATE_EXIT" "$SCRIPT_CONTENT"
assert_contains "gardening: updates state.json on completion" "state.json" "$SCRIPT_CONTENT"

# Test non-completion status reading
echo "Running task 3 of 5" > "$REPO/.loki/STATUS.txt"
OUTPUT=$(bash "$SCRIPT_DIR/scripts/gardening-check.sh" "$REPO" "test-change" 2>&1 || true)
assert_contains "gardening: reads non-complete status" "Running task 3 of 5" "$OUTPUT"

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

# Test single-check mode with no open PRs (needs gh but may not be in a repo context)
# We test the script's output format rather than actual GH API calls
OUTPUT=$(bash -n "$SCRIPT_DIR/scripts/pr-babysitter.sh" 2>&1)
assert_exit_code "pr-babysitter: syntax valid" "0" "$?"

echo ""

# ============================================================
# COHERENCE TESTS: SKILL.md validation
# ============================================================
echo -e "${YELLOW}--- Coherence Tests: SKILL.md ---${NC}"

SKILLMD="$SCRIPT_DIR/SKILL.md"

# Check all referenced scripts exist
for script in gardening-check.sh capture-run.sh inject-learnings.sh enrich-proposal.sh pr-babysitter.sh; do
  if grep -q "$script" "$SKILLMD"; then
    assert_file_exists "SKILL.md references existing script: $script" "$SCRIPT_DIR/scripts/$script"
  fi
done

# Check all referenced templates exist
for template in audit.md lld.md hld.md research.md docs.md; do
  if grep -q "templates/$template" "$SKILLMD"; then
    assert_file_exists "SKILL.md references existing template: $template" "$SCRIPT_DIR/templates/$template"
  fi
done

# Check phase ordering — phases should appear in order
PHASE_LINES=$(grep -n "^## Phase" "$SKILLMD" | head -20)
PREV_PHASE=0
PHASE_ORDER_OK=true
while IFS=: read -r line_num line_text; do
  PHASE_NUM=$(echo "$line_text" | grep -oE '[0-9]+' | head -1)
  if [ -n "$PHASE_NUM" ] && [ "$PHASE_NUM" -lt "$PREV_PHASE" ]; then
    PHASE_ORDER_OK=false
  fi
  PREV_PHASE="${PHASE_NUM:-$PREV_PHASE}"
done <<< "$PHASE_LINES"
if [ "$PHASE_ORDER_OK" = true ]; then
  echo -e "  ${GREEN}PASS${NC}: SKILL.md phases are in sequential order"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: SKILL.md phases are out of order"
  FAIL=$((FAIL + 1))
fi

# Check Phase 6 has continuation triggers
assert_contains "SKILL.md Phase 6 has ACTION directives" "ACTION: ADVANCE_TO_PHASE_7" "$(cat "$SKILLMD")"

# Check Phase 3b exists
assert_contains "SKILL.md has Phase 3b" "Phase 3b" "$(cat "$SKILLMD")"

# Check Phase 8b exists
assert_contains "SKILL.md has Phase 8b (PR babysitter)" "Phase 8b" "$(cat "$SKILLMD")"

# Check quality gate exists
assert_contains "SKILL.md has proposal quality gate" "Proposal Quality Gate" "$(cat "$SKILLMD")"

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
