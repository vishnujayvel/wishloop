# ADR Integration

Discovery, relevance matching, and consequence updates for Architectural Decision Records.

## Discovery Patterns

Scan these locations in the target project (in order):

1. `docs/adrs/*.md`
2. `docs/decisions/*.md`
3. `architecture/decisions/*.md`
4. `ADR-*.md` (repo root)
5. `adr-*.md` (repo root)

If multiple locations contain ADRs, merge results from all of them. Deduplicate primarily by ADR number. If ADR number is missing, deduplicate by normalized title (lowercase, punctuation-stripped) and file path.

## Expected ADR Format

Standard ADR structure (based on Michael Nygard's template):

```markdown
# ADR-NNN: Title

**Status:** accepted | superseded | deprecated | proposed

## Context
<why this decision was needed>

## Decision
<what was decided>

## Consequences
<known trade-offs and implications>
```

If an ADR doesn't follow this format, extract what you can: use the first heading as title, look for "Status:" on any line, and treat the first paragraph as the summary.

## Relevance Matching

Match ADRs to the current change using keyword overlap:

1. **Extract ADR topics** — tokenize the ADR title and Context section into lowercase keywords, drop stop words
2. **Extract change scope** — collect file paths from the OpenSpec change's `specs/` domains, proposal scope section, and `tasks.md` file list
3. **Score overlap** — count shared keywords between ADR topics and change scope
4. **Threshold** — include any ADR with 2+ keyword matches, or any ADR whose title contains a domain name from the change

Err on the side of inclusion. A false positive (irrelevant ADR shown) is cheap; a false negative (missed constraint) causes rework.

## Injection Format

Append to CLAUDE.md under `## Relevant ADRs`:

```markdown
## Relevant ADRs

- **ADR-001: Use SQLite for local storage** (accepted) — Chose SQLite over IndexedDB for cross-platform consistency. Applies because: change modifies data layer.
- **ADR-003: Event sourcing for state** (accepted) — All state mutations go through event log. Applies because: change adds new entity type.
```

Do not duplicate entries already present in CLAUDE.md. Check by ADR number before appending.

## Consequence Update Format

Append to the ADR file's `## Consequences` section:

```markdown
### Implementation feedback — YYYY-MM-DD (change-name)
SQLite full-text search (FTS5) required a virtual table, which complicates migrations.
The ADR did not anticipate the FTS migration complexity. Consider documenting
migration strategy as a follow-up ADR.
```

If the `## Consequences` section doesn't exist, create it at the end of the ADR.

## Superseding an ADR

When implementation proves an ADR wrong or obsolete:

1. Change `**Status:** accepted` to `**Status:** superseded`
2. Add a line: `**Superseded by:** <reason or link to new ADR>`
3. Append a consequence entry explaining what changed

Do not delete the original ADR content. ADRs are append-only records.

## Conflicting ADRs

When two relevant ADRs contradict each other:

1. Flag both in the CLAUDE.md injection with a note: `CONFLICT: contradicts ADR-NNN`
2. Do not silently pick one — surface the conflict for the implementer to resolve
3. After resolution, update the losing ADR's status to `superseded`
