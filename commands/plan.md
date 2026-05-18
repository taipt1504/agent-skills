---
name: plan
description: Decompose chosen solution into vertical slices with dependency graph. Reads Align + Brainstorm artifacts. Blocks for high-stakes lane without brainstorm artifact. WAIT for user CONFIRM before any code.
---

# /plan — Slice Decomposition Gate

## First Action (MANDATORY)

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LANE_FILE="$PROJECT_ROOT/.claude/memory/state/current-triage.json"
ALIGN_DIR="$PROJECT_ROOT/.claude/memory/align-artifacts"
BRAINSTORM_DIR="$PROJECT_ROOT/.claude/memory/brainstorm-artifacts"
PREFLIGHT_DIR="$PROJECT_ROOT/.claude/memory/preflight"

# 1. Lane check
LANE="standard"
[ -f "$LANE_FILE" ] && LANE=$(grep -o '"lane"[[:space:]]*:[[:space:]]*"[^"]*"' "$LANE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)

# 2. Trivial bypass
if [ "$LANE" = "trivial" ]; then
  echo "Trivial lane — /plan skipped. Proceed to direct Execute."
  exit 0
fi

# 3. High-stakes brainstorm precondition
if [ "$LANE" = "high-stakes" ]; then
  if ! ls "$BRAINSTORM_DIR"/*.md 2>/dev/null | grep -q .; then
    echo "BLOCKED: high-stakes lane requires brainstorm artifact. Run /brainstorm first."
    exit 2
  fi
fi

# 4. Pre-flight 2 (plan-prep) precondition
if ! ls "$PREFLIGHT_DIR"/plan-*.md 2>/dev/null | grep -q .; then
  echo "WARN: no pre-flight artifact for plan gate. Pre-flight hook will produce it."
fi

# 5. Update workflow-state
mkdir -p "$PROJECT_ROOT/.claude"
python3 -c "
import json, datetime, os
path = os.environ['PROJECT_ROOT'] + '/.claude/workflow-state.json'
state = {}
if os.path.exists(path):
    with open(path) as f:
        state = json.load(f)
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
state['phase'] = 'PLAN'
state.setdefault('startedAt', now)
state.setdefault('phaseHistory', [])
state.setdefault('decisions', [])
state.setdefault('artifacts', {})
state['lane'] = os.environ.get('LANE', 'standard')
state['autoTransition'] = True
state.setdefault('retryCount', 0)
with open(path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
print(f'workflow-state.json: phase=PLAN lane={state[\"lane\"]}')
" 2>/dev/null || echo "workflow-state.json update skipped"
```

Then:
1. Load `.claude/memory/align-artifacts/<latest>.md` (requirements + assumptions)
2. Load `.claude/memory/brainstorm-artifacts/<latest>.md` (chosen solution + rejected alternatives)
3. Load `.claude/memory/preflight/plan-<latest>.md` (applicable skills + rules)
4. CONTEXT.md vocabulary
5. **Decide slice count** — threshold rule (HARD BLOCK):
   - ≤2 slices → use `templates/PLAN_TEMPLATE.md` (single-file at `.claude/docs/plans/<feature>.md`)
   - 3+ slices → use `templates/PLAN_INDEX_TEMPLATE.md` + `templates/PLAN_SLICE_TEMPLATE.md` (split at `.claude/docs/plans/<feature>/`)
6. Load matching template(s). Copy structure verbatim. Fill from Align + Brainstorm.
7. Split shape: write `index.md` + one `slices/<NN>-<slug>.md` per slice. IDs zero-padded (`01`, `02`). Slug = kebab-case of slice title.
8. Validate before user approval:
   - Single-file: `bash scripts/ci/validate-plan-spec-templates.sh --plan .claude/docs/plans/<feature>.md`
   - Split: `bash scripts/ci/validate-plan-spec-templates.sh --plan .claude/docs/plans/<feature>/`
9. Update `workflow-state.json` `artifacts`:
   - Single-file: `artifacts.plan = "<path>.md"`
   - Split: `artifacts.plan_index = "<path>/index.md"` (NO `artifacts.plan` for split)

Invokes **planner** agent. Decomposes chosen solution into vertical slices.

## What this command does

1. Read Align artifact (requirements)
2. Read Brainstorm artifact (chosen solution)
3. Decompose into vertical slices (each independently testable)
4. Build dependency graph
5. Risk assessment per slice
6. Wait for user CONFIRM

## When to use

- Starting feature (after Align ± Brainstorm)
- Architectural change (high-stakes lane, after mandatory Brainstorm)
- Refactor touching ≥2 files
- Bug fix needing spec + scenarios

## Skip conditions (= trivial lane)

| Condition | Example |
|---|---|
| ≤5 lines change | Fix null check |
| Single file | One config tweak |
| No behavior change | Rename, reformat |
| No new dep / schema / API | Comment fix |

Triage decides — `/plan` First Action enforces.

## Subagent Context (pass to planner agent)

Include in planner prompt:

- **Phase:** PLAN gate of 5-layer workflow (after Align + Brainstorm, before Spec)
- **Pre-flight artifact:** `.claude/memory/preflight/plan-<latest>.md` (skills + rules to apply)
- **Align input:** `.claude/memory/align-artifacts/<latest>.md` (requirements + assumptions)
- **Brainstorm input:** `.claude/memory/brainstorm-artifacts/<latest>.md` (chosen solution, rejected alternatives, ADR if high-stakes)
- **Skill protocol:** Bootstrap auto-loaded. Announce skills used. Pre-flight enumerates ALL skills/rules per 1% rule.
- **Summer check:** Scan `build.gradle` for `io.f8a.summer` → if found, also load `summer-core`
- **Hard blocks:** No `.block()` in reactive src/main/. No commit/push. No code without approved plan+spec.
- **No code writes in PLAN gate** — produce plan document only.
- **Output:** vertical slices + dependency graph + risk register (see `agents/planner.md`)
- **Multi-service:** task spans services → run Cross-Service Context Protocol first; gather repo paths from user; read related CLAUDE.md + memory/; never glob/grep related service trees
- **R5 hard block:** NEVER modify related service repos. NEVER find/glob/grep their source trees.

## How it works

Planner agent:

1. **Read Align + Brainstorm artifacts** — already-agreed requirements + chosen solution
2. **Decompose into vertical slices** — each independently testable (2-5 min each)
3. **Build dependency graph** — slice X blocks slice Y means Y waits
4. **Identify risk per slice** — flag high-risk slices (auth, persistence, perf-critical)
5. **Order slices** — dependencies first, high-risk early
6. **Estimate complexity** per slice (S/M/L)
7. **Present plan** + WAIT for user CONFIRM

## Example Usage

```
User: /plan Add order notification when payment is processed

Agent (planner):
# Implementation Plan: Order Notification on Payment Processed

## Requirements Restatement
- Publish a domain event when payment is processed for an order
- Persist notifications to PostgreSQL via R2DBC
- Expose GET /api/notifications/{userId} with pagination
- Consume payment events from Kafka reactively

## Implementation Phases

### Phase 1: Domain Events
- Create `PaymentProcessedEvent` record in domain/event/
- Create `OrderNotification` entity in notification/domain/
- Define `NotificationRepository` port (interface) in domain layer

### Phase 2: Notification Service
- Create `NotificationService` in notification/application/
- Implement reactive Kafka consumer in infrastructure layer
- Implement `R2dbcNotificationRepository` adapter
- Wire R2DBC schema migration via Flyway

### Phase 3: REST Endpoint
- Create `NotificationController` in notification/interfaces/
- Implement GET /api/notifications/{userId} returning Flux<NotificationDto>
- Add @Valid request parameter validation

### Phase 4: Integration Tests
- Testcontainers setup: PostgreSQL + Kafka
- NotificationServiceIntegrationTest using StepVerifier
- Contract test for GET endpoint with WebTestClient

## Dependencies
- Spring Kafka (reactive consumer)
- R2DBC PostgreSQL driver
- Flyway for schema migration
- Testcontainers (PostgreSQL + Kafka)

## Risks
- HIGH: Kafka consumer offset management -- ensure idempotent processing
- MEDIUM: R2DBC connection pool sizing under load
- MEDIUM: Notification backlog if consumer falls behind
- LOW: Pagination cursor design for high-volume users

## Estimated Complexity: MEDIUM

**WAITING FOR CONFIRMATION**: Proceed with this plan? (yes/no/modify)
```

## Document Persistence (MANDATORY)

Plan MUST be written to file — not just presented in conversation:

- **Location**: `.claude/docs/plans/{feature-name}.md` (matches plan filename)
- **On draft**: Written when first presented
- **On revision**: Same file updated with revision history
- **On approval**: `status: approved` updated in frontmatter

Spec-writer reads this file next phase. No file = workflow breaks.

## Approval Protocol

**CRITICAL**: Planner agent will NOT write any code until explicit confirm ("yes", "proceed", or similar).

Modify responses:
- "modify: [changes]" → plan updated with revision history
- "different approach: [alternative]" → plan rewritten
- "skip phase 2 and do phase 3 first" → plan adjusted

## Workflow State Tracking

On run, create or update `.claude/workflow-state.json`:

```json
{
  "phase": "PLAN",
  "task": "{task description from user}",
  "startedAt": "{ISO timestamp}",
  "phaseHistory": [],
  "decisions": [],
  "artifacts": {},
  "autoTransition": true,
  "retryCount": 0
}
```

On user **approval**:
1. Update `workflow-state.json`:
   - Add `{"phase": "PLAN", "completedAt": "{ISO timestamp}"}` to `phaseHistory`
   - Set `phase` to `"PLAN_APPROVED"`
   - **Set `artifacts.plan`** to plan file path (e.g., `".claude/docs/plans/order-notification.md"`)
   - Multi-service plan (contains `## Service Impact Map`): **set `artifacts.spec_count`** to service count
2. Output: **"Plan approved and saved to: `.claude/docs/plans/{feature-name}.md`"**
3. Output: **"Run `/spec` to define behavioral contracts — it will read from this plan file."**
4. Multi-service: Output: **"Multi-service plan: {N} specs will be generated by `/spec` — one per service."**

**CRITICAL**: `artifacts.plan` in workflow-state.json is how `/spec` finds the correct plan.

## After Planning

- Run `/spec` to define behavioral contracts (reads from `.claude/docs/plans/`)
- Run `/build` to start TDD implementation cycle
- Use `/build-fix` if build errors occur during implementation
