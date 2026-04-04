---
name: spec
description: Generate behavioral spec from approved plan -- define observable contracts before implementation. Gate between PLAN and BUILD phases.
---

# /spec -- Define Behavioral Contracts

Generate a behavioral specification from the approved plan. Defines observable contracts (inputs, outputs, error cases) that become the test specification for the BUILD phase.

## Prerequisites

- `/plan` must have been run and approved
- Read `.claude/workflow-state.json`:
  1. Verify PLAN phase completed (`phaseHistory` contains PLAN entry or `phase` is `PLAN_APPROVED`)
  2. **Read `artifacts.plan`** — this is the exact path to the approved plan file
  3. If `artifacts.plan` is missing: scan `.claude/docs/plans/` for any file with `status: approved`
- If no approved plan found: **STOP** — output: `"No approved plan found. Run /plan first."`
- **Validate** the plan file exists and `status: approved` in its frontmatter

## Subagent Context (pass to spawned agent)

When invoking the **spec-writer** agent, include in its prompt:

- **Plan file**: `"Read the approved plan at: {artifacts.plan from workflow-state.json}. This is the EXACT file you must base the spec on. Do NOT scan the directory — use THIS file."`
- **Phase**: You are in the **SPEC** phase of SDD (PLAN → SPEC → BUILD → VERIFY → REVIEW)
- **Skill protocol**: Load `devco-agent-skills:bootstrap` first — contains the skill registry. Before every file operation, load the matching skill and announce it.
- **Summer check**: Scan `build.gradle` for `io.f8a.summer` → if found, load `devco-agent-skills:summer-core` first
- **Hard blocks**: No `.block()` in src/main/. No git commit/push. No code without approved plan+spec.
- **Gate**: This is the gate between PLAN and BUILD — spec must be approved before any code is written
- **Suggested skill**: `devco-agent-skills:api-design` for REST contract design and status code conventions

**CRITICAL**: The plan file path MUST be passed to the spec-writer agent. Without it, the spec-writer cannot find the correct plan.

## Workflow

```
/spec
  |
  +-- 1. Read approved plan from session context
  |       +-- STOP if no /plan was run or plan was rejected
  |
  +-- 2. Detect task type from plan signals
  |       +-- Controller, Handler, endpoint -> REST Endpoint
  |       +-- UseCase, Service, Command, domain -> Domain Logic
  |       +-- Kafka, RabbitMQ, event, consumer -> Messaging
  |       +-- Migration, Flyway, DDL, schema -> Database Migration
  |       +-- Scheduler, cron, job, batch -> Background Job
  |       +-- Multiple signals -> Mixed (generate spec per component)
  |
  +-- 3. Generate spec using type-specific template
  |       +-- Fill with concrete values from plan context
  |
  +-- 4. Present spec for user approval
  |       +-- Approve  -> proceed to BUILD
  |       +-- Revise   -> User provides feedback, regenerate
  |       +-- Reject   -> Return to /plan
  |
  +-- 5. On approve: map spec scenarios to test cases
          +-- Output: test case skeleton for BUILD/TDD
```

## Task Type Detection

| Signal in Plan | Detected Type |
|----------------|---------------|
| `*Controller.java`, `*Handler.java`, `endpoint`, `REST`, `API` | REST Endpoint |
| `*UseCase.java`, `*Service.java`, `Command`, `Query`, `domain` | Domain Logic |
| `Kafka`, `RabbitMQ`, `*Consumer.java`, `*Producer.java`, `event`, `topic` | Messaging |
| `*.sql`, `migration`, `Flyway`, `DDL`, `ALTER TABLE`, `schema` | Database Migration |
| `@Scheduled`, `cron`, `job`, `batch`, `*Job.java`, `*Task.java` | Background Job |

## Spec Generation

The spec-writer agent handles spec generation with:
- Automatic task type detection (REST, Domain Logic, Messaging, DB Migration, Background Job)
- 7-step process: Read Plan → Detect Type → Read Codebase → Generate Spec → Map to Tests → Task Decomposition → Present for Approval
- Concrete templates for each task type with field names, status codes, exception types

The agent will read the codebase to ground the spec in reality — using actual class names, exception types, and field names found in the code.

See `agents/spec-writer.md` for full template details.

## Spec to Test Case Mapping

After spec approval, output a test case skeleton:

```
Spec Scenarios -> Test Cases:
  Scenario 1 (happy path)     -> shouldCreateOrderWhenValidInput()
  Scenario 2 (validation)     -> shouldReturn400WhenFieldBlank()
  Scenario 3 (conflict)       -> shouldReturn409WhenDuplicate()
  Scenario 4 (auth)           -> shouldReturn401WhenNoToken()
```

This feeds directly into the BUILD phase TDD cycle.

## Task Decomposition

After spec approval, decompose into ordered atomic tasks:

| # | Task | Files | Test Method | Depends On |
|---|------|-------|-------------|------------|
| 1 | Create DTO record | CreateOrderRequest.java | -- | -- |
| 2 | Write repository method | OrderRepository.java | shouldFindByIdWhenExists() | 1 |
| 3 | Implement use case | CreateOrderUseCase.java | shouldCreateOrderWhenValid() | 1,2 |
| 4 | Add controller endpoint | OrderController.java | shouldReturn201WhenCreated() | 3 |

Each task is independently testable. BUILD phase processes tasks in order.

## Document Persistence (MANDATORY)

The spec MUST be written to a file — not just presented in conversation:

- **Location**: `.claude/docs/specs/{feature-name}.md` (matches plan filename)
- **References plan**: Frontmatter includes `plan_ref: .claude/docs/plans/{feature-name}.md`
- **On draft**: Written when first presented
- **On revision**: Same file updated with revision history
- **On approval**: `status: approved` updated in frontmatter

The build command will READ this file. If no file exists, BUILD cannot proceed.

## Workflow State Tracking

When this command runs, **update** `.claude/workflow-state.json`:
- Set `phase` to `"SPEC"`
- Add `{"phase": "PLAN", "completedAt": "{ISO timestamp}"}` to `phaseHistory` (if not already present)

When the user **approves** the spec:
1. Update `workflow-state.json`:
   - Add `{"phase": "SPEC", "completedAt": "{ISO timestamp}"}` to `phaseHistory`
   - Set `phase` to `"SPEC_APPROVED"`
   - **Set `artifacts.spec` to the spec file path** (e.g., `".claude/docs/specs/order-notification.md"`)
2. Output to user: **"Spec approved and saved to: `.claude/docs/specs/{feature-name}.md`"**
3. Output: **"Run `/build` to start TDD implementation — it will read from this spec file."**

## Approval Protocol

Present the completed spec (already written to file) and WAIT:

```
SPEC REVIEW

Spec document: .claude/docs/specs/{feature-name}.md

Approve this spec? (approve / revise / reject)
- approve -> status updated, proceed to BUILD
- revise  -> provide feedback, spec document will be updated
- reject  -> return to /plan for re-planning
```
