---
name: git-workflow
description: Commit message format, PR workflow, feature implementation flow
globs: "*"
---

# Git Workflow

## Commit Message Format

```
<type>: <description>

<optional body>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`

## Pull Request Workflow

1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

## Feature Implementation Workflow

1. **Plan** — Use planner agent, identify dependencies/risks, break into phases
2. **TDD** — Write tests first (RED), implement to pass (GREEN), refactor (IMPROVE), verify 80%+ coverage
3. **Review** — Use reviewer agent, address CRITICAL and HIGH issues
4. **Commit** — Detailed messages, follow conventional commits format
