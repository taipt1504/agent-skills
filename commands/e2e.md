---
name: e2e
description: Generate and run end-to-end API tests with Testcontainers for Spring Boot (MVC and WebFlux) applications.
---

# /e2e -- E2E Test Generation & Run

This command invokes the **test-runner** agent to generate, maintain, and execute end-to-end API tests using Testcontainers and TestRestTemplate (MVC) or WebTestClient (WebFlux).

## What This Command Does

1. **Generate API Test Journeys** - Create integration tests for API flows
2. **Run E2E Tests** - Execute tests with real infrastructure via Testcontainers
3. **Capture Results** - Test reports with JUnit 5 and JaCoCo
4. **Verify Reactive Streams** - StepVerifier for async validation
5. **Identify Flaky Tests** - Quarantine unstable tests

## When to Use

Use `/e2e` when:

- Testing critical API journeys (authentication, orders, payments)
- Verifying multi-step flows work end-to-end
- Testing integration between services and databases
- Validating Kafka/RabbitMQ event flows
- Preparing for production deployment

## How It Works

The test-runner agent will:

1. **Analyze API flow** and identify test scenarios
2. **Generate test class** with Testcontainers setup
3. **Run tests** with TestRestTemplate (MVC) or WebTestClient (WebFlux)
4. **Capture failures** with detailed logs
5. **Generate report** with test results
6. **Identify flaky tests** and recommend fixes

## Key Differences: MVC vs WebFlux

| Aspect            | Spring Boot MVC       | Spring WebFlux                                    |
|-------------------|-----------------------|---------------------------------------------------|
| **Test Client**   | `TestRestTemplate`    | `WebTestClient`                                   |
| **Database**      | JPA/Hibernate (JDBC)  | R2DBC (Reactive)                                  |
| **Config**        | `spring.datasource.*` | `spring.r2dbc.*`                                  |
| **Async Testing** | `@Async` + Awaitility | StepVerifier + Awaitility                         |
| **Annotation**    | `@SpringBootTest`     | `@SpringBootTest` + `@AutoConfigureWebTestClient` |

## Test Structure

### WebFlux Test Template

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class OrderPaymentFlowE2ETest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine");

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () ->
            String.format("r2dbc:postgresql://%s:%d/%s",
                postgres.getHost(), postgres.getFirstMappedPort(), postgres.getDatabaseName()));
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired
    private WebTestClient webTestClient;

    @Test
    @Order(1)
    @DisplayName("User can create an order")
    void shouldCreateOrder() {
        webTestClient.post()
            .uri("/api/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(orderRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.orderId").exists();
    }
}
```

### MVC Test Template

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class OrderPaymentFlowMvcE2ETest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private TestRestTemplate restTemplate;

    @Test
    @Order(1)
    @DisplayName("User can create an order")
    void shouldCreateOrder() {
        ResponseEntity<Map> response = restTemplate.postForEntity(
            "/api/orders", orderRequest, Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }
}
```

## Running Tests

```bash
# Run all E2E tests
./gradlew test --tests "*E2ETest"

# Run specific test class
./gradlew test --tests "OrderPaymentFlowE2ETest"

# Run with verbose output
./gradlew test --tests "*E2ETest" --info

# Generate test report
./gradlew test jacocoTestReport
open build/reports/tests/test/index.html
```

## Testcontainers Dependencies (build.gradle)

```groovy
dependencies {
    testImplementation 'org.testcontainers:testcontainers:1.19.3'
    testImplementation 'org.testcontainers:junit-jupiter:1.19.3'
    testImplementation 'org.testcontainers:postgresql:1.19.3'
    testImplementation 'org.testcontainers:kafka:1.19.3'
    testImplementation 'org.testcontainers:r2dbc:1.19.3'
    testImplementation 'org.awaitility:awaitility:4.2.0'
}
```

## Available Containers

| Container  | Image                         | Use Case  |
|------------|-------------------------------|-----------|
| PostgreSQL | `postgres:15-alpine`          | Database  |
| Redis      | `redis:7-alpine`              | Cache     |
| Kafka      | `confluentinc/cp-kafka:7.5.0` | Events    |
| RabbitMQ   | `rabbitmq:3-management`       | Messaging |

## Best Practices

**DO:**
- Use `@TestMethodOrder` for dependent tests
- Use `@DynamicPropertySource` for container configs
- Use Awaitility for async assertions
- Test both happy path and error scenarios
- Clean up test data after test class
- Use meaningful `@DisplayName` annotations

**DON'T:**
- Use fixed ports (use `getFirstMappedPort()`)
- Use `Thread.sleep()` (use Awaitility)
- Share state between independent tests
- Test against production databases
- Skip cleanup in `@AfterAll`

## Test Report

```
E2E Test Results
================
Status:     ALL TESTS PASSED
Total:      10 tests
Passed:     10 (100%)
Failed:     0
Flaky:      0
Duration:   24.3s

Reports:
  HTML Report: build/reports/tests/test/index.html
  JaCoCo Coverage: build/reports/jacoco/test/html/index.html
```

## Critical Flow Priority

**CRITICAL (Must Always Pass):**
1. User authentication flow
2. Order creation
3. Payment processing
4. Event publishing (Kafka/RabbitMQ)
5. Cache invalidation

**IMPORTANT:**
1. Search and filtering
2. Pagination
3. Rate limiting
4. Error responses
5. Validation messages
