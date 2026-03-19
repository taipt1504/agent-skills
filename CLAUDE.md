# CLAUDE.md — agent-skills

> Claude Code plugin for Java Spring backend development.

If `PROJECT_GUIDELINES.md` exists at project root, read it FIRST — it overrides conventions below.

## Tech Stack

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC
R2DBC · JPA/Hibernate · PostgreSQL · MySQL · Redis · Kafka · RabbitMQ
Lombok · Jackson · MapStruct · Resilience4j · Gradle · JUnit 5 · Testcontainers

**Architecture:** Hexagonal (Ports & Adapters) · CQRS · DDD · Event Sourcing

## Code Conventions

- **Immutability** — records, `@Value`, builders. No setters.
- **Reactive** — `Mono`/`Flux` chains. NEVER `.block()`.
- **DI** — Constructor injection (`@RequiredArgsConstructor`). No `@Autowired` on fields.
- **Size** — methods ≤50 lines, classes ≤400 lines (800 max).
- **DTOs** — Records for immutable DTOs. Never expose entities in API responses.
- **Imports** — Always `import` statements. Never inline fully-qualified class names.

## Naming

- Tests: `shouldDoXWhenY` (e.g., `shouldReturnOrderWhenIdExists`)
- Use cases: `CreateOrderUseCase`, `GetOrderQuery`
- Events: `OrderCreatedEvent`, `PaymentProcessedEvent`

## Package Structure (Hexagonal)

```
com.example.{service}/
├── domain/           # Entities, value objects, domain events, repository ports
├── application/      # Use cases, services, command/query handlers
├── infrastructure/   # Adapters: DB, Kafka, gRPC, external HTTP
└── interfaces/       # Controllers, REST handlers, event listeners
```

## NEVER

1. `.block()` in reactive code
2. `@Autowired` field injection
3. Expose entities in API responses
4. Log sensitive data (PII, credentials, tokens)
5. Commit secrets to git
6. Skip input validation
7. `SELECT *` in queries
8. Write code without `/plan` + `/spec` (exception: ≤5 line trivial fixes)
9. Commit on behalf of user

## ALWAYS

1. Constructor injection (`@RequiredArgsConstructor`)
2. Bean Validation on API boundaries (`@Valid`)
3. Records for immutable DTOs
4. `StepVerifier` for reactive tests
5. Domain exceptions (not generic `RuntimeException`)
6. Parameterized queries (never string concatenation)
7. Structured logging with MDC context
8. 80%+ test coverage (JaCoCo)
