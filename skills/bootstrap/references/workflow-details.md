# Workflow Details Reference

Subagent isolation protocol, commands quick reference, workflow state machine, auto-invoke chain, and circuit breakers.

---

## Subagent Isolation (BUILD phase)

Each task from the approved spec — spawn 1 separate Agent (implementer) with:
- Task description + relevant spec scenario
- Loaded skills matching files being touched
- Summary of prior completed tasks (NOT full context)

Execute continuously per task. If blocked — ask user. After each task — 2-stage review: spec compliance first, then code quality.

---

## Commands Quick Reference

| Command | Phase |
|---------|-------|
| `/plan` | Start planning |
| `/spec` | Define contracts |
| `/build` | TDD cycle |
| `/verify` | Run verification pipeline |
| `/dc-review` | Multi-aspect code review |
| `/build-fix` | Fix compilation errors |
| `/e2e` | E2E test generation |
| `/db-migrate` | Database migration |
| `/refactor` | Dead code cleanup |
| `/dc-setup` | Project install |
| `/dc-status` | Plugin health check |
| `/meta` | Learning and evolution |

---

## Workflow State Machine

The workflow state is persisted in `.claude/workflow-state.json` across the entire lifecycle of a task.

### State File Structure

```json
{
  "phase": "BUILD",
  "task": "Add order notification endpoint",
  "startedAt": "2026-04-01T10:00:00Z",
  "phaseHistory": [
    {"phase": "PLAN", "completedAt": "2026-04-01T10:05:00Z"},
    {"phase": "SPEC", "completedAt": "2026-04-01T10:15:00Z"}
  ],
  "decisions": [],
  "autoTransition": true,
  "retryCount": 0
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `phase` | string | Current active phase: `PLAN`, `PLAN_APPROVED`, `SPEC`, `SPEC_APPROVED`, `BUILD`, `VERIFY`, `REVIEW`, `COMPLETE` |
| `task` | string | User's original task description |
| `startedAt` | ISO 8601 | When the workflow was initiated |
| `phaseHistory` | array | Completed phases with timestamps and optional verdicts |
| `decisions` | array | Key decisions made during the workflow |
| `autoTransition` | boolean | Whether auto-invoke chain is active |
| `retryCount` | number | Current retry count for VERIFY phase failures |

### Phase Transitions

```
/plan creates workflow-state.json
  phase: "PLAN"
  | user approves
  phase: "PLAN_APPROVED", PLAN added to phaseHistory
  -> remind user to run /spec

/spec reads workflow-state.json
  phase: "SPEC", PLAN in phaseHistory
  | user approves
  phase: "SPEC_APPROVED", SPEC added to phaseHistory
  -> remind user to run /build

/build reads workflow-state.json
  phase: "BUILD", SPEC in phaseHistory
  | all tests pass
  BUILD added to phaseHistory
  -> AUTO /verify full (if config.workflow.autoVerify = true)

/verify reads workflow-state.json
  phase: "VERIFY", BUILD in phaseHistory
  | all checks pass
  VERIFY added to phaseHistory with verdict
  -> AUTO /dc-review (if config.workflow.autoReview = true)
  | checks fail
  retryCount++ -> build-fixer -> re-verify (up to maxRetryOnFail)

/dc-review reads workflow-state.json
  phase: "REVIEW", VERIFY in phaseHistory
  | 0 CRITICAL issues
  phase: "COMPLETE"
  -> TASK DONE
