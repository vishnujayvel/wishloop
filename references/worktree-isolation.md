# Concurrent Loki Sessions via Worktree Isolation

## Primary Method: Worktrunk

Worktrunk (`wt`) manages the full worktree lifecycle — creation, agent launch, merge, cleanup — in single commands.

### Creating and Launching

```bash
# Create worktree + launch Loki in one command
wt switch -c -x "loki start --parallel --openspec openspec/changes/<change>" <change-name>

# For parallel waves
wt switch -c -x "loki start --parallel --openspec openspec/changes/wave-1" wave-1
wt switch -c -x "loki start --parallel --openspec openspec/changes/wave-2" wave-2
```

### Monitoring

```bash
# Structured status for all active worktrees
wt list

# Full mode with CI status and AI summaries
wt list --full
```

### Merging Back

```bash
# Squash + rebase + fast-forward + cleanup in one command
wt merge main
```

Pre-merge hooks run tests automatically. Post-merge hooks can run `openspec archive`.

### Hooks (.worktrunk.toml)

Wishloop generates `.worktrunk.toml` during Phase 4 with:
- `post-start`: dependency installation (npm install, cargo build, etc.)
- `pre-merge`: build + test suite (blocks merge on failure)
- `post-merge`: `openspec archive` for change archival

### Install

```bash
brew install worktrunk && wt config shell install
```

---

## Fallback Method: Manual Git Worktrees

Use this when Worktrunk is not installed.

### Detection

Before launching Loki, check for an active session:

```bash
if [ -f .loki/loki.pid ] && kill -0 "$(cat .loki/loki.pid)" 2>/dev/null; then
  echo "Loki already running (PID $(cat .loki/loki.pid)). Using worktree."
  USE_WORKTREE=true
fi
```

Also check for active claude agents: `ps aux | grep "claude.*dangerously" | grep -v grep | wc -l`

Decision:
- **No active Loki**: Run normally in main checkout
- **Active Loki, non-overlapping files**: Create worktree (this pattern)
- **Active Loki, heavily overlapping files**: Wait for it to finish (sequential, not parallel)

### Creating the Worktree

```bash
SLUG=$(basename "$PRD_PATH" .md | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
WORKTREE=".claude/worktrees/loki-${SLUG}"
BRANCH="worktree-loki-${SLUG}"

git worktree add "$WORKTREE" -b "$BRANCH"
cd "$WORKTREE"

# Launch Loki in the worktree (it gets its own .loki/ directory)
nohup loki start "$PRD_PATH" --parallel --yes > /tmp/loki-${SLUG}.log 2>&1 &
```

### Merging Back

```bash
cd /path/to/main/checkout
git merge "$BRANCH" --no-ff -m "feat: merge Loki session ${SLUG}"
git worktree remove "$WORKTREE"
git branch -d "$BRANCH"
git worktree prune
```

### Rules

1. **Add `.claude/worktrees/` to `.gitignore`**
2. **Naming convention**: `loki-<task-slug>`
3. **File ownership**: each Loki session should own distinct files. Shared files (CLAUDE.md) are read-only
4. **Coordinate via git, not filesystem signals**
5. **Merge sequentially** to catch conflicts early
6. **Clean stale PIDs** before proceeding

### Known Pitfalls

- Auth tokens may not propagate to worktree subagents — use CLI-level `--worktree`
- `getDefaultBranch` returns wrong branch in worktrees — explicitly specify base branch
- git-crypt repos may hang on worktree creation — decrypt before creating worktrees
- **Dashboard port conflict:** Two concurrent Loki sessions fight over port 57374. Set `LOKI_DASHBOARD_PORT=<unique>` per session, or use Worktrunk's `hash_port` template filter
- **Skills not loaded in worktrees:** Claude Code loads skills from the main repo root, not the worktree (see [anthropics/claude-code#27985](https://github.com/anthropics/claude-code/issues/27985)). Copy `.claude/` into worktrees after creation, or ensure Worktrunk's post-start hook handles this
- **Resume from correct directory:** `loki resume` reads `$PWD/.loki/CONTINUITY.md`. For worktree sessions, `cd` into the worktree (or `wt switch <name>`) before resuming — running from the main checkout resumes the wrong session
- **Cross-worktree signaling:** `touch .loki/STOP` only affects the current `$PWD`. To signal a worktree Loki from elsewhere, use the full path: `touch /path/to/worktree/.loki/STOP`

### Verified Safe

The following were investigated and confirmed safe in worktrees (no action needed):

- **Subagent `$PWD` inheritance:** `claude --dangerously-skip-permissions` subagents inherit the worktree's `$PWD`. `git rev-parse --show-toplevel` returns the worktree root.
- **PID tracking:** Each worktree has its own `.loki/pids/` — no cross-contamination possible.
- **`$PWD` in scripts:** All Wishloop scripts use `$PWD`-relative paths, which resolve correctly in worktrees.
- **Git operations:** Worktrees have independent index files. `git add -A && git commit` scopes to worktree files only.
