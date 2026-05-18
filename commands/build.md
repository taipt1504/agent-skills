---
name: build
description: Execute gate — dispatches one slice-executor subagent per plan slice (parallel where independent). Reads plan + spec + pre-flight 4 artifact. Lane-aware (trivial: direct execute, no dispatch).
---

# /build — Execute Gate (Subagent Dispatch)

## First Action (MANDATORY)

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LANE_FILE="$PROJECT_ROOT/.claude/memory/state/current-triage.json"
PREFLIGHT_DIR="$PROJECT_ROOT/.claude/memory/preflight"

# 1. Lane check
LANE="standard"
[ -f "$LANE_FILE" ] && LANE=$(grep -o '"lane"[[:space:]]*:[[:space:]]*"[^"]*"' "$LANE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)

# 2. Trivial bypass — orchestrator executes directly, no subagent dispatch
if [ "$LANE" = "trivial" ]; then
  echo "Trivial lane — orchestrator executes directly (no slice dispatch)."
fi

# 3. Pre-flight 4 (execute-prep) artifact check
if ! /usr/bin/ls "$PREFLIGHT_DIR"/execute-*.md 2>/dev/null | grep -q .; then
  echo "WARN: no pre-flight 4 artifact. preflight-gate.sh will produce it."
fi

# 4. Update workflow state
mkdir -p "$PROJECT_ROOT/.claude"
python3 -c "
import json, datetime, os
path = os.environ['PROJECT_ROOT'] + '/.claude/workflow-state.json'
state = {}
if os.path.exists(path):
    with open(path) as f:
        state = json.load(f)
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
state['phase'] = 'BUILD'
state['lane'] = os.environ.get('LANE', 'standard')
state.setdefault('phaseHistory', [])
already = any(e.get('phase') == 'SPEC' for e in state['phaseHistory'])
if not already:
    state['phaseHistory'].append({'phase': 'SPEC', 'completedAt': now})
state['retryCount'] = 0
with open(path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
print(f'workflow-state.json: phase=BUILD lane={state[\"lane\"]}')
" 2>/dev/null || echo "workflow-state.json update skipped"
```

Then:
1. **Detect shape from workflow-state.json artifacts:**
   - Split shape: `artifacts.plan_index` + `artifacts.spec_index` present (per-feature dir)
   - Single-file shape: `artifacts.plan` + `artifacts.spec` present (`.md` files)
2. **Validate plan + spec template conformance** (HARD BLOCK):
   - Split: `bash scripts/ci/validate-plan-spec-templates.sh --plan <plan_index_dir> --spec <spec_index_dir>`
   - Single-file: `bash scripts/ci/validate-plan-spec-templates.sh --plan <artifacts.plan> --spec <artifacts.spec>`
   - Validation fails → STOP. Report: "Plan/spec missing required sections per templates/. Re-run /plan or /spec." Workflow violation.
3. **Approval gate (split shape only):** verify `status: APPROVED` in BOTH plan_index AND spec_index AND every `slices/*.md` (`PARTIALLY_APPROVED` blocks dispatch per §6.7 decision). Any slice DRAFT/REVISED → STOP. Report: "Slice <id> not APPROVED — `/build` waits for full feature approval."
4. Read plan/spec — single-file: read fully; split: read index for slice list + dep graph, defer slice content to subagent dispatch
5. Read pre-flight 4 artifact at `.claude/memory/preflight/execute-<latest>.md` — skills + rules to apply
6. **Dispatch (shape-aware):**
   - Trivial lane: orchestrator executes directly, no subagent
   - Single-file standard: read spec §5 scenarios → dispatch slice-executor per slice with `artifacts.plan` + `artifacts.spec` injected
   - Split standard/high-stakes: per slice in dep graph, dispatch slice-executor with `artifacts.plan_slice = <plan>/slices/<NN>-<slug>.md` + `artifacts.spec_slice = <spec>/slices/<NN>-<slug>.md` + cross-cutting excerpt from spec_index §1 (subagent-init.sh injects)
7. Parallel slices: independent slices in same batch dispatch concurrently (bounded `config.team.maxTeammates`)

> **AUTO-CONTINUATION RULE — READ FIRST**
> After ALL tasks complete and tests pass:
> 1. **IMMEDIATELY** invoke `/verify full` — do NOT ask, do NOT wait
> 2. After VERIFY passes → **IMMEDIATELY** invoke `/dc-review` — do NOT stop
> 3. Task NOT done until REVIEW verdict. **Stopping after BUILD is FORBIDDEN.**
> Read `.claude/devco-config.json` for `workflow.autoVerify` (default: true) and `workflow.autoReview` (default: true).

Execute gate. Orchestrator dispatches slice-executor subagents per plan slice. Uses bootstrap §Subagent dispatch + bootstrap §Worktree per slice (high-stakes auto).

## Prerequisites

| Lane | Required artifacts |
|---|---|
| Trivial | Pre-flight 0 (light) only — orchestrator executes directly, no plan/spec needed |
| Standard | `.claude/workflow-state.json` with `artifacts.plan` + `artifacts.spec`, plus pre-flight 4 |
| High-stakes | Same as standard + brainstorm artifact + ADR + worktree per slice |

Lane != trivial AND artifacts missing: **STOP**. Output: `"Missing plan/spec/preflight. Run prerequisite gates first."`.

## Dispatch logic by lane

### Trivial lane

Orchestrator executes directly. No subagent dispatch. No worktree.

1. Read pre-flight 0 (light format)
2. Apply listed skills (likely `coding-standards` + `testing-workflow`)
3. Make change, run light verify (compile + format)

### Standard lane (multi-slice)

For each slice in plan's dependency graph:

1. Parse slice list + dependencies
2. Identify independent slices (no `blockedBy`)
3. Dispatch first batch (up to `team.maxTeammates`) in parallel
4. Await batch completion
5. Dispatch next batch (now-unblocked slices)
6. Repeat until all slices done

### High-stakes lane

Same as standard PLUS:
- Worktree per slice via `skills/bootstrap/SKILL.md §"Worktree per slice"`
- ADR auto-check at session end
- Security scan in verify step

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

## Multi-Agent Evaluation (when team.enabled = true)

Before BUILD, check if parallel execution is appropriate:

1. Read `.claude/devco-config.json` → `team.enabled` and `team.mode`
2. `enabled: false` → single-agent BUILD (below)
3. `enabled: true` → read approved spec, count independent tasks
4. Spec has **≥2 independent tasks** AND estimated change **>50 lines**:
   - Become **coordinator** — do NOT implement directly
   - Check `team.mode` to determine spawning strategy
   - After all agents complete → run `/verify full` → `/dc-review`
5. Spec has **1 task** OR small change → single-agent BUILD

### Mode: `subagent` (default, stable)

Each agent gets isolated git worktree — safe for parallel file edits.

```
Agent({
  description: "Implement: {task title from spec}",
  prompt: "Implement task from spec at {artifacts.spec path}. Task: {task description}. Follow TDD: RED→GREEN→REFACTOR. Load devco-agent-skills:coding-standards and devco-agent-skills:testing-workflow. No .block() in src/main/, no git commit.",
  model: "{team.roles.implementer.model, default: sonnet}",
  isolation: "worktree",
  run_in_background: true
})
```

### Mode: `team` (experimental)

Agents share working directory + task list. Can message each other via `SendMessage`.

```
# 1. Create team
TeamCreate({ team_name: "build-{feature}", description: "TDD for {feature}" })

# 2. Create tasks
TaskCreate({ subject: "{task title}", description: "{task description}" })

# 3. Spawn teammates
Agent({
  description: "Implement: {task title}",
  prompt: "You are a teammate. Read task via TaskGet. TDD. Mark done via TaskUpdate.",
  team_name: "build-{feature}",
  name: "impl-{N}",
  model: "{team.roles.implementer.model, default: sonnet}",
  run_in_background: true
})
```

### Which mode to use?

| Scenario | Mode | Why |
|----------|------|-----|
| Independent modules (separate files) | `subagent` | Worktree isolation prevents conflicts |
| Shared domain model needing coordination | `team` | Agents negotiate interfaces via messaging |
| First time / unsure | `subagent` | Stable, safe default |

## Subagent-per-Task Isolation

For each task in spec's task decomposition, spawn separate Agent (slice-executor, model: sonnet):

```
For each task:
  1. Spawn Agent with: task description + spec scenario + relevant skills + prior task summary
  2. Agent executes TDD cycle: RED → GREEN → REFACTOR
  3. Agent completes → collect results
  4. 2-stage review: spec compliance check, then code quality check
  5. If blocked → surface to user
```

Each task runs in fresh context with only relevant info pre-loaded — prevents context pollution between tasks.

## TDD Cycle (per task)

```
RED    -> Write a failing test that captures the spec scenario
GREEN  -> Write minimal implementation to make the test pass
REFACTOR -> Clean up while keeping tests green
```

### Phase 1: RED (Write Failing Test)

1. Read spec scenario for current task
2. Create test class if it doesn't exist
3. Write test method: `shouldDoXWhenY`
4. Run test — confirm FAILS (expected)

```bash
./gradlew test --tests "*{TestClass}.{testMethod}" 2>&1 | tail -20
```

Test passes immediately → spec scenario already implemented — skip to next task.

### Phase 2: GREEN (Minimal Implementation)

1. Write minimum code to make failing test pass
2. Follow conventions:
   - Constructor injection (`@RequiredArgsConstructor`)
   - Records for immutable DTOs
   - Reactive chains for WebFlux (`Mono`/`Flux`, never `.block()`)
   - Hexagonal architecture (domain → application → infrastructure → interfaces)
3. Run test — confirm PASSES

```bash
./gradlew test --tests "*{TestClass}.{testMethod}" 2>&1 | tail -20
```

Test still fails → debug and fix before moving on.

### Phase 3: REFACTOR (Clean Up)

1. Review for:
   - Method length (max 50 lines)
   - Class length (max 400 lines, 800 absolute max)
   - Nesting depth (max 4 levels)
   - Duplicate code
   - Naming clarity
2. Refactor while keeping all tests green
3. Run full test suite

```bash
./gradlew test 2>&1 | tail -20
```

## Subagent Context (pass to spawned agent)

Include in each **slice-executor** subagent prompt:

- **Phase**: BUILD phase of SDD (PLAN → SPEC → BUILD → VERIFY → REVIEW)
- **Skill protocol**: Load `devco-agent-skills:bootstrap` first. Before every file op, load matching skill and announce it.
- **Summer check**: Scan `build.gradle` for `io.f8a.summer` → if found, load `devco-agent-skills:summer-core` first
- **Hard blocks**: No `.block()` in src/main/. No git commit/push. No code without approved plan+spec.
- **Fresh context**: Each slice-executor gets fresh context — pass skill and spec scenario explicitly
- **Suggested skills**: `devco-agent-skills:testing-workflow` + domain-specific skill matching files touched (e.g., `devco-agent-skills:spring-webflux-patterns`, `devco-agent-skills:database-patterns`)

## Skill Loading

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

On task failure:

1. **Auto-fix**: Invoke `/build-fix` to attempt automatic resolution
2. **Re-run**: Re-run failing task's test(s)
3. **Retry limit**: Same error 3 consecutive times → escalate to user with full error details
4. **Track retries**: Increment `retryCount` in `.claude/workflow-state.json`

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
2. **autoVerify = true**: IMMEDIATELY invoke `/verify full` — do NOT ask, do NOT wait
3. **autoVerify = false**: Remind user `"BUILD complete. Run /verify full to continue."`
4. After VERIFY passes → **auto-invoke `/dc-review`** if `workflow.autoReview` is `true` (default). Do NOT stop.
5. Only after REVIEW verdict (APPROVE/BLOCK) is workflow complete.

**CRITICAL: Stopping after BUILD without VERIFY and REVIEW is a workflow violation. Task NOT done until REVIEW completes.**

## Integration with Workflow

```
/plan -> /spec -> /build -> /verify -> /dc-review
                              ↑ YOU ARE HERE    ↑ MUST REACH HERE
```

BUILD is step 3 of 5. MUST continue through VERIFY (step 4) and REVIEW (step 5).
