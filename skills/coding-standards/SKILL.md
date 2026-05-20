---
name: coding-standards
description: >
  Unified Java code review + coding standards skill (alias "code-review"). Enforces ALL six rule sets —
  CORE-*, MVC-*, RX-*, WFL-*, XCT-*, JKS-* — across BUILD (REFACTOR self-check) and REVIEW (Stage 2
  findings). Every finding cites [<P0-P4>][<RULE-ID>]. Also encodes Java 17+ patterns (records, sealed,
  pattern matching), naming, Lombok, immutability, Optional/Stream rules. Use whenever Claude writes
  new Java code, reviews a diff, refactors, or audits style. MANDATORY TRIGGERS — Java, Spring Boot,
  Spring MVC, Spring WebFlux, Project Reactor, Jackson, ObjectMapper, @JsonProperty, @JsonCreator,
  @JsonTypeInfo, @JsonFormat, JSON, BigDecimal, money, @Transactional, R2DBC, JpaRepository, Mono, Flux,
  WebClient, code review, audit, refactor, REFACTOR step, /dc-review, /build.
triggers:
  natural: ["naming convention", "java pattern", "code style", "immutability", "records", "code review", "rule citation", "jackson", "json", "ObjectMapper"]
  code: ["*.java"]
  command: ["/dc-review", "/build"]
applicability:
  always: true
  triggers:
    files_match: ["**/*.java"]
    code_patterns: ["@Value", "@RequiredArgsConstructor", "record", "@Builder", "ObjectMapper", "@JsonProperty", "@JsonFormat", "@JsonCreator"]
    task_keywords: ["coding style", "code review", "immutability", "naming", "records", "Lombok", "jackson", "json", "BigDecimal"]
    related_rules:
      - rules/common/coding-style.md
      - rules/java/coding-style.md
      - rules/java/code-review-core.md
      - rules/java/code-review-mvc.md
      - rules/java/code-review-reactor.md
      - rules/java/code-review-webflux.md
      - rules/java/code-review-crosscut.md
      - rules/java/code-review-jackson.md
relevance_assessment: |
  Always 100% when project has Java files. Applies to every code change and every review.
---

# Coding Standards + Code Review — Unified Enforcement

> One skill, two phases. BUILD: self-check critical rule IDs during REFACTOR. REVIEW: surface findings tagged `[<severity>][<RULE-ID>]`. Detailed workflows live in `references/`.

## Rule sets enforced

| Prefix | File | Domain | Count |
|---|---|---|---|
| **CORE-*** | `rules/java/code-review-core.md` | Null · equality · money · exceptions · resources · immutability · collections · concurrency · logging · API design | ~41 |
| **MVC-*** | `rules/java/code-review-mvc.md` | Controller · validation · response · service · repository · transaction · config · exception · security (servlet stack) | ~31 |
| **RX-*** | `rules/java/code-review-reactor.md` | Operators · schedulers · context · subscription · pitfalls · testing | ~22 |
| **WFL-*** | `rules/java/code-review-webflux.md` | Reactive controller · R2DBC · transaction · WebClient · server · security · error handling | ~24 |
| **XCT-*** | `rules/java/code-review-crosscut.md` | Idempotency · observability · testing · docs · deps. + PR checklist + severity P0-P4 + full ID catalog | ~15 |
| **JKS-*** | `rules/java/code-review-jackson.md` | ObjectMapper · modules · annotations · polymorphism · date/time · BigDecimal · streaming · security · perf · Spring · records · testing · versioning | ~65 |

Total: **~198 rules**. Full catalog: `rules/java/code-review-crosscut.md §8` (+ JKS §17 in jackson file).

## Conditional load per stack

Stay token-efficient — load only relevant rule sets:

| Stack signal | Rule sets to load |
|---|---|
| Any Java diff | CORE + XCT (always) |
| `spring-boot-starter-web` + `JpaRepository` | + MVC |
| `Mono<` / `Flux<` in diff | + RX |
| `spring-boot-starter-webflux` | + RX + WFL |
| `ObjectMapper` / `@JsonProperty` / DTO with date or BigDecimal | + JKS (+ load `references/jackson-review-workflow.md`) |
| `io.f8a.summer` dep | + `rules/summer/*` |

`skills/preflight/references/gate-mappings.md` drives the selection at variants 4 (execute) and 5 (review).

## Detailed workflows — load on demand

