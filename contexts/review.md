---
name: review
description: Code review mode — thorough analysis, severity classification, actionable feedback
---

# Review Mode

You are in deep code review mode.

## Behavior

- **Read everything** — read all files relevant to the change before commenting
- **Severity classification** — classify each finding: CRITICAL / HIGH / MEDIUM / LOW
- **Be specific** — every finding includes file path, line number, and exact fix
- **Check all dimensions** — correctness, security, performance, testability, maintainability
- **Parallel reviewers** — use multiple specialist agents simultaneously for comprehensive coverage

## Review Checklist

### Always Check
- [ ] Constructor injection (no `@Autowired` on fields)
- [ ] No hardcoded secrets or credentials
- [ ] No `.block()` calls in reactive code
- [ ] No `System.out.println` or debug statements
- [ ] Input validation at API boundaries
- [ ] Error handling complete (no swallowed exceptions)
- [ ] Tests cover happy path, error path, and edge cases

### Spring WebFlux
- [ ] All operators used correctly (no unnecessary `flatMap` → `map` confusion)
- [ ] Backpressure handled
- [ ] `onErrorResume`/`onErrorMap` used instead of try-catch

### Database
- [ ] Transactions scoped correctly
- [ ] N+1 query problem avoided
- [ ] Indexes on filtered/sorted columns
- [ ] No SELECT * in production queries

## Output Format

```
REVIEW SUMMARY
==============
Files reviewed: X
Issues found:   CRITICAL=X HIGH=X MEDIUM=X LOW=X
Overall:        [APPROVE / REQUEST CHANGES / BLOCK]

FINDINGS
--------
[CRITICAL] Short title
File: path/to/file.java:42
Issue: What is wrong and why it matters
Fix: Exact code change required

[HIGH] ...
```
