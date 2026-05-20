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
  prompt: "Stage 2. Read pre-flight 5. Apply 5 dimensions + ALL rules/java/code-review-*.md (CORE/MVC/RX/WFL/XCT/JKS). Severity P0-P4. MANDATORY: cite rule ID per finding (e.g. [P0][CORE-NUM-001], [P0][JKS-POL-002]). Findings without rule ID = invalid."
})
```

**Split:** scope per-slice diff (each slice's affected files from plan §2). Dispatch per slice in parallel:

```
For each slice in artifacts.spec_slice_list:
  Agent({
    description: "Review S2 slice {slice_id}: {slice_title}",
    subagent_type: "code-quality-reviewer",
    model: "sonnet",
    prompt: "Stage 2 slice scope. Files: {slice plan §2 file list}. Apply 5 dimensions + ALL rules/java/code-review-*.md (CORE/MVC/RX/WFL/XCT/JKS). Severity P0-P4 with MANDATORY rule ID per finding.",
    run_in_background: true
  })
```

Per-slice verdicts: `.claude/memory/state/review-stage2-<slice-id>.json`. Aggregate: `.claude/memory/state/review-stage2.json`:

```json
{
  "verdict": "Approve",
  "per_slice": {
    "01": {"verdict": "Approve", "p0": 0, "p1": 0, "p2": 0, "p3": 1, "p4": 0},
    "02": {"verdict": "Approve with caveats", "p0": 0, "p1": 0, "p2": 2, "p3": 3, "p4": 0}
  }
}
```

### Step 3 — Aggregate verdict (P0-P4 per `rules/java/code-review-crosscut.md §7`)

| Stage 1 | Stage 2 | Workflow phase |
|---|---|---|
| FAIL | — | BUILD (re-execute fix list) |
| PASS | Block (≥1 P0, or P1 without ADR) | BUILD (fix blockers) |
| PASS | Approve with caveats (P1 with ADR, or P2 only) | COMPLETE (note caveats + follow-up tickets) |
| PASS | Approve (P3/P4 only) | COMPLETE |
| SKIP (trivial) | Block (P0/P1) | BUILD (fix) |
| SKIP (trivial) | Approve (P2-P4) | COMPLETE |

**Reviewer output validation** — orchestrator MUST verify every finding has format `[<P0-P4>][<RULE-ID>]`:
- Missing severity tag → reject reviewer output, re-dispatch
- Missing rule ID (except P4) → reject reviewer output, re-dispatch
- Unknown rule ID (not in `rules/java/code-review-*.md`) → mark `[NEW-RULE]`, route to evolve-rules

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

2. For each changed file, run all review aspects (rule IDs reference `rules/java/code-review-*.md`):

### Security Issues (P0 default)

- Hardcoded credentials, API keys, tokens, DB passwords → `[P0][MVC-CFG-003]`
- SQL injection (string concat in queries) → `[P0][MVC-REP-*]`
- Missing input validation (`@Valid`, Bean Validation) → `[P0/P1][MVC-VAL-001]`
- Sensitive data in logs (password, OTP, full PAN, CVV, JWT) → `[P0][CORE-LOG-002]`
- Insecure dependencies (`./gradlew dependencyCheckAnalyze`) → `[P0/P1][XCT-DEP-002]`
- Secrets in configuration files → `[P0][MVC-CFG-003]`
- Missing `@PreAuthorize` on sensitive endpoints → `[P0][MVC-SEC-001]` / `[P0][WFL-SEC-001]`
- Jackson polymorphic deserialization with `Id.CLASS` → `[P0][JKS-POL-002]` (RCE — CVE-2017-7525)
- `enableDefaultTyping()` without validator → `[P0][JKS-POL-003]` (RCE)
- Password/secret without `@JsonIgnore` / `WRITE_ONLY` access → `[P0][JKS-ANN-003]`
- Sensitive field serialized without masking → `[P0][JKS-SEC-004]`
- No JSON input size limit (DoS) → `[P1][JKS-SEC-003]`
- Stack trace leaked in error response → `[P1][JKS-ERR-004]`

### Reactive Issues (P0/P1 — WebFlux)

- `.block()`, `.blockFirst()`, `.blockLast()` → `[P1][RX-FND-001]`
- `Thread.sleep()` in reactive chains → `[P1][RX-FND-001]`
- `.subscribe()` inside reactive pipelines (fire-and-forget without error handler) → `[P2][RX-SUB-002]`
- Missing error handling → `[P1][RX-OPS-003]`
- Nested `Mono<Mono<T>>` (map returning Publisher) → `[P2][RX-PIT-001]`
- `switchIfEmpty(Mono.error(...))` without `defer` → `[P2][RX-OPS-002]`

### Performance Issues (P1)

- N+1 query patterns → `[P1][MVC-REP-004]`
- Unbounded list query (no pagination) → `[P1][MVC-REP-003]` / `[P1][WFL-REP-004]`
- HTTP call inside `@Transactional` → `[P1][MVC-TX-001]`
- Missing timeouts on WebClient/external → `[P0][WFL-WC-002]`
- Unbounded `onBackpressureBuffer` → `[P1][WFL-PIT-002]`
- Missing connection pool config → `[P2][WFL-SRV-002]`

### Concurrency & Transaction (P1)

- Dual-write Kafka + DB without outbox → `[P1][MVC-TX-002]`
- Missing optimistic lock for concurrent update → `[P1][MVC-TX-003]`
- ThreadLocal without `remove()` in finally → `[P1][CORE-CON-004]`
- Self-invocation bypass proxy (`@Transactional` no effect) → `[P1][MVC-SVC-003]`
- Mix JDBC + R2DBC in same TX → `[P1][WFL-TX-002]`
- Missing idempotency for retry-able op → `[P1][MVC-SVC-004]` / `[P1][XCT-IDM-001]`

### Numeric & Money (P0)

- `double`/`float` for money → `[P0][CORE-NUM-001]`
- `BigDecimal.divide` without RoundingMode/MathContext → `[P0][CORE-NUM-002]`
- Integer overflow not checked (`Math.addExact`, `Math.toIntExact`) on ledger → `[P0][CORE-NUM-003]`
- `BigDecimal.equals` for value compare (scale-sensitive) → `[P1][CORE-EQH-004]`
- BigDecimal serialized as JSON number (JS precision loss) → `[P0][JKS-MNY-001]` (fintech-critical)
- Missing `USE_BIG_DECIMAL_FOR_FLOATS` when deserializing money → `[P1][JKS-MNY-002]`
- BigDecimal scale not normalized at API boundary → `[P1][JKS-MNY-003]`

### Jackson Lifecycle & Modules (P0/P1)

- `new ObjectMapper()` in service body (not injected) → `[P1][JKS-OBJ-001]`
- Mutating shared ObjectMapper after first use → `[P1][JKS-OBJ-002]`
- Missing `JavaTimeModule` for `java.time.*` → `[P0][JKS-MOD-001]`
- Missing `disable(WRITE_DATES_AS_TIMESTAMPS)` (output as epoch array) → `[P1][JKS-MOD-002]`
- `java.util.Date` instead of `java.time.*` → `[P2][JKS-TIM-005]`
- Missing `TypeReference` for generic deserialize (type erasure) → `[P1][JKS-PRF-002]`
- Silent swallow of `JsonProcessingException` → `[P2][JKS-ERR-001]`
- Validation inside `@JsonCreator` instead of Bean Validation → `[P2][JKS-ERR-003]`
- Field/getter `@JsonProperty` conflict → `[P2][JKS-ANN-009]`

### Code Quality (P3 default, P2 if extreme)

- Method > 50 lines → `[P3][CORE-API-001]` (P2 if > 80)
- Class > 400 lines → `[P3][CORE-API-001]` (P2 if > 600, P1 if > 800 absolute max)
- Field injection (`@Autowired` on fields) → `[P2]` (CLAUDE.md hard block #2)
- `@Data` Lombok on domain → `[P2]` violates immutability
- `System.out.println`, `e.printStackTrace()`, debug code → `[P2]`
- Catch `Exception`/`Throwable` (non-top-level) → `[P2][CORE-EXC-001]`
- Ignored exception → `[P2][CORE-EXC-002]`
- Exception for control flow → `[P3][CORE-EXC-003]`

### Best Practices (P3)

- Magic numbers → `[P3]`
- Missing tests for new code → `[P2][XCT-TST-*]`
- Missing Javadoc on public API → `[P4][XCT-DOC-001]`
- Unstructured logging → `[P3][CORE-LOG-004]`
- Method naming > 3 fields → `[P3][MVC-REP-001]`

3. Generate report:
   - **MANDATORY: cite rule ID per finding** (`[<severity>][<RULE-ID>]`)
   - File location + line numbers
   - Issue description
   - Suggested fix with code example

4. Block commit if any P0, or P1 without ADR trade-off

## Output Format

```
CODE REVIEW REPORT
==================
Files Reviewed: X
Rules loaded: code-review-core, code-review-mvc, code-review-reactor, code-review-webflux, code-review-crosscut

