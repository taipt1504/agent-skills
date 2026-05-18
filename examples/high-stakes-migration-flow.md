# High-Stakes Lane Walkthrough — Migrate Sync REST → Kafka Outbox

End-to-end example. Architecture change + DB migration + cross-service impact. All gates mandatory + ADR + worktree.

## Setup

Project: payment-service. Currently calls notification-service via sync REST. Goal: replace with Kafka outbox event.

## User input

```
> Migrate payment-service event publishing from sync REST calls to notification-service
> to Kafka outbox pattern. Currently sync, latency cao, lockstep failure mode.
```

## Walkthrough

### 1. Triage

```
## Triage decision
**Lane:** High-stakes
**Reasoning:** Architecture change (sync→async paradigm), new dep (Kafka), cross-service contract change, breaking change for notification-service consumer.
**Next gate:** Align (mandatory for high-stakes)
**Skipped gates:** none
```

State: `LANE=high-stakes`.

### 2. Pre-flight 0 + Align (mandatory)

Pre-flight 0 enumerates ALL 31 skills + 13 rules. Selected APPLY:

```
APPLY:
- triage, preflight (meta)
- align, brainstorm (next gates)
- architecture (hex boundary impact)
- messaging-patterns (Kafka producer/consumer)
- summer-kafka (Summer outbox dispatcher)
- summer-data (outbox table schema)
- api-design (event envelope)
- observability-patterns (DLQ alerts)
- pentest (event payload PII scan)
- spring-webflux-patterns (reactive consumer)

APPLY rules:
- rules/common/lanes, spec-driven, security, patterns, skill-enforcement
- rules/summer/messaging (NEW — outbox + Kafka standards)
- rules/java/security, observability
- rules/java/migration (if schema change for outbox table)

SKIP:
- spring-mvc-patterns (project = WebFlux, verified)
- grpc-patterns (no gRPC)
- redis-patterns (no caching in scope)
- summer-payment-sdk (orthogonal to event publishing)
```

Align grills:

```
## My understanding
Move payment events to Kafka outbox. Decouples payment-service from notification-service availability.

## Assumptions
1. notification-service team agrees to consume from new Kafka topic (CROSS-TEAM DEP — verify)
2. Outbox table acceptable in payment-service DB (schema migration — high-stakes risk)
3. At-least-once delivery acceptable (notification-service must idempotent)
4. Existing sync REST endpoint deprecated, not removed immediately (backward compat window)
5. Topic naming follows cluster convention: payment.event.notification.v1

## Probes (failure modes — Pattern 4)
- SMTP / push failures downstream: retry via Kafka consumer DLQ? Manual review DLQ?
- Outbox dispatcher down: events queue but don't publish — alert threshold?
- Schema evolution: how do we add fields to event without breaking consumers?
- Idempotency on consumer: deduplication strategy?

User confirms #1 (notification team aligned), #3 (idempotent), provides answers to probes.

CONTEXT.md updates:
- "Outbox pattern" definition
- "Topic naming v1": <bounded-context>.event.<aggregate>.v<N>
- "Dispatcher health": SLO < 30s lag
```

Align artifact + CONTEXT.md updated. Written to git for cross-session vocabulary persistence.

### 3. Pre-flight 1 + Brainstorm (mandatory, ≥3 options)

Pre-flight 1 enumerates brainstorm-prep skills: brainstorm + solution-design + architecture + messaging-patterns + summer-kafka.

Brainstorm runs tournament:

