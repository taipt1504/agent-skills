---
name: tdd-workflow
description: Use this skill when writing new features, fixing bugs, or refactoring code. Enforces test-driven development with 80%+ coverage including unit, integration, and E2E tests for Java Spring projects.
---

# Test-Driven Development Workflow

This skill ensures all Java Spring development follows TDD principles with comprehensive test coverage.

## When to Activate

- Writing new features or functionality
- Fixing bugs or issues
- Refactoring existing code
- Adding API endpoints
- Creating new services or components
- Database schema changes

## Core Principles

### 1. Tests BEFORE Code

ALWAYS write tests first, then implement code to make tests pass.

### 2. Coverage Requirements

- Minimum 80% coverage (unit + integration + E2E)
- All edge cases covered
- Error scenarios tested
- Boundary conditions verified

### 3. Test Types

#### Unit Tests

- Individual methods and utilities
- Service logic
- Pure functions
- Mappers and validators

#### Integration Tests

- API endpoints (WebTestClient/TestRestTemplate)
- Repository operations (R2DBC/JPA)
- Service interactions
- External API clients

#### E2E Tests (Testcontainers)

- Complete API flows
- Database integration
- Kafka/RabbitMQ messaging
- Redis caching scenarios

## TDD Workflow Steps

### Step 1: Write User Journeys

```
As a [role], I want to [action], so that [benefit]

Example:
As a user, I want to search for markets semantically,
so that I can find relevant markets even without exact keywords.
```

### Step 2: Generate Test Cases

For each user journey, create comprehensive test cases:

```java
@ExtendWith(MockitoExtension.class)
class MarketServiceTest {

    @Mock
    private MarketRepository marketRepository;

    @Mock
    private VectorSearchService vectorSearchService;

    @InjectMocks
    private MarketService marketService;

    @Test
    @DisplayName("Should return relevant markets for query")
    void shouldReturnRelevantMarketsForQuery() {
        // Test implementation
    }

    @Test
    @DisplayName("Should return empty list when no markets match")
    void shouldReturnEmptyListWhenNoMarketsMatch() {
        // Test edge case
    }

    @Test
    @DisplayName("Should fall back to substring search when Redis unavailable")
    void shouldFallBackToSubstringSearchWhenRedisUnavailable() {
        // Test fallback behavior
    }

    @Test
    @DisplayName("Should sort results by similarity score")
    void shouldSortResultsBySimilarityScore() {
        // Test sorting logic
    }
}
```

### Step 3: Run Tests (They Should Fail)

```bash
./gradlew test
# Tests should fail - we haven't implemented yet
```

### Step 4: Implement Code

Write minimal code to make tests pass:

```java
@Service
@RequiredArgsConstructor
public class MarketService {

    private final MarketRepository marketRepository;
    private final VectorSearchService vectorSearchService;

    public Flux<Market> searchMarkets(String query, int limit) {
        // Implementation here
    }
}
```

### Step 5: Run Tests Again

```bash
./gradlew test
# Tests should now pass
```

### Step 6: Refactor

Improve code quality while keeping tests green:

- Remove duplication
- Improve naming
- Optimize performance
- Enhance readability

### Step 7: Verify Coverage

```bash
./gradlew test jacocoTestReport
# Verify 80%+ coverage achieved
```

## Testing Patterns

### Unit Test Pattern (JUnit 5 + Mockito)

