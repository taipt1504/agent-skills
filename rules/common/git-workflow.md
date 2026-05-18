---
name: git-workflow
description: Git rules — conventional commits, branch naming, PR workflow, feature implementation flow, protected branches
globs: "*"
---

# Git Workflow

## Commit Message Format (Conventional Commits)

```
<type>(<scope>): <description>

<optional body — explain WHY, not what>

<optional footer — BREAKING CHANGE:, Refs:, Co-authored-by:>
```

| Type | Use For | Example |
|------|---------|---------|
| `feat` | New feature or behavior | `feat(order): add idempotency key support` |
| `fix` | Bug fix | `fix(auth): prevent token refresh race condition` |
| `refactor` | Code restructure, no behavior change | `refactor(user): extract value objects from entity` |
| `test` | Adding or fixing tests | `test(order): add StepVerifier tests for create flow` |
| `docs` | Documentation changes | `docs: update API versioning guide` |
| `chore` | Build, CI, tooling changes | `chore: upgrade Spring Boot to 3.2.5` |
| `perf` | Performance improvements | `perf(query): add covering index for order lookup` |
| `ci` | CI/CD pipeline changes | `ci: add OWASP dependency-check to pipeline` |

**Scope** optional, recommended: `auth`, `order`, `user`, `infra`, `db`.

**Body** explains WHY — not what lines changed. Diff shows what; message explains intent.

## Branch Naming

```
<type>/<ticket-id>-<short-description>
```

Examples:
- `feat/ORD-123-add-idempotency-keys`
- `fix/AUTH-456-token-refresh-race`
- `refactor/USER-789-extract-value-objects`

## Pull Request Workflow

1. Analyze full commit history — `git diff [base-branch]...HEAD`
2. Draft PR summary: WHY and what problem this solves
3. Include test plan with verification steps
4. Push with `-u` flag if new branch
5. Request review from ≥1 team member

### PR Checklist

- [ ] Tests pass (`./gradlew test`)
- [ ] Coverage ≥80% (`./gradlew jacocoTestReport`)
- [ ] No `.block()` in reactive code
- [ ] No hardcoded secrets
- [ ] Migrations follow expand-contract pattern
- [ ] API changes are backward compatible (or new version)
- [ ] ArchUnit tests pass (architecture compliance)

## Feature Implementation Flow

1. **Plan** — planner agent; deps, risks, phases
2. **Spec** — observable behavior; spec = test spec
3. **TDD** — RED, GREEN, IMPROVE; verify ≥80% coverage
4. **Review** — reviewer agent; fix CRITICAL + HIGH
5. **Commit** — conventional commits; explain intent

## Protected Branch Rules

- NEVER force push to `main` or `develop`
- NEVER commit directly to `main` — PR only
- Agent commits FORBIDDEN — user commits only
- Rebase on latest base branch before merge

## Related Skills

- **coding-standards** — Code conventions that inform PR review
- **testing-workflow** — Verification pipeline that gates PR merging
