# Agent Orchestration

## Available Agents

Located in `.claude/agents/`:

| Agent                       | Purpose                                         | When to Use                                    |
|-----------------------------|-------------------------------------------------|------------------------------------------------|
| **planner**                 | Implementation planning                         | Complex features, multi-step tasks             |
| **architect**               | Backend system design (CQRS, DDD, Hexagonal)    | Architectural decisions, microservices design  |
| **tdd-guide**               | Test-driven development (JUnit 5, StepVerifier) | New features, bug fixes                        |
| **code-reviewer**           | General code review                             | After writing any code                         |
| **spring-webflux-reviewer** | Reactive programming review                     | WebFlux controllers, services, reactive chains |
| **spring-mvc-reviewer**     | Spring MVC (servlet) code review                | MVC controllers, filters, MockMvc tests        |
| **spring-boot-reviewer**    | Spring Boot best practices                      | DI patterns, configuration, beans              |
| **database-reviewer**       | PostgreSQL database & SQL review                | R2DBC, Liquibase, PostgreSQL queries           |
| **mysql-reviewer**          | MySQL 8.x & JPA/Hibernate review                | MySQL queries, Flyway migrations, HikariCP     |
| **security-reviewer**       | Security vulnerability analysis                 | Before commits, auth code                      |
| **performance-reviewer**    | Application performance analysis                | Latency issues, high-throughput code review    |
| **rabbitmq-reviewer**       | RabbitMQ & Spring AMQP review                   | Producers, consumers, DLQ config, AMQP code   |
| **build-error-resolver**    | Fix Java/Gradle build errors                    | When build fails                               |
| **e2e-runner**              | E2E testing (Testcontainers)                    | Critical API flows                             |
| **refactor-cleaner**        | Dead code cleanup                               | Code maintenance, dependency cleanup           |

## Agent Categories

### 🔍 Code Review Agents

| Agent                     | Focus Area                                              |
|---------------------------|---------------------------------------------------------|
| `code-reviewer`           | General quality, security basics                        |
| `spring-webflux-reviewer` | Reactive patterns, blocking detection, backpressure     |
| `spring-mvc-reviewer`     | MVC controllers, validation, filters, MockMvc tests     |
| `spring-boot-reviewer`    | DI, configuration, Spring conventions                   |
| `database-reviewer`       | PostgreSQL, R2DBC, Liquibase, query optimization        |
| `mysql-reviewer`          | MySQL 8.x, JPA/Hibernate, HikariCP, Flyway migrations   |
| `rabbitmq-reviewer`       | RabbitMQ, Spring AMQP, DLQ, manual ack, retry patterns  |
| `performance-reviewer`    | JVM tuning, N+1 queries, caching, async parallelism     |
| `security-reviewer`       | OWASP Top 10, secrets, vulnerabilities                  |

### 🏗️ Design & Planning Agents

| Agent       | Focus Area                           |
|-------------|--------------------------------------|
| `planner`   | Task breakdown, implementation steps |
| `architect` | System design, CQRS, DDD, patterns   |

### 🧪 Testing Agents

| Agent                  | Focus Area                                                                                 |
|------------------------|--------------------------------------------------------------------------------------------|
| `tdd-guide`            | Unit tests, JUnit 5, StepVerifier                                                          |
| `blackbox-test-runner` | **Blackbox API tests (uses `blackbox-test` skill), JSON-driven, WireMock, Testcontainers** |
| `e2e-runner`           | Integration tests, Testcontainers                                                          |

### 🔧 Maintenance Agents

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
| Spring MVC controller/filter changed | **spring-mvc-reviewer**                               |
| Spring configuration changed         | **spring-boot-reviewer**                              |
| PostgreSQL / R2DBC code changed      | **database-reviewer**                                 |
| MySQL / JPA / Flyway code changed    | **mysql-reviewer**                                    |
| RabbitMQ producer/consumer changed   | **rabbitmq-reviewer**                                 |
| Performance concerns or load review  | **performance-reviewer**                              |
| Bug fix or new feature               | **tdd-guide**                                         |
| Architectural decision needed        | **architect**                                         |
| Build fails                          | **build-error-resolver**                              |
| Before commit/PR                     | **security-reviewer**                                 |

## Review Chain Pattern

For comprehensive review, chain multiple reviewers:

```markdown
# For Spring WebFlux API endpoint:
1. spring-webflux-reviewer  → Check reactive patterns
2. spring-boot-reviewer     → Check DI and config
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

| File Pattern                       | Primary Agent           | Secondary Agents                      |
|------------------------------------|-------------------------|---------------------------------------|
| `*Controller.java` (WebFlux)       | spring-webflux-reviewer | code-reviewer                         |
| `*Controller.java` (MVC)           | spring-mvc-reviewer     | code-reviewer                         |
| `*Service.java`                    | spring-boot-reviewer    | spring-webflux-reviewer               |
| `*Repository.java` (R2DBC/PG)      | database-reviewer       | spring-webflux-reviewer               |
| `*Repository.java` (JPA/MySQL)     | mysql-reviewer          | spring-boot-reviewer                  |
| `*Consumer.java`, `*Producer.java` | rabbitmq-reviewer       | performance-reviewer                  |
| `*Config.java`                     | spring-boot-reviewer    | security-reviewer                     |
| `*.yml`, `*.properties`            | spring-boot-reviewer    | security-reviewer                     |
| `*Test.java`                       | tdd-guide               | -                                     |
| `*.sql` (PostgreSQL/Liquibase)     | database-reviewer       | -                                     |
| `V*.sql` (Flyway/MySQL)            | mysql-reviewer          | -                                     |
| `build.gradle`, `pom.xml`          | build-error-resolver    | -                                     |

## Multi-Perspective Analysis

For complex problems, use split role sub-agents:

- **Factual reviewer** - Verify correctness
- **Senior engineer/Reactive expert** - Check non-blocking patterns
- **Security expert** - Identify vulnerabilities
- **Performance expert** - Check efficiency
- **Consistency reviewer** - Verify patterns across codebase
