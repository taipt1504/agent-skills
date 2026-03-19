---
name: build
description: TDD cycle command -- explicit BUILD phase trigger. Invokes implementer agent, follows RED-GREEN-REFACTOR cycle, loads relevant skills based on files being touched.
---

# /build -- TDD Implementation Cycle

Explicit BUILD phase trigger. Invokes the implementer agent to follow the RED-GREEN-REFACTOR TDD cycle based on the approved spec.

## Prerequisites

- `/plan` must have been run and approved
- `/spec` must have been run and approved (spec scenarios and task decomposition available)
- If no spec exists: **STOP** -- output: `"No approved spec found. Run /spec first."`

## Usage

```
/build              -> start BUILD phase from spec task list
/build <task#>      -> start from specific task number in decomposition
/build continue     -> resume BUILD from last completed task
```

## Subagent-per-Task Isolation

For each task in the spec's task decomposition, **spawn a separate Agent** (implementer, model: sonnet):

```
For each task:
  1. Spawn Agent with: task description + spec scenario + relevant skills + prior task summary
  2. Agent executes TDD cycle: RED → GREEN → REFACTOR
  3. Agent completes → collect results
  4. 2-stage review: spec compliance check, then code quality check
  5. If blocked → surface to user
```

This ensures each task runs in a **fresh context** with only the relevant information pre-loaded, preventing context pollution between tasks.

## TDD Cycle (per task)

```
RED    -> Write a failing test that captures the spec scenario
GREEN  -> Write minimal implementation to make the test pass
REFACTOR -> Clean up while keeping tests green
```

### Phase 1: RED (Write Failing Test)

1. Read the spec scenario for the current task
2. Create test class if it doesn't exist
3. Write test method following naming convention: `shouldDoXWhenY`
4. Run the test -- confirm it FAILS (expected)

```bash
./gradlew test --tests "*{TestClass}.{testMethod}" 2>&1 | tail -20
```

If the test passes immediately, the spec scenario may already be implemented -- skip to next task.

### Phase 2: GREEN (Minimal Implementation)

1. Write the minimum code to make the failing test pass
2. Follow project conventions:
   - Constructor injection (`@RequiredArgsConstructor`)
   - Records for immutable DTOs
   - Reactive chains for WebFlux (`Mono`/`Flux`, never `.block()`)
   - Hexagonal architecture (domain -> application -> infrastructure -> interfaces)
3. Run the test -- confirm it PASSES

```bash
./gradlew test --tests "*{TestClass}.{testMethod}" 2>&1 | tail -20
```

If the test still fails after implementation, debug and fix before moving on.

### Phase 3: REFACTOR (Clean Up)

1. Review the implementation for:
   - Method length (max 50 lines)
   - Class length (max 400 lines, 800 absolute max)
   - Nesting depth (max 4 levels)
   - Duplicate code
   - Naming clarity
2. Refactor while keeping all tests green
3. Run full test suite to verify nothing broke

```bash
./gradlew test 2>&1 | tail -20
```

## Skill Loading

Based on the files being touched, automatically load relevant skills:

| File Pattern | Skills to Load |
|-------------|---------------|
| `*Controller.java`, `*Handler.java` | REST endpoint patterns, validation |
| `*Service.java`, `*UseCase.java` | Domain logic, reactive chains |
| `*Repository.java` | R2DBC/JPA patterns, query optimization |
| `*Consumer.java`, `*Producer.java` | Kafka/RabbitMQ patterns |
| `*Config.java` | Spring configuration patterns |
| `*.sql`, `migration` | Database migration rules |
| `*Test.java` | Testing patterns, StepVerifier, Testcontainers |

## Task Progress Tracking

After each task completes all three phases (RED-GREEN-REFACTOR), report progress:

```
BUILD PROGRESS
==============
Task 1/4: Create DTO record                    [DONE]
Task 2/4: Write repository method               [DONE]
Task 3/4: Implement use case                    [IN PROGRESS - GREEN]
Task 4/4: Add controller endpoint               [PENDING]

Tests: 6 passed, 0 failed
Coverage: 78% (target: 80%)
```

## When a Task Fails

If a test cannot be made to pass after 3 attempts:

1. Log the failure with context
2. Ask the user whether to:
   - Debug further
   - Skip and move to next task
   - Return to `/spec` to revise the scenario
   - Run `/build-fix` for compilation issues

## Completion

When all tasks are complete:

1. Run full test suite: `./gradlew test`
2. Check coverage: `./gradlew jacocoTestReport`
3. Report final status

```
BUILD COMPLETE
==============
Tasks: 4/4 completed
Tests: 12 passed, 0 failed
Coverage: 84% (target: 80% -- PASS)

Next steps:
- Run /verify to check quality, security, and style
- Run /review before committing
```

## Integration with Workflow

```
/plan -> /spec -> /build -> /verify -> /review
```

The BUILD phase sits between SPEC (contracts defined) and VERIFY (quality gates). Each task in the build follows the TDD cycle independently, producing tested, incremental code.
