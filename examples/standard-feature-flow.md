# Standard Lane Walkthrough — Add Pagination to User List Endpoint

End-to-end example. Bounded feature. Multiple slices. Full reasoning gates.

## Setup

Project: Spring WebFlux user-service.
Endpoint: `GET /api/v1/users` currently returns `Flux<UserDto>` unbounded.
Task: add pagination with `Pageable` parameter.

## User input

```
> Add pagination to GET /api/v1/users. Use Spring Data Pageable.
> Default page size 20, max 100.
```

## Walkthrough

### 1. Triage

Auto-fires:

```
## Triage decision
**Lane:** Standard
**Reasoning:** Feature with bounded scope, single endpoint, no architectural change, no schema change.
**Next gate:** Align (request specific but verifying assumptions)
```

State written. `LANE=standard`.

### 2. Align — agent surfaces assumptions

Request specific (3 requirements stated: pagination, default 20, max 100), so Align runs lightweight check:

```
Agent (align):
## My understanding
You want pagination on GET /api/v1/users using Spring Data Pageable.
Default size 20. Max size 100 (enforced via @Max validation).

## Assumptions I'm making
1. Existing endpoint returns Flux<UserDto> — switching to Mono<Page<UserDto>>
2. Underlying UserRepository is ReactiveSortingRepository (R2DBC)
3. Sort field whitelist needed to prevent SQL injection via Sort.by(...)
4. Response includes pagination metadata (page, size, totalElements, totalPages)
5. No breaking change to existing clients — but Mono<Page<...>> shape differs from Flux<...>
   ↑ This is actually a breaking change for clients streaming the Flux. Verify acceptable.

Any wrong?
```

User confirms #5 acceptable (clients don't stream). Align writes artifact:

`.claude/memory/align-artifacts/2026-05-15-pagination.md`:

```markdown
# Alignment: Add pagination to user list

## Agreed requirements
1. GET /api/v1/users supports `?page=N&size=M&sort=field,asc`
2. Default page size 20, max 100 (@Max validation)
3. Response: Mono<Page<UserDto>> with metadata
4. Sort field whitelist: id, username, createdAt
5. Breaking change accepted: clients update from Flux to Page<>

## Assumptions confirmed
- UserRepository = ReactiveSortingRepository
- @Max(100) validates size parameter
- Whitelist enforced in service layer
```

CONTEXT.md updates: adds "Pageable response shape" to vocabulary if not already present.

### 3. Brainstorm — agent assesses if needed

```
Agent: Single obvious solution (Spring Data Pageable). No paradigm shift opens new dimensions. Standard lane allows skip.

Skipping Brainstorm. Proceeding to Plan.
```

Logged: `brainstorm_skipped: true, reason: "single obvious solution"`.

(If user typed "I want pagination" without specifying, agent would Brainstorm offset vs cursor.)

### 4. Pre-flight 2 (plan-prep)

`.claude/memory/preflight/plan-1747391500.md`:

```markdown
# Pre-flight: Plan
**Lane:** Standard
**Gate:** Plan

## Skills enumeration (31 total)

### APPLY (5)
| Skill | Score | Action |
|---|---|---|
| architecture | 70% | Hexagonal: change in interfaces + application layers |
| api-design | 95% | Pageable response shape, REST conventions |
| coding-standards | 100% | Always |
| spring-webflux-patterns | 100% | Reactive endpoint |
| testing-workflow | 100% | TDD mandatory |

### SKIP (26)
| Skill | Reason |
|---|---|
| brainstorm | Skipped this task |
| messaging-patterns | No events emitted from list endpoint |
| spring-mvc-patterns | Project = WebFlux, MVC stack disabled (verified application.yml) |
| ... |

## Rules (13 total)

### APPLY (8)
- rules/common/coding-style.md (100%)
- rules/common/spec-driven.md (100%)
- rules/java/api-design.md (95%)
- rules/java/coding-style.md (100%)
- rules/java/reactive.md (100%)
- rules/java/security.md (90% — sort whitelist)
- rules/java/observability.md (70% — metric on slow page query)
- rules/java/testing.md (100%)

### SKIP (5)
- rules/summer/audit.md — read endpoint, no audit field write
- rules/summer/messaging.md — no events
- rules/java/migration.md — no schema change
- ...
```

### 5. Plan

Agent decomposes into slices:

`.claude/docs/plans/user-pagination.md`:

