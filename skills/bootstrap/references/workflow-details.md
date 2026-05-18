# Workflow Details — Reference

Subagent dispatch protocol, commands reference, workflow state machine, auto-invoke chain, circuit breakers, lane-aware execution. Updated for 5-layer adaptive workflow (v4.0).

---

## Subagent Dispatch (Execute gate)

Each slice from approved Plan → spawn 1 separate `slice-executor` Agent. Subagent context contains:

1. **Slice description** (from `.claude/docs/plans/<feature>.md`)
2. **Slice spec** (from `.claude/docs/specs/<feature>.md`)
3. **Pre-flight 4 artifact** (`.claude/memory/preflight/execute-<ts>.md`) — skills + rules + scoring per 1% rule
4. **CONTEXT.md vocabulary** (project domain language)
5. Files this slice will touch (main agent identifies via plan dependency graph)

**Do NOT include:**
- Other slices' specs (irrelevant — pollutes context)
- Full conversation history (noise)
- Unrelated past decisions

**Subagent process:**
1. Re-verify pre-flight items match this slice's needs
2. If new items emerge mid-slice → append to artifact
3. Apply listed skills/rules
4. Cite skill names in commits + result summary
5. Report files changed + tests added + deviations from spec to main agent

After each slice: 2-stage review (spec compliance → quality).

---

## Commands Quick Reference

| Command | Gate / Phase | Lane gate? |
|---|---|---|
| `/triage` | Triage router | All |
| `/align` | Align (grill ambiguity) | Standard (vague), High-stakes (always) |
| `/brainstorm` | Solution exploration | Standard (multi-path), High-stakes (mandatory ≥3) |
| `/plan` | Slice decomposition + dependency graph | Standard, High-stakes |
| `/spec` | Behavioral contracts per slice | Standard (if behavior change), High-stakes (always) |
| `/build` | TDD subagent dispatch | All non-trivial |
| `/verify` | Compile + tests + coverage + security scan | All |
| `/dc-review` | Two-stage review (S1 compliance → S2 quality) | All |
| `/build-fix` | Verify/fix loop after BUILD failure | All |
| `/e2e` | E2E test generation | On-demand |
| `/db-migrate` | DB migration (high-stakes auto-trigger) | High-stakes |
| `/meta refactor` | Dead code cleanup (subcommand) | On-demand |
| `/dc-setup` | Project install | One-shot |
| `/dc-status` | Plugin health check | On-demand |
| `/meta` | Learning + evolution + ADR + improve-architecture | On-demand |

---

## Workflow State Machine

State persisted in `.claude/workflow-state.json` (phase tracking) + `.claude/memory/state/current-triage.json` (lane).

### State files

```json
// .claude/workflow-state.json
{
  "phase": "BUILD",
  "lane": "standard",
  "task": "Add order notification endpoint",
  "startedAt": "2026-05-15T10:00:00Z",
  "phaseHistory": [
    {"phase": "PLAN", "completedAt": "2026-05-15T10:05:00Z"},
    {"phase": "SPEC", "completedAt": "2026-05-15T10:15:00Z"}
  ],
  "decisions": [],
  "artifacts": {
    "preflight": ".claude/memory/preflight/plan-<ts>.md",
    "align": ".claude/memory/align-artifacts/<date>-<task>.md",
    "brainstorm": ".claude/memory/brainstorm-artifacts/<date>-<task>.md",
    "plan": ".claude/docs/plans/<feature>.md",
    "spec": ".claude/docs/specs/<feature>.md"
  },
  "autoTransition": true,
  "retryCount": 0
}

// .claude/memory/state/current-triage.json
{
  "lane": "standard",
  "task_description": "Add order notification endpoint",
  "timestamp": "2026-05-15T09:55:00Z",
  "reasoning": "Feature with bounded scope, single service",
  "user_override": false
}
```

### Field reference

