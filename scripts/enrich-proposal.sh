#!/usr/bin/env bash
# Auto-enrich a proposal with project context before Loki launch.
# Usage: bash enrich-proposal.sh <project-dir> <proposal-path>
#
# Appends a ## Context (auto-generated) section to the proposal with:
# - Relevant file paths + line numbers
# - CLAUDE.md rules that apply
# - Test file patterns
# - Build/run/test commands
# - Recent git history for relevant files
# - Tech stack summary

set -uo pipefail
# Note: set -e is intentionally omitted. Many commands (grep, find, node) return
# non-zero when they find no matches, which is expected during enrichment.
# Each command handles its own errors via || true or conditional checks.

PROJECT_DIR="${1:-.}"
PROPOSAL="${2:-}"

if [ -z "$PROPOSAL" ] || [ ! -f "$PROPOSAL" ]; then
  echo "Usage: enrich-proposal.sh <project-dir> <proposal-path>"
  echo "Error: Proposal file not found: $PROPOSAL"
  exit 1
fi

cd "$PROJECT_DIR" || { echo "Error: Cannot access project directory: $PROJECT_DIR"; exit 1; }

# Skip if already enriched
if grep -q "## Context (auto-generated)" "$PROPOSAL" 2>/dev/null; then
  echo "Proposal already enriched. Skipping."
  exit 0
fi

# Extract key terms from proposal title and scope (first 20 lines)
TITLE=$(head -5 "$PROPOSAL" | grep -E "^#" | head -1 | sed 's/^#* *//')
SCOPE_TERMS=$(head -20 "$PROPOSAL" | tr '[:upper:]' '[:lower:]' | \
  grep -oE '[a-zA-Z_][a-zA-Z0-9_]{3,}' | \
  sort -u | grep -vE '^(this|that|with|from|have|been|will|should|must|when|then|each|some|they|their|what|also|into|more|than|just|like|only|after|before|problem|solution|because|which|about|every|other|these|those|does|need|make|used|using|very|most|such|many|both|where|between|same|could|would|first|last|over|under|through|during|without|within|against|since|until|while|still)' | \
  head -20 || true)

echo ""
echo "=== Enriching proposal: $TITLE ==="
echo ""

# Start building context section
CONTEXT_FILE=$(mktemp)
cat > "$CONTEXT_FILE" << 'HEADER'

## Context (auto-generated)

HEADER

# --- 1. Relevant file paths ---
echo "### Files to modify" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

FOUND_FILES=false
for term in $SCOPE_TERMS; do
  # Search for the term in source files, show file:line
  MATCHES=$(grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    --include="*.py" --include="*.go" --include="*.rs" --include="*.rb" \
    --include="*.java" --include="*.swift" --include="*.kt" \
    -l "$term" . 2>/dev/null | grep -v node_modules | grep -v .git | head -5 || true)
  if [ -n "$MATCHES" ]; then
    for f in $MATCHES; do
      LINE=$(grep -n "$term" "$f" 2>/dev/null | head -1 | cut -d: -f1)
      echo "- \`${f}:${LINE}\` — matches \`$term\`" >> "$CONTEXT_FILE"
      FOUND_FILES=true
    done
  fi
done

if [ "$FOUND_FILES" = false ]; then
  echo "_No matching source files found for extracted terms._" >> "$CONTEXT_FILE"
fi
echo "" >> "$CONTEXT_FILE"

# --- 2. CLAUDE.md rules ---
if [ -f CLAUDE.md ]; then
  echo "### Project rules (from CLAUDE.md)" >> "$CONTEXT_FILE"
  echo "" >> "$CONTEXT_FILE"

  # Extract Known Pitfalls and Mandatory Rules sections
  RULES=$(awk '/^##.*[Pp]itfall|^##.*[Rr]ule|^##.*[Mm]andatory|^##.*[Cc]onvention/{found=1} found && /^##/ && !/[Pp]itfall|[Rr]ule|[Mm]andatory|[Cc]onvention/{found=0} found{print}' CLAUDE.md | head -30)

  if [ -n "$RULES" ]; then
    echo "$RULES" >> "$CONTEXT_FILE"
  else
    # Fallback: grep for lines with rule-like patterns
    RULE_LINES=$(grep -iE '(always|never|must|do not|don.t|required|mandatory|forbidden)' CLAUDE.md | head -10 || true)
    if [ -n "$RULE_LINES" ]; then
      echo "$RULE_LINES" | while IFS= read -r line; do
        echo "- $line" >> "$CONTEXT_FILE"
      done
    else
      echo "_No specific rules extracted from CLAUDE.md._" >> "$CONTEXT_FILE"
    fi
  fi
  echo "" >> "$CONTEXT_FILE"
fi

# --- 3. Test file patterns ---
echo "### Test patterns" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

# Find test files matching scope terms
TEST_FILE=""
for term in $SCOPE_TERMS; do
  MATCH=$(find . -path ./node_modules -prune -o \( -name "*test*" -o -name "*spec*" \) -type f -print 2>/dev/null | \
    grep -i "$term" | head -1 || true)
  if [ -n "$MATCH" ]; then
    TEST_FILE="$MATCH"
    break
  fi
