# Working Workflow

**The mandatory workflow for every Claude Code session in Java Spring projects.**

Every session follows seven phases. No exceptions. No shortcuts. This document is the single source of truth for how work gets done.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          SESSION LIFECYCLE                                │
│                                                                          │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌───────┐  ┌────────┐  ┌────────┐      │
│  │ BOOT │─▶│ PLAN │─▶│ SPEC │─▶│ BUILD │─▶│ VERIFY │─▶│ REVIEW │      │
│  │  ①   │  │  ②   │  │  ③   │  │  ④    │  │   ⑤    │  │   ⑥    │      │
│  └──────┘  └──┬───┘  └──┬───┘  └───┬───┘  └───┬────┘  └───┬────┘      │
│     ▲         │         │          │           │            │             │
│     │         │         │    ┌─────┘           │            ▼             │
│     │         │         │    │ TDD cycle       │     ┌──────────┐        │
│     │         │         │    │ per step        │     │ DELIVER  │        │
│     │         │         │    ▼                 │     │ to user  │        │
│     │         │         │  RED → GREEN         │     └──────────┘        │
│     │         │         │    → REFACTOR        │            │             │
│     │         │         │                      │            ▼             │
│  ┌──────┐    │         │                      │     ┌──────────┐        │
│  │LEARN │◀───┴─────────┴──────────────────────┴─────│  END     │        │
│  │  ⑦   │             SessionEnd hook               └──────────┘        │
│  └──────┘                                                                │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

