# CLAUDE.md — agent-skills

> Claude Code plugin for Java Spring backend development.
> Agent = Model + Harness. This file is the harness entry point.

If `PROJECT_GUIDELINES.md` exists at project root, read it FIRST — it overrides conventions below.

## How This Plugin Works

You are enhanced with **skills, hooks, and agents**. The bootstrap skill (`skills/bootstrap/SKILL.md`) loads automatically at session start and teaches you the full workflow. Trust the harness — it handles skill discovery, verification loops, context management, and observability for you.

**Your responsibilities**: follow the 5-phase workflow, announce skills before use, never skip VERIFY + REVIEW, never self-assess (only external verification counts).

## Tech Stack

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC · R2DBC · JPA/Hibernate · PostgreSQL · MySQL · Redis · Kafka · RabbitMQ · Lombok · Jackson · MapStruct · Resilience4j · Gradle · JUnit 5 · Testcontainers

**Architecture:** Hexagonal (Ports & Adapters) · CQRS · DDD · Event Sourcing

## Code Conventions

- **Immutability** — records, `@Value`, builders. No setters.
- **Reactive** — `Mono`/`Flux` chains. NEVER `.block()`.
- **DI** — Constructor injection (`@RequiredArgsConstructor`). No `@Autowired` on fields.
- **Size** — methods ≤50 lines, classes ≤400 lines (800 max).
- **DTOs** — Records for immutable DTOs. Never expose entities in API responses.
- **Imports** — Always `import` statements. Never inline fully-qualified class names.

## Naming

Tests: `shouldDoXWhenY` · Use cases: `CreateOrderUseCase`, `GetOrderQuery` · Events: `OrderCreatedEvent`

## Package Structure (Hexagonal)

```
com.example.{service}/
├── domain/           # Entities, value objects, domain events, repository ports
├── application/      # Use cases, services, command/query handlers
├── infrastructure/   # Adapters: DB, Kafka, gRPC, external HTTP
└── interfaces/       # Controllers, REST handlers, event listeners
```

## Workflow — 5 Phases (Non-Negotiable)

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

Skip condition: ≤5 lines AND 1 file AND no new behavior → BUILD directly.
After BUILD: VERIFY runs automatically → if fail, verify/fix loop retries → REVIEW runs automatically.
**A task is NOT complete until REVIEW passes.** See bootstrap SKILL.md for full workflow rules.

## Hard Blocks

1. `.block()` in reactive code → CRITICAL, fix immediately
2. `@Autowired` field injection → use `@RequiredArgsConstructor`
3. Expose entities in API → use record DTOs
4. Log sensitive data (PII, credentials, tokens)
5. Commit secrets to git
6. Skip input validation on API boundaries
7. `SELECT *` in queries → explicit column selection
8. Write code without `/plan` + `/spec` (except trivial ≤5-line fixes)
9. Agent commits to git → FORBIDDEN, only user commits
10. Stop after BUILD without VERIFY + REVIEW → FORBIDDEN

## Always

1. Constructor injection (`@RequiredArgsConstructor`)
2. Bean Validation on API boundaries (`@Valid`)
3. Records for immutable DTOs
4. `StepVerifier` for reactive tests
5. Domain exceptions (not generic `RuntimeException`)
6. Parameterized queries (never string concatenation)
7. Structured logging with MDC context
8. 80%+ test coverage (JaCoCo)
9. Announce skill before use: "Using skill: {name} for {reason}"
10. Drive workflow to completion — never stop at BUILD

## Harness Awareness

- **Hooks** enforce rules automatically — quality gates, skill routing, verify/fix loops, context budget, observability traces. You don't need to manage these manually.
- **Context budget** is monitored. Act on compact-advisor warnings promptly.
- **State lives on disk**, not in context: `workflow-state.json`, `verify-fix-state.json`, `build-checkpoint.json`, `session-metrics.json`. Read from disk when resuming.
- **Verification is external**: tests, compile, lint determine pass/fail. Never trust self-assessment.