```java
@ExtendWith(MockitoExtension.class)
class MarketServiceTest {

    @Mock
    private MarketRepository marketRepository;

    @InjectMocks
    private MarketService marketService;

    @BeforeEach
    void setUp() {
        // Common setup
    }

    @Test
    @DisplayName("Should create market successfully")
    void shouldCreateMarket() {
        // Arrange
        var request = new CreateMarketRequest("Test Market", "Description");
        var expected = Market.builder()
            .id("market-123")
            .name("Test Market")
            .status(MarketStatus.PENDING)
            .build();

        when(marketRepository.save(any(Market.class)))
            .thenReturn(Mono.just(expected));

        // Act
        var result = marketService.create(request);

        // Assert
        StepVerifier.create(result)
            .assertNext(market -> {
                assertThat(market.id()).isEqualTo("market-123");
                assertThat(market.name()).isEqualTo("Test Market");
                assertThat(market.status()).isEqualTo(MarketStatus.PENDING);
            })
            .verifyComplete();

        verify(marketRepository).save(any(Market.class));
    }

    @Test
    @DisplayName("Should throw exception when market not found")
    void shouldThrowWhenMarketNotFound() {
        // Arrange
        when(marketRepository.findById("unknown"))
            .thenReturn(Mono.empty());

        // Act & Assert
        StepVerifier.create(marketService.findById("unknown"))
            .expectError(MarketNotFoundException.class)
            .verify();
    }
}
```

### WebFlux Integration Test Pattern

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@Testcontainers
class MarketControllerIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () -> 
            "r2dbc:postgresql://" + postgres.getHost() + ":" + 
            postgres.getFirstMappedPort() + "/testdb");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private MarketRepository marketRepository;

    @BeforeEach
    void setUp() {
        marketRepository.deleteAll().block();
    }

    @Test
    @DisplayName("GET /api/markets returns all markets")
    void shouldReturnAllMarkets() {
        // Arrange
        var market = Market.builder()
            .id(UUID.randomUUID().toString())
            .name("Test Market")
            .status(MarketStatus.ACTIVE)
            .build();
        marketRepository.save(market).block();

        // Act & Assert
        webTestClient.get()
            .uri("/api/markets")
            .exchange()
            .expectStatus().isOk()
            .expectBodyList(Market.class)
            .hasSize(1)
            .contains(market);
    }

    @Test
    @DisplayName("POST /api/markets creates new market")
    void shouldCreateMarket() {
        var request = new CreateMarketRequest("New Market", "Description");

        webTestClient.post()
            .uri("/api/markets")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.id").isNotEmpty()
            .jsonPath("$.name").isEqualTo("New Market")
            .jsonPath("$.status").isEqualTo("PENDING");
    }

    @Test
    @DisplayName("POST /api/markets validates input")
    void shouldValidateInput() {
        var invalidRequest = new CreateMarketRequest("", "");

        webTestClient.post()
            .uri("/api/markets")
            .bodyValue(invalidRequest)
            .exchange()
            .expectStatus().isBadRequest()
            .expectBody()
            .jsonPath("$.code").isEqualTo("VALIDATION_ERROR");
    }

    @Test
    @DisplayName("GET /api/markets/{id} returns 404 for unknown market")
    void shouldReturn404ForUnknownMarket() {
        webTestClient.get()
            .uri("/api/markets/unknown-id")
            .exchange()
            .expectStatus().isNotFound();
    }
}
```

### Spring Boot MVC Integration Test Pattern

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class MarketControllerMvcIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    }

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private MarketRepository marketRepository;

    @Test
    @Order(1)
    @DisplayName("GET /api/markets returns all markets")
    void shouldReturnAllMarkets() {
        // Arrange
        var market = Market.builder()
            .name("Test Market")
            .status(MarketStatus.ACTIVE)
            .build();
        marketRepository.save(market);

        // Act
        ResponseEntity<List<Market>> response = restTemplate.exchange(
            "/api/markets",
            HttpMethod.GET,
            null,
            new ParameterizedTypeReference<List<Market>>() {}
        );

        // Assert
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
    }

    @Test
    @DisplayName("POST /api/markets creates new market")
    void shouldCreateMarket() {
        var request = new CreateMarketRequest("New Market", "Description");

        ResponseEntity<Market> response = restTemplate.postForEntity(
            "/api/markets",
            request,
            Market.class
        );

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody().getName()).isEqualTo("New Market");
    }
}
```

### Repository Test Pattern (R2DBC)