| Field | Description |
|---|---|
| `phase` | Current execution phase: PLAN, PLAN_APPROVED, SPEC, SPEC_APPROVED, BUILD, VERIFY, REVIEW_PENDING, REVIEW, COMPLETE |
| `lane` | Workflow lane from triage: trivial, standard, high-stakes |
| `phaseHistory` | Completed phases with timestamps + verdicts |
| `artifacts` | Paths to gate output documents (pre-flight, align, brainstorm, plan, spec) |
| `autoTransition` | Whether auto-invoke chain is active |
| `retryCount` | VERIFY phase retry counter |

### Phase transitions (post-Triage)

```
TRIAGE → writes lane to current-triage.json
       ├── trivial → /build (skip Align, Brainstorm, Plan, Spec)
       └── standard / high-stakes → /align (if vague or high-stakes)

/align → writes align-artifacts/<date>-<task>.md → /brainstorm (if needed) or /plan

/brainstorm → writes brainstorm-artifacts/<date>-<task>.md (+ docs/adr/NNNN if high-stakes) → /plan

/plan → creates workflow-state.json, phase=PLAN, writes .claude/docs/plans/<feature>.md
       | user approves
       phase=PLAN_APPROVED, PLAN added to phaseHistory
       → remind /spec

/spec → phase=SPEC, writes .claude/docs/specs/<feature>.md
       | user approves
       phase=SPEC_APPROVED, SPEC added to phaseHistory
       → remind /build

/build → phase=BUILD, dispatches one slice-executor subagent per plan slice
       | all slices complete + tests pass
       BUILD added to phaseHistory
       → AUTO /verify full (if config.workflow.autoVerify)

/verify → phase=VERIFY, runs compile + tests + coverage + security scan
       | all green
       VERIFY added to phaseHistory with verdict
       → AUTO /dc-review (if config.workflow.autoReview)
       | checks fail
       retryCount++ → /build-fix → re-verify (up to maxRetryOnFail)

/dc-review → phase=REVIEW
       Stage 1 (spec-compliance-reviewer) → spec compliance binary
       | Stage 1 fail
       returns to BUILD with deltas
       | Stage 1 pass
       Stage 2 (code-quality-reviewer) → quality severity report
       | 0 CRITICAL
       phase=COMPLETE → TASK DONE
```

---

## Auto-Invoke Chain

After BUILD passes, workflow chains automatically:

```
BUILD passes → /verify full → /dc-review → COMPLETE
```

Controlled by `.claude/devco-config.json`:

- `workflow.autoVerify` (default `true`) — auto-invoke `/verify full` after BUILD
- `workflow.autoReview` (default `true`) — auto-invoke `/dc-review` after VERIFY passes

When auto-transition active:
1. Do NOT ask user permission between phases
2. Do NOT stop / wait — proceed immediately
3. Report progress at each transition
4. Only stop if circuit breaker trips or REVIEW returns BLOCK verdict

---

## Lane-Aware Execution

### Trivial lane bypass

`workflow-gate.sh` reads `.claude/memory/state/current-triage.json` first. If `lane=trivial`:
- Allow direct src/main/ writes (no PLAN/SPEC gate enforcement)
- `/verify` runs compile + format only (no security scan, no full suite)
- `/dc-review` runs Stage 2 quality only (no Stage 1 spec compliance)

### Standard lane

Full gate sequence. Brainstorm conditional (skip if single obvious solution).

### High-stakes lane

All gates mandatory. Additional protections:
- `/plan` BLOCKED until brainstorm artifact exists
- ADR auto-generation by `scripts/hooks/auto-adr.sh` at session end if missing
- Worktree dispatch via `skills/bootstrap/SKILL.md §"Worktree per slice"` (planned)
- `/verify` adds dependency CVE scan + security review

---

## Circuit Breakers

Safety mechanisms preventing infinite loops + wasted compute.

### No-progress detection

