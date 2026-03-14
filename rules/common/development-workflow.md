# Development Workflow

## Step 0: Research & Reuse (Before Writing Code)

Before implementing anything, search for existing solutions:

1. **Search existing code** — use Grep/Glob to find similar patterns already in the codebase
2. **Check library docs** — verify the API/pattern you plan to use is current
3. **Review related tests** — understand how similar features are tested
4. **Check for shared utilities** — avoid duplicating existing helpers/mappers/validators

This prevents reinventing existing code and ensures consistency with established patterns.

## Phase Flow

```
RESEARCH → PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW → DELIVER
```

### RESEARCH
- Search codebase for existing patterns
- Read relevant skill documentation
- Identify reusable components

### PLAN
- Run `/plan` before writing any code (exception: < 5 line fixes)
- Define scope, approach, and acceptance criteria
- Identify affected files and dependencies

### SPEC
- Run `/spec` after plan approval, before writing any code
- Define: inputs, outputs, error cases, scenarios — for the actual task type
- Approved spec becomes the test specification for BUILD/TDD
- Exception: trivial changes (≤5 lines, no new behavior, single file)

### BUILD (TDD)
- Write tests first based on approved spec scenarios (use `tdd-guide` agent)
- Implement minimal code to pass tests
- Refactor while tests remain green

### VERIFY
- Run `/verify` after implementation
- All 6 phases must pass (compile, test, coverage, security, static analysis)

### REVIEW
- Run `/code-review` before requesting commit
- Use domain-specific reviewers for specialized code
- Address all CRITICAL findings before proceeding

### DELIVER
- User commits (never auto-commit)
- Final `/quality-gate` before PR