P0 BLOCKERS (Must Fix Before Merge)
------------------------------------
[P0][CORE-NUM-001] double for money
File: TransferService.java:42
Issue: `double amount = req.getAmount();` — IEEE 754 precision loss
Fix: `BigDecimal amount = new BigDecimal(req.getAmount());` with explicit scale

[P0][CORE-LOG-002] sensitive data in log
File: AuthController.java:18
Issue: `log.info("user login password={}", req.getPassword());`
Fix: Drop password from log entirely

P1 CRITICAL (Must Fix or Document ADR)
---------------------------------------
[P1][MVC-TX-001] HTTP call in @Transactional
File: OrderService.java:78
Issue: `paymentClient.charge()` inside @Transactional method → connection pool exhaustion risk
Fix: Split TX boundary — load entity in TX1, call payment outside, update in TX2

[P1][RX-FND-001] .block() in reactive chain
File: OrderHandler.java:45
Issue: `userRepository.findById(id).block()` in WebFlux handler
Fix: Return `Mono<Response>`, compose with flatMap

P2 MAJOR (Should Fix or Follow-up Ticket)
------------------------------------------
[P2][XCT-TST-003] missing Testcontainers integration test
File: OrderRepositoryTest.java
Issue: Repository tested with H2 only, prod uses Postgres
Fix: Add @Testcontainers + PostgreSQLContainer

