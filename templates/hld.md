# High-Level Design (HLD) / Architecture Template

**Triggers:** "architecture for X", "system design", "HLD for Y"

## Required Inputs

- [ ] System or project name
- [ ] Problem space definition
- [ ] Key stakeholders and their concerns
- [ ] Non-functional requirements (performance, scale, reliability, cost)

## Workflow

### 1. Problem Space
Document:
- Who are the stakeholders? What do they care about?
- What constraints exist (regulatory, budget, timeline, team skills)?
- What are the non-functional requirements?

### 2. C4 Modeling
Work through the C4 model layers:

**Context (L1):** System boundary — who/what interacts with the system?
- Users, external systems, third-party services

**Container (L2):** Major deployment units — what runs where?
- Web apps, APIs, databases, message queues, workers

**Component (L3):** Internal structure of key containers
- Modules, services, repositories within a container

Document each layer with a description. Use Mermaid or ASCII diagrams.

### 3. Technology Selection
Create an options matrix for key technology decisions:

| Decision | Option A | Option B | Option C | Winner |
|----------|----------|----------|----------|--------|
| Database | PostgreSQL | DynamoDB | SQLite | ... |
| Criteria: Cost | Low | Medium | Free | ... |
| Criteria: Scale | High | Very High | Low | ... |
| Criteria: Team familiarity | High | Low | High | ... |

Weight criteria by importance. Show your reasoning.

### 4. ADR Writing
Write one ADR per major technology or architectural decision:

```markdown
# ADR-NNN: Title

**Status:** Proposed
**Context:** Why this decision is needed
**Decision:** What we decided
**Consequences:** What changes as a result (positive and negative)
```

Store in `docs/adrs/` or `architecture/decisions/`.

### 5. Presentation
Create a summary document suitable for review:
- Architecture overview (1-page executive summary)
- C4 diagrams
- Technology decisions with rationale
- Risk assessment
- Open questions

## Output Artifacts

- `docs/plans/<name>-architecture.md` — Architecture document
- `docs/adrs/ADR-NNN.md` — One per major decision
- C4 diagrams (Mermaid in the doc or separate `.mmd` files)

## Quality Gates

- [ ] All three C4 levels documented (Context, Container, Component)
- [ ] At least one ADR per major technology decision
- [ ] Non-functional requirements addressed
- [ ] Risk assessment included
- [ ] User has reviewed the architecture

## Exit Criteria

Architecture is complete when the user approves the design and all ADRs are written.