```java
@DataR2dbcTest
@Testcontainers
@Import(TestConfig.class)
class MarketRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () -> 
            "r2dbc:postgresql://" + postgres.getHost() + ":" + 
            postgres.getFirstMappedPort() + "/testdb");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired
    private MarketRepository repository;

    @Test
    @DisplayName("Should save and retrieve market")
    void shouldSaveAndRetrieve() {
        var market = Market.builder()
            .id(UUID.randomUUID().toString())
            .name("Test")
            .status(MarketStatus.ACTIVE)
            .build();

        StepVerifier.create(repository.save(market))
            .expectNext(market)
            .verifyComplete();

        StepVerifier.create(repository.findById(market.id()))
            .assertNext(found -> {
                assertThat(found.name()).isEqualTo("Test");
                assertThat(found.status()).isEqualTo(MarketStatus.ACTIVE);
            })
            .verifyComplete();
    }

    @Test
    @DisplayName("Should find markets by status")
    void shouldFindByStatus() {
        var activeMarket = createMarket("Active", MarketStatus.ACTIVE);
        var pendingMarket = createMarket("Pending", MarketStatus.PENDING);

        repository.saveAll(List.of(activeMarket, pendingMarket)).blockLast();

        StepVerifier.create(repository.findByStatus(MarketStatus.ACTIVE))
            .assertNext(m -> assertThat(m.name()).isEqualTo("Active"))
            .verifyComplete();
    }
}
```

### Kafka Integration Test Pattern

```java
@SpringBootTest
@Testcontainers
@EmbeddedKafka(partitions = 1, topics = {"market-events"})
class MarketEventPublisherTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine");

    @Autowired
    private MarketEventPublisher eventPublisher;

    @Autowired
    private KafkaTemplate<String, String> kafkaTemplate;

    @Autowired
    @Qualifier("testConsumer")
    private KafkaConsumer<String, String> consumer;

    @Test
    @DisplayName("Should publish market created event")
    void shouldPublishMarketCreatedEvent() throws Exception {
        // Arrange
        var event = new MarketCreatedEvent("market-123", "Test Market");

        // Act
        eventPublisher.publish(event).block();

        // Assert
        ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(5));
        assertThat(records.count()).isEqualTo(1);

        var record = records.iterator().next();
        assertThat(record.topic()).isEqualTo("market-events");
        assertThat(record.value()).contains("market-123");
    }
}
```

## Test File Organization

```
src/
├── main/java/com/example/
│   ├── domain/
│   │   └── model/Market.java
│   ├── application/
│   │   └── service/MarketService.java
│   ├── infrastructure/
│   │   └── persistence/MarketRepositoryImpl.java
│   └── adapter/
│       └── web/MarketController.java
│
└── test/java/com/example/
    ├── domain/
    │   └── model/MarketTest.java              # Unit test
    ├── application/
    │   └── service/MarketServiceTest.java     # Unit test
    ├── infrastructure/
    │   └── persistence/MarketRepositoryTest.java  # Integration test
    ├── adapter/
    │   └── web/MarketControllerTest.java      # Integration test
    ├── e2e/
    │   └── MarketFlowE2ETest.java             # E2E test
    └── fixtures/
        └── TestDataFactory.java               # Test utilities
```

## Mocking Patterns

### Repository Mock

```java
@Mock
private MarketRepository marketRepository;

@BeforeEach
void setupMocks() {
    when(marketRepository.findById(anyString()))
        .thenReturn(Mono.just(Market.builder()
            .id("market-123")
            .name("Test")
            .build()));

    when(marketRepository.save(any(Market.class)))
        .thenAnswer(invocation -> Mono.just(invocation.getArgument(0)));

    when(marketRepository.findByStatus(MarketStatus.ACTIVE))
        .thenReturn(Flux.just(
            Market.builder().id("1").name("Market 1").build(),
            Market.builder().id("2").name("Market 2").build()
        ));
}
```

### External Service Mock (WireMock)

