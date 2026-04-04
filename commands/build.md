---
name: build
description: TDD cycle command -- explicit BUILD phase trigger. Invokes implementer agent, follows RED-GREEN-REFACTOR cycle, loads relevant skills based on files being touched.
---

# /build -- TDD Implementation Cycle

> **AUTO-CONTINUATION RULE — READ FIRST**
> After ALL tasks complete and tests pass:
> 1. **IMMEDIATELY** invoke `/verify full` — do NOT ask, do NOT wait
> 2. After VERIFY passes → **IMMEDIATELY** invoke `/dc-review` — do NOT stop
> 3. Task is NOT done until REVIEW verdict. **Stopping after BUILD is FORBIDDEN.**
> Read `.claude/devco-config.json` for `workflow.autoVerify` (default: true) and `workflow.autoReview` (default: true).

Explicit BUILD phase trigger. Invokes the implementer agent to follow the RED-GREEN-REFACTOR TDD cycle based on the approved spec.

## Prerequisites

- Read `.claude/workflow-state.json`:
  1. Verify SPEC phase completed (`phaseHistory` contains SPEC entry or `phase` is `SPEC_APPROVED`)
  2. **Read `artifacts.spec`** — this is the exact path to the approved spec file
  3. **Read `artifacts.plan`** — this is the exact path to the approved plan file (for reference)
  4. If `artifacts.spec` missing: fallback to scanning `.claude/docs/specs/` for `status: approved`
- If no approved spec found: **STOP** — output: `"No approved spec found. Run /spec first."`
- **Read the spec file** to get task decomposition, scenarios, and `plan_ref`
- **Validate**: spec's `plan_ref` matches `artifacts.plan` in workflow-state.json

### Workflow State on Entry

Update `.claude/workflow-state.json`:
- Set `phase` to `"BUILD"`
- Add `{"phase": "SPEC", "completedAt": "{ISO timestamp}"}` to `phaseHistory` (if not already present)

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

## Subagent Context (pass to spawned agent)

When invoking each **implementer** subagent (one per task), include in its prompt:

- **Phase**: You are in the **BUILD** phase of SDD (PLAN → SPEC → BUILD → VERIFY → REVIEW)
- **Skill protocol**: Load `devco-agent-skills:bootstrap` first — contains the skill registry. Before every file operation, load the matching skill and announce it.
- **Summer check**: Scan `build.gradle` for `io.f8a.summer` → if found, load `devco-agent-skills:summer-core` first
- **Hard blocks**: No `.block()` in src/main/. No git commit/push. No code without approved plan+spec.
- **Fresh context**: Each implementer subagent gets a fresh context — pass the skill and spec scenario explicitly
- **Suggested skills**: `devco-agent-skills:testing-workflow` + domain-specific skill matching the files being touched (e.g., `devco-agent-skills:spring-patterns`, `devco-agent-skills:database-patterns`)

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

## Build Failure Handling

If a task fails during BUILD:

1. **Auto-fix**: Invoke `/build-fix` to attempt automatic resolution
2. **Re-run**: Re-run the failing task's test(s)
3. **Retry limit**: If the same error persists **3 consecutive times** → escalate to user with full error details
4. **Track retries**: Increment `retryCount` in `.claude/workflow-state.json` after each failed attempt

```
On task failure:
  1. Capture error output
  2. Run /build-fix with error context
  3. Re-run failing test
  4. If PASS → continue to next task
  5. If FAIL with same error (3x) → ESCALATE:
     "Task {N} failed 3 times with: {error summary}. Options:
      - Debug further
      - Skip and move to next task
      - Return to /spec to revise the scenario"
  6. Update workflow-state.json retryCount
```

## Completion — MANDATORY: Continue to VERIFY + REVIEW

When ALL tasks complete and tests pass:

1. Run full test suite: `./gradlew test`
2. Check coverage: `./gradlew jacocoTestReport`
3. Update `.claude/workflow-state.json` — add `{"phase": "BUILD", "completedAt": "{ISO timestamp}"}` to `phaseHistory`
4. Report BUILD status

```
BUILD COMPLETE
==============
Tasks: 4/4 completed
Tests: 12 passed, 0 failed
Coverage: 84% (target: 80% -- PASS)

Proceeding to VERIFY phase...
```

## Auto-Invoke Chain (after BUILD success)

When ALL tasks complete and tests pass:

1. **Read config**: Check `.claude/devco-config.json` for `workflow.autoVerify` (default: `true`)
2. **If autoVerify = true**: IMMEDIATELY invoke `/verify full`
   - Do NOT ask the user
   - Do NOT wait
   - Just run it
3. **If autoVerify = false**: Remind user `"BUILD complete. Run /verify full to continue."`
4. After VERIFY passes, **AUTO-INVOKE `/dc-review`** — if `workflow.autoReview` is `true` (default), IMMEDIATELY invoke `/dc-review`. Do NOT stop. This is MANDATORY.
5. Only after REVIEW produces a verdict (APPROVE/BLOCK) is the workflow complete.

**CRITICAL: Stopping after BUILD without running VERIFY and REVIEW is a workflow violation. The task is NOT done until REVIEW completes. After all tasks complete, IMMEDIATELY run /verify full — no asking, no waiting.**

## Integration with Workflow

```
/plan -> /spec -> /build -> /verify -> /dc-review
                              ↑ YOU ARE HERE    ↑ MUST REACH HERE
```

The BUILD phase is step 3 of 5. You MUST continue through VERIFY (step 4) and REVIEW (step 5) to complete the workflow.
