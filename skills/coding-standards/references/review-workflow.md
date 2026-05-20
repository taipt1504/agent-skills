# Code Review Workflow

> Load this reference during Stage 2 review (`code-quality-reviewer`) or during BUILD REFACTOR self-check (`slice-executor`). Provides the priority-ordered scan across ALL 6 rule sets and the verdict logic.
> For Jackson-specific deep dive load `jackson-review-workflow.md` in addition.

## Table of Contents
1. [When this fires](#when-this-fires)
2. [Pre-scan setup](#pre-scan-setup)
3. [Priority-ordered scan](#priority-ordered-scan)
4. [Severity policy](#severity-policy)
5. [Output format](#output-format)
6. [Verdict logic](#verdict-logic)
7. [Do / Don't](#do--dont)

## When this fires

- Stage 2 review (after Stage 1 spec compliance passes).
- `/dc-review` invocation.
- Trivial lane (Stage 2 only; no Stage 1).
- BUILD REFACTOR step (slice-executor self-check before declaring slice done).

## Pre-scan setup

1. Read pre-flight artifact at `.claude/memory/preflight/review-<latest>.md` (or `execute-<latest>.md` for REFACTOR).
2. Confirm Stage 1 verdict (review path): `.claude/memory/state/review-stage1.json` status = PASS. If FAIL → stop, do not run Stage 2.
3. Detect shape (whole-feature single-file vs per-slice).
4. Run `git diff` scoped to slice files (per-slice) or full diff (whole-feature).
5. Classify changed files; activate matching rule sets:

| Stack signal | Rule sets to load |
|---|---|
| Any Java in diff | `code-review-core.md` + `code-review-crosscut.md` (always) |
| `spring-boot-starter-web` + `JpaRepository` | + `code-review-mvc.md` |
| `Mono<` / `Flux<` in diff | + `code-review-reactor.md` |
| `spring-boot-starter-webflux` | + `code-review-webflux.md` |
| `ObjectMapper` / `@JsonProperty` / BigDecimal-DTO / date-DTO | + `code-review-jackson.md` (+ load `jackson-review-workflow.md`) |
| `io.f8a.summer` dep | + `rules/summer/*` |

## Priority-ordered scan

Walk dimensions in priority. Surface P0 first.

### P1. Security (P0 default)

- `[P0][CORE-LOG-002]` sensitive data in logs (password, OTP, full PAN, CVV, JWT).
- `[P0][MVC-CFG-003]` hardcoded credentials / secrets.
- `[P0][MVC-REP-*]` SQL injection (string concat in queries).
- `[P0][MVC-SEC-001]` / `[P0][WFL-SEC-001]` missing `@PreAuthorize` on sensitive endpoint.
- `[P0][JKS-POL-002]` `JsonTypeInfo.Id.CLASS` (RCE — CVE-2017-7525 class).
- `[P0][JKS-POL-003]` `enableDefaultTyping()` without validator.
- `[P0][JKS-ANN-003]` password/secret without `@JsonIgnore` or `WRITE_ONLY`.
- `[P0][JKS-SEC-004]` sensitive field serialized without masking.
- `[P1][JKS-SEC-003]` no JSON input size limit (DoS).
- `[P1][JKS-ERR-004]` stack trace leaked in error response.

### P2. Money / Precision (P0 — fintech)

- `[P0][CORE-NUM-001]` `double`/`float` for money.
- `[P0][CORE-NUM-002]` `BigDecimal.divide` without RoundingMode / MathContext.
- `[P0][CORE-NUM-003]` integer overflow not guarded with `Math.addExact` / `Math.toIntExact` on ledger.
- `[P0][JKS-MNY-001]` BigDecimal serialized as JSON number (precision loss).
- `[P1][JKS-MNY-002]` deserialize without `USE_BIG_DECIMAL_FOR_FLOATS`.
- `[P1][JKS-MNY-003]` money scale not normalized at API boundary.
- `[P1][CORE-EQH-004]` `BigDecimal.equals` for value compare (scale-sensitive).

### P3. Transaction & Concurrency (P0-P1)

- `[P1][MVC-TX-001]` HTTP call inside `@Transactional` → connection pool exhaustion.
- `[P1][MVC-TX-002]` dual-write Kafka + DB without outbox.
- `[P1][MVC-TX-003]` concurrent update without optimistic lock.
- `[P1][MVC-SVC-003]` self-invocation bypasses proxy (`@Transactional` no-op).
- `[P1][WFL-TX-002]` mix JDBC + R2DBC in same TX.
- `[P1][MVC-SVC-004]` retry-able operation without idempotency.
- `[P1][CORE-CON-004]` `ThreadLocal` not removed in `finally`.
- `[P1][XCT-IDM-001]` mutation endpoint without `Idempotency-Key`.

### P4. Reactive (P0-P1, WebFlux only)

- `[P1][RX-FND-001]` `.block()` / `.blockFirst()` / `.blockLast()` in reactive chain.
- `[P0][WFL-WC-002]` missing timeout on `WebClient` (hang forever).
- `[P1][RX-OPS-002]` `switchIfEmpty(Mono.error(...))` without `defer` (eager evaluation).
- `[P2][RX-PIT-001]` nested `Mono<Mono<T>>` (`map` returning Publisher).
- `[P2][RX-SUB-002]` fire-and-forget `.subscribe()` without error handler.
- `[P1][WFL-PIT-002]` unbounded backpressure.

### P5. Performance (P1-P2)

- `[P1][MVC-REP-004]` N+1 query (no `@EntityGraph` / fetch join).
- `[P1][MVC-REP-003]` / `[P1][WFL-REP-004]` unbounded list query (no pagination).
- `[P1][JKS-PRF-002]` missing `TypeReference` for generic deserialize.
- `[P2][JKS-PRF-001]` no `ObjectReader` cache on hot path.
- `[P2][WFL-SRV-002]` connection pool not configured.

### P6. Code quality (P2-P3)

- `[P2][CORE-EXC-001]` `catch (Exception e)` non-top-level.
- `[P2][CORE-EXC-002]` ignored exception (no log, no rethrow).
- `[P2]` field injection (`@Autowired` on field — CLAUDE.md hard block #2).
- `[P2]` `@Data` on domain entity (violates immutability).
- `[P2]` `System.out.println` / `e.printStackTrace()` / debug code.
- `[P2][MVC-VAL-001]` `@RequestBody` without `@Valid`.
- `[P3][CORE-API-001]` method > 50 LOC (P2 > 80) · class > 400 LOC (P2 > 600, P1 > 800).
- `[P3][CORE-LOG-004]` unstructured log message.
- `[P3][JKS-PRF-004]` `Map<String, Object>` on hot path.
- `[P2][JKS-ANN-009]` field-vs-getter `@JsonProperty` conflict.

### P7. Testing & Observability (P2)

- `[P2][XCT-TST-003]` missing Testcontainers integration test for DB layer.
- `[P2][XCT-TST-005]` missing contract test for cross-service consumer.
- `[P2][JKS-TST-002]` no round-trip test for DTO.
- `[P2][XCT-OBS-001]` no metric for new business event.
- `[P2][XCT-OBS-002]` missing trace span on external call.

### P8. Docs & Deps (P3-P4)

- `[P3][XCT-DOC-001]` missing Javadoc on public API.
- `[P3][XCT-DEP-002]` HIGH/CRITICAL CVE in dependencies.
- `[P4][JKS-TIM-005]` cosmetic: `java.util.Date` → `java.time.*` migration.

## Severity policy

Per `rules/java/code-review-crosscut.md §7`:

| Severity | Definition | Block merge? |
|----------|------------|--------------|
| **P0** | Security hole · data loss · money calc wrong · transaction broken | YES |
| **P1** | Race condition · TX boundary wrong · missing idempotency · perf regression | YES (or ADR documents trade-off) |
| **P2** | Missing test coverage · insufficient exception handling · missing validation | YES if possible; else follow-up ticket |
| **P3** | Style · naming · DRY violation · documentation | Discuss in comment, no block |
| **P4** | Personal preference · micro-optimization | Optional suggestion |

## Output format

```markdown
## Stage 2: Code Quality Review

**Verdict:** Block | Approve with caveats | Approve
**Rules loaded:** <list of code-review-*.md files>

### P0 Blockers (N)

1. `<file>:<line>` — **[P0][<RULE-ID>]** <issue>
   - **Why blocker:** <one sentence>
   - **Fix:** <one sentence or code snippet>

### P1 Critical (N)

1. `<file>:<line>` — **[P1][<RULE-ID>]** <issue>
   - **Why critical:** <one sentence>
   - **Fix:** <one sentence>

### P2 Major (N)

1. `<file>:<line>` — **[P2][<RULE-ID>]** <issue>
   - **Recommendation:** <one sentence>

### P3 Minor (N)

1. `<file>:<line>` — **[P3][<RULE-ID>]** <issue>

### P4 Nits (N)

1. `<file>:<line>` — **[P4]** <issue>

### Observations (non-blocking)

- <pattern noticed worth mentioning, with rule ID where applicable>

### Test coverage

- Line: <X>% · Branch: <Y>% · Verdict: ≥ 80% [✅/❌]

### PR Checklist

- [ ] 6.1 General · 6.2 Correctness · 6.3 Concurrency & TX · 6.4 Reactive · 6.5 Security · 6.5b Jackson · 6.6 Performance · 6.7 Observability
  (per `rules/java/code-review-crosscut.md §6`)
```

## Verdict logic

| Findings | Verdict | Workflow phase |
|---|---|---|
| ≥1 P0, or P1 without ADR | **Block** | BUILD (fix list) |
| P1 with ADR, or P2 only | **Approve with caveats** | COMPLETE (note caveats + follow-up tickets) |
| P3/P4 only | **Approve** | COMPLETE |

## Do / Don't

### Do

- Cite rule ID on every finding: `[<P0-P4>][<RULE-ID>]`. P4 nits may omit ID.
- Provide concrete fix (one sentence or code snippet) for P0/P1.
- Scope strictly to `git diff` — do not review unchanged code.
- Group findings by severity so P0/P1 surface first.
- Reference the rule file path when first citing a new prefix.
- If a pattern recurs that has no existing rule ID, mark `[NEW-RULE]` and route to evolve-rules.

### Don't

- Do not block on style nits that do not change meaning — demote to P3/P4.
- Do not emit findings without rule ID citation (except P4). Orchestrator rejects such output.
- Do not re-verify spec compliance (Stage 1 owns scenario↔test mapping).
- Do not praise or use filler ("Looks good!") — findings only.
- Do not flag old severity labels (CRITICAL/HIGH/MEDIUM) — only P0/P1/P2/P3/P4.
- Do not invent rule IDs — only cite IDs that exist in `rules/java/code-review-*.md`.