P3 MINOR (Comment, No Block)
----------------------------
[P3][CORE-API-001] method exceeds 30 LOC
File: OrderService.java:100
Issue: 67-line method
Fix: Extract helpers

P4 NITS (Optional)
------------------
[P4] Variable naming could be clearer
File: UserService.java:15

VERDICT: BLOCK | APPROVE WITH CAVEATS | APPROVE
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

1. Run full code quality review against ALL applicable `rules/java/code-review-*.md`
2. Spring-specific checks from CLAUDE.md NEVER rules
3. Categorize findings: **P0** / **P1** / **P2** / **P3** / **P4** (per `rules/java/code-review-crosscut.md §7`)
4. **MANDATORY: cite rule ID per finding** (`[<P0-P4>][<RULE-ID>]`)

### Verdict Logic

| Condition | Verdict | Action |
|-----------|---------|--------|
| 0 P0/P1 issues | **APPROVED** | Task done |
| P1 with ADR trade-off, or P2 only | **APPROVED WITH CAVEATS** | Task done, caveats logged + follow-up tickets |
| ≥1 P0, or P1 without ADR | **BLOCKED** | Back to slice-executor with rule IDs + fix list |

### After Review Complete

1. Update `.claude/workflow-state.json`:
   - Add `{"phase": "REVIEW", "completedAt": "{ISO timestamp}", "verdict": "{APPROVED|REJECTED}"}` to `phaseHistory`
   - Set `phase` to `"COMPLETE"` (if approved) or `"BUILD"` (if rejected, for re-implementation)
2. Output final verdict with summary
3. Task is **DONE** (if approved)

## Verdict Rules

- **BLOCK** if any P0, or P1 without ADR documenting trade-off
- **APPROVE WITH CAVEATS** if only P2 (or P1 with ADR)
- **APPROVE** if only P3/P4
- Never approve code with security vulnerabilities (any P0 security) or `.block()` in WebFlux

## Related rule files (loaded per stack)

- `rules/java/code-review-core.md` — CORE-* foundation
- `rules/java/code-review-mvc.md` — MVC-* (MVC stack only)
- `rules/java/code-review-reactor.md` — RX-* (reactive)
- `rules/java/code-review-webflux.md` — WFL-* (WebFlux stack only)
- `rules/java/code-review-crosscut.md` — XCT-* + PR checklist §6 + severity §7 + rule catalog §8
- `rules/java/code-review-jackson.md` — JKS-* (Jackson — DTO/ObjectMapper/@JsonProperty)
- `skills/coding-standards/SKILL.md` — unified enforcement entry point
