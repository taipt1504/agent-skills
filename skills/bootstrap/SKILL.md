---
name: bootstrap
description: >
  Core enforcement engine for devco-agent-skills plugin. Loaded automatically at session start
  via SessionStart hook. Teaches the agent: skill discovery, workflow compliance, project detection,
  and mandatory skill usage. This skill is the foundation — all other skills depend on it.
triggers:
  natural: ["plugin status", "skill discovery", "workflow engine"]
  code: ["SessionStart"]
---

# You Have Skills. Use Them.

You are enhanced with a skill system. Before EVERY action involving code generation, modification, or review, search available skills for a match.

1. **Search** available skills for a match
2. **Announce** which skill you are using: "Using skill: {name} for {reason}"
3. **Load** the skill's SKILL.md if not already loaded
4. If no skill matches: state "No matching skill found, proceeding with general knowledge"

Search available skills when the task involves code generation, modification, or review.

## Workflow Completion Rule (CRITICAL — read before ANY work)

**A task is NOT complete until ALL phases execute.** After BUILD completes:
1. **IMMEDIATELY** run `/verify full` — no asking, no waiting
2. If VERIFY fails → Verify/Fix Loop handles retry automatically
3. After VERIFY passes → **IMMEDIATELY** run `/dc-review`
4. Only after REVIEW verdict is the task done

**You MUST drive the workflow to completion. Never stop at BUILD.**

Config: Read `.claude/devco-config.json` for autoVerify/autoReview settings.

## Project Detection (run once per session)

```
1. Scan build.gradle / build.gradle.kts / pom.xml
2. No build file found? → NOT a Java project → skip all skills
3. Java project detected:
   a. spring-boot-starter-webflux? → Spring WebFlux (Reactive)
   b. spring-boot-starter-web?     → Spring MVC (Servlet)
   c. Neither?                     → Plain Java
4. io.f8a.summer:summer-platform?  → Summer Framework → ALSO load summer skills
   NOT found? → NEVER load/suggest/apply summer patterns
```

## Skill Registry

Match file patterns against loaded skill frontmatter descriptions. Each skill's description contains its triggers. Load the matching skill on demand.

### Summer Skills (ONLY when io.f8a.summer:summer-platform detected)

| Skill | Trigger |
|-------|---------|
| `summer-core` | Always load when summer detected (shared types, version) |
| `summer-rest` | BaseController, RequestHandler, @Handler, WebClientBuilderFactory |
| `summer-data` | AuditService, OutboxService, f8a.audit.*, f8a.outbox.* |
| `summer-security` | @AuthRoles, ReactiveKeycloakClient, f8a.security.* |
| `summer-ratelimit` | RateLimiterService, f8a.rate-limiter.* (v0.2.2+ only) |
| `summer-test` | src/test/ + summer-test dependency |

### Meta Skills (on-demand only)

| Skill | Trigger |
|-------|---------|
| `continuous-learning` | `/meta learn`, `/meta evolve`, `/meta instinct` |

## Workflow Engine — 5 Phases

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

Phase transitions write to `.claude/workflow-state.json`:
- `/plan` → phase:PLAN → user approves → remind `/spec`
- `/spec` → phase:SPEC → user approves → remind `/build`
- `/build` → phase:BUILD → tests pass → AUTO `/verify` (if config.workflow.autoVerify)
  - **BUILD failure** → Verify/Fix Loop activates → `/build-fix` → re-run `/verify` (max 3 retries)
- `/verify` → phase:VERIFY → all green → AUTO `/dc-review` (if config.workflow.autoReview)
- `/dc-review` → phase:REVIEW → 0 CRITICAL → TASK COMPLETE

### workflow-state.json Structure

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

### Phase Rules

| Phase | Entry | Agent | Exit | Auto-Transition |
|-------|-------|-------|------|-----------------|
| **PLAN** | User task or `/plan` | planner | User approves plan | → remind `/spec` |
| **SPEC** | `/spec` after plan approved | spec-writer | User approves spec | → remind `/build` |
| **BUILD** | After spec approved | implementer (1 subagent per task) | All tests pass | → AUTO `/verify full` |
| **VERIFY** | Auto after build or `/verify` | (pipeline) | All checks pass | → AUTO `/dc-review` |
| **REVIEW** | Auto after verify or `/dc-review` | reviewer | No blocking issues | → TASK COMPLETE |

### Skip Condition

IF ALL true: ≤5 lines, 1 file, no new behavior, no arch impact, no schema change
THEN → BUILD directly (skip PLAN + SPEC)

