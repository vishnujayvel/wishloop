#!/usr/bin/env bash
# Inject relevant learnings from accumulated store into CLAUDE.md
# Usage: bash inject-learnings.sh <project-dir> [tech-stack-csv]
# Example: bash inject-learnings.sh /path/to/project electron,react

set -euo pipefail

PROJECT_DIR="${1:-.}"
TECH_STACK="${2:-}"
LEARNINGS_FILE="$HOME/.local/share/wishloop/learnings.json"
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"

if [ ! -f "$LEARNINGS_FILE" ]; then
  echo "No learnings file found at $LEARNINGS_FILE"
  exit 0
fi

if [ ! -f "$CLAUDE_MD" ]; then
  echo "No CLAUDE.md found at $CLAUDE_MD"
  exit 0
fi

# Auto-detect tech stack if not provided
if [ -z "$TECH_STACK" ]; then
  TECH_STACK=""
  [ -f "$PROJECT_DIR/package.json" ] && grep -q "electron" "$PROJECT_DIR/package.json" 2>/dev/null && TECH_STACK="$TECH_STACK,electron"
  [ -f "$PROJECT_DIR/package.json" ] && grep -q "react" "$PROJECT_DIR/package.json" 2>/dev/null && TECH_STACK="$TECH_STACK,react"
  [ -f "$PROJECT_DIR/Cargo.toml" ] && TECH_STACK="$TECH_STACK,rust"
  [ -f "$PROJECT_DIR/go.mod" ] && TECH_STACK="$TECH_STACK,go"
  TECH_STACK=$(echo "$TECH_STACK" | sed 's/^,//')
fi

# Always include: loki, workflow, testing
CATEGORIES="loki,workflow,testing"
if [ -n "$TECH_STACK" ]; then
  CATEGORIES="$CATEGORIES,$TECH_STACK"
fi

echo "Injecting learnings for categories: $CATEGORIES"

# Remove old injection block if present
sed -i '' '/^## Known Pitfalls (from prior runs)/,/^## [^K]/{ /^## [^K]/!d; }' "$CLAUDE_MD" 2>/dev/null || true
# Also remove trailing marker
sed -i '' '/^## Known Pitfalls (from prior runs)/d' "$CLAUDE_MD" 2>/dev/null || true

# Extract learnings using python (jq alternative)
PITFALLS=$(python3 -c "
import json, sys
with open('$LEARNINGS_FILE') as f:
    data = json.load(f)
categories = '$CATEGORIES'.split(',')
lines = []
for cat in categories:
    if cat in data:
        for entry in data[cat]:
            lines.append(f'- [{cat}] {entry[\"learning\"]}')
print('\n'.join(lines))
" 2>/dev/null || echo "")

if [ -z "$PITFALLS" ]; then
  echo "No relevant learnings to inject."
  exit 0
fi

# Append to CLAUDE.md
cat >> "$CLAUDE_MD" << EOF

## Known Pitfalls (from prior runs)
<!-- Auto-injected by wishloop. Do not edit manually. -->
$PITFALLS
EOF

PITFALL_COUNT=$(echo "$PITFALLS" | wc -l | tr -d ' ')
echo "Injected $PITFALL_COUNT learnings into $CLAUDE_MD"
