# Intelligent Batching Algorithm

Used by **Bug Batch** work type and the **Autonomous Issue Loop** (Phase 9) to group issues into execution waves.

## Step 1: ANALYZE each issue

For each open GitHub issue:
```
- issue_number: #N
- title: <from gh>
- files_touched: [list of files likely affected, from reading issue + codebase]
- priority: critical | high | medium | low (from labels or judgment)
- estimated_effort: small (1 file) | medium (2-4 files) | large (5+ files)
- dependencies: [list of issue numbers this depends on]
- risk: low (isolated) | medium (shared files) | high (cross-cutting)
```

## Step 2: GRAPH dependencies

Build a directed acyclic graph:
- Nodes = issues
- Edges = "issue A must complete before issue B"
- Detect cycles (break them by splitting issues)

## Step 3: BATCH into waves

```
Wave 1: Critical + quick wins (small effort, no dependencies, low risk)
  -> Fast momentum, immediate value, validates the pipeline

Wave 2: High priority + medium effort (may depend on Wave 1)
  -> Core fixes that improve user experience

Wave 3: Medium priority + larger effort
  -> Feature-level fixes, integration work

Wave 4: Low priority + testing/polish
  -> Nice-to-haves, test coverage gaps

Wave N (last): Issues that depend on all previous waves
```

## Step 4: File conflict analysis

Within each wave, check for file overlaps:
- If two issues in the same wave touch the same file, move one to the next wave
- Loki's parallel agents will conflict if they edit the same file simultaneously

## Step 5: Execute per-wave

Each wave becomes one OpenSpec change:
```bash
openspec new change bugfix-wave-1
# Write specs referencing issue numbers
# Execute via Loki
# Verify
# Archive
# Next wave
```