| Reference | When to load | Content |
|---|---|---|
| **`references/review-workflow.md`** | Stage 2 review · BUILD REFACTOR self-check · `/dc-review` invocation | Priority-ordered scan across ALL 6 rule sets · output format · verdict logic · severity policy |
| **`references/jackson-review-workflow.md`** | Diff touches Jackson (`ObjectMapper`, `@Json*`, DTO with BigDecimal/date) | Jackson-specific priority scan · output format · context-specific guidance (payment / SIMO / Kafka / REST) · workflow examples |
| **`references/java-patterns.md`** | Writing new Java code · refactoring patterns | Immutability (records, builders, defensive copies) · null safety (Optional patterns) · concurrency · collections · streams. Pattern → rule ID map. |

Read these only when needed — keep main context clean.

## BUILD phase — REFACTOR self-check

Slice-executor verifies these critical IDs before declaring a slice done. Full priority-ordered scan in `references/review-workflow.md`.

### Always (any Java)

- `CORE-NUM-001` — no `double`/`float` for money. BigDecimal only.
- `CORE-LOG-002` — no sensitive data in logs (password, OTP, full PAN, CVV, JWT, full national ID).
- `CORE-EXC-004` — service boundary wraps `IOException`/`SQLException` to business exception.
- `CORE-API-001` — method ≤ 50 LOC, class ≤ 400 LOC (800 abs max).

### MVC stack

- `MVC-TX-001` — no HTTP call inside `@Transactional`.
- `MVC-TX-002` — Kafka publish uses outbox pattern (same TX as DB).
- `MVC-VAL-001` — `@Valid` on `@RequestBody`.
- `MVC-REP-004` — N+1 query check (entity graph / fetch join).

### Reactive

- `RX-FND-001` — no `.block()` in reactive chain.
- `RX-OPS-002` — `switchIfEmpty(Mono.defer(...))`, not direct `Mono.error()`.
- `WFL-WC-002` — explicit timeouts on `WebClient`.

### Jackson (load `references/jackson-review-workflow.md` for full scan)

- `JKS-OBJ-001` — no `new ObjectMapper()` in service body. Inject from Spring.
- `JKS-MOD-001` — `JavaTimeModule` registered when using `java.time.*`.
- `JKS-MNY-001` — BigDecimal serialized as string (`@JsonFormat(shape = STRING)` or `WRITE_BIGDECIMAL_AS_PLAIN`). **Fintech-critical.**
- `JKS-POL-002` / `JKS-POL-003` — no `JsonTypeInfo.Id.CLASS`; no `enableDefaultTyping()` without validator. **RCE prevention.**
- `JKS-ANN-003` — passwords/secrets `@JsonIgnore` or `WRITE_ONLY`.
- `JKS-PRF-002` — `TypeReference` for generic deserialize.

### Cross-cutting

- `XCT-IDM-001` — `Idempotency-Key` for mutation endpoint.

Cite enforced IDs in the slice result report and commit body (see `agents/slice-executor.md`).

## REVIEW phase — Stage 2 findings

Every finding has format `[<P0-P4>][<RULE-ID>]`. Missing rule ID = invalid output, orchestrator rejects and re-dispatches.

### Common citation patterns

| Pattern | Rule | Severity |
|---|---|---|
| `double` for money | `CORE-NUM-001` | P0 |
| Sensitive data in log | `CORE-LOG-002` | P0 |
| `JsonTypeInfo.Id.CLASS` (RCE) | `JKS-POL-002` | P0 |
| `enableDefaultTyping()` (RCE) | `JKS-POL-003` | P0 |
| BigDecimal as JSON number | `JKS-MNY-001` | P0 |
| Password serialized | `JKS-ANN-003` | P0 |
| HTTP inside `@Transactional` | `MVC-TX-001` | P1 |
| `.block()` in reactive | `RX-FND-001` | P1 |
| `new ObjectMapper()` per call | `JKS-OBJ-001` | P1 |
| N+1 query | `MVC-REP-004` | P1 |
| Silent swallow `JsonProcessingException` | `JKS-ERR-001` | P2 |
| Unstructured log | `CORE-LOG-004` | P3 |

### Verdict logic (per `rules/java/code-review-crosscut.md §7`)

- Any **P0**, or **P1 without ADR** → **Block**
- P1 with ADR, or P2 only → **Approve with caveats**
- P3/P4 only → **Approve**

Detailed dispatch and output format live in `references/review-workflow.md`.

## Coding patterns — quick reference

