---
name: dc-review
description: Two-stage code review orchestrator. Stage 1 (spec compliance, binary) → Stage 2 (code quality, severity-tagged). Stage 2 skipped if Stage 1 fails. Lane-aware (trivial = Stage 2 only).
---

# /dc-review — Two-Stage Review Gate

## First Action (MANDATORY)

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LANE_FILE="$PROJECT_ROOT/.claude/memory/state/current-triage.json"
PREFLIGHT_DIR="$PROJECT_ROOT/.claude/memory/preflight"

# 1. Lane
LANE="standard"
[ -f "$LANE_FILE" ] && LANE=$(grep -o '"lane"[[:space:]]*:[[:space:]]*"[^"]*"' "$LANE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)

# 2. Pre-flight 5 (review-prep) check
if ! /usr/bin/ls "$PREFLIGHT_DIR"/review-*.md 2>/dev/null | grep -q .; then
  echo "WARN: no pre-flight 5 artifact. preflight-gate.sh will produce it."
fi

# 3. Update workflow state
mkdir -p "$PROJECT_ROOT/.claude"
python3 -c "
import json, datetime, os
path = os.environ['PROJECT_ROOT'] + '/.claude/workflow-state.json'
state = {}
if os.path.exists(path):
    with open(path) as f:
        state = json.load(f)
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
state['phase'] = 'REVIEW'
state['lane'] = os.environ.get('LANE', 'standard')
state.setdefault('phaseHistory', [])
already = any(e.get('phase') == 'VERIFY' for e in state['phaseHistory'])
if not already:
    state['phaseHistory'].append({'phase': 'VERIFY', 'completedAt': now, 'verdict': 'PASS'})
with open(path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
print(f'workflow-state.json: phase=REVIEW lane={state[\"lane\"]}')
" 2>/dev/null || echo "workflow-state.json update skipped"
```

## Lane behavior

| Lane | Stage 1 | Stage 2 |
|---|---|---|
| Trivial | SKIP (no spec) | RUN (quality only) |
| Standard | RUN if spec exists | RUN if Stage 1 PASS |
| High-stakes | RUN, mandatory | RUN if Stage 1 PASS, security deep dive |

## Orchestration

### Step 0 — Detect shape

Read `workflow-state.json`:
- Split shape: `artifacts.spec_index` + `artifacts.spec_slice_list` (list of all slice spec paths)
- Single-file shape: `artifacts.spec` (single `.md`)

### Step 1 — Stage 1: Spec Compliance (shape-aware)

If lane != trivial AND spec exists:

**Single-file:** one Stage 1 dispatch covers whole spec.

```
Agent({
  description: "Review S1: spec compliance for {feature_name}",
  subagent_type: "spec-compliance-reviewer",
  model: "sonnet",
  prompt: "Stage 1. Spec at {artifacts.spec}. Map ALL scenarios to tests."
})
```

**Split:** dispatch ONE Stage 1 per slice (parallel — slices are independent for spec compliance):

```
For each slice in artifacts.spec_slice_list:
  Agent({
    description: "Review S1 slice {slice_id}: {slice_title}",
    subagent_type: "spec-compliance-reviewer",
    model: "sonnet",
    prompt: "Stage 1 slice scope. Read spec_slice at {slice path} + spec_index §1 Cross-cutting. Map slice §5 scenarios to tests. Per-slice verdict.",
    run_in_background: true
  })
```

Per-slice verdicts written to `.claude/memory/state/review-stage1-<slice-id>.json`. Aggregate verdict in `.claude/memory/state/review-stage1.json`:

```json
{
  "status": "PASS",  // PASS only if ALL slices PASS; FAIL if ANY slice FAILS
  "per_slice": {
    "01": "PASS",
    "02": "PASS",
    "03": "FAIL"
  }
}
```

- Aggregate PASS → proceed to Step 2
- Aggregate FAIL → STOP. Route back to BUILD with per-slice fix list (failed slices only). Stage 2 does NOT run.

### Step 2 — Stage 2: Code Quality (shape-aware)

Only if Stage 1 passed (or trivial lane):

**Single-file:** one Stage 2 dispatch covers whole diff.

```
Agent({
  description: "Review S2: code quality for {feature_name}",
  subagent_type: "code-quality-reviewer",
  model: "sonnet",
  prompt: "Stage 2. Read pre-flight 5. Apply 5 dimensions. Severity-tag findings."
})
```

**Split:** scope per-slice diff (each slice's affected files from plan §2). Dispatch per slice in parallel:

```
For each slice in artifacts.spec_slice_list:
  Agent({
    description: "Review S2 slice {slice_id}: {slice_title}",
    subagent_type: "code-quality-reviewer",
    model: "sonnet",
    prompt: "Stage 2 slice scope. Files: {slice plan §2 file list}. Apply 5 dimensions. Severity-tag findings.",
    run_in_background: true
  })
```

Per-slice verdicts: `.claude/memory/state/review-stage2-<slice-id>.json`. Aggregate: `.claude/memory/state/review-stage2.json`:

```json
{
  "verdict": "Approve",  // Block if ANY slice has Critical; Approve with caveats if any Major; Approve if all clean
  "per_slice": {
    "01": {"verdict": "Approve", "critical": 0, "major": 0, "minor": 1},
    "02": {"verdict": "Approve with caveats", "critical": 0, "major": 2, "minor": 3}
  }
}
```

### Step 3 — Aggregate verdict

| Stage 1 | Stage 2 | Workflow phase |
|---|---|---|
| FAIL | — | BUILD (re-execute fix list) |
| PASS | Block (≥1 Critical) | BUILD (fix critical issues) |
| PASS | Approve with caveats | COMPLETE (note caveats) |
| PASS | Approve | COMPLETE |
| SKIP (trivial) | Block | BUILD (fix critical) |
| SKIP (trivial) | Approve | COMPLETE |

Write final to workflow-state.json `phase`. User commits (per CLAUDE.md hard block #9 — agent never commits).

## Usage

```
/dc-review              -> two-stage review (lane-aware)
/dc-review stage1       -> Stage 1 only (debug)
/dc-review stage2       -> Stage 2 only (debug — bypass Stage 1)
/dc-review <file>       -> review specific file (Stage 2 scope only)
```

## Prerequisites

- `/verify` must have passed before `/dc-review` (compile + tests green)
- Pre-flight 5 artifact at `.claude/memory/preflight/review-<ts>.md`
- For Stage 1: spec at `artifacts.spec`

## Usage

```
/dc-review              -> review all uncommitted changes
/dc-review security     -> security-focused review only
/dc-review performance  -> performance-focused review only
/dc-review <file>       -> review specific file
```

## Prerequisites

- Run `/verify` before `/dc-review` — catch compile and test failures first
- Feature implementation: ensure approved spec is available for adherence checking

## Subagent Context (pass to spawned agent)

Include in **reviewer** agent prompt:

- **Phase**: REVIEW phase of SDD (PLAN → SPEC → BUILD → VERIFY → REVIEW)
- **Skill protocol**: Load `devco-agent-skills:bootstrap` first. Before every file op, load matching skill and announce it.
- **Summer check**: Scan `build.gradle` for `io.f8a.summer` → if found, load `devco-agent-skills:summer-core` first
- **Hard blocks**: No `.block()` in src/main/. No git commit/push. No code without approved plan+spec.
- **Classify first**: For each changed file, classify type, then load matching skill BEFORE checklist (e.g., `devco-agent-skills:spring-security` for security files, `devco-agent-skills:database-patterns` for repositories)
- **Suggested skill**: Dynamic — determined per file classification

## Instructions

1. Get changed files:

```bash
git diff --name-only HEAD -- '*.java' '*.yml' '*.yaml' '*.gradle'
```

2. For each changed file, run all review aspects:

### Security Issues (CRITICAL)

- Hardcoded credentials, API keys, tokens, DB passwords
- SQL injection vulnerabilities (string concatenation in queries)
- Missing input validation (`@Valid`, Bean Validation)
- Insecure dependencies (run `./gradlew dependencyCheckAnalyze`)
- Secrets in configuration files
- Missing `@PreAuthorize` on sensitive endpoints

### Reactive Issues (CRITICAL -- WebFlux)

- `.block()`, `.blockFirst()`, `.blockLast()` calls
- `Thread.sleep()` in reactive chains
- `.subscribe()` inside reactive pipelines (fire-and-forget)
- Missing error handling (no `onErrorResume`/`onErrorMap`)

### Performance Issues (HIGH)

- N+1 query patterns (findAll in loops, missing @EntityGraph)
- Missing connection pool configuration
- Unbounded collections without pagination
- Missing caching for repeated expensive calls
- Missing timeouts on WebClient/external service calls

### Code Quality (HIGH)

- Methods > 50 lines
- Classes > 800 lines
- Nesting depth > 4 levels
- Missing error handling
- `System.out.println` or `printStackTrace` statements
- TODO/FIXME comments without tickets
- Missing Javadoc for public APIs
- Field injection (`@Autowired` on fields)

### Best Practices (MEDIUM)

- Mutation patterns (use immutable builders instead)
- Missing tests for new code
- Magic numbers without constants
- Circular dependencies

3. Generate report with:
    - Severity: CRITICAL, HIGH, MEDIUM, LOW
    - File location and line numbers
    - Issue description
    - Suggested fix with code example

4. Block commit if CRITICAL or HIGH issues found

## Output Format

```
CODE REVIEW REPORT
==================
Files Reviewed: X

CRITICAL (Must Fix)
-------------------
[CRITICAL] SQL Injection
File: OrderRepository.java:45
Issue: String concatenation in SQL query
Fix: Use parameterized query with .bind()

[CRITICAL] Blocking call in reactive chain
File: OrderService.java:78
Issue: .block() used in WebFlux service
Fix: Return Mono/Flux, compose with flatMap

HIGH (Should Fix)
-----------------
[HIGH] Field injection
File: UserService.java:15
Issue: @Autowired on field
Fix: Use constructor injection with @RequiredArgsConstructor

[HIGH] Missing error handling
File: PaymentService.java:42
Issue: No onErrorResume in reactive chain
Fix: Add error handling for downstream failures

MEDIUM (Consider)
-----------------
[MEDIUM] Method too long
File: OrderService.java:100
Issue: Method is 67 lines (limit: 50)
Fix: Extract helper methods

VERDICT: [APPROVE / BLOCK]
```

## Two-Stage Review Orchestration

### Stage 1: Spec Compliance Review

1. Read approved spec from `.claude/docs/specs/`
2. Read git diff (baseline SHA from `workflow-state.json` → current SHA)
3. Check **every** acceptance criterion in spec is met
4. Check no over-engineering beyond spec scope
5. Check no missing requirements

**Output**: `SPEC_COMPLIANT` or `SPEC_ISSUES: [list]`

**If SPEC_ISSUES**: Send issues back to slice-executor. Do NOT proceed to Stage 2.

### Stage 2: Code Quality Review (only after Stage 1 passes)

1. Run full code quality review (all checklists: Security, Reactive, Performance, Code Quality, Best Practices)
2. Spring-specific checks from CLAUDE.md NEVER rules
3. Categorize findings: **CRITICAL** / **IMPORTANT** / **MINOR**

### Verdict Logic

| Condition | Verdict | Action |
|-----------|---------|--------|
| 0 CRITICAL issues | **APPROVED** | Task is done |
| IMPORTANT items only (no CRITICAL) | **APPROVED WITH NOTES** | Task done, notes logged |
| ≥1 CRITICAL issue | **REJECTED** | Back to slice-executor with feedback |

### After Review Complete

1. Update `.claude/workflow-state.json`:
   - Add `{"phase": "REVIEW", "completedAt": "{ISO timestamp}", "verdict": "{APPROVED|REJECTED}"}` to `phaseHistory`
   - Set `phase` to `"COMPLETE"` (if approved) or `"BUILD"` (if rejected, for re-implementation)
2. Output final verdict with summary
3. Task is **DONE** (if approved)

## Verdict Rules

- **BLOCK** if any CRITICAL or unresolved HIGH issues
- **APPROVE** with warnings if only MEDIUM/LOW issues
- Never approve code with security vulnerabilities or blocking calls in WebFlux
