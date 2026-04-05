# Low-Level Design (LLD) Template

**Triggers:** "design X feature", "write a design doc for Y", "LLD for Z"

## Required Inputs

- [ ] Feature or component name
- [ ] Problem statement (what are we solving?)
- [ ] Constraints (performance, compatibility, existing patterns)

## Workflow

### 1. Context Gathering
Read existing code to understand:
- Current interfaces and data flows
- Existing patterns and conventions
- Where the new code fits in the architecture

```bash
# Useful commands
grep -rn "interface\|type\|class" <relevant-dirs>  # Find interfaces
git log --oneline -10 -- <relevant-files>           # Recent changes
```

### 2. Design
Document the following:
- **Component diagram:** What new components are introduced? How do they interact with existing ones?
- **Data flow:** How does data move through the system for this feature?
- **API contracts:** New or modified APIs with request/response shapes
- **Error handling:** What can go wrong? How is each failure mode handled?
- **State management:** What state is introduced? Where does it live?

### 3. Alternatives
Consider at least 2 alternative approaches:

| Approach | Pros | Cons | Effort |
|----------|------|------|--------|
| A (recommended) | ... | ... | S/M/L |
| B | ... | ... | S/M/L |

Explain why the recommended approach wins.

### 4. Review
Present the design to the user. Iterate based on feedback. Ask:
- Does this match your mental model?
- Any constraints I'm missing?
- Which alternative do you prefer?

### 5. Decision Record
If architectural: Write an ADR in `docs/adrs/ADR-NNN.md`.
If feature-level: Write design doc only.

## Output Artifacts

- `docs/plans/<name>.md` or `openspec/changes/<name>/design.md` — Design document
- ADR (if architectural decision is involved)

## Quality Gates

- [ ] Context section shows understanding of existing code
- [ ] At least 2 alternatives considered with trade-offs
- [ ] API contracts specified (if applicable)
- [ ] Error handling documented
- [ ] User has reviewed and approved the design

## Exit Criteria

Design is complete when the user approves the approach and the document is committed.