### Hard Blocks (STOP immediately if violated)

- Writing code without approved plan → STOP → `/plan` first
- Writing code without approved spec → STOP → `/spec` first
- No tests → BLOCK — code does not ship without tests
- `.block()` in src/main/ → CRITICAL — fix immediately
- Agent attempts git commit → FORBIDDEN — only user commits
- **Stopping after BUILD without running VERIFY + REVIEW → FORBIDDEN**
- **Plan/Spec without document file → FORBIDDEN** — plans MUST be written to `.claude/docs/plans/`, specs to `.claude/docs/specs/`

### Circuit Breakers (Non-Negotiable)

| Component | Mechanism | Default |
|-----------|-----------|---------|
| No-progress | Same normalized error 3 consecutive times → escalate to user | `noProgressThreshold: 3` |
| Max iterations | Absolute ceiling per phase → force exit | `maxIterationsPerPhase: 10` |
| Max retries | Verify failures before force-accept with warning | `maxRetryOnFail: 3` |
| Context budget | >95% context utilization → force exit | Hardcoded |

When a circuit breaker trips: log the reason, preserve state in `workflow-state.json`, escalate to user with full context.

### Verify/Fix Loop (Ralph Pattern)

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

### BUILD Checkpoint-Resume

During BUILD, every file edit is tracked in `.claude/sessions/build-checkpoint.json`.
If context resets mid-BUILD: read checkpoint → see which files were already modified → resume from last completed sub-task instead of restarting.

### Workflow Completion Rule (CRITICAL)

**A task is NOT complete until ALL phases execute.** After BUILD completes:
1. **IMMEDIATELY** run `/verify full` — no asking, no waiting
2. If VERIFY fails → Verify/Fix Loop handles retry automatically
3. After VERIFY passes → **IMMEDIATELY** run `/dc-review`
4. Only after REVIEW verdict is the task done

You MUST drive the workflow to completion. Never stop at BUILD.

### Plugin Configuration

Settings in `.claude/devco-config.json` control workflow behavior.
Default mode: `standard` (requires plan+spec approval, auto-verify, auto-review).
See `config/defaults.json` for all defaults. Key workflow settings:

| Setting | Default | Effect |
|---------|---------|--------|
| `workflow.autoVerify` | `true` | Auto-invoke `/verify full` after BUILD |
| `workflow.autoReview` | `true` | Auto-invoke `/dc-review` after VERIFY |
| `workflow.maxRetryOnFail` | `3` | Max VERIFY retries before force-accept |
| `workflow.maxIterationsPerPhase` | `10` | Absolute ceiling per phase |
| `workflow.noProgressThreshold` | `3` | Same error N times → escalate |

## Agent Team Support

Main agent = Team Lead — orchestrates, never implements. PLAN + SPEC always solo.

**Spawn conditions** (ALL must be true): `team.enabled`, `project-profile.json` exists, phase = BUILD, spec has ≥2 independent tasks, total change >50 lines, under `maxTeammates`.

**Model routing**: planner/spec-writer → opus. implementer/reviewer/tester/build-fixer → sonnet (overridable via config).

**Teammate rules**: TDD first, announce skill, scope-locked files only, no git commits, report completion.

See [references/workflow-details.md](references/workflow-details.md) for spawn matrix, model routing, context injection, and agent×skill×command matrix.

## Harness Engineering — Operational Awareness

### Observability (automatic)

Every tool call is traced to `.claude/sessions/execution-trace.jsonl` (JSONL format).
Session metrics aggregate in `.claude/sessions/session-metrics.json`: tool call distribution, skill usage, phase timing, quality gate violations.
Use `/dc-status --metrics` to view current session telemetry.

### Context Budget (automatic)

compact-advisor.sh estimates token usage from known sources (bootstrap + skills + rules + conversation).
Warnings at 70% / 85% / 95% of budget. Act on warnings promptly — context rot degrades all phases.

### Auto-Extract Learning

On session end, if >20 tool calls AND >3 file changes, a signal file is written to `.claude/instincts/personal/.auto-extract-pending.json`. On next session start, consider running `/meta learn extract` to capture patterns from the productive session.

## Skill Loading Protocol

```
Session start → load ONLY: bootstrap (this file)
               + summer-core (if io.f8a.summer detected)
On-demand    → load when touching relevant files:
  1. Detect which files are being modified
  2. Match file patterns → skill from registry above
  3. Load that skill's SKILL.md (≤800 tokens each)
  4. Load references/*.md ONLY when deep detail needed
```
