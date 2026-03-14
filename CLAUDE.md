# CLAUDE.md — agent-skills

> Claude Code plugin for Java Spring WebFlux development.
> Skills, agents, commands, rules, and hooks — all loaded automatically.

---

## ⚠️ MANDATORY: Read WORKING_WORKFLOW.md FIRST

Every session MUST follow the **6-phase workflow** defined in `WORKING_WORKFLOW.md`.
No exceptions. No shortcuts.

---

## Tech Stack

Java 17+ · Spring Boot 3.x · Spring WebFlux (reactive) · Spring MVC (servlet)
R2DBC · JPA/Hibernate · PostgreSQL · MySQL · Redis · Kafka · RabbitMQ · gRPC
Lombok · Jackson · MapStruct · Resilience4j · Docker · Gradle · JUnit 5 · Testcontainers

## Architecture

| Pattern | Role |
|---------|------|
| **Hexagonal Architecture** | Primary structure — ports & adapters |
| **CQRS** | Separate command/query models |
| **DDD** | Domain-driven design with bounded contexts |
| **Event Sourcing** | Event-driven state management (where applicable) |

---

## Workflow Enforcement 🚨

These rules are NON-NEGOTIABLE:

| Violation | Action |
|-----------|--------|
| Writing code without `/plan` | **STOP** → run `/plan` first (exception: <5 line fixes) |
| Skipping tests | **BLOCK** — no code ships without tests |
| `.block()` in reactive code | **CRITICAL** — must fix immediately |
| Agent attempts git commit | **FORBIDDEN** — only user commits after final review |

---

## Key Conventions

### Code Style
- **Immutability ALWAYS** — builders, records, `@Value`, no setters
- **Reactive chains** — `Mono`/`Flux`, NEVER `.block()`
- **Constructor injection only** — `@RequiredArgsConstructor`, no `@Autowired` on fields
- **Small units** — methods ≤50 lines, classes ≤400 lines (800 max)
- **No god classes** — single responsibility per class

### Naming
- Test methods: `shouldDoXWhenY` (e.g., `shouldReturnOrderWhenIdExists`)
- Use cases: `CreateOrderUseCase`, `GetOrderQuery`
- Events: `OrderCreatedEvent`, `PaymentProcessedEvent`

### Package Structure (Hexagonal)
```
com.example.{service}/
├── domain/           # Entities, value objects, domain events, repository interfaces (ports)
├── application/      # Use cases, services, command/query handlers
├── infrastructure/   # Repository impls (adapters), Kafka, gRPC, external clients
└── interfaces/       # Controllers, REST handlers, event listeners
```

### Testing
- **80%+ coverage** minimum (enforced via JaCoCo)
- **StepVerifier** for all reactive tests
- **Testcontainers** for integration tests (PostgreSQL, Redis, Kafka)
- Test data via factory methods, not random/hardcoded values

---

## Available Resources

### Skills (`skills/`)
| Skill | Purpose |
|-------|---------|
| `api-design` | RESTful and reactive API design — URL conventions, error handling, pagination |
| `backend-patterns` | RESTful API, DB optimization, messaging patterns |
| `blackbox-test` | JSON-driven black box integration tests |
| `coding-standards` | KISS, DRY, SOLID, readability |
| `continuous-learning-v2` | Instinct-based learning with confidence scoring |
| `grpc-patterns` | gRPC service patterns — protobuf, streaming, error handling |
| `hexagonal-arch` | Hexagonal architecture patterns |
| `java-patterns` | Java 17+ best practices |
| `kafka-patterns` | Kafka producer/consumer, exactly-once, reactive Kafka, DLT |
| `mysql-patterns` | MySQL optimization, indexing, JPA best practices, connection pooling |
| `observability-patterns` | Micrometer, distributed tracing, structured logging, alerting |
| `postgres-patterns` | PostgreSQL optimization, indexing, RLS |
| `project-guidelines` | Reads project-root `PROJECT_GUIDELINES.md` |
| `rabbitmq-patterns` | RabbitMQ exchanges, queues, DLQ, Spring AMQP patterns |
| `redis-patterns` | Redis caching, distributed locks, rate limiting |
| `security-review` | OWASP Top 10, secrets, auth |
| `solution-design` | Architecture documentation |
| `spring-mvc-patterns` | Spring MVC patterns — controllers, exception handlers, validation |
| `spring-webflux-patterns` | Spring WebFlux reactive patterns — Mono/Flux chains, backpressure, WebClient |
| `strategic-compact` | Context-efficient `/compact` suggestions |
| `tdd-workflow` | Write-tests-first TDD enforcement |
| `verification-loop` | Multi-phase build/test/security verification |

