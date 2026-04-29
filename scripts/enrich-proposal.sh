#!/usr/bin/env bash
# Auto-enrich a proposal with project context before Loki launch.
# Usage: bash enrich-proposal.sh <project-dir> <proposal-path>
#
# Appends a ## Context (auto-generated) section. Codebase intelligence is
# delegated to `loki code` (v6.75+); Wishloop only adds proposal-local context
# (CLAUDE.md rules) and pointers to Loki commands the session will use.

set -uo pipefail

PROJECT_DIR="${1:-.}"
PROPOSAL="${2:-}"

if [ -z "$PROPOSAL" ] || [ ! -f "$PROPOSAL" ]; then
  echo "Usage: enrich-proposal.sh <project-dir> <proposal-path>"
  echo "Error: Proposal file not found: $PROPOSAL"
  exit 1
fi

cd "$PROJECT_DIR" || { echo "Error: Cannot access project directory: $PROJECT_DIR"; exit 1; }

if grep -q "## Context (auto-generated)" "$PROPOSAL" 2>/dev/null; then
  echo "Proposal already enriched. Skipping."
  exit 0
fi

# Strip ANSI escape codes — `loki code` colorizes for terminal but Markdown won't render them.
strip_ansi() { sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'; }

TITLE=$(head -5 "$PROPOSAL" | grep -E "^#" | head -1 | sed 's/^#* *//')

echo ""
echo "=== Enriching proposal: $TITLE ==="
echo ""

CONTEXT_FILE=$(mktemp)
trap 'rm -f "$CONTEXT_FILE"' EXIT

{
  echo ""
  echo "## Context (auto-generated)"
  echo ""
  echo "_Codebase intelligence delegated to \`loki code\` — Loki owns this output._"
  echo ""

  echo "### Codebase overview"
  echo ""
  echo '```'
  loki code overview --silent 2>/dev/null | strip_ansi || echo "_loki code unavailable — run from a repo with Loki installed_"
  echo '```'
  echo ""

  echo "### Recent activity (hotspots)"
  echo ""
  echo '```'
  loki code hotspots --top 5 2>/dev/null | strip_ansi || echo "_loki code unavailable_"
  echo '```'
  echo ""

  if [ -f CLAUDE.md ]; then
    echo "### Project rules (from CLAUDE.md)"
    echo ""
    RULES=$(awk '/^##.*[Pp]itfall|^##.*[Rr]ule|^##.*[Mm]andatory|^##.*[Cc]onvention/{found=1} found && /^##/ && !/[Pp]itfall|[Rr]ule|[Mm]andatory|[Cc]onvention/{found=0} found{print}' CLAUDE.md | head -30)
    if [ -n "$RULES" ]; then
      echo "$RULES"
    else
      RULE_LINES=$(grep -iE '(always|never|must|do not|don.t|required|mandatory|forbidden)' CLAUDE.md | head -10 || true)
      if [ -n "$RULE_LINES" ]; then
        echo "$RULE_LINES" | sed 's/^/- /'
      else
        echo "_No specific rules extracted from CLAUDE.md._"
      fi
    fi
    echo ""
  fi

  echo "### Test patterns"
  echo ""
  echo "Loki discovers tests during its session. To inspect manually:"
  echo ""
  echo '```bash'
  echo "loki code symbols 'test|spec|describe|def test_'"
  echo '```'
  echo ""

  echo "### Build commands"
  echo ""
  echo "Loki reads build/test/lint commands natively from \`package.json\` / \`Makefile\` / \`pyproject.toml\` / \`Cargo.toml\` / \`go.mod\`. For an explicit summary:"
  echo ""
  echo '```bash'
  echo "loki onboard       # generates/refreshes CLAUDE.md with build commands"
  echo '```'
  echo ""
} >> "$CONTEXT_FILE"

cat "$CONTEXT_FILE" >> "$PROPOSAL"

echo ""
echo "Proposal enriched successfully."
echo "Review: $PROPOSAL"