```java
@WireMockTest(httpPort = 8089)
class ExternalApiClientTest {

    @Autowired
    private ExternalApiClient apiClient;

    @Test
    @DisplayName("Should fetch data from external API")
    void shouldFetchFromExternalApi(WireMockRuntimeInfo wmRuntimeInfo) {
        // Arrange
        stubFor(get("/api/data")
            .willReturn(aResponse()
                .withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("{\"value\": 123}")));

        // Act & Assert
        StepVerifier.create(apiClient.fetchData())
            .assertNext(data -> assertThat(data.value()).isEqualTo(123))
            .verifyComplete();
    }

    @Test
    @DisplayName("Should handle external API error")
    void shouldHandleApiError() {
        stubFor(get("/api/data")
            .willReturn(aResponse().withStatus(500)));

        StepVerifier.create(apiClient.fetchData())
            .expectError(ExternalApiException.class)
            .verify();
    }
}
```

### Redis Mock

```java
@Mock
private ReactiveRedisTemplate<String, Market> redisTemplate;

@Mock
private ReactiveValueOperations<String, Market> valueOps;

@BeforeEach
void setupRedisMock() {
    when(redisTemplate.opsForValue()).thenReturn(valueOps);
    when(valueOps.get(anyString())).thenReturn(Mono.empty());
    when(valueOps.set(anyString(), any(), any(Duration.class)))
        .thenReturn(Mono.just(true));
}
```

## Test Coverage Configuration

### Gradle (build.gradle.kts)

```kotlin
plugins {
    id("jacoco")
}

tasks.test {
    useJUnitPlatform()
    finalizedBy(tasks.jacocoTestReport)
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required.set(true)
        html.required.set(true)
    }
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                minimum = "0.80".toBigDecimal()
            }
        }
    }
}
```

## Common Testing Mistakes to Avoid

### WRONG: Testing Implementation Details

```java
// Don't test private methods directly
assertThat(service.getInternalState()).isEqualTo(expected);
```

### CORRECT: Test Observable Behavior

```java
// Test public API and side effects
StepVerifier.create(service.processOrder(request))
    .assertNext(order -> assertThat(order.status()).isEqualTo(OrderStatus.COMPLETED))
    .verifyComplete();

verify(notificationService).sendOrderConfirmation(any());
```

### WRONG: No Test Isolation

```java
// Tests depend on each other
@Test void test1_createUser() { /* creates user */ }
@Test void test2_updateUser() { /* depends on test1 */ }
```

### CORRECT: Independent Tests

```java
@BeforeEach
void setUp() {
    // Reset state before each test
    repository.deleteAll().block();
}

@Test void shouldCreateUser() { /* independent */ }
@Test void shouldUpdateUser() { /* independent */ }
```

### WRONG: Sleeping Instead of Awaiting

```java
// Flaky and slow
Thread.sleep(5000);
assertThat(result).isNotNull();
```

### CORRECT: Use StepVerifier or Awaitility

```java
// Reactive testing
StepVerifier.create(asyncOperation())
    .expectNext(expected)
    .verifyComplete();

// Or with Awaitility
await().atMost(5, SECONDS)
    .untilAsserted(() -> assertThat(getResult()).isNotNull());
```

## Continuous Testing

### Watch Mode During Development

```bash
./gradlew test --continuous
# Tests run automatically on file changes
```

### Pre-Commit Hook (CI Integration)

```yaml
# .github/workflows/test.yml
- name: Run Tests
  run: ./gradlew test

- name: Check Coverage
  run: ./gradlew jacocoTestCoverageVerification

- name: Upload Coverage
  uses: codecov/codecov-action@v3
  with:
    files: build/reports/jacoco/test/jacocoTestReport.xml
```

## Success Metrics

- 80%+ code coverage achieved
- All tests passing (green)
- No skipped or disabled tests
- Fast test execution (<30s for unit tests)
- Integration tests with Testcontainers
- E2E tests cover critical user flows
- Tests catch bugs before production

---

**Remember**: Tests are not optional. They are the safety net that enables confident refactoring, rapid development, and
production reliability.