```
## Phase 1 — Frame
Dimensions: throughput, latency p95, ops complexity, consistency, failure recovery, implementation time
Constraints: at-least-once (regulation), payment.event.notification.v1 (cluster convention)
Assumptions: must use Summer outbox (questionable — could use raw Kafka)

## Phase 2 — Tournament

### A1: Summer OutboxService + dispatcher (cluster standard)
- Approach: OutboxService.saveEvent() in payment transaction, Summer dispatcher publishes to Kafka.
- Weakness: dispatcher single point of failure, adds polling overhead.

### Challenge 1 — Beat A1 on latency
### A2: Transactional outbox + Debezium CDC
- Approach: outbox table, Debezium reads WAL, publishes to Kafka. No app-side dispatcher.
- vs A1: lower latency (no polling), but adds Debezium ops complexity.
- Champion: A1 (ops complexity wins for current scale)

### Challenge 2 — Different paradigm
### A3: Direct producer with idempotency + transactional outbox as fallback
- Approach: sync KafkaProducer.send() in transaction (Kafka transactions), outbox as recovery if Kafka unavailable.
- vs A1: lower latency, but Kafka tx complexity + needs broker upgrade.
- Champion: A1 (operational simplicity)

### Challenge 3 — Question assumption
### A4: Cluster-standard Summer outbox (sticking with assumption)
- Reaffirmed: assumption "must use Summer outbox" reflects cluster ADR-0007 (all 8 services standardized).
- Deviation would require cluster ADR.
- Verdict: assumption holds.

## Phase 3 — Synthesis

| Dim | A1: Summer | A2: Debezium | A3: Direct |
|---|---|---|---|
| Throughput | 5k/sec | 15k/sec | 10k/sec |
| Latency p95 | 100ms | 30ms | 50ms |
| Ops complexity | Low (cluster pattern) | High (Debezium) | Medium (Kafka tx) |
| Consistency | Strong | Strong | Strong (with tx) |
| Failure recovery | App-side retry | WAL guarantees | Outbox fallback |
| Implementation | 1 week | 3 weeks | 2 weeks |

**Recommendation: A1 — Summer OutboxService + dispatcher**

Why: cluster-standard, ops team trained, deviation would require cluster ADR. Hits throughput target (5k/sec >> projected 800/sec).

Trade-off: latency 100ms vs A2's 30ms. Acceptable (notification not real-time).

Caveat: revisit A2 if scale >5x or latency SLO tightens.
```

ADR auto-generated (high-stakes mandatory):

`docs/adr/0042-payment-event-outbox.md`:

```markdown
# ADR-0042: Payment events via Summer outbox pattern

**Status:** Accepted
**Date:** 2026-05-15
**Lane:** high-stakes

## Context
Payment-service publishes events to notification-service via sync REST. Lockstep failure mode: notification-service down → payment-service errors. High coupling.

## Decision
Adopt Summer OutboxService + cluster-standard Kafka outbox pattern.

## Considered alternatives

### A1: Summer OutboxService + dispatcher (Chosen)
Cluster-standard. Ops team trained.

### A2: Debezium CDC (Rejected)
Lower latency but adds Debezium ops complexity. Revisit if scale 5x+.

### A3: Direct producer + Kafka transactions (Rejected)
Lower latency but Kafka tx complexity. Outbox fallback adds confusion.

## Consequences
Positive:
- Decouples payment from notification availability
- Cluster-aligned (8 services already on this pattern)
- At-least-once + idempotent consumer = no message loss

Negative:
- 100ms latency from dispatcher polling
- Outbox table adds DB write per event
- Dispatcher = SPOF (mitigated: monitor, auto-restart)

**Reversibility:** Medium — events still flowing, fallback to REST possible within 1 week
**Cost to revert:** ~3 days

## When to revisit
- Throughput projection >25k events/sec (A1 ceiling ~5k/sec)
- Latency SLO tightens to <50ms p95
- Cluster ADR-0007 changes
```

### 4. Architect review (auto, high-stakes)

```
## Architect verdict: APPROVE_WITH_CAVEATS

### ADR cross-check
| ADR | Conflict? | Resolution |
|---|---|---|
| ADR-0007 (cluster outbox standard) | None | Aligned |
| ADR-0023 (payment-service uses Postgres) | None | Outbox table in same DB |
| ADR-0031 (notification-service consumes from Kafka) | None | New topic fits existing consumer pattern |

### Bounded context check
- Payment-service owns outbox table — OK (same bounded context)
- Event published cross-bounded-context — OK (decoupling improvement)

### Layer responsibility
- OutboxService used in application layer (CreateOrderHandler) — correct
- Dispatcher infrastructure adapter — correct
- Event payload in domain layer — correct

### Caveats
- New topic name must be registered in cluster topic registry (cross-team coordination)
- Outbox table migration is a high-stakes schema change — apply expand-contract per rules/java/migration.md

### CONTEXT.md updates needed
- (done by Align)
```

### 5. Pre-flight 2 + Plan

Slice decomposition:

