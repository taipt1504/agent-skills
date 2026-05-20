---
name: code-review-crosscut
description: Cross-cutting code review rules — idempotency, observability, testing, documentation, dependency management. Plus PR review checklist + severity levels P0-P4 + rule ID catalog. Rule IDs XCT-*. Always loaded for Java review.
globs: "*.java,*.md,*.yml,*.gradle,*.xml"
applicability:
  always: false
  triggers:
    files_match: ["**/*.java", "**/*.md", "**/build.gradle*", "**/pom.xml", "**/application*.yml"]
    task_keywords: ["review", "code review", "PR", "checklist", "severity", "idempotency", "observability", "testing", "ADR"]
    related_rules:
      - rules/java/code-review-core.md
      - rules/java/code-review-mvc.md
      - rules/java/code-review-reactor.md
      - rules/java/code-review-webflux.md
      - rules/java/observability.md
      - rules/java/testing.md
relevance_assessment: |
  HIGH 90%+: any Java review task (severity + checklist always relevant)
  HIGH 95%+: PR review explicitly invoked
---

# Code Review — Cross-cutting (`XCT-*`) + Checklist + Severity

> Cross-cutting rules, PR checklist, severity P0-P4, rule ID catalog. Load with every code review.

## 5.1. Idempotency (`XCT-IDM`)

### XCT-IDM-001 — Idempotency-Key for mutation endpoints

```
POST /payments
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

Server stores `key + response` in a table with TTL (24-48h). Within TTL, requests with the same key → return cached response, do not re-execute.

Critical for: payment, transfer, ledger entry. Network retry, client retry, timeout retry → same key, no duplication.

## 5.2. Observability (`XCT-OBS`)

### XCT-OBS-001 — Metrics with Micrometer

```java
@Component
@RequiredArgsConstructor
public class OrderMetrics {
    private final MeterRegistry registry;

    public void recordCreated(String type) {
        registry.counter("orders.created", "type", type).increment();
    }

    public Timer.Sample startProcessing() {
        return Timer.start(registry);
    }
}
```

Standard metric types:
- **Counter**: count events (orders.created, errors.count)
- **Gauge**: snapshot value (queue.size, connections.active)
- **Timer**: duration distribution (api.latency, db.query.time)

### XCT-OBS-002 — Tracing with OpenTelemetry

Auto-instrument for Spring + WebClient + R2DBC. Custom span for business operations:

```java
@WithSpan("onboarding.submit")
public Mono<Result> submit(@SpanAttribute("applicationId") String appId) { ... }
```

Cross-service trace propagation via W3C TraceContext header.

### XCT-OBS-003 — Health check

```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true
      show-details: when-authorized
  health:
    livenessstate:
      enabled: true
    readinessstate:
      enabled: true
```

- `/actuator/health/liveness` — process alive? (restart pod if fail)
- `/actuator/health/readiness` — ready to take traffic? (remove from LB if fail)

Custom indicator for critical dependencies:

```java
@Component
public class KafkaHealthIndicator implements ReactiveHealthIndicator {
    @Override
    public Mono<Health> health() {
        return checkKafka()
            .map(ok -> Health.up().withDetail("broker", broker).build())
            .onErrorResume(e -> Mono.just(Health.down(e).build()));
    }
}
```

## 5.3. Testing (`XCT-TST`)

### XCT-TST-001 — Test pyramid

- **Unit** (~70%): Service logic, pure functions, fast (ms)
- **Integration** (~25%): With DB, Kafka, Redis — Testcontainers
- **E2E** (~5%): Full system, slow

### XCT-TST-002 — Slice test

```java
@WebMvcTest(OrderController.class)        // MVC layer only
@WebFluxTest(OrderController.class)        // WebFlux layer only
@DataJpaTest                                // JPA repository only
@DataR2dbcTest                              // R2DBC repository only
@JsonTest                                   // JSON serialization only
```

Faster than full `@SpringBootTest`.

### XCT-TST-003 — Testcontainers for integration

```java
@SpringBootTest
@Testcontainers
class OrderIntegrationTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
        .withDatabaseName("test");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.r2dbc.url", () -> "r2dbc:postgresql://" + postgres.getHost() + 
            ":" + postgres.getFirstMappedPort() + "/test");
    }
}
```

Do NOT mock infrastructure (DB, Kafka). Test against real containers.

### XCT-TST-004 — Do not mock classes you do not own

OK: mock repository interface, service interface you define.
NOT OK: mock `Mono`, `Flux`, `RestTemplate`, `KafkaTemplate`, `EntityManager`. Use real test doubles (TestPublisher, Embedded Kafka, H2).

### XCT-TST-005 — Contract test

Spring Cloud Contract or Pact:
- Producer defines the contract
- Consumer tests with a mock following the contract
- Producer test against the contract must pass

Prevents integration breakage when APIs change.

## 5.4. Documentation (`XCT-DOC`)

### XCT-DOC-001 — Javadoc for public API

```java
/**
 * Submit application from DRAFT → SUBMITTED, triggers AML screening.
 *
 * @param appId application ID, format APP-YYYYMMDD-NNNNNN
 * @param actor user submitting (Maker), non-null
 * @param req submit request; lockVersion must match current version
 * @return updated application with new status
 * @throws OptimisticLockException if lockVersion mismatched
 * @throws BusinessException PHONE_DUPLICATE if phone already used by another merchant
 * @since 2.3.0
 */
