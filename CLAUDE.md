# CLAUDE.md — agent-skills

> Claude Code plugin for Java Spring WebFlux development.
> Skills, agents, commands, rules, and hooks — all loaded automatically.

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

## Workflow — 7 Phases (NON-NEGOTIABLE)

Every session follows these phases without exception. Full reference: `WORKING_WORKFLOW.md`.

### Phases

| # | Phase | Trigger | Key Output |
|---|-------|---------|------------|
| ① | **BOOT** | Session start (automatic) | Project type detected, guidelines + memory loaded |
| ② | **PLAN** | Non-trivial task → `/plan` | Implementation plan → ⏸️ **wait for user confirm** |
| ③ | **SPEC** | Plan confirmed → `/spec` | Behavioral contracts + test scenarios → ⏸️ **wait for user approve** |
| ④ | **BUILD** | Spec approved → TDD per step | Failing test → implementation → passing test → `/checkpoint` |
| ⑤ | **VERIFY** | All steps done → `/verify` | Build + tests (≥80%) + reactive safety + security scan |
| ⑥ | **REVIEW** | Verify passes → `/code-review` | Multi-agent review → APPROVE / WARN / BLOCK |
| ⑦ | **LEARN** | Session end (automatic) | Patterns + instincts saved to claude-mem |

### Phase Decision — Trivial vs Non-Trivial

```
New task received
  ├── ALL true: ≤5 lines, 1 file, no new behavior, no arch impact → BUILD directly (skip PLAN+SPEC)
  └── ANY false → /plan → confirm → /spec → approve → BUILD
When in doubt → /plan first.
```

### Hard Blocks — Non-Negotiable

| Violation | Response |
|-----------|----------|
| Writing code without `/plan` approval | **STOP** — run `/plan`, wait for user confirm |
| Writing code without `/spec` approval | **STOP** — run `/spec`, wait for user approve |
| Skipping tests | **BLOCK** — write the test first, always |
| `.block()` anywhere in `src/main/` | **CRITICAL** — stop everything, fix now |
| Agent runs `git commit` | **FORBIDDEN** — user is the only one who commits |

### TDD Cycle (Phase ④, per step)

```
RED:      Write test from spec scenario → run → confirm FAILS
GREEN:    Write minimal implementation → run → confirm PASSES
REFACTOR: Clean up, rename, extract → run → still PASSES
          → /checkpoint create "step-N-done"
```

### Reactive Safety Rules (`src/main/` only)

| Forbidden | Fix |
|-----------|-----|
| `.block()` | Chain with `flatMap` / `then` / `zip` |
| `Thread.sleep()` | `Mono.delay()` / `StepVerifier.withVirtualTime()` |
| `.subscribe()` inside a chain | `flatMap` / `concatWith` / `then` |
| `Mono.just(blockingCall())` | `Mono.fromCallable(() -> blockingCall()).subscribeOn(Schedulers.boundedElastic())` |

### Verification Gates (`/verify`)

```
Build clean → Compile zero errors → Tests 100% pass + ≥80% coverage
  → No .block()/.sleep() in src/main/ → No hardcoded secrets → No debug prints
  → Diff review (only planned files changed)
All gates must be GREEN before REVIEW phase begins.
```

### Review Chain (`/code-review`)

Always: `code-reviewer` + `security-reviewer`
Conditional:
- WebFlux / reactive code changed → `spring-webflux-reviewer`
- Config / Spring beans changed → `spring-reviewer`
- Repository / SQL / migration changed → `database-reviewer`
- New packages / DDD boundaries → `architect`

Verdict: ✅ APPROVE → deliver · ⚠️ WARNING → deliver with notes · ❌ BLOCK → fix then re-verify + re-review

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
| Writing code without approved spec | **STOP** → run `/spec` first (exception: ≤5 line fixes, no new behavior) |
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
| `blackbox-test` | JSON-driven black box integration tests |
| `continuous-learning-v2` | Instinct-based learning with confidence scoring |
| `database-migrations` | Zero-downtime migrations — Flyway, expand-contract, Testcontainers validation |
| `grpc-patterns` | gRPC service patterns — protobuf, streaming, error handling |
| `hexagonal-arch` | Hexagonal architecture patterns |
| `java-patterns` | Java 17+ best practices |
| `java-standards` | Java 17+ coding standards — KISS/DRY/SOLID, records, sealed classes, naming, Optional, Streams |
| `jpa-patterns` | JPA/Hibernate — entity design, N+1 prevention, HikariCP, pagination |
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
| `springboot-patterns` | REST controllers, pagination, caching, async, rate limiting, production defaults |
| `springboot-security` | JWT filter, SecurityFilterChain, CORS, secrets management, OWASP scanning |
| `strategic-compact` | Context-efficient `/compact` suggestions |
| `tdd-workflow` | Write-tests-first TDD enforcement |
| `verification` | Verification pipeline — compile, test, coverage, security, static analysis, diff review |

