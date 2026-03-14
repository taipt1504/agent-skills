---
description: Generate and run end-to-end API tests with Testcontainers for Spring Boot (MVC and WebFlux) applications.
---

# E2E Command

This command invokes the **e2e-runner** agent to generate, maintain, and execute end-to-end API tests using
Testcontainers and TestRestTemplate (MVC) or WebTestClient (WebFlux).

## What This Command Does

1. **Generate API Test Journeys** - Create integration tests for API flows
2. **Run E2E Tests** - Execute tests with real infrastructure via Testcontainers
3. **Capture Results** - Test reports with JUnit 5 and Jacoco
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

The e2e-runner agent will:

1. **Analyze API flow** and identify test scenarios
2. **Generate test class** with Testcontainers setup
3. **Run tests** with TestRestTemplate (MVC) or WebTestClient (WebFlux)
4. **Capture failures** with detailed logs
5. **Generate report** with test results
6. **Identify flaky tests** and recommend fixes

> **Note**: Use `TestRestTemplate` for Spring Boot MVC projects and `WebTestClient` for Spring WebFlux projects.

---

## Example Usage

```
User: /e2e Test the order creation and payment flow

Agent (e2e-runner):
# E2E Test Generation: Order Creation and Payment Flow
```

## Generated Test Code

