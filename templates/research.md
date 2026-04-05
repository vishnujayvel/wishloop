# Research / Spike Template

**Triggers:** "research X", "spike on Y", "evaluate Z", "compare A vs B"

## Required Inputs

- [ ] Research question (crisp, specific)
- [ ] Success criteria (what would a good answer look like?)
- [ ] Time box (how long before we stop and report findings?)

## Workflow

### 1. Question Definition
Write the research question clearly:
- **Question:** [One sentence]
- **Success criteria:** [What constitutes an answer?]
- **Scope:** [What's in/out of this research?]
- **Time box:** [Hours/days]

### 2. Investigation
Use multiple sources:
- Web search for prior art, blog posts, documentation
- Code reading (existing codebase, open-source repos)
- Prototyping (small proof-of-concept if needed)
- Benchmarking (if performance is a factor)

Track what you tried and what you found. Dead ends are useful data.

### 3. Findings

**If evaluating options (comparison):**

| Criteria | Option A | Option B | Option C |
|----------|----------|----------|----------|
| criterion 1 | ... | ... | ... |
| criterion 2 | ... | ... | ... |
| verdict | ... | ... | ... |

**If answering a question (summary):**
- Key findings (bulleted, concise)
- Evidence (links, code snippets, benchmark results)
- Surprising discoveries
- What remains unknown

### 4. Recommendation
- **Recommendation:** [Clear statement]
- **Confidence:** High / Medium / Low
- **Reasoning:** [Why this, not the alternatives?]
- **Next steps:** [What to do with this knowledge]

## Output Artifacts

- `docs/plans/<name>-research.md` — Research document

## Quality Gates

- [ ] Research question clearly defined
- [ ] Multiple sources consulted (not just one blog post)
- [ ] Findings structured (comparison table or summary)
- [ ] Recommendation stated with confidence level
- [ ] Dead ends documented (saves future researchers time)

## Exit Criteria

Research is complete when the recommendation is clear enough to act on.
