# Trivial Lane Walkthrough — Fix Typo in Error Message

End-to-end example. Time-to-edit: ~30 seconds. Time-to-commit-ready: ~2 minutes.

## Setup

Project: any Java/Spring repo with this plugin installed.
Branch: feature branch, clean.

## User input

```
> Fix typo in src/main/java/com/example/OrderController.java line 42:
> error message says "Ordr not found" should be "Order not found"
```

## What happens

### 1. SessionStart hook

`session-init.sh` fires. Loads project profile, CONTEXT.md if exists, recent ADRs.

```
[session-init] project: example-order-service
[session-init] springType: WebFlux
[session-init] Skills (likely): coding-standards, testing-workflow, spring-webflux-patterns
[session-init] No active triage — awaiting task description
```

### 2. Triage

Task description detected. `/triage` auto-fires.

```
## Triage decision
**Lane:** Trivial
**Reasoning:** 1 line, no behavior change, single file, no new dep.
**Next gate:** Execute (direct, no subagent dispatch)
**Skipped gates:** Align, Brainstorm, Plan, Spec, Review Stage 1
**Override:** "treat as standard" if you want full workflow
```

State written to `.claude/memory/state/current-triage.json`:

```json
{
  "lane": "trivial",
  "task_description": "Fix typo: Ordr → Order in OrderController.java line 42",
  "timestamp": "2026-05-15T14:23:01Z",
  "reasoning": "1 line, no behavior change",
  "user_override": false
}
```

### 3. Pre-flight 0 (light)

Light format. 3 lines.

`.claude/memory/preflight/initial-1747391100.md`:

```markdown
# Pre-flight (trivial): Fix typo in OrderController.java
**Skills applied:** none (trivial fix)
**Rules applied:** rules/common/coding-style.md, rules/java/coding-style.md
**Action:** apply format on save, ensure consistent style
```

### 4. Execute (direct, no subagent)

Orchestrator executes single edit. No dispatch.

```
Agent: I'll fix the typo.

[Edit tool: src/main/java/com/example/OrderController.java]
- throw new OrderNotFoundException("Ordr not found");
+ throw new OrderNotFoundException("Order not found");

Skills loaded: coding-standards
```

### 5. Verify (light)

`workflow-gate.sh` lane-check passes for trivial. `quality-gate.sh` runs:

```bash
./gradlew compileJava    # PASS
./gradlew spotlessCheck  # PASS
```

No full test suite. No coverage check. No security scan.

### 6. Review Stage 2 (quality only)

`/dc-review` orchestrator reads triage = trivial → skip Stage 1 (no spec).

Stage 2 (code-quality-reviewer) runs:

```markdown
## Stage 2: Code Quality Review

**Verdict:** Approve

### Critical issues (0)
### Major issues (0)
### Minor issues (0)

### Observations
- Typo fix is mechanical. Consider adding a unit test that asserts the exact error message string to prevent regression (optional, not blocking).

### Test coverage
- Line coverage: 84% (unchanged)
- Verdict: ≥ 80% ✓
```

### 7. Learn (Stop hook)

`evolution-check.sh`:
```
[evolution-check] 0 candidates ready for promotion
```

`auto-adr.sh` skipped (lane != high-stakes).

`session-save.sh` writes session state.

### 8. Commit (user)

Agent reports task complete. User commits:

```bash
git add src/main/java/com/example/OrderController.java
git commit -m "fix: correct typo in OrderNotFoundException message

Skills applied: coding-standards"
```

## Artifacts produced

| Path | Content |
|---|---|
| `.claude/memory/state/current-triage.json` | lane: trivial |
| `.claude/memory/preflight/initial-1747391100.md` | light format, 3 lines |
| `.claude/memory/state/review-stage2.json` | verdict: Approve, 0 critical |

**No:** plan, spec, brainstorm, align artifacts. No worktree. No ADR.

## Total time

| Step | Time |
|---|---|
| Session boot + triage | ~5s |
| Pre-flight 0 (light) | ~3s |
| Edit + compile + format | ~10s |
| Review Stage 2 | ~10s |
| **Total** | **~30s** |

vs v1 full 5-phase workflow: ~5 minutes for the same fix.

## Override examples

### Force standard lane

```
> /triage standard "Fix typo: Ordr → Order"
```

Output:
```
## Triage decision
**Lane:** Standard (user override)
**user_override:** true
```

Now full workflow runs — Align (skipped, request specific), Plan (1-slice trivial), Spec (typo behavior), Execute, Review S1+S2.

### Upgrade discovered mid-flight

If during Execute the agent realizes the "typo fix" actually requires changing behavior (e.g., callers depend on the string for error parsing — discovered via grep):

```
Agent: Found 3 callers parsing the error message string. This is a public API contract change. Re-triaging.

/triage high-stakes
```

Workflow restarts at Triage with new lane.

## Lessons captured

1. Triage is fast — 5s overhead beats wrong-gate cost
2. Pre-flight light format is mandatory but tiny — 3 lines
3. No spec needed for genuinely no-behavior-change fixes
4. Stage 2 still catches issues (e.g., "consider adding regression test")
5. User commits — agent NEVER commits per CLAUDE.md hard block #9
