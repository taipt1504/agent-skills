---
name: development-workflow
description: 5-layer adaptive workflow — Triage routes to lane, lane decides which gates run. All non-trivial tasks complete REVIEW before "done".
globs: "*"
applicability:
  always: true
---

# Development Workflow

## 5-Layer Adaptive Flow

```
REQ → BOOT → PREFLIGHT0 → TRIAGE
                            ├── trivial → EXECUTE (light) → REVIEW (S2) → COMMIT
                            └── standard / high-stakes →
                                ALIGN → PREFLIGHT1 → BRAINSTORM →
                                PREFLIGHT2 → PLAN → PREFLIGHT3 → SPEC →
                                PREFLIGHT4 → EXECUTE (subagent per slice) →
                                PREFLIGHT5 → REVIEW (S1 + S2) → LEARN → COMMIT
```

Pre-flight 0..5 = 1% rule. Mandatory before every gate. See `skills/preflight/SKILL.md`.

## Gate / command / agent matrix

| Gate | Command | Skill / Agent |
|---|---|---|
| Triage | `/triage` | `skills/triage/SKILL.md` |
| Align | `/align` | `skills/align/SKILL.md` |
| Brainstorm | `/brainstorm` | `skills/brainstorm/SKILL.md` |
| Plan | `/plan` | `agents/planner.md` |
| Spec | `/spec` | `agents/spec-writer.md` |
| Execute (BUILD phase) | `/build` | `agents/slice-executor.md` (formerly implementer) |
| Verify | `/verify` | hook-driven (no agent) |
| Review S1 (spec compliance) | `/dc-review` Stage 1 | `agents/spec-compliance-reviewer.md` |
| Review S2 (quality) | `/dc-review` Stage 2 | `agents/code-quality-reviewer.md` |
| Learn | `/meta evolve` | `commands/meta.md §"/meta evolve" + Claude native /memory` |

## Lane behavior

| Lane | Skipped | Required |
|---|---|---|
| Trivial | Align, Brainstorm, Plan, Spec, Review S1 | Pre-flight (light), Execute, Verify (compile+format), Review S2, Commit |
| Standard | Brainstorm (if obvious solution) | All other gates |
| High-stakes | none | All gates + ADR + worktree |

See `rules/common/lanes.md`.

## Completion rule

**Task NOT complete until REVIEW returns verdict.** After BUILD:
1. Run `/verify full` (auto if `config.workflow.autoVerify=true`)
2. After VERIFY passes, run `/dc-review`
3. Task done only after REVIEW (S1 pass → S2 verdict)

Stopping after PLAN / SPEC / BUILD without VERIFY + REVIEW = workflow violation.

## Rule loading by project profile

```
Always loaded:           rules/common/* + rules/java/*
Conditional (Summer):    rules/summer/*  (only when io.f8a.summer detected in build.gradle)
```

`scripts/hooks/preflight-discovery.sh` enforces conditional. `rules/summer/*` enumeration is automatic — listed when applicable, omitted otherwise (no manual SKIP justification needed for whole folder).

## Document persistence

Plans + specs MUST be written to files — never conversation-only.


| Artifact | Location | Lane |
|---|---|---|
| Pre-flight artifacts | `.claude/memory/preflight/<gate>-<ts>.md` | All (when gate fires) |
| Align artifact | `.claude/memory/align-artifacts/<date>-<task>.md` | Standard (if vague), High-stakes (always) |
| Brainstorm artifact | `.claude/memory/brainstorm-artifacts/<date>-<task>.md` | Standard (if multi-path), High-stakes (always, ≥3 options) |
| Plan | `.claude/docs/plans/<feature>.md` | Standard, High-stakes |
| Spec | `.claude/docs/specs/<feature>.md` | Standard, High-stakes |
| ADR | `docs/adr/NNNN-<decision>.md` | High-stakes mandatory |
| CONTEXT.md updates | project root | When new vocabulary surfaced |

Conversation-only plans/specs = workflow violation.


## Definition of Done — Runtime Verification (HARD BLOCK)

Workflow completion requires ALL 3:

1. **Workflow done:** Triage → (Align) → (Brainstorm) → Plan → Spec → Build → Verify → Review (S1 PASS + S2 verdict)
2. **Build success:** `./gradlew build` green, coverage ≥ 80%
3. **Service boots (high-stakes + Summer):** `./gradlew bootRun` starts without exceptions, `/actuator/health` returns 200

**Test pass + service crash = INCOMPLETE.** Common causes:
- Bean cycle / missing bean / `BeanCurrentlyInCreationException`
- Config parse fail
- Flyway checksum mismatch
- Schema mismatch
- Kafka topic mismatch

### Verification protocol (high-stakes + Summer)

After VERIFY pass:


```bash
# 1. Build
./gradlew clean build -x integrationTest

# 2. Boot check
./gradlew bootRun &
BOOTRUN_PID=$!
sleep 30
curl -fsS http://localhost:8080/actuator/health | jq .status
# Expected: "UP"
kill $BOOTRUN_PID

# 3. Catch startup exceptions
./gradlew bootRun 2>&1 | grep -E "BeanCurrentlyInCreationException|FATAL|UnsatisfiedDependency|FlywayException|ApplicationContextException" \
  && exit 1 || echo "boot OK"
```

### BUILD checklist

- [ ] `./gradlew bootRun` (with docker-compose up postgres redis kafka)
- [ ] `Started <AppName> in X seconds` in logs
- [ ] No `BeanCurrentlyInCreationException` / `UnsatisfiedDependencyException`
- [ ] No `FlywayException`
- [ ] `curl /actuator/health` → `{"status":"UP"}`
- [ ] Smoke test 1 endpoint
- [ ] Documented in BUILD checkpoint: "service boot OK; smoke test <endpoint>: PASS"

### Enforcement

- BUILD reviewer rejects if checkpoint lacks "service boot verified"
- PR template: "Service runs successfully? (Y/N + log proof)"

Trivial lane skips runtime verification (no behavior change, no boot risk). Standard lane applies if dependency / config / Flyway change in scope. High-stakes: always required.

## Related

- `rules/common/lanes.md` — lane definitions
- `rules/common/spec-driven.md` — spec mandate by lane
- `rules/common/skill-enforcement.md` — 1% rule
- `rules/java/migration.md` — Flyway checksum compliance
- `skills/bootstrap/references/workflow-details.md` — state machine + subagent dispatch + circuit breakers
