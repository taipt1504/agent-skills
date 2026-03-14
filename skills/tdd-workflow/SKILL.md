---
name: tdd-workflow
description: Test-Driven Development workflow for Java Spring Boot projects. Use when writing new features, fixing bugs, or refactoring code. Enforces write-tests-first, 80%+ coverage, and comprehensive unit/integration/E2E tests with JUnit 5, Mockito, Testcontainers, WireMock, and StepVerifier.
---

# Test-Driven Development Workflow

TDD for Java Spring Boot 3.x (MVC + WebFlux). Tests first, always.

**Test patterns reference**: See [references/test-patterns.md](references/test-patterns.md) for concrete examples of every test type.

## Core Principles

1. **Tests BEFORE code** — write a failing test, then implement
2. **Coverage minimum** — 80% line coverage (unit + integration + E2E)
3. **Test types pyramid**: unit > integration > E2E
4. **Independent tests** — `@BeforeEach` cleanup; no test depends on another

## TDD Workflow (RED → GREEN → REFACTOR)

### Step 1: Write Failing Test

```java
@Test
@DisplayName("Should create order and return PENDING status")
void shouldCreateOrder() {
    StepVerifier.create(orderService.create(validCommand))
        .assertNext(o -> assertThat(o.getStatus()).isEqualTo(OrderStatus.PENDING))
        .verifyComplete();
}
```

```bash
./gradlew test  # FAILS — RED phase
```

### Step 2: Implement Minimal Code

Write the minimum code to make the test pass. Resist the urge to add more.

```bash
./gradlew test  # PASSES — GREEN phase
```

### Step 3: Refactor

Clean up duplication, naming, and structure while keeping tests green.

```bash
./gradlew test jacocoTestReport  # Verify coverage stays ≥ 80%
```

## Test Types — When to Write Each

| Type | Annotation | Use For | Speed |
|------|-----------|---------|-------|
| Unit | `@ExtendWith(MockitoExtension.class)` | Service logic, domain objects | Fast |
| Controller (WebFlux) | `@SpringBootTest + @AutoConfigureWebTestClient` | API contract | Medium |
| Controller (MVC) | `@WebMvcTest` | API contract, auth | Medium |
| Repository (R2DBC) | `@DataR2dbcTest` | DB queries | Medium |
| Repository (JPA) | `@DataJpaTest` | JPA queries, MySQL | Medium |
| Messaging | `@EmbeddedKafka` / `RabbitMQContainer` | Event publishing | Medium |
| E2E | `@SpringBootTest + @Testcontainers` | Full stack flows | Slow |

## Testcontainers Container Reuse

Always use `.withReuse(true)` for local development speed:

```java
@Container
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
    .withDatabaseName("testdb").withUsername("test").withPassword("test")
    .withReuse(true);  // ✅ Reuse across test classes

@Container
static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
    .withReuse(true);

@Container
static KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.4.0"))
    .withReuse(true);
```

## Test File Organization

```
src/test/java/com/example/
├── unit/
│   ├── service/OrderServiceTest.java         # @ExtendWith(MockitoExtension.class)
│   └── domain/OrderTest.java
├── integration/
│   ├── web/OrderControllerTest.java          # @WebMvcTest or @SpringBootTest
│   └── repository/OrderRepositoryTest.java   # @DataJpaTest / @DataR2dbcTest
├── e2e/
│   └── OrderFlowE2ETest.java                 # @SpringBootTest + @Testcontainers
└── fixtures/
    └── TestDataFactory.java                  # Shared test builders
```

## Quick Test Commands

```bash
# All tests
./gradlew test

# Single test class
./gradlew test --tests "com.example.service.OrderServiceTest"

# Watch mode (runs on file change)
./gradlew test --continuous

# Coverage report
./gradlew test jacocoTestReport
# Report: build/reports/jacoco/test/html/index.html
```

## Detailed Examples

For complete test examples including:
- Unit tests (JUnit 5 + Mockito + StepVerifier)
- WebFlux integration tests (WebTestClient)
- Spring MVC tests (MockMvc)
- Repository tests (R2DBC, JPA/MySQL)
- Kafka integration tests
- WireMock for external APIs
- Redis mocking
- JaCoCo coverage configuration (Gradle + Maven)

**→ Read [references/test-patterns.md](references/test-patterns.md)**