```java
// src/test/java/com/example/e2e/OrderPaymentFlowE2ETest.java
package com.example.e2e;

import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.testcontainers.containers.KafkaContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import reactor.test.StepVerifier;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
@DisplayName("Order and Payment Flow E2E Tests")
class OrderPaymentFlowE2ETest {

    // ==================== TESTCONTAINERS ====================
    
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0"));

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        // PostgreSQL R2DBC
        registry.add("spring.r2dbc.url", () -> 
            String.format("r2dbc:postgresql://%s:%d/%s",
                postgres.getHost(),
                postgres.getFirstMappedPort(),
                postgres.getDatabaseName()));
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        
        // Liquibase (JDBC for migrations)
        registry.add("spring.liquibase.url", postgres::getJdbcUrl);
        registry.add("spring.liquibase.user", postgres::getUsername);
        registry.add("spring.liquibase.password", postgres::getPassword);
        
        // Redis
        registry.add("spring.redis.host", redis::getHost);
        registry.add("spring.redis.port", () -> redis.getFirstMappedPort());
        
        // Kafka
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }

    // ==================== DEPENDENCIES ====================

    @Autowired
    private WebTestClient webTestClient;

    private static String createdOrderId;
    private static String authToken;

    // ==================== SETUP ====================

    @BeforeAll
    static void beforeAll() {
        // Wait for containers to be ready
        await().atMost(30, TimeUnit.SECONDS)
            .until(() -> postgres.isRunning() && redis.isRunning() && kafka.isRunning());
    }

    // ==================== TEST CASES ====================

    @Test
    @Order(1)
    @DisplayName("1. User can authenticate and get token")
    void shouldAuthenticateUser() {
        var loginRequest = """
            {
                "username": "testuser",
                "password": "testpass123"
            }
            """;

        webTestClient.post()
            .uri("/api/auth/login")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(loginRequest)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.token").exists()
            .jsonPath("$.token").value(token -> {
                authToken = (String) token;
                assertThat(authToken).isNotBlank();
            });
    }

    @Test
    @Order(2)
    @DisplayName("2. User can create an order")
    void shouldCreateOrder() {
        var orderRequest = """
            {
                "customerId": "CUST-001",
                "items": [
                    {"productId": "PROD-001", "quantity": 2, "price": 29.99},
                    {"productId": "PROD-002", "quantity": 1, "price": 49.99}
                ]
            }
            """;

        webTestClient.post()
            .uri("/api/orders")
            .header("Authorization", "Bearer " + authToken)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(orderRequest)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.orderId").exists()
            .jsonPath("$.orderId").value(id -> {
                createdOrderId = (String) id;
                assertThat(createdOrderId).startsWith("ORD-");
            })
            .jsonPath("$.status").isEqualTo("PENDING")
            .jsonPath("$.totalAmount").isEqualTo(109.97);
    }

    @Test
    @Order(3)
    @DisplayName("3. User can retrieve created order")
    void shouldGetOrderById() {
        webTestClient.get()
            .uri("/api/orders/{id}", createdOrderId)
            .header("Authorization", "Bearer " + authToken)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.orderId").isEqualTo(createdOrderId)
            .jsonPath("$.status").isEqualTo("PENDING")
            .jsonPath("$.items.length()").isEqualTo(2);
    }

    @Test
    @Order(4)
    @DisplayName("4. User can process payment for order")
    void shouldProcessPayment() {
        var paymentRequest = """
            {
                "orderId": "%s",
                "paymentMethod": "CREDIT_CARD",
                "cardToken": "tok_test_visa"
            }
            """.formatted(createdOrderId);

        webTestClient.post()
            .uri("/api/payments")
            .header("Authorization", "Bearer " + authToken)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(paymentRequest)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.paymentId").exists()
            .jsonPath("$.status").isEqualTo("COMPLETED");
    }

    @Test
    @Order(5)
    @DisplayName("5. Order status should be updated after payment")
    void shouldUpdateOrderStatusAfterPayment() {
        // Wait for async event processing
        await().atMost(5, TimeUnit.SECONDS)
            .pollInterval(Duration.ofMillis(500))
            .untilAsserted(() -> {
                webTestClient.get()
                    .uri("/api/orders/{id}", createdOrderId)
                    .header("Authorization", "Bearer " + authToken)
                    .exchange()
                    .expectStatus().isOk()
                    .expectBody()
                    .jsonPath("$.status").isEqualTo("PAID");
            });
    }

    @Test
    @Order(6)
    @DisplayName("6. Kafka event should be published for order paid")
    void shouldPublishOrderPaidEvent() {
        // Verify Kafka consumer received the event
        await().atMost(10, TimeUnit.SECONDS)
            .pollInterval(Duration.ofSeconds(1))
            .untilAsserted(() -> {
                webTestClient.get()
                    .uri("/api/admin/events?orderId={id}&type=ORDER_PAID", createdOrderId)
                    .header("Authorization", "Bearer " + authToken)
                    .exchange()
                    .expectStatus().isOk()
                    .expectBody()
                    .jsonPath("$.length()").value(count -> 
                        assertThat((Integer) count).isGreaterThan(0));
            });
    }

    @Test
    @Order(7)
    @DisplayName("7. Order can be retrieved from cache on second request")
    void shouldRetrieveFromCache() {
        // First request (cache miss)
        webTestClient.get()
            .uri("/api/orders/{id}", createdOrderId)
            .header("Authorization", "Bearer " + authToken)
            .exchange()
            .expectStatus().isOk()
            .expectHeader().doesNotExist("X-Cache-Hit");

        // Second request (cache hit)
        webTestClient.get()
            .uri("/api/orders/{id}", createdOrderId)
            .header("Authorization", "Bearer " + authToken)
            .exchange()
            .expectStatus().isOk()
            .expectHeader().valueEquals("X-Cache-Hit", "true");
    }

    // ==================== NEGATIVE TESTS ====================

    @Test
    @DisplayName("Should return 404 for non-existent order")
    void shouldReturn404ForNonExistentOrder() {
        webTestClient.get()
            .uri("/api/orders/ORD-NONEXISTENT")
            .header("Authorization", "Bearer " + authToken)
            .exchange()
            .expectStatus().isNotFound()
            .expectBody()
            .jsonPath("$.error").isEqualTo("ORDER_NOT_FOUND");
    }

    @Test
    @DisplayName("Should return 401 for unauthenticated request")
    void shouldReturn401ForUnauthenticatedRequest() {
        webTestClient.get()
            .uri("/api/orders/{id}", createdOrderId)
            .exchange()
            .expectStatus().isUnauthorized();
    }

    @Test
    @DisplayName("Should return 400 for invalid order request")
    void shouldReturn400ForInvalidOrderRequest() {
        var invalidRequest = """
            {
                "customerId": "",
                "items": []
            }
            """;

        webTestClient.post()
            .uri("/api/orders")
            .header("Authorization", "Bearer " + authToken)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(invalidRequest)
            .exchange()
            .expectStatus().isBadRequest()
            .expectBody()
            .jsonPath("$.errors").isArray()
            .jsonPath("$.errors.length()").value(count -> 
                assertThat((Integer) count).isGreaterThanOrEqualTo(2));
    }
}
```

