# Agent Orchestration

## Available Agents

Located in `.claude/agents/`:

| Agent                       | Purpose                                         | When to Use                                    |
|-----------------------------|-------------------------------------------------|------------------------------------------------|
| **planner**                 | Implementation planning                         | Complex features, multi-step tasks             |
| **architect**               | Backend system design (CQRS, DDD, Hexagonal)    | Architectural decisions, microservices design  |
| **tdd-guide**               | Test-driven development (JUnit 5, StepVerifier) | New features, bug fixes                        |
| **code-reviewer**           | Language-level code review (readability, naming) | After writing any code                         |
| **spring-webflux-reviewer** | Reactive programming review                     | WebFlux controllers, services, reactive chains |
| **spring-reviewer**         | Spring Boot + MVC review                        | DI, controllers, validation, security, config  |
| **database-reviewer**       | PostgreSQL + MySQL database review              | SQL, JPA, migrations, connection pooling       |
| **security-reviewer**       | Security vulnerability analysis                 | Before commits, auth code                      |
| **performance-reviewer**    | Application performance analysis                | Latency issues, high-throughput code review    |
| **rabbitmq-reviewer**       | RabbitMQ & Spring AMQP review                   | Producers, consumers, DLQ config, AMQP code   |
| **build-error-resolver**    | Fix Java/Gradle build errors                    | When build fails                               |
| **e2e-runner**              | E2E testing (Testcontainers)                    | Critical API flows                             |
| **refactor-cleaner**        | Dead code cleanup                               | Code maintenance, dependency cleanup           |

## Agent Categories

### Code Review Agents

| Agent                     | Focus Area                                              |
|---------------------------|---------------------------------------------------------|
| `code-reviewer`           | Readability, naming, complexity, algorithms             |
| `spring-webflux-reviewer` | Reactive patterns, blocking detection, backpressure     |
| `spring-reviewer`         | DI, controllers, validation, filters, security, testing |
| `database-reviewer`       | PostgreSQL, MySQL, JPA, query optimization, migrations  |
| `rabbitmq-reviewer`       | RabbitMQ, Spring AMQP, DLQ, manual ack, retry patterns  |
| `performance-reviewer`    | JVM tuning, N+1 queries, caching, async parallelism     |
| `security-reviewer`       | OWASP Top 10, secrets, vulnerabilities                  |

### Design & Planning Agents

| Agent       | Focus Area                           |
|-------------|--------------------------------------|
| `planner`   | Task breakdown, implementation steps |
| `architect` | System design, CQRS, DDD, patterns   |

**SDD Mandate**: Planner and architect agents must not approve designs without a completed spec. Every plan must include a Spec Handoff section identifying task type and spec inputs for `/spec`.

### Testing Agents

| Agent                  | Focus Area                                                                                 |
|------------------------|--------------------------------------------------------------------------------------------|
| `tdd-guide`            | Unit tests, JUnit 5, StepVerifier                                                          |
| `blackbox-test-runner` | **Blackbox API tests (uses `blackbox-test` skill), JSON-driven, WireMock, Testcontainers** |
| `e2e-runner`           | Integration tests, Testcontainers                                                          |

### Maintenance Agents

| Agent                  | Focus Area                        |
|------------------------|-----------------------------------|
| `build-error-resolver` | Compilation errors, Gradle issues |
| `refactor-cleaner`     | Dead code, unused dependencies    |

## Immediate Agent Usage

No user prompt needed - invoke automatically:

| Trigger                              | Agent to Use                                          |
|--------------------------------------|-------------------------------------------------------|
| Complex feature request              | **planner** → **architect**                           |
| **API endpoint implemented/changed** | **blackbox-test-runner** (uses `blackbox-test` skill) |
| Code just written/modified           | **code-reviewer**                                     |
| WebFlux reactive code changed        | **spring-webflux-reviewer**                           |
| Spring MVC controller/config changed | **spring-reviewer**                                   |
| Database / SQL / JPA code changed    | **database-reviewer**                                 |
| RabbitMQ producer/consumer changed   | **rabbitmq-reviewer**                                 |
| Performance concerns or load review  | **performance-reviewer**                              |
| Spec approved (non-trivial task)     | **tdd-guide** (reads spec as test specification)      |
| Bug fix or new feature               | **tdd-guide**                                         |
| Architectural decision needed        | **architect**                                         |
| Build fails                          | **build-error-resolver**                              |
| Before commit/PR                     | **security-reviewer**                                 |

## Review Chain Pattern

For comprehensive review, chain multiple reviewers:

```markdown
# For Spring WebFlux API endpoint:
0. spec-verification        → Check implementation matches approved spec
1. spring-webflux-reviewer  → Check reactive patterns
2. spring-reviewer          → Check DI, config, validation
3. database-reviewer        → Check queries
4. security-reviewer        → Check vulnerabilities
5. code-reviewer            → Final quality check
```

## Parallel Task Execution

ALWAYS use parallel execution for independent operations:

```markdown
# GOOD: Parallel execution
Launch 3 agents in parallel:
1. Agent 1: spring-webflux-reviewer for OrderService
2. Agent 2: database-reviewer for OrderRepository
3. Agent 3: security-reviewer for auth endpoints

# BAD: Sequential when unnecessary
First agent 1, then agent 2, then agent 3
```

## Agent Selection by File Type

| File Pattern                       | Primary Agent           | Secondary Agents         |
|------------------------------------|-------------------------|--------------------------|
| `*Controller.java` (WebFlux)       | spring-webflux-reviewer | code-reviewer            |
| `*Controller.java` (MVC)           | spring-reviewer         | code-reviewer            |
| `*Service.java`                    | spring-reviewer         | spring-webflux-reviewer  |
| `*Repository.java` (R2DBC/PG)      | database-reviewer       | spring-webflux-reviewer  |
| `*Repository.java` (JPA)           | database-reviewer       | spring-reviewer          |
| `*Consumer.java`, `*Producer.java` | rabbitmq-reviewer       | performance-reviewer     |
| `*Config.java`                     | spring-reviewer         | security-reviewer        |
| `*.yml`, `*.properties`            | spring-reviewer         | security-reviewer        |
| `*Test.java`                       | tdd-guide               | -                        |
| `*.sql`, `V*.sql`                  | database-reviewer       | -                        |
| `build.gradle`, `pom.xml`          | build-error-resolver    | -                        |

## Model Selection for Agents

Agents use tiered models to balance quality and cost:

| Tier | Model | Agents | Rationale |
|------|-------|--------|-----------|
| **Deep reasoning** | opus | architect, planner | Complex architectural decisions, multi-step planning |
| **Pattern matching** | sonnet | All reviewers, tdd-guide, build-error-resolver, e2e-runner, refactor-cleaner | Checklist-based review, template-driven generation |
| **Lightweight** | haiku | (future workers) | Simple search, grep, file reading |

See `rules/common/performance.md` for full model selection guidance.

## Multi-Perspective Analysis

For complex problems, run specialized reviewers in parallel (see `/orchestrate review`).