```markdown
## Slices

### Slice 1: Outbox table migration (V100__create_payment_outbox.sql)
- Files: 1 new SQL migration
- Skills: database-patterns, summer-data
- Dependencies: none
- Risk: High (schema change, expand-contract first phase)
- Complexity: M (3h)

### Slice 2: Event class + envelope
- Files: 2 new (PaymentEvent.java, OrderCreatedPayload.java)
- Skills: coding-standards, summer-data
- Dependencies: Slice 1
- Risk: Low
- Complexity: S (1h)

### Slice 3: Replace sync REST call with OutboxService.saveEvent()
- Files: 1 modified (CreatePaymentHandler.java), 1 deprecated (NotificationClient.java)
- Skills: spring-webflux-patterns, summer-kafka, messaging-patterns
- Dependencies: Slice 2
- Risk: Medium (transaction boundary change)
- Complexity: M (3h)

### Slice 4: Dispatcher monitoring + alert
- Files: 2 new (DispatcherHealthIndicator.java, alert rule config)
- Skills: observability-patterns
- Dependencies: Slice 3
- Risk: Low
- Complexity: S (1h)

### Slice 5: Deprecate sync REST path (feature flag)
- Files: 1 modified (NotificationClient.java with @Deprecated + flag)
- Skills: coding-standards
- Dependencies: Slice 3
- Risk: Low
- Complexity: S (30min)

## Dependency graph
- Slice 1 → blocks 2, 4
- Slice 2 → blocks 3
- Slice 3 → blocks 4, 5
- Slice 4 → leaf
- Slice 5 → leaf

## Execution order
1. Slice 1 (high risk, must succeed before code depends on table)
2. Slice 2 (depends on 1)
3. Slice 3 (depends on 2)
4. Parallel: Slice 4 + Slice 5 (both depend on 3)

## Risk register
| Slice | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | Schema migration on prod DB | High | Apply to staging first, monitor 24h, then prod |
| 3 | Transaction boundary change → outbox not flushed if save fails | Medium | Test transaction rollback explicitly; review Spec scenario |
```

User approves.

### 6. Pre-flight 3 + Spec

Spec defines scenarios per slice. Slice 3 (the critical one):

```markdown
## Slice 3 — Replace sync REST with OutboxService

### Scenarios
| ID | Name | Input | Expected |
|---|---|---|---|
| S3.1 | shouldSaveEventWhenPaymentSucceeds | Valid PaymentCommand | Order saved + outbox row created in SAME transaction |
| S3.2 | shouldRollbackOutboxWhenPaymentFails | PaymentCommand triggers DB constraint violation | NO order saved, NO outbox row (transaction rolled back) |
| S3.3 | shouldNotCallNotificationServiceDirect | Valid PaymentCommand | Verify: NotificationClient.send() NOT invoked (deprecated path) |
| S3.4 | shouldPublishEnvelope | Valid PaymentCommand | Outbox row contains {eventId, eventType=PaymentCompleted, occurredAt, aggregateId, payload} |
| S3.5 | shouldHandleDispatcherFailureGracefully | Mock dispatcher unavailable | Event remains in outbox, retry on next dispatcher poll |
```

### 7. Pre-flight 4 + Execute (worktree per slice for high-stakes)

```
git worktree add ../payment-svc-outbox-slice-1 feature/outbox-slice-1
git worktree add ../payment-svc-outbox-slice-2 feature/outbox-slice-2
...

Orchestrator dispatches:
- Slice 1: slice-executor in worktree 1
- Wait for completion
- Slice 2: slice-executor in worktree 2
- ... sequential per dep graph

Slice 4 + 5 dispatched in parallel after Slice 3.

Each subagent receives:
- Slice description
- Slice spec scenarios
- Pre-flight 4 artifact
- CONTEXT.md vocabulary
```

After all slices done, orchestrator merges worktree branches → feature branch.

### 8. Verify (high-stakes full)

```bash
./gradlew clean build         # PASS
./gradlew test                # PASS (all unit + integration)
./gradlew jacocoTestReport    # PASS (87% coverage)
./gradlew dependencyCheckAnalyze  # PASS (no Critical CVE)
./gradlew bootRun (smoke)     # PASS (/actuator/health = 200)
```

### 9. Pre-flight 5 + Review Stage 1

```markdown
✅ Spec compliance: PASS
All 18 scenarios mapped to passing tests across 5 slices.
→ Proceeding to Stage 2 (security deep-dive for high-stakes).
```

### 10. Review Stage 2 (security deep-dive)