public Mono<Application> submit(String appId, AuditActor actor, SubmitRequest req) { ... }
```

Param, return, throws, since — enough for someone else to use the API.

### XCT-DOC-002 — Module-level README

Each service/module has a README:
- Purpose
- How to run locally
- How to test
- Dependencies on other services
- Owner / on-call

### XCT-DOC-003 — ADR (Architecture Decision Record)

For significant decisions (database choice, sync vs async, event format), store in `docs/adr/0001-use-r2dbc.md`:

```markdown
# ADR-0001: Use R2DBC for party-service

## Status
Accepted

## Context
party-service handles high-concurrency merchant lookups ...

## Decision
Use R2DBC + Postgres.

## Consequences
- (+) Non-blocking I/O, scales better
- (-) No lazy loading, manual relationship resolution
- (-) Smaller ecosystem than JPA
```

## 5.5. Dependency Management (`XCT-DEP`)

### XCT-DEP-001 — BOM for version alignment

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>3.3.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

BOM manages versions → dependencies don't need explicit versions, compatibility guaranteed.

### XCT-DEP-002 — Audit dependencies

- `mvn dependency:tree` → inspect transitive
- Snyk / OWASP Dependency-Check → CVE scan
- Renovate / Dependabot → automatic update PRs

CI fails on HIGH/CRITICAL CVE.

### XCT-DEP-003 — No duplicate SLF4J binding

```bash
mvn dependency:tree | grep slf4j
```

If both `slf4j-log4j12` and `logback-classic` are present → SLF4J warning, logging may misbehave. Exclude one of the transitive deps.

---

# 6. PR Review Checklist

## 6.1. General

- [ ] Title clear, follows convention (feat:/fix:/refactor:/test:/docs:)
- [ ] Description explains WHY, not just WHAT
- [ ] Link to ticket / issue
- [ ] Diff focused, doesn't mix concerns
- [ ] CI passes: build, test, lint, security scan

## 6.2. Correctness

- [ ] Tests cover happy path + error case + edge cases (null, empty, boundary) — [CORE-EXC-*, XCT-TST-*]
- [ ] Validation on external input — [MVC-VAL-*]
- [ ] No `System.out.println`, `e.printStackTrace()`, debug code
- [ ] No hardcoded secrets, URLs, env-specific values — [MVC-CFG-003]
- [ ] Logging has context (operation, id, actor), parameterized — [CORE-LOG-001, CORE-LOG-004]
- [ ] Exceptions have business meaning, don't leak technical detail — [CORE-EXC-004]
- [ ] Nullable contract is clear (annotation, Javadoc, or Optional) — [CORE-NUL-003]

## 6.3. Concurrency & Transaction

- [ ] Transaction boundary is narrow (no external calls inside) — [MVC-TX-001]
- [ ] Outbox pattern for cross-service events, no direct send — [MVC-TX-002]
- [ ] Optimistic lock with @Version for concurrent updates — [MVC-TX-003]
- [ ] Idempotency for retry-able operations — [MVC-SVC-004, XCT-IDM-001]
- [ ] No race condition in check-then-act (DB unique constraint as backup)
- [ ] ThreadLocal is removed in finally — [CORE-CON-004]

## 6.4. Reactive (if reactive code)

- [ ] No `.block()` in reactive chain — [RX-FND-001]
- [ ] `switchIfEmpty(Mono.defer(...))` rather than direct `Mono.error()` — [RX-OPS-002]
- [ ] Scheduler matches work type (parallel vs boundedElastic) — [RX-SCH-002]
- [ ] Context/MDC propagated across reactive boundary — [RX-CTX-001]
- [ ] No nested Mono/Flux (`Mono<Mono<T>>`) — [RX-PIT-001]
- [ ] subscribeOn applied once, publishOn for downstream switch — [RX-SCH-001]
- [ ] StepVerifier for tests, no `.block()` in tests — [RX-TST-001, RX-PIT-005]

## 6.5. Security

- [ ] Input validated (Bean Validation + business rules) — [MVC-VAL-*]
- [ ] No sensitive data logged (password, OTP, card number, ID) — [CORE-LOG-002]
- [ ] Authz check at method/endpoint level — [MVC-SEC-001, WFL-SEC-001]
- [ ] SQL injection: parameterized query, no string concat — [MVC-REP-*]
- [ ] XSS: output encoding, CSP header
- [ ] Rate limit on critical endpoints — [MVC-SEC-003]
- [ ] CORS config correct (no `*` in prod)
- [ ] No Jackson `Id.CLASS` polymorphic deser (RCE) — [JKS-POL-002]
- [ ] `enableDefaultTyping()` only with validator — [JKS-POL-003]
- [ ] Passwords/secrets `@JsonIgnore` or `WRITE_ONLY` — [JKS-ANN-003]
- [ ] Sensitive fields masked on serialize — [JKS-SEC-004]
- [ ] JSON input size limit set (StreamReadConstraints) — [JKS-SEC-003]
- [ ] No stack trace leak in error response — [JKS-ERR-004]

## 6.5b. Jackson (if Jackson DTO/ObjectMapper in diff)

- [ ] ObjectMapper injected from Spring (not `new ObjectMapper()`) — [JKS-OBJ-001]
- [ ] No mutation of shared ObjectMapper post-config — [JKS-OBJ-002]
- [ ] `JavaTimeModule` registered if using `java.time.*` — [JKS-MOD-001]
- [ ] `WRITE_DATES_AS_TIMESTAMPS` disabled (ISO-8601) — [JKS-MOD-002]
- [ ] BigDecimal serialized as string (fintech precision) — [JKS-MNY-001]
- [ ] `USE_BIG_DECIMAL_FOR_FLOATS` enabled when deserializing money — [JKS-MNY-002]
- [ ] BigDecimal scale normalized at API boundary — [JKS-MNY-003]
- [ ] No `java.util.Date` — use `java.time.*` — [JKS-TIM-005]
- [ ] `TypeReference` used for generic deserialize — [JKS-PRF-002]
- [ ] `JsonProcessingException` not swallowed — [JKS-ERR-001]
- [ ] Validation via `@Valid` (not in `@JsonCreator`) — [JKS-ERR-003]
- [ ] No field/getter `@JsonProperty` conflict — [JKS-ANN-009]
- [ ] `@JsonTest` slice covers round-trip + golden file — [JKS-TST-002, JKS-TST-004]

## 6.6. Performance

- [ ] N+1 query check (entity graph or fetch join) — [MVC-REP-004]
- [ ] List endpoints have pagination — [MVC-REP-003, WFL-REP-004]
- [ ] Cache for expensive reads (Redis, Caffeine)
- [ ] DB index for queries in PR
- [ ] Connection pool size matches workload — [WFL-SRV-002]

## 6.7. Observability

- [ ] Metric for new business events — [XCT-OBS-001]
- [ ] Log enough to debug production incidents — [CORE-LOG-004]
- [ ] Trace span on external calls — [XCT-OBS-002]
- [ ] Health check doesn't break when dependency is down (graceful) — [XCT-OBS-003]

---

# 7. Severity Levels & Triage

| Severity | Definition | Block before merge? |
|----------|------------|----------------------|
| **P0 (Blocker)** | Security hole, data loss risk, money calculation wrong, transaction broken | **YES** |
| **P1 (Critical)** | Race condition, wrong transaction boundary, missing idempotency, performance regression | **YES** (or ADR documenting trade-off) |
| **P2 (Major)** | Missing test coverage, insufficient exception handling, missing validation | YES if possible, or follow-up ticket in sprint |
| **P3 (Minor)** | Style, naming, DRY violation, documentation | Comment to discuss, no block |
| **P4 (Nit)** | Personal preference, micro-optimization | Optional suggestion |

**Reviewer convention** — prefix comment with severity + rule ID:
- `[P0][CORE-NUM-001]` — Blocker with rule reference
- `[P1][MVC-TX-001]` — Critical
- `[P2][XCT-TST-003]` — Major
- `[P3][CORE-LOG-004]` — Minor
- `[P4]` — Nit (rule ID optional)
- `[NIT]` — short form for P4
- `[Q]` — clarification question (not an issue)
- `[PRAISE]` — call out good practice (positive feedback matters)

---

# 8. Rule ID Catalog

## Core Java (`CORE-*`)
- `CORE-NUL` — Null handling (4 rules)
- `CORE-EQH` — Equality & Hashing (4 rules)
- `CORE-NUM` — Numeric & Money (4 rules)
- `CORE-EXC` — Exceptions (5 rules)
- `CORE-RES` — Resource management (2 rules)
- `CORE-IMM` — Immutability (3 rules)
- `CORE-COL` — Collections & Streams (5 rules)
- `CORE-CON` — Concurrency (4 rules)
- `CORE-LOG` — Logging (5 rules)
- `CORE-API` — API Design (5 rules)

## Spring MVC (`MVC-*`)
- `MVC-CTL` — Controller (5 rules)
- `MVC-VAL` — Validation (3 rules)
- `MVC-RSP` — Response (2 rules)
- `MVC-SVC` — Service Layer (4 rules)
- `MVC-REP` — Repository (4 rules)
- `MVC-TX` — Transaction (4 rules)
- `MVC-CFG` — Configuration (3 rules)
- `MVC-EXC` — Exception Handling (3 rules)
- `MVC-SEC` — Security (3 rules)

## Reactor (`RX-*`)
- `RX-FND` — Fundamentals (3 rules)
- `RX-OPS` — Operators (4 rules)
- `RX-SCH` — Schedulers (3 rules)
- `RX-CTX` — Context (2 rules)
- `RX-SUB` — Subscription (2 rules)
- `RX-PIT` — Pitfalls (5 rules)
- `RX-TST` — Testing (3 rules)

## WebFlux (`WFL-*`)
- `WFL-CTL` — Controller (2 rules)
- `WFL-REP` — Repository R2DBC (4 rules)
- `WFL-TX` — Transaction (3 rules)
- `WFL-WC` — WebClient (5 rules)
- `WFL-SRV` — Server (2 rules)
- `WFL-SEC` — Security (2 rules)
- `WFL-EXC` — Exception (2 rules)
- `WFL-PIT` — Pitfalls (4 rules)

## Cross-cutting (`XCT-*`)
- `XCT-IDM` — Idempotency (1 rule)
- `XCT-OBS` — Observability (3 rules)
- `XCT-TST` — Testing (5 rules)
- `XCT-DOC` — Documentation (3 rules)
- `XCT-DEP` — Dependency (3 rules)

## Jackson (`JKS-*`)
- `JKS-OBJ` — ObjectMapper lifecycle (4 rules)
- `JKS-MOD` — Module registration (4 rules)
- `JKS-ANN` — Annotations (9 rules)
- `JKS-POL` — Polymorphism (4 rules — `JKS-POL-002`/`JKS-POL-003` = P0 RCE prevention)
- `JKS-TIM` — Date/Time (6 rules)
- `JKS-MNY` — Money/BigDecimal (4 rules — `JKS-MNY-001` = P0 fintech)
- `JKS-STR` — Streaming (3 rules)
- `JKS-ERR` — Error handling (4 rules)
- `JKS-SEC` — Security (6 rules)
- `JKS-PRF` — Performance (5 rules)
- `JKS-SPR` — Spring integration (5 rules)
- `JKS-REC` — Records (4 rules)
- `JKS-TST` — Testing (4 rules)
- `JKS-VER` — Versioning (3 rules)
- `JKS-PIT` — Anti-patterns recap (catalog)

Full bodies in `rules/java/code-review-jackson.md`.

## Related

- `rules/java/code-review-core.md` — CORE-* full bodies
- `rules/java/code-review-mvc.md` — MVC-* full bodies
- `rules/java/code-review-reactor.md` — RX-* full bodies
- `rules/java/code-review-webflux.md` — WFL-* full bodies
- `rules/java/code-review-jackson.md` — JKS-* full bodies (Jackson — RCE + fintech BigDecimal)
- `skills/coding-standards/SKILL.md` — unified code-review enforcement
- `agents/code-quality-reviewer.md` — enforces rule ID citation
- `commands/dc-review.md` — runs full review with these rule sets
