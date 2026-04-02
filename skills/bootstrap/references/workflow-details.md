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