- Track normalized error messages across consecutive attempts
- Same error appears `noProgressThreshold` times (default 3) → escalate to user
- Normalization: strip line numbers, timestamps, variable values

### Max iterations per phase

- Each phase ceiling: `maxIterationsPerPhase` (default 10)
- Exceeding → force exit with state preserved
- Log iteration details for user review

### Max retries on verify failure

- VERIFY failures trigger `/build-fix` + re-verify cycle
- After `maxRetryOnFail` (default 3) failures → force-accept with warning
- Force-accept proceeds to `/dc-review` with unresolved issues flagged

### Context budget

- Monitor context window utilization
- > 95% utilization → force exit immediately
- Preserve workflow state so next session resumes
- Hardcoded — not configurable

### Breaker response protocol

When any breaker trips:
1. Log breaker type + reason to workflow-state.json
2. Preserve all progress + state
3. Present clear summary to user:
   - What was being attempted
   - Why breaker tripped
   - User options (retry, skip, modify approach)

---

## Agent Team Support

### When to use teams

- Plan has ≥2 independent slices (per dependency graph)
- Each slice modifies different files
- Combined change > 50 lines
- `team.enabled = true` in devco-config.json
- `.claude/project-profile.json` exists (stack detection completed)

### Team workflow

1. Team lead (orchestrator) reads approved plan + dependency graph
2. Spawns `slice-executor` agents — one per independent slice (max `config.team.maxTeammates`)
3. Each slice-executor works scope-locked per slice files
4. After all slices complete → spawn parallel reviewers (S1 spec compliance + S2 quality)
5. Aggregate results, report to user

### Cost control

- Default execution model: sonnet (fast, cheap)
- Opus reserved for: plan, spec, brainstorm, architecture decisions
- Override via devco-config.json: `team.roles.<role>.model`
- Max teammates capped: `config.team.maxTeammates` (default 4)
- `team.costControl.preferFastModel` (default true) — prefer sonnet for execution
- `team.costControl.useOpusOnlyFor` (default `["plan", "spec", "brainstorm", "architecture"]`)

### Teammate scope lock

Each slice-executor assigned specific files from plan's dependency graph.
- MUST NOT modify files outside assigned slice scope
- If shared file needed → message orchestrator
- Scope violations flagged during S1 review

---

## Multi-Agent Modes

Two modes for parallel execution. Configured via `team.mode` in devco-config.json:

### Mode 1: Subagent (default, stable) — `team.mode: "subagent"`

Independent agents with **worktree isolation**. Each agent gets isolated git worktree copy. Best for: independent slices that don't coordinate.

```
Agent({
  description: "Execute slice {N}: {slice title}",
  prompt: "Execute slice {N} from plan at {artifacts.plan}. Pre-flight at {artifacts.preflight}. Spec at {artifacts.spec}. TDD: RED→GREEN→REFACTOR. No .block(), no git commit.",
  subagent_type: "slice-executor",
  model: "{team.roles.implementer.model}",
  isolation: "worktree",
  run_in_background: true
})
```

**Key properties:**
- `isolation: "worktree"` — safe parallel file edits (each agent has own git worktree)
- `run_in_background: true` — concurrent
- Agents report to parent only — no inter-agent communication
- After completion: merge worktree changes → `/verify full` → `/dc-review`

### Mode 2: Agent Teams (experimental) — `team.mode: "team"`

Coordinated agents with **shared task list** + **inter-agent messaging**. Best for: interdependent slices needing interface negotiation. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

```
TeamCreate({ team_name: "build-{feature}", description: "Execute plan for {feature}" })
TaskCreate({ subject: "{slice title}", description: "{slice description}" })
Agent({
  description: "Execute slice: {slice title}",
  prompt: "You are a teammate. Read task via TaskGet. Pre-flight: {preflight path}. TDD. Mark done via TaskUpdate.",
  team_name: "build-{feature}",
  name: "slice-{N}",
  subagent_type: "slice-executor",
  model: "{team.roles.implementer.model}",
  run_in_background: true
})
```