```markdown
# Plan: Add Pagination to GET /api/v1/users

## Chosen solution (from Align)
Spring Data Pageable on existing endpoint. Reactive Page<> response.

## Slices

### Slice 1: Domain layer — sort field whitelist
- Files: 1 new (`UserSortField.java` enum)
- Skills: coding-standards
- Dependencies: none
- Risk: Low
- Complexity: S (30 min)
- Rationale: enum prevents reflection-based attack via untrusted Sort field

### Slice 2: Application layer — UserQueryService.findAll(Pageable) method
- Files: 1 modified (`UserQueryService.java`)
- Skills: spring-webflux-patterns, coding-standards
- Dependencies: Slice 1
- Risk: Low
- Complexity: M (2h)
- Rationale: service-level whitelist enforcement + R2DBC pagination

### Slice 3: Interfaces layer — controller signature change + DTO
- Files: 2 modified (`UserController.java`, `PagedUsersResponse.java`)
- Skills: spring-webflux-patterns, api-design
- Dependencies: Slice 2
- Risk: Medium (breaking change for streaming clients)
- Complexity: M (2h)
- Rationale: client-facing contract, validation, error responses

## Dependency graph

- Slice 1 → blocks: 2
- Slice 2 → blocks: 3
- Slice 3 → blocks: (none, leaf)

## Execution order
1. Slice 1 (no deps)
2. Slice 2 (depends on 1)
3. Slice 3 (depends on 2)

No parallel — sequential chain.

## Risk register

| Slice | Risk | Severity | Mitigation |
|---|---|---|---|
| 3 | Breaking change for Flux-streaming clients | Medium | Documented in Align as accepted; smoke test with sample client |

## Estimated total: 4.5 hours
```

User approves.

### 6. Spec

Per slice, behavioral contracts.

`.claude/docs/specs/user-pagination.md` (excerpt):

```markdown
## Slice 3 — Controller signature change

### Endpoint contract

**Request:**
```
GET /api/v1/users?page=0&size=20&sort=createdAt,desc
```

**Response 200:**
```json
{
  "content": [{"id": "...", "username": "..."}],
  "page": 0,
  "size": 20,
  "totalElements": 1234,
  "totalPages": 62
}
```

**Response 400 (invalid sort field):**
```json
{
  "type": "https://example.com/problems/invalid-sort",
  "title": "Invalid sort field",
  "status": 400,
  "detail": "Sort field 'password' not allowed. Allowed: id, username, createdAt"
}
```

### Scenarios

| ID | Name | Input | Expected |
|---|---|---|---|
| S3.1 | shouldReturnFirstPageWhenDefaultParams | GET /api/v1/users | 200, page=0, size=20 |
| S3.2 | shouldRespectCustomSize | GET /api/v1/users?size=50 | 200, size=50 |
| S3.3 | shouldRejectSizeOver100 | GET /api/v1/users?size=200 | 400 (ProblemDetail: max size 100) |
| S3.4 | shouldRejectInvalidSortField | GET /api/v1/users?sort=password,asc | 400 (ProblemDetail: invalid sort) |
| S3.5 | shouldSortByCreatedAtDesc | GET /api/v1/users?sort=createdAt,desc | 200, results ordered by createdAt desc |
| S3.6 | shouldReturnEmptyPageWhenBeyondTotal | GET /api/v1/users?page=999 | 200, empty content, totalPages reflects actual |
```

User approves.

### 7. Pre-flight 4 (execute-prep) + Execute

Pre-flight 4 written. Orchestrator dispatches sequentially (slices chain).

**Slice 1 dispatch** (slice-executor subagent, model: sonnet):

```
You are slice-executor for slice 1 of 3.

Slice: Domain layer — sort field whitelist
Pre-flight 4: <injected>
Spec: <Slice 1 spec>

Process: RED → GREEN → REFACTOR.
```

Subagent:
1. RED — writes test for `UserSortField.from("password")` → throws IllegalArgumentException
2. GREEN — implements `UserSortField` enum with `from(String)` factory
3. REFACTOR — extracts whitelist constants
4. Reports back to orchestrator

Orchestrator unblocks Slice 2.

**Slice 2 dispatch:** UserQueryService method. Similar TDD cycle.

**Slice 3 dispatch:** Controller + DTO. WebTestClient integration tests for all 6 scenarios from spec.

After all 3 done, orchestrator triggers `/verify`.

### 8. Verify

```bash
./gradlew clean test         # PASS (all unit + integration tests)
./gradlew jacocoTestReport   # PASS (coverage 86%, threshold 80%)
./gradlew spotlessCheck      # PASS
```

`workflow-tracker.sh` auto-sets phase → REVIEW_PENDING.

### 9. Review Stage 1 (spec compliance)

