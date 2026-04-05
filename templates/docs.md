# Documentation Template

**Triggers:** "write docs for X", "document Y", "API docs", "update README"

## Required Inputs

- [ ] Documentation scope (what to document)
- [ ] Target audience (developers, end users, ops?)
- [ ] Output location (`docs/`, README, API docs)

## Workflow

### 1. Inventory
Assess current documentation state:
- What exists? What's missing? What's stale?
- Read existing docs to understand the current coverage
- Check code comments and README for inline documentation

### 2. Outline
Create a structure before writing:
- Section headers with brief descriptions
- Order by user journey (getting started -> usage -> advanced -> reference)
- Identify which sections need code examples

### 3. Draft
Write content following these principles:
- Lead with the "what" and "why" before the "how"
- Include runnable code examples (test them!)
- Use consistent terminology (match the codebase)
- Keep paragraphs short (3-4 sentences max)
- Use headers, lists, and tables for scannability

### 4. Verify
Before committing:
- Build the docs site (if applicable)
- Check all links work
- Verify code examples compile/run
- Read through as the target audience

```bash
# Common verification commands
npx markdownlint docs/          # Lint markdown
grep -rn "TODO\|FIXME" docs/    # Find incomplete sections
```

## Output Artifacts

- `docs/` files — Documentation content
- Updated README.md (if applicable)

## Quality Gates

- [ ] All planned sections written
- [ ] Code examples are runnable (not pseudocode)
- [ ] Links verified (no 404s)
- [ ] Consistent with current codebase (not documenting removed features)
- [ ] Target audience can follow the docs without external help

## Exit Criteria

Documentation is complete when all sections are written, verified, and committed.
