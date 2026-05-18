# Example: Pre-flight Artifact for Execute Gate (variant 4)

> **TEMPLATE / EXAMPLE.** Live artifacts go to `.claude/memory/preflight/execute-<timestamp>.md`.

## Context

**Task:** "Add pagination to GET /users endpoint" (slice 2 of 3)
**Lane:** Standard
**Gate:** Execute (variant 4)
**Date:** 2026-05-16T11:22:00Z
**Plan slice:** "Wire Pageable from controller to repository, return Page<UserDto>"
**Spec ref:** `.claude/memory/preflight/spec-1747387200.md` (variant 3)

## Skills enumeration (total: 26)

### APPLY (11)

| Skill | Score | Action |
|---|---|---|
| testing-workflow | 100% | TDD mandatory — write RED test first |
| coding-standards | 100% | Immutability, Lombok, records for DTOs |
| api-design | 95% | RFC 7807 errors, Pageable response shape |
| spring-webflux-patterns | 100% | Reactive controller + repository chain (project=WebFlux) |
| database-patterns | 90% | ReactiveCrudRepository pagination via PageRequest |
| observability-patterns | 70% | MDC correlation, request metrics |
| spring-security | 60% | Endpoint already authenticated, verify @PreAuthorize |
| pentest | 40% | Verify no SQL injection via sort field whitelist |
| architecture | 70% | Stay within `interfaces/` + `application/` boundary |
| summer-rest | 85% | Project uses Summer — BaseController.execute() dispatch |
| summer-data | 60% | Summer pagination conventions if present |

### SKIP (15)

| Skill | Reason |
|---|---|
| bootstrap | Already loaded (always) |
| preflight | Already running (meta) |
| triage | Lane already set |
| align | No vague requirements remaining |
| brainstorm | Standard lane, single obvious approach |
| api-docs-datatype-sync | No new @Schema annotations in this slice |
| caller-aware-audit-pattern | Read endpoint, no audit field write |
| deployment-patterns | No config / profile changes |
| grpc-patterns | No gRPC (verified `grep -r '@GrpcService' src/` = 0) |
| messaging-patterns | No events emitted from list endpoint |
| redis-patterns | No caching decision in this slice |
| spring-mvc-patterns | Project uses WebFlux (servlet stack disabled) |
| summer-file | No file ops |
| summer-kafka | No messaging |
| summer-payment-sdk | No payment flow |
| summer-ratelimit | Not in slice scope (separate slice) |
| summer-security | Auth already configured |
| summer-test | Will use, moved to "implicit" via testing-workflow + skill is summer-* — re-checking |

## Rules enumeration (total: 13)

### APPLY (10)

| Rule | Score | Action |
|---|---|---|
| rules/common/coding-style.md | 100% | Immutability, naming |
| rules/common/security.md | 100% | Input validation (page, size bounds) |
| rules/common/git-workflow.md | 100% | Conventional commits |
| rules/common/skill-enforcement.md | 100% | 1% rule live |
| rules/common/spec-driven.md | 100% | Scenarios → tests 1:1 |
| rules/java/coding-style.md | 100% | Records for `PagedUserResponse`, @RequiredArgsConstructor |
| rules/java/reactive.md | 100% | NO `.block()`; backpressure on Flux source |
| rules/java/api-design.md | 95% | Page response shape, sort param whitelist |
| rules/java/security.md | 80% | Sort field allowlist (no SQL injection via Sort) |
| rules/java/observability.md | 75% | Add `users.list.latency` histogram |
| rules/java/testing.md | 100% | 80%+ coverage, StepVerifier + WebTestClient |

### SKIP (3)

| Rule | Reason |
|---|---|
| rules/common/lanes.md | Lane already decided |
| rules/common/patterns.md | No architectural decision in this slice |
| rules/common/development-workflow.md | Already executing |

## Active instincts (≥0.6 confidence)

| Instinct | Confidence | Action |
|---|---|---|
| "Pageable sort field must be whitelisted vs reflection on entity" | 0.82 | Enforce in this slice — validate `sort` against allowed columns |
| "Default page size cap at 100 to prevent abuse" | 0.71 | Include in validation |

## Subagent dispatch context

This artifact is injected into the slice-executor subagent context with:
- Plan slice (above)
- Spec for this slice (`.claude/memory/preflight/spec-...md` linked)
- CONTEXT.md vocabulary

Subagent process:
1. Re-verify pre-flight items match this slice's needs
2. Append new items if discovered during implementation
3. Apply listed skills/rules during code
4. Cite skill names in commit message

## Total summary

- Skills: 11 APPLY, 15 SKIP
- Rules: 10 APPLY, 3 SKIP
- All SKIPs justified with concrete evidence
- Subagent receives this artifact as primary context