```markdown
✅ Spec compliance: PASS

| Scenario | Test | Result |
|---|---|---|
| S1.1 | UserSortFieldTest.shouldThrowWhenFieldNotAllowed | PASS |
| S2.1 | UserQueryServiceTest.shouldApplyPageableToRepository | PASS |
| S3.1 | UserControllerTest.shouldReturnFirstPageWhenDefaultParams | PASS |
| S3.2 | UserControllerTest.shouldRespectCustomSize | PASS |
| S3.3 | UserControllerTest.shouldRejectSizeOver100 | PASS |
| S3.4 | UserControllerTest.shouldRejectInvalidSortField | PASS |
| S3.5 | UserControllerTest.shouldSortByCreatedAtDesc | PASS |
| S3.6 | UserControllerTest.shouldReturnEmptyPageWhenBeyondTotal | PASS |

All 8 scenarios mapped to passing tests.
→ Proceeding to Stage 2.
```

### 10. Review Stage 2 (code quality)

```markdown
## Stage 2: Code Quality Review

**Verdict:** Approve with caveats

### Critical issues (0)
### Major issues (1)
1. UserController.java:42 — Sort field whitelist hardcoded in controller layer
   - Recommendation: extract to UserSortField enum (already done in Slice 1) — controller should delegate to enum. Currently has dual list (maintenance risk).

### Minor issues (2)
1. PagedUsersResponse.java:18 — totalPages computation duplicated from Page<>.getTotalPages(). Consider returning page directly from service if no field renaming needed.
2. UserQueryServiceTest.java:73 — Mock returns hardcoded data. Consider using a fixture factory for reusability.

### Observations
- Coverage 86% (above 80% threshold ✓)
- No security issues (sort whitelist enforced, @Max validation on size)
- Performance: assumes index on `created_at` for default sort. Verify exists in db migration history.

### Skills + rules applied
spring-webflux-patterns, api-design, coding-standards, testing-workflow
rules: common/coding-style, common/spec-driven, java/api-design, java/coding-style, java/reactive, java/security, java/testing
```

User reviews Major issue. Decides:
- Option A: fix now → back to BUILD with delta
- Option B: accept caveat, fix in follow-up → COMPLETE with note

User chooses A. Slice-executor fixes Major issue. Re-run `/dc-review` Stage 2 only. Approve.

### 11. Learn

```
[evolution-check] 0 candidates ready for promotion
[session-save] phase=COMPLETE
```

Maybe a new instinct surfaces: "Sort field whitelist belongs in domain layer, not controller". Recorded at confidence 0.5 → may evolve over more occurrences.

### 12. Commit (user)

```bash
git add .
git commit -m "feat: add pagination to GET /api/v1/users

- New: UserSortField enum (domain, sort field whitelist)
- Modified: UserQueryService.findAll(Pageable) method
- Modified: UserController returns Mono<Page<UserDto>> (breaking)
- Tests: 8 scenarios, coverage 86%

Skills applied: spring-webflux-patterns, api-design, coding-standards, testing-workflow
Rules applied: java/api-design, java/reactive, java/security, java/testing
Refs: plans/user-pagination.md, specs/user-pagination.md"
```

## Artifacts produced

| Path | Lane | Purpose |
|---|---|---|
| `.claude/memory/state/current-triage.json` | standard | Lane decision |
| `.claude/memory/preflight/initial-*.md` | standard | Pre-flight 0 enumeration |
| `.claude/memory/align-artifacts/2026-05-15-pagination.md` | standard | Requirements + assumptions |
| `.claude/memory/preflight/plan-*.md` | standard | Pre-flight 2 |
| `.claude/docs/plans/user-pagination.md` | standard | Slices + dependency graph |
| `.claude/memory/preflight/spec-*.md` | standard | Pre-flight 3 |
| `.claude/docs/specs/user-pagination.md` | standard | Scenarios per slice |
| `.claude/memory/preflight/execute-*.md` | standard | Pre-flight 4 (injected into subagents) |
| `.claude/memory/state/build-checkpoint.json` | standard | Build progress |
| `.claude/memory/preflight/review-*.md` | standard | Pre-flight 5 |
| `.claude/memory/state/review-stage1.json` | standard | Stage 1 verdict |
| `.claude/memory/state/review-stage2.json` | standard | Stage 2 verdict |

## Total time

| Phase | Time |
|---|---|
| Triage | ~5s |
| Align | ~3 min (conversation) |
| Brainstorm | skipped |
| Plan | ~5 min (slice decomposition + user approval) |
| Spec | ~10 min (scenarios + user approval) |
| Execute (3 slices sequential) | ~3 hours (TDD per slice) |
| Verify | ~30s |
| Review S1 + S2 | ~2 min |
| Fix Major issue + re-review | ~10 min |
| **Total** | **~3.5 hours** |

## Lessons captured

1. Align caught the breaking-change risk early (assumption #5) — saved late rework
2. Brainstorm skipped correctly — single obvious solution, no paradigm shift available
3. Slice 1 had no production-code dep — independently testable, fast feedback
4. Stage 1 binary gate caught a missed test before Stage 2 wasted effort
5. Stage 2 Major issue triggered re-build cycle — quality gate working