Apply when **writing** code. The same patterns drive REFACTOR self-check (citing the corresponding rule IDs).

### Java 17+

- **Records** — DTO, value objects, events. Compact constructor for validation. Not for JPA entities or Spring beans. Records work natively with Jackson 2.12+ (`JKS-REC-001`).
- **Sealed classes** — exhaustive type hierarchies. Combine with Jackson sealed support (`JKS-POL-004`, `JKS-REC-004`).
- **Pattern matching `instanceof`** — `if (event instanceof OrderCreatedEvent e)`.
- **Switch expressions**, **text blocks** — prefer over chained `if-else` and string concat.

### Naming

| Element | Convention | Example |
|---|---|---|
| Class | PascalCase | `OrderService` |
| Method | camelCase, verb-first | `createOrder()` |
| Test | shouldDoXWhenY | `shouldReturnOrderWhenIdExists()` |
| Constant | UPPER_SNAKE_CASE | `MAX_RETRY_ATTEMPTS` |
| Boolean | is/has/can prefix | `isActive()` |
| Exception | Descriptive + `Exception` suffix | `OrderNotFoundException` |

### Lombok

| Annotation | Use | Avoid |
|---|---|---|
| `@RequiredArgsConstructor` | Spring beans | DTOs (records are better) |
| `@Value` | Immutable non-record (JPA entities) | Where record fits |
| `@Builder(toBuilder=true)` | ≥3-field construction | 1-2 field objects |
| `@Slf4j` | Any class that logs | — |

Never `@Data` — generates setters and violates immutability.

```java
public record CreateOrderRequest(@NotBlank String productId, @Positive int quantity) {}

@Service @RequiredArgsConstructor @Slf4j
public class OrderService {
    private final OrderRepository orderRepository;
}
```

### Immutability (`CORE-IMM-001..003`)

- Final fields by default.
- Records + `@Builder(toBuilder = true)` + `@With` for new-instance updates.
- Defensive copies: `List.copyOf(items)` in constructor and getter.
- Never mutate inside reactive chains — transform with `.map()`.

### Optional & streams

- Optional: return type only. Never field, parameter, or collection element (`CORE-NUL-002`).
- Streams: filter early. Primitive streams for numerics. No side effects in map/filter (`CORE-COL-002`). Collect to unmodifiable (`CORE-COL-004`). Never `parallelStream()` without benchmark (`CORE-COL-003`).

### Error handling

- Domain exception extends `RuntimeException` with an `ErrorCode` enum (`CORE-EXC-004` / `CORE-EXC-005`).
- Specific exceptions: `OrderNotFoundException`, `InsufficientStockException`.
- Never generic `RuntimeException`. No empty catch blocks (`CORE-EXC-002`).
- Reactive: `switchIfEmpty(Mono.error(...))`, `onErrorMap()`, `onErrorResume()` (`RX-OPS-002` / `RX-OPS-003`).

Code-pattern depth lives in `references/java-patterns.md`.

## Skill announcement

When loading this skill, announce:

```
Skill loaded: coding-standards (unified code-review enforcement)
Rule sets active: CORE, XCT [+ MVC if MVC] [+ RX/WFL if reactive] [+ JKS if Jackson DTO/ObjectMapper]
References ready: review-workflow.md, jackson-review-workflow.md (if Jackson), java-patterns.md
Total rule IDs available: ~198
Citation format: [<P0-P4>][<RULE-ID>]
```

## Related rules

- `rules/java/code-review-core.md` — CORE-* foundation (always for Java)
- `rules/java/code-review-mvc.md` — MVC-* (servlet stack)
- `rules/java/code-review-reactor.md` — RX-* (reactive)
- `rules/java/code-review-webflux.md` — WFL-* (WebFlux)
- `rules/java/code-review-crosscut.md` — XCT-* + PR checklist §6 + severity P0-P4 §7 + rule catalog §8
- `rules/java/code-review-jackson.md` — JKS-* (Jackson — fintech BigDecimal + RCE prevention)
- `rules/java/coding-style.md` — Lombok, DI, error handling shorthand
- `rules/common/coding-style.md` — common style conventions

## Related skills

- **spring-mvc-patterns** — servlet stack patterns
- **spring-webflux-patterns** — reactive patterns
- **architecture** — hexagonal layer rules
- **testing-workflow** — TDD cycle, test naming
- **pentest** — OWASP scanning (pairs with `JKS-POL-*` / `JKS-SEC-*` for deserialization CVE)