### Agents (`agents/`)
| Agent | Purpose |
|-------|---------|
| `architect` | Backend architecture — WebFlux, CQRS, DDD |
| `blackbox-test-runner` | Generates E2E API tests |
| `build-error-resolver` | Fixes Gradle/compile errors with minimal diffs |
| `code-reviewer` | Language-level code review — readability, naming, complexity, algorithms |
| `database-reviewer` | PostgreSQL + MySQL — schema, queries, JPA, indexing, connection pooling |
| `e2e-runner` | E2E testing with Testcontainers |
| `performance-reviewer` | Performance bottlenecks, memory leaks, slow queries |
| `planner` | Feature/architecture/refactor planning |
| `rabbitmq-reviewer` | RabbitMQ config, message handling, DLQ setup |
| `refactor-cleaner` | Dead code removal |
| `security-reviewer` | Security vulnerability detection |
| `spring-reviewer` | Spring Boot + MVC — DI, controllers, validation, security, config, testing |
| `spring-webflux-reviewer` | Reactive patterns, backpressure review |
| `tdd-guide` | TDD enforcement specialist |

### Commands (`commands/`)
| Command | Purpose |
|---------|---------|
| `/plan` | Restate requirements → risk assessment → implementation plan |
| `/spec` | Define behavioral contracts (inputs, outputs, error cases) from approved plan |
| `/verify` | Build + compile + tests + security scan (modes: quick/full/gate) |
| `/code-review` | Comprehensive review of uncommitted changes |
| `/build-fix` | Incrementally fix build errors |
| `/checkpoint` | Create/verify workflow checkpoint |
| `/adr` | Create Architecture Decision Record for key decisions |
| `/db-migrate` | Generate and validate Flyway migration workflow |
| `/api-doc` | Generate/update OpenAPI spec from controllers |
| `/e2e` | Generate + run E2E tests |
| `/eval` | Eval-driven development |
| `/evolve` | Cluster instincts into skills/commands/agents |
| `/instinct` | Manage instincts — status, export, import (subcommands) |
| `/learn` | Extract patterns from current session |
| `/mcp-setup` | Guided MCP server setup — audit, token budget, install core/optional |
| `/orchestrate` | Sequential/parallel multi-agent workflow |
| `/refactor-clean` | Identify + remove dead code |
| `/resume-session` | Load context from a previous session file |
| `/save-session` | Manually persist current session context |
| `/skill-create` | Generate SKILL.md from git history |

### Contexts (`contexts/`)
Behavioral injection files — load with `/load contexts/<name>.md` to change Claude's operating mode:
| Context | When to Use |
|---------|-------------|
| `dev.md` | Active coding — code-first, minimal explanation, TDD loop |
| `review.md` | Code review — severity classification, thorough analysis |
| `research.md` | Investigation — root cause analysis, architecture evaluation |

### Rules (`rules/`)
**`common/`** (language-agnostic): `agents` · `development-workflow` · `git-workflow` · `hooks` · `patterns` · `performance` · `spec-driven`
**`java/`** (Java/Spring-specific): `api-design` · `coding-style` · `observability` · `reactive` · `security` · `testing`

### Hooks (`scripts/hooks/`)
`session-start` · `session-end` · `pre-compact` · `suggest-compact` · `evaluate-session` · `java-compile-check` · `java-format` · `check-debug-statements` · `cost-tracker` · `run-with-flags`

Hook profiles: `minimal` | `standard` (default) | `strict` — set via `HOOK_PROFILE` env var.

---

## Memory (Cross-Session Context)

If `claude-mem` is available, it provides cross-session memory:
- Learned patterns persist between sessions
- Instincts (via `continuous-learning-v2`) accumulate with confidence scores
- Use `/instinct status` to see what's been learned
- Use `/evolve` to promote high-confidence instincts to skills

---

## Quick Reference

```
/plan              → Start here. Always. Plan before code.
/spec              → After /plan. Define contracts before code.
/verify            → Run after implementation (quick/full/gate modes).
/code-review       → Before asking user to commit.
/build-fix         → When Gradle/compile fails.
/checkpoint        → Mark workflow phase completion.
/e2e               → Generate E2E integration tests.
/orchestrate       → Complex tasks needing multiple agents.
/mcp-setup         → Configure MCP servers for the stack.
/save-session      → Persist current context for next session.
/resume-session    → Load context from a previous session.
```

### CI Validation
```bash
bash scripts/ci/run-all.sh     # Validate all plugin structure
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
11. Write implementation code without approved spec

### 🟢 ALWAYS
1. Constructor injection (`@RequiredArgsConstructor`)
2. Bean Validation on API boundaries
3. Records for immutable DTOs
4. `StepVerifier` for reactive tests
5. 80%+ test coverage
6. Follow the 7-phase workflow
7. Domain exceptions (not generic `RuntimeException`)
8. Parameterized queries
9. Indexes for frequently queried columns
10. Structured logging with context
11. Run `/spec` after `/plan` for all non-trivial tasks