---

## Spring Boot MVC Example (TestRestTemplate)

For traditional Spring Boot MVC projects, use `TestRestTemplate` instead of `WebTestClient`:

```java
// src/test/java/com/example/e2e/OrderPaymentFlowMvcE2ETest.java
package com.example.e2e;

import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.*;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
@DisplayName("Order and Payment Flow E2E Tests (MVC)")
class OrderPaymentFlowMvcE2ETest {

    // ==================== TESTCONTAINERS ====================
    
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        // PostgreSQL JDBC (for JPA/Hibernate)
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        
        // JPA/Hibernate
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
        registry.add("spring.jpa.show-sql", () -> "true");
        
        // Redis
        registry.add("spring.redis.host", redis::getHost);
        registry.add("spring.redis.port", () -> redis.getFirstMappedPort());
    }

    // ==================== DEPENDENCIES ====================

    @Autowired
    private TestRestTemplate restTemplate;

    private static String createdOrderId;
    private static String authToken;

    // ==================== TEST CASES ====================

    @Test
    @Order(1)
    @DisplayName("1. User can authenticate and get token")
    void shouldAuthenticateUser() {
        var loginRequest = Map.of(
            "username", "testuser",
            "password", "testpass123"
        );

        ResponseEntity<Map> response = restTemplate.postForEntity(
            "/api/auth/login",
            loginRequest,
            Map.class
        );

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).containsKey("token");
        authToken = (String) response.getBody().get("token");
        assertThat(authToken).isNotBlank();
    }

    @Test
    @Order(2)
    @DisplayName("2. User can create an order")
    void shouldCreateOrder() {
        var orderRequest = Map.of(
            "customerId", "CUST-001",
            "items", new Object[]{
                Map.of("productId", "PROD-001", "quantity", 2, "price", 29.99),
                Map.of("productId", "PROD-002", "quantity", 1, "price", 49.99)
            }
        );

        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(authToken);
        headers.setContentType(MediaType.APPLICATION_JSON);
        
        HttpEntity<Map> request = new HttpEntity<>(orderRequest, headers);
        
        ResponseEntity<Map> response = restTemplate.postForEntity(
            "/api/orders",
            request,
            Map.class
        );

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody()).containsKey("orderId");
        createdOrderId = (String) response.getBody().get("orderId");
        assertThat(createdOrderId).startsWith("ORD-");
        assertThat(response.getBody().get("status")).isEqualTo("PENDING");
    }

    @Test
    @Order(3)
    @DisplayName("3. User can retrieve created order")
    void shouldGetOrderById() {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(authToken);
        HttpEntity<?> request = new HttpEntity<>(headers);

        ResponseEntity<Map> response = restTemplate.exchange(
            "/api/orders/{id}",
            HttpMethod.GET,
            request,
            Map.class,
            createdOrderId
        );

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().get("orderId")).isEqualTo(createdOrderId);
        assertThat(response.getBody().get("status")).isEqualTo("PENDING");
    }

    @Test
    @DisplayName("Should return 404 for non-existent order")
    void shouldReturn404ForNonExistentOrder() {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(authToken);
        HttpEntity<?> request = new HttpEntity<>(headers);

        ResponseEntity<Map> response = restTemplate.exchange(
            "/api/orders/ORD-NONEXISTENT",
            HttpMethod.GET,
            request,
            Map.class
        );

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    @DisplayName("Should return 401 for unauthenticated request")
    void shouldReturn401ForUnauthenticatedRequest() {
        ResponseEntity<Map> response = restTemplate.getForEntity(
            "/api/orders/{id}",
            Map.class,
            createdOrderId
        );

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }
}
```

---

## Key Differences: MVC vs WebFlux

