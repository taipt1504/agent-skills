# SDD Workflow Architecture Review

> **Reviewer**: workflow-reviewer | **Grade**: B (Design A, Enforcement C)
> **Scope**: Plugin code only. `docs/` excluded (document storage, not plugin structure).

---

## 1. Workflow Overview

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
  │       │        │            │         │
  │       │        │            │         └── reviewer agent (7 checklists)
  │       │        │            └── pipeline (4 modes)
  │       │        └── N implementer subagents (1 per task)
  │       └── spec-writer agent (5 templates)
  └── planner agent (architecture + task decomposition)
```

**Skip condition**: ALL must be true: ≤5 lines, 1 file, no new behavior, no arch impact, no schema change

---

## 2. Phase Implementation Scores

| Phase | Command | Agent | Quality | Key Strength |
|-------|---------|-------|---------|-------------|
| PLAN | /plan | planner | 5/5 | Spec Handoff section bridges to SPEC |
| SPEC | /spec | spec-writer | 5/5 | 7-step process, 5 templates, test mapping |
| BUILD | /build | implementer | 4/5 | Subagent-per-task isolation, TDD cycle |
| VERIFY | /verify | (pipeline) | 4/5 | 4 modes (quick/pre-commit/full/gate) |
| REVIEW | /review | reviewer | 5/5 | Conditional checklists, spec adherence check |

---

## 3. Critical Finding: No Persistent Workflow State

**The entire workflow state exists only in conversation context.**

- No file tracks which phase is active
- No file records plan/spec approval status
- No file records BUILD task completion progress
- Compaction destroys all workflow context
- Session boundaries reset workflow awareness

### Impact
- Agent loses phase awareness after compaction
- Agent can't resume mid-BUILD after session restart
- No deterministic verification that plan/spec was approved

### Recommended Fix
```json
// .claude/workflow-state.json
{
  "phase": "BUILD",
  "plan_approved": true,
  "plan_file": ".claude/plans/feature-x.md",
  "spec_approved": true,
  "spec_file": ".claude/specs/feature-x.md",
  "build_tasks": {
    "1": "completed",
    "2": "completed",
    "3": "in_progress",
    "4": "pending"
  }
}
```

---

## 4. Critical Finding: Advisory-Only Enforcement

| Hard Block | Mechanism | Deterministic? |
|-----------|----------|----------------|
| No code without plan | Prompt instruction | **NO** |
| No code without spec | Prompt instruction | **NO** |
| No tests = BLOCK | Post-hoc (/verify) | Partial |
| No .block() | Post-hoc (/verify, /review) | Partial |
| No git commit | Prompt instruction | **NO** |

**quality-gate.sh fires on every Java file edit** but only checks:
- Compilation errors
- Debug statements (System.out, printStackTrace, @Disabled)

**Missing from quality-gate.sh** (easy additions):
- `.block()` detection
- `@Autowired` field injection detection
- `SELECT *` detection
- git commit/push in Bash commands

### Recommended Addition
```bash
# In quality-gate.sh — add after debug check
if grep -n '\.block()' "$FILE" 2>/dev/null | grep -v 'test\|Test'; then
  echo "[QualityGate] CRITICAL: .block() found in $FILE" >&2
fi
if grep -n '@Autowired' "$FILE" 2>/dev/null | grep -v 'constructor'; then
  echo "[QualityGate] WARNING: @Autowired field injection in $FILE" >&2
fi
```

---

## 5. Phase Gating Assessment

### Gates That Work
- `/spec` checks for approved plan → STOP if missing
- `/build` checks for approved spec → STOP if missing
- Skip conditions are conservative (all 5 must be true)

### Gates That Don't Exist
- `/verify` has no prerequisite (can run without BUILD completing)
- `/review` has no prerequisite (can run without /verify)
- `/db-migrate` bypasses SDD entirely (despite schema changes requiring specs)
- `/refactor` bypasses SDD (can do multi-file changes without plan)
- No mid-workflow revision/restart mechanism

---

## 6. Handoff Quality

| Handoff | Mechanism | Structured? | Survives Compaction? |
|---------|-----------|-------------|---------------------|
| PLAN → SPEC | "Spec Handoff" section in planner output | Semi-structured | **NO** |
| SPEC → BUILD | Task decomposition table + scenarios | Structured | **NO** |
| BUILD → VERIFY | Implicit (user runs /verify) | Ad-hoc | N/A |
| VERIFY → REVIEW | Implicit (user runs /review) | Ad-hoc | N/A |

### Strengths
- Planner's "Spec Handoff" explicitly lists task type, components, constraints, NFRs
- Spec's task decomposition with file/test/dependency is directly consumable by BUILD
- Reviewer has "Spec Adherence Check" closing the feedback loop

### Weakness
All handoff data lives in conversation context — not persisted to files. Recommend writing plans to `.claude/plans/` and specs to `.claude/specs/`.

---

## 7. Subagent Isolation in BUILD

### Design
```
For each spec task:
  1. Spawn implementer agent with:
     - Task description + spec scenario
     - Relevant skills (based on file patterns)
     - Prior task summary
  2. Agent runs TDD: RED → GREEN → REFACTOR
  3. 2-stage review: spec compliance → code quality
```

### Strengths
- Fresh context per agent (no cross-task pollution)
- 2-stage review catches issues incrementally
- Blocked tasks escalate to user

### Issues
- Model contradiction (build.md says sonnet, agent says opus)
- No `maxTurns` on implementer (infinite loop risk)
- No worktree isolation for concurrent execution
- "Prior task summary" format is unspecified

---

## 8. Error Handling

| Failure | Handling | Quality |
|---------|----------|---------|
| Plan rejected | User modifies, re-plans | OK |
| Spec rejected | "reject → /plan" or "revise → feedback" | Good |
| Build task fails | 3 attempts → escalate to user | Good |
| Verify fails | Reports PASS/BLOCK verdict | Good |
| Review blocks | Must fix before merge | Good |
| Session ends mid-BUILD | No progress persistence | **Bad** |
| User changes direction | No invalidation protocol | **Bad** |
| Compaction mid-workflow | Phase state lost | **Bad** |

---

## 9. Command Integration

| Command | SDD Phase | Requires Plan? | Requires Spec? | Issue |
|---------|-----------|---------------|---------------|-------|
| /plan | PLAN | — | — | |
| /spec | SPEC | **YES** | — | |
| /build | BUILD | implicit | **YES** | |
| /build-fix | BUILD support | No | No | OK — tactical fix only |
| /verify | VERIFY | No | No | **No prerequisite** |
| /review | REVIEW | No | No | **No prerequisite** |
| /db-migrate | N/A | No | No | **Bypasses SDD** |
| /refactor | N/A | No | No | Large refactors should require plan |
| /e2e | N/A | No | No | **No workflow position** |

---

## Priority Summary

| Priority | Finding |
|----------|---------|
| **Critical** | No persistent workflow state — compaction destroys phase tracking |
| **Critical** | Plan/spec artifacts not persisted to files |
| **High** | Phase gates are advisory-only (no deterministic enforcement) |
| **High** | quality-gate.sh misses .block(), @Autowired, SELECT *, git commit |
| **High** | Model contradiction (build.md vs implementer.md) |
| **High** | /db-migrate bypasses SDD |
| **High** | No mid-workflow revision mechanism |
| **Medium** | /verify and /review have no prerequisite checks |
| **Medium** | /e2e has no workflow position |
| **Medium** | Prior task summary format unspecified |
| **Low** | No automated rollback at BUILD start |
