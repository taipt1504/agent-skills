# CLAUDE.md — agent-skills

> Claude Code plugin for Java Spring WebFlux development.

---

## Project-Specific Guidelines (PRIORITY)

If `PROJECT_GUIDELINES.md` exists at the project root, read it FIRST.
It overrides all generic conventions below.

---

## First-Time Setup (After Plugin Install)

After running `claude plugin add devco-agent-skills@devco-agent-skills`, run `/setup` **once**
to make rules auto-load in every session across all projects:

```
/setup
```

Or from the terminal:
```bash
bash ~/.claude/plugins/cache/devco-agent-skills/scripts/setup.sh
```

For a new project, also install project-level rules:
```bash
bash ~/.claude/plugins/cache/devco-agent-skills/scripts/setup.sh --project
```

---

## Mandatory Workflow

Every session follows the SDD (Spec-Driven Design) 7-phase workflow. No exceptions.

```
BOOT → PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW → LEARN
```

Full details: [WORKING_WORKFLOW.md](./WORKING_WORKFLOW.md)

**Phase Decision:** If ALL true (≤5 lines, 1 file, no new behavior, no arch impact) → BUILD directly. Otherwise → `/plan` → `/spec` → BUILD. When in doubt → `/plan` first.

### Enforcement (non-negotiable)

| Violation | Action |
|-----------|--------|
| Writing code without `/plan` | STOP → run `/plan` first (exception: ≤5 line fixes) |
| Writing code without approved spec | STOP → run `/spec` first (exception: ≤5 line fixes, no new behavior) |
| Skipping tests | BLOCK — no code ships without tests |
| `.block()` in reactive code | CRITICAL — must fix immediately |
| Agent attempts git commit | FORBIDDEN — only user commits |

**TDD Cycle:** RED (write failing test) → GREEN (minimal impl) → REFACTOR (clean up) → `/checkpoint`

---

## Tech Stack

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC
R2DBC · JPA/Hibernate · PostgreSQL · MySQL · Redis · Kafka · RabbitMQ · gRPC
Lombok · Jackson · MapStruct · Resilience4j · Docker · Gradle · JUnit 5 · Testcontainers

**Architecture:** Hexagonal (Ports & Adapters) · CQRS · DDD · Event Sourcing

---

## Key Conventions

### Code Style
- Immutability ALWAYS — builders, records, `@Value`, no setters
- Reactive chains — `Mono`/`Flux`, NEVER `.block()`
- Constructor injection only — `@RequiredArgsConstructor`, no `@Autowired` on fields
- Small units — methods ≤50 lines, classes ≤400 lines (800 max)

### Naming
- Test methods: `shouldDoXWhenY` (e.g., `shouldReturnOrderWhenIdExists`)
- Use cases: `CreateOrderUseCase`, `GetOrderQuery`
- Events: `OrderCreatedEvent`, `PaymentProcessedEvent`

### Package Structure (Hexagonal)
```
com.example.{service}/
├── domain/           # Entities, value objects, domain events, repository interfaces
├── application/      # Use cases, services, command/query handlers
├── infrastructure/   # Repository impls, Kafka, gRPC, external clients
└── interfaces/       # Controllers, REST handlers, event listeners
```

### Testing
- 80%+ coverage minimum (JaCoCo)
- `StepVerifier` for all reactive tests
- Testcontainers for integration tests (PostgreSQL, Redis, Kafka)
- Test data via factory methods, not random/hardcoded values

---

## Critical Rules

### NEVER
1. `.block()` in reactive code
2. `@Autowired` field injection
3. Expose entities in API responses (use DTOs)
4. Log sensitive data (PII, credentials)
5. Commit secrets to git
6. Skip input validation
7. `SELECT *` in queries
8. Inline fully-qualified class names — use `import` statements, never `java.util.List<com.example.Order>`
9. Write code without `/plan` + `/spec`
10. Commit on behalf of user

### ALWAYS
1. Constructor injection (`@RequiredArgsConstructor`)
2. Bean Validation on API boundaries
3. Records for immutable DTOs
4. `StepVerifier` for reactive tests
5. Domain exceptions (not generic `RuntimeException`)
6. Parameterized queries
7. Structured logging with context
8. 80%+ test coverage

---

## Quick Reference

```
/plan              → Start here. Plan before code.
/spec              → After /plan. Define contracts before code.
/verify            → Run after implementation (quick/full/gate modes).
/code-review       → Before asking user to commit.
/build-fix         → When Gradle/compile fails.
/checkpoint        → Mark workflow phase completion.
/mcp-setup         → Configure MCP servers.
/save-session      → Persist current context for next session.
/resume-session    → Load context from a previous session.
```

## Compaction Preservation

When compacting, always preserve: current workflow phase, last checkpoint,
modified files list, approved plan summary, approved spec summary, failing tests.