**Key properties:**
- Shared working directory — partition files by ownership (no worktree)
- Teammates can `SendMessage` for interface negotiation
- Shared `TaskList` — teammates self-claim available slices
- After completion: `/verify full` → `/dc-review` → `TeamDelete`

### Mode selection

| Scenario | Use | Why |
|---|---|---|
| Independent slices (separate packages/files) | `subagent` | Worktree prevents conflicts |
| Shared domain model (entity + repo + service across slices) | `team` | Agents negotiate interfaces |
| First time / unsure | `subagent` | Stable default |

### Model routing

| Role | Default | Override |
|---|---|---|
| planner, spec-writer, brainstorm | opus | `team.costControl.useOpusOnlyFor` |
| slice-executor | sonnet | `team.roles.implementer.model` |
| spec-compliance-reviewer | sonnet | `team.roles.reviewer.model` |
| code-quality-reviewer | sonnet | `team.roles.reviewer.model` |
| slice-executor | sonnet | `team.roles.tester.model` |

### After parallel BUILD completes

1. Collect / merge results from all slice-executors
2. Run `/verify full` (covers all slices' work)
3. Run `/dc-review` (Stage 1 then Stage 2, unified)
4. Only after REVIEW returns verdict is task complete

---

## Verify / Fix Loop (Ralph Pattern)

When BUILD or VERIFY fails (gradle test/build returns error):

```
1. Hook detects failure → extracts normalized error signature
2. Error count < noProgressThreshold AND attempt < maxRetryOnFail:
   → Emit: "Run /build-fix with error context, then re-run /verify"
   → Agent executes fix cycle automatically
3. Same error ≥ noProgressThreshold (3):
   → ESCALATE to user — no more auto-retry
4. Total attempts ≥ maxRetryOnFail (3):
   → FORCE_ACCEPT with warning — move to REVIEW with known issues
```

State persists in `.claude/verify-fix-state.json` (disk, not context).
**Never trust self-assessment** — only external verification (tests, compile, lint) determines pass/fail.

---

## BUILD Checkpoint-Resume

During BUILD, every file edit tracked in `.claude/sessions/build-checkpoint.json`. If context resets mid-BUILD:
1. Read checkpoint → see which files were modified
2. Resume from last completed slice instead of restarting
3. Re-read pre-flight artifact to recover skill/rule context

---

## Pre-flight Artifact Handoff

Artifacts pass forward through gates. NOT regenerated — referenced.

| Gate | Reads | Writes |
|---|---|---|
| Triage | (none) | `current-triage.json` + `preflight/initial-<ts>.md` |
| Align | `preflight/initial-<ts>.md`, `CONTEXT.md` | `align-artifacts/<date>-<task>.md` + updates `CONTEXT.md` |
| Brainstorm | `align-artifacts/...`, `preflight/brainstorm-<ts>.md` | `brainstorm-artifacts/<date>-<task>.md` + `docs/adr/NNNN-...md` (high-stakes) |
| Plan | `align-artifacts/...`, `brainstorm-artifacts/...`, `preflight/plan-<ts>.md` | `.claude/docs/plans/<feature>.md` |
| Spec | `align-artifacts/...`, `brainstorm-artifacts/...`, plan, `preflight/spec-<ts>.md` | `.claude/docs/specs/<feature>.md` |
| Execute | plan, spec, `preflight/execute-<ts>.md`, CONTEXT.md | code + tests; updates `build-checkpoint.json` |
| Review S1 | spec, code diff | verdict in `workflow-state.json` |
| Review S2 | code diff, `preflight/review-<ts>.md` | severity report; final verdict |
| Learn | full session | instinct candidates → `.claude/memory/promotion-candidates.md` |

Skip the dead `.claude/sessions/skills-loaded.json` — removed in v4.0 per REFACTOR_PLAN §3.6.1. Skill announcement is the contract, not a file gate.
