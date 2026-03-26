# Learnings Accumulation System

Cross-run institutional knowledge that prevents repeating known mistakes.

## Storage

**Location:** `~/.local/share/wishloop/learnings.json`

If the file doesn't exist, create it with:
```json
{
  "loki": [],
  "workflow": [],
  "testing": []
}
```

## Schema

```json
{
  "<category>": [
    {
      "learning": "<concise, actionable statement — imperative mood>",
      "source": "<project>/<change>",
      "date": "<YYYY-MM-DD>"
    }
  ]
}
```

## Categories

Categories are dynamic. Common ones:
- `loki` — Loki-specific behavior, gotchas, workarounds (ALWAYS relevant)
- `workflow` — Process and orchestration patterns (ALWAYS relevant)
- `testing` — Testing strategies, gaps, coverage patterns (ALWAYS relevant)
- Technology categories added as projects introduce new tech stacks:
  - `electron`, `react`, `sqlite`, `rapier`, etc.

## Categorization logic

When adding a new learning:
1. If it mentions a specific technology -> categorize under that technology
2. If about Loki behavior -> `loki`
3. If about workflow/process -> `workflow`
4. If about testing -> `testing`
5. If unclear -> ask the user

## Deduplication

Before appending, check if a semantically similar learning exists (same technology + same core concept). If so, update the existing entry's `source` and `date` rather than creating a duplicate.

## Filtering for injection (Phase 4)

Before a Loki run, read learnings and filter:

1. Identify the project's tech stack from CLAUDE.md, package.json, or the proposal
2. **Always include:** `loki`, `workflow`, and `testing` categories
3. **Conditionally include:** technology categories matching the project's stack
4. **Exclude:** learnings where `source` matches `{current-project}/{current-change}`

## Injection targets

Inject filtered learnings into:

1. **CLAUDE.md** — Append a `## Known Pitfalls (from prior runs)` section:
   ```markdown
   ## Known Pitfalls (from prior runs)
   <!-- Auto-injected by wishloop. Do not edit manually. -->
   - [electron] frame:false + titleBarStyle:'hiddenInset' are mutually exclusive
   - [loki] Queue pending.json is permanently stale — trust git log for progress
   ```

2. **Proposal** — If it references technologies with known learnings, add a `### Known Risks` section at the bottom.

Only inject learnings that are actionable for the current change. Do not dump the entire database.

## Interactive extraction (Phase 7)

After a run completes, prompt the user:
```
Run captured: {project}/{change} ({duration} min, {commits} commits, {files} files)
Build: {PASS/FAIL}  |  Unit tests: {PASS/FAIL}  |  E2E: {PASS/FAIL}

1. What surprised you about this run?
2. What did Loki get wrong or miss?
3. Any new patterns or anti-patterns to remember?

(Type observations, or "skip" to continue)
```
