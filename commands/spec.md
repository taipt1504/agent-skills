---
name: spec
description: Generate behavioral spec from approved plan -- define observable contracts before implementation. Gate between PLAN and BUILD phases.
---

# /spec -- Define Behavioral Contracts

## First Action (MANDATORY)

Before anything else, update the workflow state:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
mkdir -p "$PROJECT_ROOT/.claude"
python3 -c "
import json, datetime, os
path = os.environ['PROJECT_ROOT'] + '/.claude/workflow-state.json'
state = {}
if os.path.exists(path):
    with open(path) as f:
        state = json.load(f)
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
state['phase'] = 'SPEC'
state.setdefault('phaseHistory', [])
already = any(e.get('phase') == 'PLAN' for e in state['phaseHistory'])
if not already:
    state['phaseHistory'].append({'phase': 'PLAN', 'completedAt': now})
with open(path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
print('workflow-state.json updated: phase=SPEC')
" 2>/dev/null || echo "workflow-state.json update skipped"
```

Generate a behavioral specification from the approved plan. Defines observable contracts (inputs, outputs, error cases) that become the test specification for the BUILD phase.

## Prerequisites

- `/plan` must have been run and approved
- Read `.claude/workflow-state.json`:
  1. Verify PLAN phase completed (`phaseHistory` contains PLAN entry or `phase` is `PLAN_APPROVED`)
  2. **Read `artifacts.plan`** — this is the exact path to the approved plan file
  3. If `artifacts.plan` is missing: scan `.claude/docs/plans/` for any file with `status: approved`
- If no approved plan found: **STOP** — output: `"No approved plan found. Run /plan first."`
- **Validate** the plan file exists and `status: approved` in its frontmatter
- After reading and validating the plan file:
  4. Check `artifacts.spec_count` in workflow-state.json — if present and > 1, this is a **multi-spec run**
  5. Check if the plan contains `## Service Impact Map` — confirm multi-service scope
  6. If multi-service: output "**Multi-spec mode**: {N} services detected. Will generate {N} coordinated specs."

## Subagent Context (pass to spawned agent)

When invoking the **spec-writer** agent, include in its prompt:

- **Plan file**: `"Read the approved plan at: {artifacts.plan from workflow-state.json}. This is the EXACT file you must base the spec on. Do NOT scan the directory — use THIS file."`
- **Phase**: You are in the **SPEC** phase of SDD (PLAN → SPEC → BUILD → VERIFY → REVIEW)
- **Skill protocol**: Load `devco-agent-skills:bootstrap` first — contains the skill registry. Before every file operation, load the matching skill and announce it.
- **Summer check**: Scan `build.gradle` for `io.f8a.summer` → if found, load `devco-agent-skills:summer-core` first
- **Hard blocks**: No `.block()` in src/main/. No git commit/push. No code without approved plan+spec.
- **Gate**: This is the gate between PLAN and BUILD — spec must be approved before any code is written
- **Suggested skill**: `devco-agent-skills:api-design` for REST contract design and status code conventions

- **Multi-spec mode**: If the plan has `## Service Impact Map`, generate one spec per service. Use sequential generation (provider first). Apply the Cross-Reference Pass after all specs are written.
- **Contract Registry**: Extract all API paths, event topics, shared DTOs from the plan's `## Cross-Service Integration Points` into a Contract Registry. Every spec MUST use values from this registry exactly.
- **R5 compliance**: For each related service, read only CLAUDE.md + session files + specific files named in the plan. NEVER glob/grep related service trees.
- **Spec naming**: Multi-service specs use `.claude/docs/specs/{feature-name}-{service-name}.md` — kebab-case service name appended.

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

**Multi-Spec Workflow (when plan has `## Service Impact Map`):**

```
/spec (multi-service mode)
  |
  +-- 1. Read approved plan → detect ## Service Impact Map → multi-spec mode
  |
  +-- 2. Extract Contract Registry from ## Cross-Service Integration Points
  |
  +-- 3. For each service (provider first):
  |       +-- Read related service CLAUDE.md + session files (R5)
  |       +-- Read ONLY named API/event/DTO files from plan
  |       +-- Detect task type for THIS service
  |       +-- Generate spec from type-specific template
  |       +-- Add ## Cross-Service Dependencies section
  |       +-- Add integration_ref + service + contract_version to frontmatter
  |       +-- Write to .claude/docs/specs/{feature}-{service}.md
  |
  +-- 4. Cross-Reference Pass (MANDATORY)
  |       +-- Verify all event topics match producer/consumer specs
  |       +-- Verify all endpoint paths/schemas match caller/provider specs
  |       +-- Verify all shared DTOs have identical fields
  |       +-- Fix any mismatches, log corrections
  |
  +-- 5. Present ALL specs together for user approval
          +-- Approve all  → update all to status:approved, set artifacts.spec + artifacts.specs
          +-- Revise [N]   → update specific spec, re-run cross-reference pass
          +-- Reject       → return to /plan
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

When the user **approves** the specs (multi-service):
1. Update `workflow-state.json`:
   - Add `{"phase": "SPEC", "completedAt": "{ISO timestamp}"}` to `phaseHistory`
   - Set `phase` to `"SPEC_APPROVED"`
   - **Set `artifacts.spec`** to the FIRST spec path (provider spec) — backward compatibility with `/build`
   - **Set `artifacts.specs`** to the ordered array of ALL spec paths:
     ```json
     "artifacts": {
       "plan": ".claude/docs/plans/{feature-name}.md",
       "spec": ".claude/docs/specs/{feature-name}-{service-a}.md",
       "specs": [
         ".claude/docs/specs/{feature-name}-{service-a}.md",
         ".claude/docs/specs/{feature-name}-{service-b}.md"
       ]
     }
     ```
2. Output: **"All {N} specs approved and saved."**
3. List all spec file paths with service names
4. Output: **"Run `/build` to implement {service-a} spec first. After completion, run `/build` again for remaining service specs."**

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