```

---

## Auto-Invoke Chain

After BUILD completes with passing tests, the workflow automatically chains:

```
BUILD passes -> /verify full -> /dc-review -> COMPLETE
```

This chain is controlled by config settings:
- `config.workflow.autoVerify` (default: `true`) — auto-invoke `/verify full` after BUILD
- `config.workflow.autoReview` (default: `true`) — auto-invoke `/dc-review` after VERIFY passes

When auto-transition is active:
1. Do NOT ask the user for permission between phases
2. Do NOT stop or wait — proceed immediately
3. Report progress at each transition
4. Only stop if a circuit breaker trips or REVIEW produces a BLOCK verdict

---

## Circuit Breakers

Safety mechanisms that prevent infinite loops and wasted resources.

### No-Progress Detection

- Track normalized error messages across consecutive attempts
- If the same error appears `noProgressThreshold` times (default: 3) → escalate to user
- Normalization: strip line numbers, timestamps, and variable values before comparison

### Max Iterations Per Phase

- Each phase has a ceiling of `maxIterationsPerPhase` (default: 10) iterations
- Exceeding the ceiling → force exit with state preserved
- Log all iteration details for user review

### Max Retries on Verify Failure

- VERIFY failures trigger build-fixer + re-verify cycle
- After `maxRetryOnFail` (default: 3) failures → force-accept with warning
- Force-accept proceeds to `/dc-review` with all unresolved issues flagged

### Context Budget

- Monitor context window utilization
- >95% utilization → force exit immediately
- Preserve workflow state so the next conversation can resume
- This is hardcoded and cannot be overridden

### Circuit Breaker Response Protocol

When any breaker trips:
1. Log the breaker type and reason to workflow-state.json
2. Preserve all progress and state
3. Present clear summary to user:
   - What was being attempted
   - Why the breaker tripped
   - What options the user has (retry, skip, modify approach)

---

## Agent Team Support

### When to Use Teams

- Spec has ≥2 independent tasks
- Each task modifies different files
- Combined change >50 lines
- `team.enabled = true` in devco-config.json
- `project-profile.json` exists (stack detection completed)

### Team Workflow

1. Team Lead reads approved spec
2. Analyzes task dependencies from spec's task decomposition table
3. Spawns implementer agents (one per independent task, max `config.team.maxTeammates`)
4. Each implementer works in scope-locked isolation
5. After all implementers complete → spawn parallel reviewers (security + quality)
6. Aggregate results and report

### Cost Control

- Default model for execution: sonnet (fast, cheap)
- Opus reserved for: plan, spec, architecture decisions
- Override via devco-config.json: `team.roles.{role}.model`
- Max teammates capped by `config.team.maxTeammates` (default: 4)
- `team.costControl.preferFastModel` (default: true) — prefer sonnet for execution tasks
- `team.costControl.useOpusOnlyFor` (default: ["plan", "spec", "architecture"]) — roles that use opus

### Teammate Scope Lock

Each teammate is assigned specific files from the spec's task decomposition.
A teammate MUST NOT modify files outside its assigned scope.
If a teammate needs to touch a shared file, it must message the team lead.
Scope violations are flagged during the 2-stage review after each task.

---

## Multi-Agent Modes (Subagent vs Team)

Two modes for parallel execution, configured via `team.mode` in `devco-config.json`:

### Mode 1: Subagents (default, stable) — `team.mode: "subagent"`

Independent agents with **worktree isolation**. Each agent gets an isolated copy of the repo. Best for: independent TDD modules that don't need to coordinate with each other.

```
Agent({
  description: "Implement: {task title}",
  prompt: "Implement task from spec at {artifacts.spec}. TDD: RED->GREEN->REFACTOR. Load devco-agent-skills:coding-standards. No .block(), no git commit.",
  model: "{team.roles.implementer.model}",
  isolation: "worktree",
  run_in_background: true
})
```

**Key properties:**
- `isolation: "worktree"` — safe parallel file edits (each agent has own git worktree)
- `run_in_background: true` — concurrent execution
- Agents report results to parent only — no inter-agent communication
- After completion: merge worktree changes -> `/verify full` -> `/dc-review`

### Mode 2: Agent Teams (experimental) — `team.mode: "team"`

Coordinated agents with **shared task list** and **inter-agent messaging**. Best for: interdependent work where agents need to negotiate interfaces. Requires: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.

```
TeamCreate({ team_name: "build-{feature}", description: "TDD for {feature}" })
TaskCreate({ subject: "{task title}", description: "{task description}" })
Agent({
  description: "Implement: {task title}",
  prompt: "You are a teammate. Read task via TaskGet. TDD. Mark done via TaskUpdate.",
  team_name: "build-{feature}",
  name: "impl-{N}",
  model: "{team.roles.implementer.model}",
  run_in_background: true
})
```

**Key properties:**
- Shared working directory — partition files by ownership (no worktree)
- Teammates can `SendMessage` to each other for interface negotiation
- Shared `TaskList` — teammates self-claim available tasks
- After completion: `/verify full` -> `/dc-review` -> `TeamDelete`

### Choosing the Mode

| Scenario | Use | Why |
|----------|-----|-----|
| Independent modules (separate packages/files) | `subagent` | Worktree isolation prevents conflicts |
| Shared domain model (entity + repo + service) | `team` | Agents need to negotiate interfaces |
| First time / unsure | `subagent` | Stable, safe default |

### Model Routing

| Role | Default | Override |
|------|---------|---------|
| planner, spec-writer | opus | `team.costControl.useOpusOnlyFor` |
| implementer | sonnet | `team.roles.implementer.model` |
| reviewer | sonnet | `team.roles.reviewer.model` |
| tester | sonnet | `team.roles.tester.model` |

### After Parallel BUILD Completes

1. Collect/merge results from all agents
2. Run `/verify full` (covers all agents' work)
3. Run `/dc-review` (unified review)
4. Only after REVIEW passes is the task complete

---

## Verify/Fix Loop (Ralph Pattern)

When BUILD or VERIFY fails (gradle test/build returns error):

```
1. Hook detects failure → extracts normalized error signature
2. Error count < noProgressThreshold AND attempt < maxRetryOnFail:
   → Emit: "Run /build-fix with error context, then re-run /verify"
   → Agent executes fix cycle automatically
3. Same error >= noProgressThreshold (3):
   → ESCALATE to user — no more auto-retry
4. Total attempts >= maxRetryOnFail (3):
   → FORCE_ACCEPT with warning — move to REVIEW with known issues
```

State persists in `.claude/verify-fix-state.json` (disk, not context).
**Never trust self-assessment** — only external verification (tests, compile, lint) determines pass/fail.

---

## BUILD Checkpoint-Resume

During BUILD, every file edit is tracked in `.claude/sessions/build-checkpoint.json`. If context resets mid-BUILD: read checkpoint → see which files were already modified → resume from last completed sub-task instead of restarting.