| Aspect            | Spring Boot MVC       | Spring WebFlux                                    |
|-------------------|-----------------------|---------------------------------------------------|
| **Test Client**   | `TestRestTemplate`    | `WebTestClient`                                   |
| **Database**      | JPA/Hibernate (JDBC)  | R2DBC (Reactive)                                  |
| **Config**        | `spring.datasource.*` | `spring.r2dbc.*`                                  |
| **Async Testing** | `@Async` + Awaitility | StepVerifier + Awaitility                         |
| **Annotation**    | `@SpringBootTest`     | `@SpringBootTest` + `@AutoConfigureWebTestClient` |

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

---

## Test Report

```
╔══════════════════════════════════════════════════════════════╗
║                    E2E Test Results                          ║
╠══════════════════════════════════════════════════════════════╣
║ Status:     ✅ ALL TESTS PASSED                              ║
║ Total:      10 tests                                         ║
║ Passed:     10 (100%)                                        ║
║ Failed:     0                                                ║
║ Flaky:      0                                                ║
║ Duration:   24.3s                                            ║
╚══════════════════════════════════════════════════════════════╝

Infrastructure Used:
📦 PostgreSQL 15 (Testcontainers)
📦 Redis 7 (Testcontainers)
📦 Kafka 7.5 (Testcontainers)

Reports:
📊 HTML Report: build/reports/tests/test/index.html
📊 Jacoco Coverage: build/reports/jacoco/test/html/index.html
📊 JUnit XML: build/test-results/test/*.xml

View report: open build/reports/tests/test/index.html
```

---

## Testcontainers Setup

### build.gradle

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

### Available Containers

| Container  | Image                         | Use Case  |
|------------|-------------------------------|-----------|
| PostgreSQL | `postgres:15-alpine`          | Database  |
| Redis      | `redis:7-alpine`              | Cache     |
| Kafka      | `confluentinc/cp-kafka:7.5.0` | Events    |
| RabbitMQ   | `rabbitmq:3-management`       | Messaging |

---

## Best Practices

**DO:**

- ✅ Use `@TestMethodOrder` for dependent tests
- ✅ Use `@DynamicPropertySource` for container configs
- ✅ Use Awaitility for async assertions
- ✅ Test both happy path and error scenarios
- ✅ Clean up test data after test class
- ✅ Use meaningful `@DisplayName` annotations

**DON'T:**

- ❌ Use fixed ports (use `getFirstMappedPort()`)
- ❌ Use `Thread.sleep()` (use Awaitility)
- ❌ Share state between independent tests
- ❌ Test against production databases
- ❌ Skip cleanup in `@AfterAll`

---

## Flaky Test Detection

```
⚠️  FLAKY TEST DETECTED: OrderPaymentFlowE2ETest.shouldPublishOrderPaidEvent

Test passed 7/10 runs (70% pass rate)

Common failure:
"Awaitility condition not met within 10 seconds"

Recommended fixes:
1. Increase timeout: await().atMost(15, TimeUnit.SECONDS)
2. Add retry: .ignoreExceptions()
3. Check Kafka consumer lag
4. Verify event handler is processing

Quarantine recommendation: Mark as @Disabled("Flaky - investigating") until fixed
```

---

## CI/CD Integration

```yaml
# .github/workflows/e2e.yml
jobs:
  e2e-tests:
    runs-on: ubuntu-latest
    services:
      docker:
        image: docker:dind
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      
      - name: Run E2E Tests
        run: ./gradlew test --tests "*E2ETest"
      
      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: build/reports/tests/
```

---

## Critical Flow Priority

**🔴 CRITICAL (Must Always Pass):**

1. User authentication flow
2. Order creation
3. Payment processing
4. Event publishing (Kafka/RabbitMQ)
5. Cache invalidation

**🟡 IMPORTANT:**

1. Search and filtering
2. Pagination
3. Rate limiting
4. Error responses
5. Validation messages

---

## Related Commands

- `/plan` - Identify critical journeys to test
- `/tdd` - TDD workflow for unit tests
- `/verify` - Full verification after tests pass
- Use **e2e-runner** agent for complex test scenarios