### Agents (`agents/`)
| Agent | Purpose |
|-------|---------|
| `architect` | Backend architecture — WebFlux, CQRS, DDD |
| `blackbox-test-runner` | Generates E2E API tests |
| `build-error-resolver` | Fixes Gradle/compile errors with minimal diffs |
| `code-reviewer` | Quality + security code review |
| `database-reviewer` | PostgreSQL/MySQL schema, queries, JPA optimization |
| `e2e-runner` | E2E testing with Testcontainers |
| `mysql-reviewer` | MySQL-specific review — indexes, JPA N+1, connection pool |
| `performance-reviewer` | Performance bottlenecks, memory leaks, slow queries |
| `planner` | Feature/architecture/refactor planning |
| `rabbitmq-reviewer` | RabbitMQ config, message handling, DLQ setup |
| `refactor-cleaner` | Dead code removal |
| `security-reviewer` | Security vulnerability detection |
| `spring-boot-reviewer` | DI, config, auto-configuration review |
| `spring-mvc-reviewer` | Spring MVC patterns, servlet filters, exception handlers |
| `spring-webflux-reviewer` | Reactive patterns, backpressure review |
| `tdd-guide` | TDD enforcement specialist |

### Commands (`commands/`)
| Command | Purpose |
|---------|---------|
| `/plan` | Restate requirements → risk assessment → implementation plan |
| `/verify` | Gradle build → compile → tests → security scan |
| `/quality-gate` | Final quality check before PR — all reviewers + coverage |
| `/code-review` | Comprehensive review of uncommitted changes |
| `/build-fix` | Incrementally fix build errors |
| `/checkpoint` | Create/verify workflow checkpoint |
| `/adr` | Create Architecture Decision Record for key decisions |
| `/db-migrate` | Generate and validate Flyway migration workflow |
| `/api-doc` | Generate/update OpenAPI spec from controllers |
| `/e2e` | Generate + run E2E tests |
| `/eval` | Eval-driven development |
| `/evolve` | Cluster instincts into skills/commands/agents |
| `/instinct-status` | Show learned instincts with confidence |
| `/instinct-export` | Export instincts for team sharing |
| `/instinct-import` | Import instincts from teammates |
| `/learn` | Extract patterns from current session |
| `/orchestrate` | Sequential multi-agent workflow |
| `/refactor-clean` | Identify + remove dead code |
| `/skill-create` | Generate SKILL.md from git history |

### Contexts (`contexts/`)
Behavioral injection files — load with `/load contexts/<name>.md` to change Claude's operating mode:
| Context | When to Use |
|---------|-------------|
| `dev.md` | Active coding — code-first, minimal explanation, TDD loop |
| `review.md` | Code review — severity classification, thorough analysis |
| `research.md` | Investigation — root cause analysis, architecture evaluation |

### Rules (`rules/`)
`agents` · `coding-style` · `git-workflow` · `hooks` · `patterns` · `performance` · `security` · `testing`

### Hooks (`scripts/hooks/`)
`session-start` · `session-end` · `pre-compact` · `suggest-compact` · `evaluate-session` · `java-compile-check` · `java-format` · `check-debug-statements`

---

## Memory (Cross-Session Context)

If `claude-mem` is available, it provides cross-session memory:
- Learned patterns persist between sessions
- Instincts (via `continuous-learning-v2`) accumulate with confidence scores
- Use `/instinct-status` to see what's been learned
- Use `/evolve` to promote high-confidence instincts to skills

---

## Quick Reference

```
/plan              → Start here. Always. Plan before code.
/verify            → Run after implementation. Build + test + security.
/code-review       → Before asking user to commit.
/build-fix         → When Gradle/compile fails.
/checkpoint        → Mark workflow phase completion.
/e2e               → Generate E2E integration tests.
/orchestrate       → Complex tasks needing multiple agents.
```

### Common Build Commands
```bash
./gradlew clean build          # Full build
./gradlew test                 # Run tests
./gradlew spotlessApply        # Format code
./gradlew jacocoTestReport     # Coverage report
./gradlew dependencyCheckAnalyze  # Security scan
```

---

## Project-Specific Guidelines

If `PROJECT_GUIDELINES.md` exists at the project root, **read it first**.
It overrides generic conventions with project-specific rules.
See `templates/PROJECT_GUIDELINES_TEMPLATE.md` for the standard template.

---

## Critical Rules Summary

### 🔴 NEVER
1. `.block()` in reactive code
2. `@Autowired` field injection
3. Expose entities in API responses (use DTOs)
4. Log sensitive data (PII, credentials)
5. Commit secrets to git
6. Skip input validation
7. `SELECT *` in queries
8. Deploy without migrations
9. Write code without `/plan`
10. Commit on behalf of user

### 🟢 ALWAYS
1. Constructor injection (`@RequiredArgsConstructor`)
2. Bean Validation on API boundaries
3. Records for immutable DTOs
4. `StepVerifier` for reactive tests
5. 80%+ test coverage
6. Follow the 6-phase workflow
7. Domain exceptions (not generic `RuntimeException`)
8. Parameterized queries
9. Indexes for frequently queried columns
10. Structured logging with context