```markdown
## Stage 2: Code Quality Review (high-stakes)

**Verdict:** Approve with caveats

### Critical issues (0)

### Major issues (2)
1. PaymentEvent.java:34 — Payload field `card_last_4` could be PII concern depending on payload retention. Verify outbox table retention policy via DBA.
2. DispatcherHealthIndicator.java:21 — Health check polls every 30s. May miss short-lived dispatcher outages. Consider event-driven alert via Kafka consumer lag metric.

### Minor issues (3)
1. CreatePaymentHandler.java:67 — Method now 55 LOC (was 42). Approaching 50 LOC max. Consider extracting outbox-save to private method.
2. V100__create_payment_outbox.sql — Index `idx_outbox_unpublished` should be CONCURRENTLY in prod migration to avoid table lock.
3. PaymentEventTest.java:42 — Mock returns hardcoded eventId. Use UUID factory for realism.

### Security review (high-stakes)
- ✓ Outbox payload does not contain PCI data (only `card_last_4` which is PCI-allowed per regulation)
- ✓ Topic publishes via Summer dispatcher (cluster-secured Kafka cluster)
- ✓ Consumer-side authn handled by Summer Kafka client (mutual TLS)
- ✓ At-least-once + idempotency: consumer has dedup table (verified with notification-service team)

### Performance review
- Outbox-save adds ~5ms p95 to payment transaction (acceptable per Align)
- Dispatcher poll every 30s = max 30s outbox lag (within SLO)
- Verify: outbox table has index on `unpublished_at` to avoid full scan

### Coverage: 87% line, 81% branch ✓

### Skills + rules applied
spring-webflux-patterns, summer-kafka, summer-data, messaging-patterns, observability-patterns, pentest, database-patterns
rules: java/messaging, java/migration, java/audit, java/security, java/observability, java/reactive
```

User reviews:
- Issue #1 (PII concern) → discuss with DBA, accept retention policy
- Issue #2 (alert mechanism) → fix in this slice (already in scope)

After fixes:
- Re-run Stage 2: Approve.

### 11. Learn

```
[auto-adr] ADR found: 0042-payment-event-outbox.md ✓
[evolution-check] 1 candidate ready: "Outbox-save must be in SAME transaction as domain write" (confidence 0.85, occurrences 4, 2 sessions, 2 projects)
[evolution-check] Run /meta evolve to review.
[session-save] phase=COMPLETE
```

User runs `/meta evolve` later. Promotes the instinct to a skill in `~/.claude/skills/auto-evolved/outbox-transaction-discipline/`.

### 12. Commit (user)

```bash
git add .
git commit -m "feat(payment): migrate to Kafka outbox via Summer dispatcher

Replaces sync REST call to notification-service with Summer OutboxService.
Cluster-standard pattern per ADR-0042. At-least-once delivery + idempotent
consumer ensures no message loss.

Slices:
1. V100 outbox table migration
2. PaymentEvent + envelope
3. CreatePaymentHandler uses OutboxService (in same tx)
4. Dispatcher health indicator
5. Sync REST path deprecated (feature flag)

Coverage: 87% line / 81% branch
ADR: docs/adr/0042-payment-event-outbox.md

Skills applied: spring-webflux-patterns, summer-kafka, summer-data, messaging-patterns, pentest
Rules: java/messaging, java/migration, java/audit, java/security, java/observability"
```

User commits feature branch. Opens PR. Cluster reviewer (another team) approves.

### 13. Deploy (out of scope but noted)

- Staging deploy + 24h monitor
- Prod deploy via canary 10% → 100% over 1 week
- Old sync REST path retained for 30 days (feature flag), then removed

## Artifacts produced

All standard-lane artifacts PLUS:

| Path | High-stakes addition |
|---|---|
| `docs/adr/0042-payment-event-outbox.md` | Mandatory ADR |
| `.claude/memory/architect-reviews/<date>.md` | Architect review |
| 5x worktrees (cleaned after merge) | Slice isolation |
| `.claude/memory/state/active-worktrees.json` | Worktree tracking |
| Updated CONTEXT.md (committed) | Cluster vocabulary growth |
| Promotion candidate (after session) | Auto-evolution loop |

## Total time

| Phase | Time |
|---|---|
| Triage | ~5s |
| Pre-flight 0 + Align | ~10 min |
| Pre-flight 1 + Brainstorm + ADR | ~30 min |
| Architect review | ~5 min |
| Pre-flight 2 + Plan | ~15 min |
| Pre-flight 3 + Spec | ~20 min |
| Pre-flight 4 + Execute (5 slices, worktrees) | ~1 day |
| Verify + security scan | ~5 min |
| Pre-flight 5 + Review S1 + S2 | ~15 min |
| Fix iterations | ~30 min |
| **Total** | **~1.5 days** |

vs ad-hoc approach: 3-5 days with much higher risk of incomplete consideration of alternatives, missing ADR, or insufficient testing of edge cases.

## Lessons captured

1. ADR mandatory: future "why did we pick outbox over Debezium?" answered explicitly
2. Architect review caught the cluster ADR-0007 alignment requirement
3. Worktree isolation per slice = clean rollback if Slice 1 (schema) had issues
4. Pre-flight 5 security deep-dive caught PII review item before merge
5. Auto-evolution captured "outbox-tx discipline" as cross-project pattern → may evolve to skill
6. Cross-team coordination (notification-service) surfaced in Align — saved late merge conflict
