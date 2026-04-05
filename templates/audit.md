# Audit Template

**Triggers:** "audit X", "review Y for Z", "check compliance", "assess code quality"

## Required Inputs

- [ ] Audit scope (files, modules, or rules to check)
- [ ] Audit criteria (what "good" looks like — linting rules, conventions, security checklist)
- [ ] Boundary definition (what's in scope, what's explicitly excluded)

## Workflow

### 1. Scope Definition
Define audit boundaries. Be specific:
- Which directories/files/modules?
- Which rules or standards apply?
- What time range for git history (if relevant)?

### 2. Evidence Gathering
Read code, grep for patterns, check git history, run linters/scanners.

```bash
# Common evidence-gathering commands
grep -rn "<pattern>" <scope>          # Pattern search
git log --oneline -20 -- <files>      # Recent history
npx eslint <files>                    # Lint check (JS/TS)
```

Collect evidence systematically — don't jump to conclusions.

### 3. Findings Table
Document each finding in this format:

| # | Finding | Severity | Location | Recommendation |
|---|---------|----------|----------|----------------|
| 1 | description | Critical/High/Medium/Low | file:line | what to do |

**Severity guide:**
- **Critical:** Security vulnerability, data loss risk, production outage
- **High:** Bug, convention violation with downstream impact
- **Medium:** Code smell, maintainability concern
- **Low:** Style nit, minor improvement

### 4. Report
Write `docs-internal/audit-<name>.md` with:
- Executive summary (2-3 sentences)
- Scope definition
- Findings table (from step 3)
- Recommendations (prioritized)
- Action items with owners (if known)

### 5. Issue Filing
For each actionable finding (Critical/High/Medium):
```bash
gh issue create --title "audit: <finding>" --body "<details>" --label "audit" --label "<severity>"
```

## Output Artifacts

- `docs-internal/audit-<name>.md` — Audit report
- GitHub issues — One per actionable finding

## Quality Gates

- [ ] All in-scope files/modules reviewed
- [ ] Findings table complete with severity and location
- [ ] Report written with executive summary
- [ ] GitHub issues filed for all Critical/High/Medium findings
- [ ] No false positives (each finding verified with evidence)

## Exit Criteria

Audit is complete when the report is written and all actionable findings have GitHub issues.