done

# Fallback: find any test file
if [ -z "$TEST_FILE" ]; then
  TEST_FILE=$(find . -path ./node_modules -prune -o \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" \) -type f -print 2>/dev/null | head -1 || true)
fi

if [ -n "$TEST_FILE" ]; then
  TOTAL_TESTS=$(grep -c "it(\|test(\|func Test\|def test_" "$TEST_FILE" 2>/dev/null || echo "?")
  echo "- File: \`$TEST_FILE\` ($TOTAL_TESTS tests)" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
  head -10 "$TEST_FILE" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
else
  echo "_No test files found matching proposal scope._" >> "$CONTEXT_FILE"
fi
echo "" >> "$CONTEXT_FILE"

# --- 4. Build commands ---
echo "### Build commands" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

if [ -f package.json ]; then
  echo '```bash' >> "$CONTEXT_FILE"
  # Extract scripts section
  node -e "const p=require('./package.json'); Object.entries(p.scripts||{}).forEach(([k,v])=>console.log(k+': '+v))" 2>/dev/null | \
    grep -iE '(build|test|lint|check|start|dev)' | head -8 >> "$CONTEXT_FILE" || \
    echo "# See package.json scripts" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
elif [ -f Makefile ]; then
  echo '```bash' >> "$CONTEXT_FILE"
  grep -E '^[a-zA-Z_-]+:' Makefile | head -8 | sed 's/:.*/ /' >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
elif [ -f Cargo.toml ]; then
  echo '```bash' >> "$CONTEXT_FILE"
  echo "cargo build" >> "$CONTEXT_FILE"
  echo "cargo test" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
elif [ -f go.mod ]; then
  echo '```bash' >> "$CONTEXT_FILE"
  echo "go build ./..." >> "$CONTEXT_FILE"
  echo "go test ./..." >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
elif [ -f pyproject.toml ]; then
  echo '```bash' >> "$CONTEXT_FILE"
  echo "pip install -e ." >> "$CONTEXT_FILE"
  echo "pytest" >> "$CONTEXT_FILE"
  echo '```' >> "$CONTEXT_FILE"
else
  echo "_No build system detected._" >> "$CONTEXT_FILE"
fi
echo "" >> "$CONTEXT_FILE"

# --- 5. Recent git history for relevant files ---
echo "### Recent git history" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

if [ "$FOUND_FILES" = true ]; then
  # Get unique files from the matches (first 5)
  for term in $SCOPE_TERMS; do
    FILE=$(grep -rl --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" --include="*.go" \
      "$term" . 2>/dev/null | grep -v node_modules | head -1 || true)
    if [ -n "$FILE" ]; then
      HISTORY=$(git log --oneline -3 -- "$FILE" 2>/dev/null)
      if [ -n "$HISTORY" ]; then
        echo "**$FILE:**" >> "$CONTEXT_FILE"
        echo '```' >> "$CONTEXT_FILE"
        echo "$HISTORY" >> "$CONTEXT_FILE"
        echo '```' >> "$CONTEXT_FILE"
      fi
      break  # Just show one file's history to keep it concise
    fi
  done
else
  echo "_No relevant files to show history for._" >> "$CONTEXT_FILE"
fi
echo "" >> "$CONTEXT_FILE"

# --- 6. Tech stack summary ---
echo "### Tech stack" >> "$CONTEXT_FILE"
echo "" >> "$CONTEXT_FILE"

if [ -f package.json ]; then
  echo "**Dependencies:**" >> "$CONTEXT_FILE"
  node -e "const p=require('./package.json'); const d={...p.dependencies,...p.devDependencies}; Object.keys(d).sort().slice(0,15).forEach(k=>console.log('- '+k+': '+d[k]))" 2>/dev/null >> "$CONTEXT_FILE" || \
    echo "_Could not parse package.json_" >> "$CONTEXT_FILE"
elif [ -f go.mod ]; then
  echo "**Go modules:**" >> "$CONTEXT_FILE"
  grep -E '^\t' go.mod 2>/dev/null | head -10 | sed 's/^\t/- /' >> "$CONTEXT_FILE"
elif [ -f Cargo.toml ]; then
  echo "**Cargo dependencies:**" >> "$CONTEXT_FILE"
  awk '/\[dependencies\]/{found=1;next} /^\[/{found=0} found && NF{print "- "$0}' Cargo.toml | head -10 >> "$CONTEXT_FILE"
elif [ -f pyproject.toml ]; then
  echo "**Python dependencies:**" >> "$CONTEXT_FILE"
  awk '/dependencies/{found=1;next} /^\[/{found=0} found && NF{print "- "$0}' pyproject.toml | head -10 >> "$CONTEXT_FILE"
fi

# --- Append to proposal ---
cat "$CONTEXT_FILE" >> "$PROPOSAL"
rm -f "$CONTEXT_FILE"

echo ""
echo "Proposal enriched successfully."
echo "Review: $PROPOSAL"