- [Phase 1: BOOT](#phase-1-boot)
- [Phase 2: PLAN](#phase-2-plan)
- [Phase 3: SPEC](#phase-3-spec)
- [Phase 4: BUILD](#phase-4-build)
- [Phase 5: VERIFY](#phase-5-verify)
- [Phase 6: REVIEW](#phase-6-review)
- [Phase 7: LEARN](#phase-7-learn)
- [Enforcement Rules](#enforcement-rules)
- [Memory Flow](#memory-flow)
- [Quick Reference](#quick-reference)

---

## Phase 1: BOOT

**Trigger:** Automatic — `SessionStart` hook (`scripts/hooks/session-start.sh`)
**Purpose:** Establish full context before any work begins.

### What Happens

```
SessionStart
    │
    ├── 1. Detect project type
    │       ├── build.gradle + spring-boot-starter-webflux  → WebFlux
    │       ├── build.gradle + spring-boot-starter-web      → Boot (MVC)
    │       ├── settings.gradle with include(...)           → Monorepo
    │       └── pom.xml                                     → Maven project
    │
    ├── 2. Load PROJECT_GUIDELINES.md
    │       └── Project-specific rules, conventions, architecture decisions
    │
    ├── 3. Query claude-mem
    │       ├── Last 5 session summaries → inject context
    │       ├── Active instincts (confidence ≥ 0.5) → apply as rules
    │       └── Unresolved issues → surface as blockers
    │
    ├── 4. Report environment
    │       ├── Java version (java -version)
    │       ├── Build tool (Gradle Wrapper / Maven Wrapper)
    │       ├── Git branch (git branch --show-current)
    │       └── Uncommitted changes (git status --short)
    │
    └── 5. Print active TODO/blockers
            ├── From session files (.claude/sessions/)
            ├── From learned skills (.claude/learned-skills/)
            └── From PROJECT_GUIDELINES.md #blockers section
```

### Boot Output Example

```
[SessionStart] Project type: Spring WebFlux
[SessionStart] Build tool: Gradle Wrapper (./gradlew)
[SessionStart] Java version: 17.0.9
[SessionStart] Branch: feature/order-notifications
[SessionStart] Uncommitted: 3 files modified

[claude-mem] Last session: Implemented OrderService with CQRS pattern
[claude-mem] Active instincts:
  - "Always use StepVerifier for reactive tests" (confidence: 0.8)
  - "Prefer R2DBC DatabaseClient over JPA for complex queries" (confidence: 0.6)
[claude-mem] Unresolved: OrderRepository.findByStatus() returns empty for COMPLETED status

[TODO] Complete notification handler integration tests
[BLOCKER] Redis connection config not finalized for staging
```

### Boot Checklist

| Step | Source | Required |
|------|--------|----------|
| Detect project type | `build.gradle` / `pom.xml` | Yes |
| Load guidelines | `PROJECT_GUIDELINES.md` | Yes (skip if missing) |
| Query claude-mem | `.claude/sessions/`, instincts | Yes |
| Report environment | System commands | Yes |
| Print TODOs | Session files | If any exist |

---

## Phase 2: PLAN

**Trigger:** `/plan` command or automatically when receiving a new task
**Purpose:** Think before touching code. Understand, decompose, assess risk.
**Agent:** `planner` (see `agents/planner.md`)

### Planning Process

```
New Task Received
    │
    ├── Is this a trivial change?
    │     ├── Bug fix < 5 lines         → Skip to BUILD
    │     ├── Typo fix                   → Skip to BUILD
    │     └── Config change only         → Skip to BUILD
    │
    └── Non-trivial change
          │
          ├── 1. Restate requirements
          │       └── Clarify what is being built, in concrete terms
          │
          ├── 2. Identify affected files/modules
          │       ├── Controllers
          │       ├── Services
          │       ├── Repositories
          │       ├── DTOs / Commands / Events
          │       ├── Configuration
          │       └── Tests
          │
          ├── 3. Break down into steps
          │       └── Each step = one verifiable unit of work
          │
          ├── 4. Risk assessment
          │       ├── HIGH   — Breaking changes, data migration, auth
          │       ├── MEDIUM — New integration, schema change
          │       └── LOW    — Internal refactor, new endpoint
          │
          ├── 5. Choose architecture approach
          │       ├── Hexagonal (Ports & Adapters)
          │       ├── CQRS (Command/Query Separation)
          │       ├── Event-driven (Kafka/RabbitMQ)
          │       └── Simple layered (Controller → Service → Repository)
          │
          ├── 6. ⏸️  WAIT FOR USER CONFIRM
          │       └── DO NOT touch any code until user says "proceed"
          │
          └── 7. /checkpoint create "plan-approved"
```

### Plan Output Format

```markdown
# Implementation Plan: [Feature Name]

## Requirements
- [Clear, concrete requirement 1]
- [Clear, concrete requirement 2]

## Affected Components
| Component | File | Change Type |
|-----------|------|-------------|
| Controller | OrderController.java | New endpoint |
| Service | OrderService.java | New method |
| Repository | OrderRepository.java | New query |
| DTO | CreateOrderRequest.java | New file |
| Test | OrderServiceTest.java | New tests |

## Implementation Steps

### Step 1: [Description]
- Files: path/to/file.java
- Action: What to do
- Test: What test covers this

### Step 2: [Description]
...

## Risk Assessment: [HIGH/MEDIUM/LOW]
- [Risk 1]: [Mitigation]
- [Risk 2]: [Mitigation]

## Architecture: [Hexagonal / CQRS / Event-driven / Layered]

⏸️ **WAITING FOR CONFIRMATION** — Proceed? (yes / modify / reject)
```

### Skip Conditions

The planning phase can be skipped only when **all** of these are true:

| Condition | Example |
|-----------|---------|
| Change is ≤ 5 lines of code | Fix null check, update constant |
| Single file affected | One config file, one typo |
| No architectural impact | No new dependencies, no schema change |
| No risk of breaking existing tests | Pure addition or cosmetic fix |

When in doubt, plan.

---

## Phase 3: SPEC

**Trigger:** `/spec` command after plan approval (or automatically after `/plan` confirm)
**Purpose:** Define observable behavioral contracts before writing any code.
**Command:** `/spec` (see `commands/spec.md`)
**Rule:** `rules/common/spec-driven.md`

### What Happens

```
Plan Approved
    │
    ├── Is this a trivial change?
    │     ├── Bug fix < 5 lines         → Skip to BUILD
    │     ├── Typo fix                   → Skip to BUILD
    │     └── Config change only         → Skip to BUILD
    │
    └── Non-trivial change
          │
          ├── 1. Detect task type from plan signals
          │       ├── REST Endpoint (Controller, Handler, API)
          │       ├── Domain Logic (UseCase, Service, Command)
          │       ├── Messaging (Kafka, RabbitMQ, Event)
          │       ├── Database Migration (DDL, Flyway, schema)
          │       └── Background Job (Scheduler, cron, batch)
          │
          ├── 2. Generate spec using type-specific template
          │       ├── Inputs — what goes in
          │       ├── Outputs / Side Effects — what comes out
          │       ├── Contracts / Invariants — what must always hold
          │       └── Error Cases — what can go wrong
          │
          ├── 3. Map scenarios to test cases
          │       └── Each scenario → one or more test methods
          │
          ├── 4. ⏸️  WAIT FOR USER APPROVAL
          │       ├── Approve → /checkpoint create "spec-approved"
          │       ├── Revise  → Update spec based on feedback
          │       └── Reject  → Return to /plan
          │
          └── 5. Hand off to BUILD phase
                  └── Spec scenarios become TDD test specification
```

### Spec Output Format

Every spec includes at minimum:

| Section | Description |
|---------|-------------|
| **Inputs** | What goes in — request body, command fields, event payload |
| **Outputs / Side Effects** | What comes out — response, state changes, events published |
| **Contracts / Invariants** | What must always hold — validation, ordering, consistency |
| **Error Cases** | What can go wrong — with trigger condition and expected behavior |
| **Scenarios** | ≥1 happy path + ≥2 failure/edge cases — concrete and testable |

### Spec → TDD Mapping

Each spec scenario maps directly to test cases for the BUILD phase:

```
Spec Scenario                          → Test Method
─────────────────────────────────────────────────────
Happy path: valid order created        → shouldCreateOrderWhenValidInput()
Validation: blank customer ID          → shouldReturn400WhenCustomerIdBlank()
Conflict: duplicate order              → shouldReturn409WhenOrderExists()
Auth: missing token                    → shouldReturn401WhenNoAuthToken()
```

### Skip Conditions

Same as Phase 2 (PLAN) — skip only when **all** of these are true:

| Condition | Example |
|-----------|---------|
| Change is ≤ 5 lines of code | Fix null check, update constant |
| Single file affected | One config file, one typo |
| No new observable behavior | Rename, reformat, comment fix |
| No architectural impact | No new dependencies, no schema change |

When in doubt, spec.

---

## Phase 4: BUILD

**Trigger:** User approves spec (or skip conditions met for trivial changes)
**Purpose:** Implement using strict TDD — Red → Green → Refactor.
**Agent:** `tdd-guide` (see `agents/tdd-guide.md`)

### TDD Cycle Per Step

```
For each step in the approved plan (using approved spec as test specification):
    │
    ├── 4a. Write Test FIRST (RED)
    │       ├── Test cases derived from approved spec scenarios
    │       ├── Unit test with JUnit 5 + Mockito
    │       ├── Integration test with @SpringBootTest + Testcontainers
    │       └── Reactive test with StepVerifier
    │
    ├── 4b. Run Test → Confirm FAILS
    │       └── ./gradlew test --tests "ClassName.methodName"
    │       └── Expected: FAIL (method not implemented yet)
    │
    ├── 4c. Write Implementation (GREEN)
    │       ├── Minimal code to make the test pass
    │       ├── Follow hexagonal architecture
    │       ├── No .block() — reactive all the way
    │       ├── No mutation — immutable objects
    │       └── No side effects in pure functions
    │
    ├── 4d. Run Test → Confirm PASSES
    │       └── ./gradlew test --tests "ClassName.methodName"
    │       └── Expected: PASS
    │       └── If FAIL → /build-fix (invoke build-error-resolver agent)
    │
    ├── 4e. Refactor (IMPROVE)
    │       ├── Extract methods for clarity
    │       ├── Remove duplication
    │       ├── Improve naming
    │       ├── Simplify logic
    │       └── Run tests again to confirm nothing broke
    │
    └── /checkpoint create "step-N-done"
```

### Build Rules

| Rule | Rationale |
|------|-----------|
| Test FIRST, always | Catch regressions immediately. Tests define the contract. |
| Minimal implementation | Don't gold-plate. Make the test pass, then refactor. |
| No `.block()` in reactive code | Blocks the event loop. Use `StepVerifier` for testing. |
| No `Thread.sleep()` in tests | Use `StepVerifier.withVirtualTime()` or `Awaitility`. |
| No `subscribe()` inside chains | Causes fire-and-forget. Chain with `flatMap` / `then`. |
| Checkpoint after each step | Enables rollback and progress tracking. |

### Test Writing Examples

**Unit Test (Service Layer)**

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepository;

    @InjectMocks
    private OrderService orderService;

    @Test
    void shouldCreateOrderWithPendingStatus() {
        // Arrange
        var command = new CreateOrderCommand("CUST-001", List.of(item1, item2));
        var expected = Order.create(command);
        when(orderRepository.save(any())).thenReturn(Mono.just(expected));

        // Act & Assert
        StepVerifier.create(orderService.create(command))
            .assertNext(order -> {
                assertThat(order.getStatus()).isEqualTo("PENDING");
                assertThat(order.getCustomerId()).isEqualTo("CUST-001");
            })
            .verifyComplete();
    }
}
```

**Integration Test (API Layer)**

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@Testcontainers
class OrderApiIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void shouldCreateOrderViaApi() {
        var request = new CreateOrderRequest("CUST-001", List.of(item1));

        webTestClient.post()
            .uri("/api/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.orderId").isNotEmpty()
            .jsonPath("$.status").isEqualTo("PENDING");
    }
}
```

### Context Management During BUILD

The `suggest-compact.sh` hook (PreToolUse) monitors tool call count:

```
Tool calls < 50     →  Normal operation
Tool calls = 50     →  "[StrategicCompact] 50 tool calls reached — consider /compact"
Tool calls > 50     →  Reminder every 25 calls
```

**When to compact:** Between steps (after `/checkpoint`), never mid-implementation.

---

## Phase 5: VERIFY

**Trigger:** All build steps complete, or manually via `/verify`
**Purpose:** Multi-phase validation before review.
**Reference:** `commands/verify.md`

### Verification Pipeline

```
/verify [mode]
    │
    ├── 1. Build Check
    │       └── ./gradlew clean build -x test
    │       └── FAIL → Stop. Fix build errors first.
    │
    ├── 2. Compile Check
    │       └── ./gradlew compileJava compileTestJava
    │       └── Report all errors with file:line
    │
    ├── 3. Full Test Suite
    │       └── ./gradlew test jacocoTestReport
    │       └── Coverage must be ≥ 80%
    │       └── All tests must PASS
    │
    ├── 4. Reactive Safety Scan
    │       ├── grep -rn "\.block()" --include="*.java" src/main/
    │       ├── grep -rn "Thread\.sleep" --include="*.java" src/main/
    │       └── grep -rn "\.subscribe()" --include="*.java" src/main/
    │       └── Any match in production code → CRITICAL
    │
    ├── 5. Security Scan
    │       ├── Hardcoded secrets (password, api_key, token in source)
    │       ├── ./gradlew dependencyCheckAnalyze (CVE scan)
    │       └── Debug statements (System.out.println, printStackTrace)
    │
    └── 6. Diff Review
            ├── git diff --stat
            ├── Check for unintended file changes
            └── Verify no files outside scope were modified
```

### Verification Modes

| Mode | Command | Checks | When to Use |
|------|---------|--------|-------------|
| Quick | `/verify quick` | Build + Compile | Mid-development sanity check |
| Pre-commit | `/verify pre-commit` | Build + Tests + Debug audit | Before committing |
| Pre-PR | `/verify pre-pr` | All checks + Security scan | Before opening a pull request |
| Full | `/verify` or `/verify full` | Everything | Default — end of implementation |

### Verification Report Format

```
VERIFICATION: [PASS/FAIL]
═════════════════════════

Build:          [OK/FAIL]
Compile:        [OK/X errors]
Tests:          [X/Y passed, Z% coverage]
Reactive:       [OK/X blocking calls found]
Security:       [OK/X issues found]
Debug:          [OK/X statements found]
Diff:           [X files changed, Y insertions, Z deletions]

Ready for Review: [YES/NO]

Issues to Address:
──────────────────
1. [Issue description → fix]
2. [Issue description → fix]
```

### Verification Gates

| Check | Pass Criteria | On Failure |
|-------|---------------|------------|
| Build | Exit code 0 | STOP — fix before continuing |
| Compile | Zero errors | STOP — fix all compilation errors |
| Tests | 100% pass, ≥80% coverage | Fix failing tests. Improve coverage. |
| Reactive | Zero `.block()` / `Thread.sleep()` / orphan `.subscribe()` in `src/main/` | CRITICAL — must fix before review |
| Security | No hardcoded secrets, no HIGH/CRITICAL CVEs | BLOCK — must fix before review |
| Debug | No `System.out.println` / `printStackTrace` | WARNING — remove before commit |
| Diff | Only planned files changed | Review unintended changes |

---

## Phase 6: REVIEW

**Trigger:** Verification passes
**Purpose:** Multi-agent code review, then deliver results to user.
**Agents:** `code-reviewer`, `security-reviewer`, and conditional reviewers

### Review Chain

```
Verification PASS
    │
    ├── 1. Code Reviewer (ALWAYS)
    │       ├── Quality, readability, naming
    │       ├── DRY — no duplicated code
    │       ├── SOLID principles
    │       ├── Error handling completeness
    │       └── Test quality assessment
    │
    ├── 2. Security Reviewer (ALWAYS)
    │       ├── OWASP Top 10
    │       ├── Secrets in code
    │       ├── Injection vulnerabilities
    │       ├── Auth/authz correctness
    │       └── Dependency CVEs
    │
    ├── 3. Spring WebFlux Reviewer (CONDITIONAL)
    │       └── Triggered when: *Controller.java, reactive chains, WebFlux config changed
    │       ├── Backpressure handling
    │       ├── Non-blocking verification
    │       ├── Error propagation in reactive chains
    │       └── Project Reactor best practices
    │
    ├── 4. Database Reviewer (CONDITIONAL)
    │       └── Triggered when: *Repository.java, *.sql, migration files changed
    │       ├── Query optimization
    │       ├── Index usage
    │       ├── N+1 detection
    │       └── Schema design review
    │
    ├── 5. Architect (CONDITIONAL)
    │       └── Triggered when: new modules, DDD boundaries, significant refactoring
    │       ├── Architecture consistency
    │       ├── Bounded context boundaries
    │       ├── Event flow correctness
    │       └── Coupling analysis
    │
    └── VERDICT
          ├── ✅ APPROVE   — No critical or high issues
          ├── ⚠️  WARNING  — Medium issues only (document and proceed)
          └── ❌ BLOCK     — Critical or high issues (must fix)
```

### Conditional Reviewer Triggers

| Reviewer | Triggers When |
|----------|---------------|
| Spring WebFlux Reviewer | Files matching `*Controller.java`, `*Handler.java`, or `*WebFlux*` changed |
| Spring Boot Reviewer | Files matching `*Config.java`, `application*.yml`, `build.gradle` changed |
| Database Reviewer | Files matching `*Repository.java`, `*.sql`, `changelog*`, `migration*` changed |
| Architect | New packages created, `>5 files` in different modules changed, domain boundary touched |

### Review Report Format

```markdown
# Code Review Report

## Summary
| Reviewer | Verdict | Issues |
|----------|---------|--------|
| Code Reviewer | ✅ APPROVE | 0 critical, 0 high, 2 suggestions |
| Security Reviewer | ✅ APPROVE | 0 critical, 0 high |
| WebFlux Reviewer | ⚠️ WARNING | 1 medium (missing timeout) |

## Overall Verdict: ⚠️ WARNING

## Issues

### [MEDIUM] Missing timeout on external service call
**File:** `PaymentService.java:78`
**Issue:** WebClient call without timeout — risks thread exhaustion
**Fix:**
​```java
return webClient.get()
    .uri("/api/payment/{id}", paymentId)
    .retrieve()
    .bodyToMono(PaymentResponse.class)
    .timeout(Duration.ofSeconds(5));  // Add this
​```

### [SUGGESTION] Consider extracting mapper
**File:** `OrderController.java:45`
**Issue:** Inline DTO mapping — extract to dedicated mapper for reuse
```

### After Review: Delivery Protocol

```
Review Complete
    │
    ├── APPROVE
    │     └── Deliver summary to user
    │           └── "Implementation complete. Review passed. Ready for your final review."
    │
    ├── WARNING
    │     └── Deliver summary + issue list to user
    │           └── "Implementation complete with warnings. See issues below."
    │
    └── BLOCK
          └── Fix blocking issues → re-run VERIFY → re-run REVIEW
          └── Do NOT deliver blocked code to user
```

**CRITICAL RULE: The agent does NOT commit.** The agent delivers completed, reviewed code. The user does the final review and commits manually. This is non-negotiable.

---

## Phase 7: LEARN

**Trigger:** Automatic — `SessionEnd` hook (`scripts/hooks/session-end.sh`, `evaluate-session.sh`)
**Purpose:** Extract patterns and learnings for future sessions.

### Learning Process

```
Session Ending (≥ 10 messages)
    │
    ├── 1. Evaluate Session
    │       ├── What was built?
    │       ├── What patterns emerged?
    │       ├── What bugs were fixed?
    │       └── What corrections did the user make?
    │
    ├── 2. Extract Patterns
    │       │
    │       ├── Bug fixed → Anti-pattern instinct
    │       │     Example: "NullPointerException in stream"
    │       │            → "Always use Optional.ofNullable() before stream operations"
    │       │
    │       ├── New pattern discovered → Pattern instinct
    │       │     Example: "Used @Retryable for transient failures"
    │       │            → "Apply @Retryable(maxAttempts=3) for external service calls"
    │       │
    │       └── User correction → Correction instinct
    │             Example: User says "Don't use Lombok here"
    │                    → "This project avoids Lombok — use records or manual builders"
    │
    ├── 3. Save to claude-mem
    │       ├── Session summary (what was done, what files changed)
    │       ├── New instincts with initial confidence (0.3–0.5)
    │       └── Files modified list
    │
    └── 4. Update Instinct Confidence
            ├── Instinct confirmed by this session → confidence + 0.1
            ├── Instinct contradicted → confidence - 0.1
            └── Instinct at confidence < 0.1 → mark for removal
```

### Instinct Lifecycle

```
                    Session N          Session N+1        Session N+2
                  ┌───────────┐      ┌───────────┐      ┌───────────┐
Discovered        │ conf: 0.3 │──────│ conf: 0.4 │──────│ conf: 0.5 │──▶ Active
(from bug fix)    └───────────┘  +0.1└───────────┘  +0.1└───────────┘
                                confirmed           confirmed

                    Session N          Session N+1        Session N+2
                  ┌───────────┐      ┌───────────┐      ┌───────────┐
Discovered        │ conf: 0.4 │──────│ conf: 0.3 │──────│ conf: 0.2 │──▶ Fading
(from pattern)    └───────────┘  -0.1└───────────┘  -0.1└───────────┘
                                contradicted        contradicted
```

### Instinct Storage Format

```json
{
  "id": "instinct-2024-001",
  "pattern": "Always add timeout to WebClient calls",
  "source": "Bug fix — service hung indefinitely on external API failure",
  "confidence": 0.7,
  "category": "anti-pattern",
  "created": "2024-01-15",
  "lastConfirmed": "2024-01-20",
  "project": "order-service"
}
```

### PreCompact Hook

Before context compaction occurs (`scripts/hooks/pre-compact.sh`):

1. Save current session state to `.claude/sessions/`
2. Log compaction event to `compaction-log.txt`
3. Preserve in-progress work context

This prevents losing important context during automatic compaction.

---

## Enforcement Rules

These rules are non-negotiable. They prevent the most common workflow violations.

### Hard Blocks

| Violation | Action | Exception |
|-----------|--------|-----------|
| Writing code without `/plan` | **STOP** — run `/plan` first | Bug fix ≤ 5 lines, typo, config-only change |
| Writing code without approved spec | **STOP** — run `/spec` first | Bug fix ≤ 5 lines, no new behavior |
| Committing without `/verify` | **BLOCK** — run `/verify` first | None |
| Skipping tests for new code | **BLOCK** — write tests first | None |
| `.block()` in reactive production code | **CRITICAL** — must fix immediately | Test code only (still discouraged) |
| Agent attempts `git commit` | **BLOCK** — only user commits | None |

### Enforcement Flow

```
Code change detected
    │
    ├── Was /plan run? ─── NO ──▶ STOP. "Run /plan first."
    │       │                      (unless trivial fix)
    │      YES
    │       │
    ├── Was /spec run and approved? ── NO ──▶ STOP. "Run /spec first."
    │       │                          (unless trivial fix)
    │      YES
    │       │
    ├── Were tests written first? ── NO ──▶ BLOCK. "Write tests first."
    │       │
    │      YES
    │       │
    ├── Do tests pass? ── NO ──▶ Fix with /build-fix
    │       │
    │      YES
    │       │
    ├── Was /verify run? ── NO ──▶ BLOCK. "Run /verify before review."
    │       │
    │      YES
    │       │
    ├── Any .block() in src/main/? ── YES ──▶ CRITICAL. Fix now.
    │       │
    │       NO
    │       │
    └── Proceed to REVIEW
```

### Reactive Safety Rules

These patterns are forbidden in production code (`src/main/`):

| Pattern | Why It's Forbidden | Alternative |
|---------|--------------------|-------------|
| `.block()` | Blocks the event loop thread, defeats reactive purpose | Chain with `flatMap`, `map`, `then` |
| `Thread.sleep()` | Blocks thread, wastes resources | `Mono.delay()`, `delayElement()` |
| `.subscribe()` inside a chain | Fire-and-forget, loses error context | `flatMap`, `then`, `concatWith` |
| `Mono.just(blockingCall())` | Executes blocking call on event loop | `Mono.fromCallable(blockingCall).subscribeOn(Schedulers.boundedElastic())` |

---

## Memory Flow

The `claude-mem` integration provides cross-session continuity. Sessions within the same project share memory.

### Memory Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     claude-mem Store                          │
│                                                              │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │  Sessions    │  │  Instincts   │  │  Unresolved       │  │
│  │  (last 5)    │  │  (active)    │  │  Issues           │  │
│  └──────┬──────┘  └──────┬───────┘  └────────┬──────────┘  │
│         │                │                    │              │
└─────────┼────────────────┼────────────────────┼──────────────┘
          │                │                    │
          ▼                ▼                    ▼
    ┌───────────────────────────────────────────────┐
    │              SessionStart (BOOT)              │
    │  "Load last 5 sessions, active instincts,     │
    │   unresolved issues for this project"         │
    └───────────────────┬───────────────────────────┘
                        │
                        ▼
    ┌───────────────────────────────────────────────┐
    │              During Session                    │
    │  Hooks capture observations:                  │
    │  - PostToolUse: compilation results           │
    │  - PreToolUse: tool count for compact suggest │
    │  - Stop: evaluate session patterns            │
    └───────────────────┬───────────────────────────┘
                        │
                        ▼
    ┌───────────────────────────────────────────────┐
    │              SessionEnd (LEARN)               │
    │  Save to claude-mem:                          │
    │  - Session summary                            │
    │  - New instincts (confidence 0.3–0.5)         │
    │  - Updated instinct confidence                │
    │  - Files modified                             │
    │  - Unresolved issues                          │
    └───────────────────────────────────────────────┘
```

### Memory Operations by Phase

| Phase | Operation | Data |
|-------|-----------|------|
| BOOT | **Read** | Last 5 sessions, active instincts, unresolved issues |
| PLAN | **Read** | Similar past plans, architecture decisions |
| SPEC | **Read** | Past specs for similar task types, reusable patterns |
| BUILD | **Observe** | Hooks capture compile results, tool count |
| VERIFY | **Observe** | Test results, coverage metrics |
| REVIEW | **Observe** | Review verdicts, common issues |
| LEARN | **Write** | Session summary, new instincts, confidence updates |

### Cross-Session Continuity

```
Session 1 (order-service)          Session 2 (order-service)
┌─────────────────────┐            ┌─────────────────────┐
│ Built OrderService   │            │ [BOOT loads context] │
│ Fixed N+1 query      │──write──▶  │ "Last session: Built │
│ Learned: use @Query  │            │  OrderService, fixed  │
│ Instinct: conf 0.4   │            │  N+1. Instinct: use   │
└─────────────────────┘            │  @Query (conf 0.4)"   │
                                   └─────────────────────┘
```

---

## Quick Reference

### Command Cheat Sheet

| Command | Phase | Purpose |
|---------|-------|---------|
| `/plan` | ② PLAN | Create implementation plan and wait for confirmation |
| `/spec` | ③ SPEC | Define behavioral contracts from approved plan |
| `/build-fix` | ④ BUILD | Fix build/compilation errors (invokes `build-error-resolver`) |
| `/checkpoint create "name"` | ②③④ | Save progress at milestones |
| `/checkpoint verify "name"` | Any | Compare current state to a checkpoint |
| `/verify` | ⑤ VERIFY | Run full verification pipeline |
| `/verify quick` | ⑤ VERIFY | Build + Compile only |
| `/verify pre-commit` | ⑤ VERIFY | Build + Tests + Debug audit |
| `/verify pre-pr` | ⑤ VERIFY | Full checks + Security scan |
| `/code-review` | ⑥ REVIEW | Trigger multi-agent code review |
| `/learn` | ⑦ LEARN | Manually extract patterns from current session |
| `/instinct status` | Any | Show all learned instincts with confidence |
| `/evolve` | Any | Cluster related instincts into skills |
| `/compact` | Any | Compact context (use at phase boundaries) |

### Phase Decision Flowchart

```
User sends a message
    │
    ├── "Fix this typo" / "Change this constant"
    │     └── Skip PLAN/SPEC → BUILD (trivial) → VERIFY quick → Done
    │
    ├── "Add feature X" / "Refactor Y"
    │     └── PLAN → confirm → SPEC → approve → BUILD (TDD) → VERIFY → REVIEW → Deliver
    │
    ├── "Build is broken"
    │     └── /build-fix → VERIFY quick → Done
    │
    ├── "/verify" or "/verify pre-pr"
    │     └── Run verification pipeline → Report
    │
    └── "/plan [description]"
          └── Run planning agent → Present plan → Wait for confirm
```

### Agent Selection Quick Reference

| Situation | Agent(s) |
|-----------|----------|
| New feature planning | `planner` → `architect` |
| Writing new code | `tdd-guide` |
| Build failure | `build-error-resolver` |
| Code review | `code-reviewer` + `security-reviewer` |
| WebFlux code changed | + `spring-webflux-reviewer` |
| Spring config changed | + `spring-reviewer` |
| Database code changed | + `database-reviewer` |
| Architecture decision | `architect` |
| Dead code cleanup | `refactor-cleaner` |
| E2E test generation | `e2e-runner` or `blackbox-test-runner` |

### File References

| File | Purpose |
|------|---------|
| `agents/*.md` | Agent definitions (12 specialized agents) |
| `commands/*.md` | Slash command definitions (15 commands) |
| `rules/common/*.md` | Language-agnostic workflow rules (6 files) |
| `rules/java/*.md` | Java/Spring-specific rules (6 files) |
| `scripts/hooks/*.sh` | Lifecycle hook scripts (8 scripts) |
| `skills/*/SKILL.md` | Skill definitions (13+ skills) |
| `PROJECT_GUIDELINES.md` | Per-project rules (in each project root) |

---

## Appendix A: Complete Phase Transition Diagram

```
                    ┌─────────────────────────────────┐
                    │         SESSION START            │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────────────┐
                    │  ① BOOT (automatic)             │
                    │  - Detect project type           │
                    │  - Load PROJECT_GUIDELINES.md    │
                    │  - Query claude-mem              │
                    │  - Report environment            │
                    └────────────┬────────────────────┘
                                 │
                         New task received
                                 │
                    ┌────────────┴────────────────────┐
                    │                                  │
               Trivial?                          Non-trivial
               (≤5 lines)                              │
                    │                                  ▼
                    │               ┌─────────────────────────────────┐
                    │               │  ② PLAN                        │
                    │               │  - Restate requirements         │
                    │               │  - Identify files               │
                    │               │  - Risk assessment              │
                    │               │  - ⏸️  WAIT for user confirm    │
                    │               └────────────┬────────────────────┘
                    │                            │
                    │                     User confirms
                    │                            │
                    └────────────┬───────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────────────┐
                    │  ③ SPEC                         │
                    │  - Detect task type from plan    │
                    │  - Generate behavioral spec      │
                    │  - Map scenarios to test cases    │
                    │  - ⏸️  WAIT for user approve     │
                    └────────────┬────────────────────┘
                                 │
                          User approves spec
                                 │
                    └────────────┬───────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────────────┐
                    │  ④ BUILD (TDD per step)         │
                    │  ┌───────────────────────────┐  │
                    │  │ RED: Write test            │  │
                    │  │ Run → confirm FAILS        │  │
                    │  │ GREEN: Write implementation │  │
                    │  │ Run → confirm PASSES       │  │
                    │  │ REFACTOR: Clean up         │  │
                    │  │ /checkpoint create         │  │
                    │  └───────────┬───────────────┘  │
                    │              │ repeat per step   │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────────────┐
                    │  ⑤ VERIFY                       │
                    │  - Build check                   │
                    │  - Compile check                 │
                    │  - Test suite (≥80% coverage)    │
                    │  - Reactive safety scan          │
                    │  - Security scan                 │
                    │  - Diff review                   │
                    └────────────┬────────────────────┘
                                 │
                          PASS?──┤
                           │     │
                          NO    YES
                           │     │
                     Fix issues  │
                     and re-run  │
                                 ▼
                    ┌─────────────────────────────────┐
                    │  ⑥ REVIEW                       │
                    │  - Code Reviewer                 │
                    │  - Security Reviewer             │
                    │  - Conditional reviewers          │
                    │  - Verdict: APPROVE/WARN/BLOCK   │
                    └────────────┬────────────────────┘
                                 │
                          ┌──────┴──────┐
                          │             │
                        BLOCK        APPROVE/
                          │          WARNING
                     Fix issues        │
                     → re-VERIFY       │
                     → re-REVIEW       ▼
                              ┌─────────────────────┐
                              │  DELIVER to user    │
                              │  (user reviews and  │
                              │   commits manually) │
                              └────────┬────────────┘
                                       │
                                       ▼
                    ┌─────────────────────────────────┐
                    │  ⑦ LEARN (automatic)            │
                    │  - Extract patterns              │
                    │  - Save instincts to claude-mem  │
                    │  - Update confidence scores      │
                    │  - PreCompact: save state        │
                    └─────────────────────────────────┘
```

## Appendix B: Hook-to-Phase Mapping

| Hook | Script | Phase | Fires When |
|------|--------|-------|------------|
| `SessionStart` | `session-start.sh` | ① BOOT | New session begins |
| `PreToolUse` | `suggest-compact.sh` | ④ BUILD | Before each tool call (monitors count) |
| `PostToolUse` | `java-compile-check.sh` | ④ BUILD | After Java file edits |
| `PostToolUse` | `java-format.sh` | ④ BUILD | After Java file edits |
| `Stop` | `check-debug-statements.sh` | ⑤ VERIFY | Session stopping — final audit |
| `Stop` | `evaluate-session.sh` | ⑦ LEARN | Session stopping — extract patterns |
| `PreCompact` | `pre-compact.sh` | Any | Before context compaction |
| `SessionEnd` | `session-end.sh` | ⑦ LEARN | Session ending — persist state |

## Appendix C: Error Recovery

| Error | Recovery Path |
|-------|---------------|
| Build fails during VERIFY | Run `/build-fix` → re-run `/verify` |
| Test fails after implementation | Check test logic → fix implementation → re-run test |
| Coverage below 80% | Write additional tests for uncovered paths → re-run |
| `.block()` detected in production code | Replace with reactive alternative → re-verify |
| Review returns BLOCK | Fix all critical/high issues → re-run `/verify` → re-run review |
| Context too large (>50 tool calls) | `/checkpoint create` → `/compact` → continue from checkpoint |
| Session crashes mid-work | Next session BOOT loads last checkpoint and session state from claude-mem |

---

_This workflow is enforced, not optional. Every phase exists for a reason. Skip nothing. Trust the process._