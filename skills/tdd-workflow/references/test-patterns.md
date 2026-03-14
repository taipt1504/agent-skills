# Test Patterns Reference

Concrete test examples for Java Spring projects. Load this when writing tests.

## Table of Contents
- [Unit Test Pattern](#unit-test-pattern-junit-5--mockito)
- [WebFlux Integration Test](#webflux-integration-test-pattern)
- [Spring MVC Integration Test](#spring-mvc-integration-test-pattern)
- [Repository Test (R2DBC)](#repository-test-pattern-r2dbc)
- [Repository Test (JPA)](#repository-test-pattern-jpa--mysql)
- [Kafka Integration Test](#kafka-integration-test-pattern)
- [Mocking Patterns](#mocking-patterns)
- [Coverage Configuration](#test-coverage-configuration)
- [Common Mistakes](#common-testing-mistakes-to-avoid)

---

## Unit Test Pattern (JUnit 5 + Mockito)

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock private OrderRepository orderRepository;
    @Mock private NotificationService notificationService;

    @InjectMocks private OrderService orderService;

    @Test
    @DisplayName("Should create order successfully")
    void shouldCreateOrder() {
        // Arrange
        var cmd = new CreateOrderCommand(1L, List.of(new OrderItem(100L, 2)));
        var expected = Order.builder().id(1L).status(OrderStatus.PENDING).build();
        when(orderRepository.save(any())).thenReturn(Mono.just(expected));

        // Act & Assert
        StepVerifier.create(orderService.create(cmd))
            .assertNext(order -> {
                assertThat(order.getId()).isEqualTo(1L);
                assertThat(order.getStatus()).isEqualTo(OrderStatus.PENDING);
            })
            .verifyComplete();

        verify(orderRepository).save(any(Order.class));
    }

    @Test
    @DisplayName("Should throw NotFoundException when order not found")
    void shouldThrowWhenNotFound() {
        when(orderRepository.findById(99L)).thenReturn(Mono.empty());

        StepVerifier.create(orderService.findById(99L))
            .expectError(ResourceNotFoundException.class)
            .verify();
    }
}
```

---

## WebFlux Integration Test Pattern

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@Testcontainers
class OrderControllerIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withReuse(true);  // ✅ Reuse container for faster tests

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:postgresql://" + postgres.getHost() + ":" +
            postgres.getFirstMappedPort() + "/testdb");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired private WebTestClient webTestClient;
    @Autowired private OrderRepository orderRepository;

    @BeforeEach
    void setUp() { orderRepository.deleteAll().block(); }

    @Test
    void shouldCreateOrder() {
        var request = new CreateOrderRequest(1L, List.of(new OrderItemRequest(100L, 2)), "123 Main St", null);

        webTestClient.post().uri("/api/v1/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.status").isEqualTo("PENDING")
            .jsonPath("$.id").isNotEmpty();
    }

    @Test
    void shouldReturn404ForUnknownOrder() {
        webTestClient.get().uri("/api/v1/orders/99999")
            .exchange()
            .expectStatus().isNotFound();
    }

    @Test
    void shouldReturn400ForInvalidRequest() {
        webTestClient.post().uri("/api/v1/orders")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(new CreateOrderRequest(null, List.of(), "", null))
            .exchange()
            .expectStatus().isBadRequest()
            .expectBody()
            .jsonPath("$.errors").isArray();
    }
}
```

---

## Spring MVC Integration Test Pattern

```java
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)
class OrderControllerMvcTest {

    @Autowired MockMvc mockMvc;
    @MockBean OrderService orderService;
    @MockBean OrderMapper orderMapper;
    @Autowired ObjectMapper objectMapper;

    @Test
    @WithMockUser(roles = "USER")
    void shouldCreateOrder() throws Exception {
        var request = new CreateOrderRequest(1L, List.of(new OrderItemRequest(100L, 2)), "addr", null);
        var response = new OrderResponse(1L, "PENDING", BigDecimal.TEN);
        when(orderService.create(any(), any())).thenReturn(new Order());
        when(orderMapper.toResponse(any())).thenReturn(response);

        mockMvc.perform(post("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.status").value("PENDING"));
    }

    @Test
    void shouldReturn401WhenUnauthenticated() throws Exception {
        mockMvc.perform(get("/api/v1/orders"))
            .andExpect(status().isUnauthorized());
    }
}
```

---

## Repository Test Pattern (R2DBC)

```java
@DataR2dbcTest
@Testcontainers
@Import(R2dbcConfig.class)
class OrderRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withReuse(true);

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:postgresql://" + postgres.getHost() + ":" +
            postgres.getFirstMappedPort() + "/testdb");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired private OrderRepository repository;

    @BeforeEach
    void setUp() { repository.deleteAll().block(); }

    @Test
    void shouldSaveAndRetrieve() {
        var order = Order.builder().userId(1L).status(OrderStatus.PENDING).build();

        StepVerifier.create(repository.save(order).flatMap(saved -> repository.findById(saved.getId())))
            .assertNext(found -> {
                assertThat(found.getUserId()).isEqualTo(1L);
                assertThat(found.getStatus()).isEqualTo(OrderStatus.PENDING);
            })
            .verifyComplete();
    }
}
```

---

## Repository Test Pattern (JPA + MySQL)

```java
@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class OrderRepositoryJpaTest {

    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withReuse(true);

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
    }

    @Autowired private OrderRepository repository;

    @BeforeEach
    void setUp() { repository.deleteAll(); }

    @Test
    void shouldPersistOrder() {
        var order = Order.builder().userId(1L).status(OrderStatus.PENDING)
            .totalAmount(BigDecimal.TEN).build();
        var saved = repository.save(order);
        assertThat(saved.getId()).isNotNull();
        assertThat(repository.findById(saved.getId())).isPresent();
    }
}
```

---

## Kafka Integration Test Pattern

```java
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = {"order-events"})
class OrderEventPublisherTest {

    @Autowired private OrderEventPublisher publisher;

    @Autowired
    @Qualifier("testKafkaConsumer")
    private Consumer<String, String> consumer;

    @Test
    void shouldPublishOrderCreatedEvent() throws Exception {
        var event = new OrderCreatedEvent(1L, 1L, BigDecimal.TEN);

        publisher.publish(event);

        ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(5));
        assertThat(records.count()).isEqualTo(1);

        var record = records.iterator().next();
        assertThat(record.topic()).isEqualTo("order-events");
        assertThat(record.value()).contains("\"orderId\":1");
    }
}
```

---

## Mocking Patterns

### Repository Mock (Reactive)

```java
@Mock private OrderRepository orderRepository;

@BeforeEach
void setupMocks() {
    // Single item
    when(orderRepository.findById(1L)).thenReturn(Mono.just(buildOrder(1L)));

    // Empty (not found)
    when(orderRepository.findById(99L)).thenReturn(Mono.empty());

    // List
    when(orderRepository.findByUserId(1L)).thenReturn(Flux.just(buildOrder(1L), buildOrder(2L)));

    // Save (return argument)
    when(orderRepository.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
}
```

### External HTTP Client (WireMock)

```java
@WireMockTest(httpPort = 8089)
class InventoryClientTest {

    @Autowired private InventoryClient client;

    @Test
    void shouldFetchInventory() {
        stubFor(get("/inventory/100")
            .willReturn(okJson("{\"productId\":100,\"quantity\":50}")));

        StepVerifier.create(client.getInventory(100L))
            .assertNext(inv -> assertThat(inv.quantity()).isEqualTo(50))
            .verifyComplete();
    }

    @Test
    void shouldHandleServiceUnavailable() {
        stubFor(get("/inventory/100").willReturn(serviceUnavailable()));

        StepVerifier.create(client.getInventory(100L))
            .expectError(ServiceUnavailableException.class)
            .verify();
    }
}
```

### Redis Mock (Reactive)

```java
@Mock private ReactiveRedisTemplate<String, Order> redisTemplate;
@Mock private ReactiveValueOperations<String, Order> valueOps;

@BeforeEach
void setupRedisMock() {
    when(redisTemplate.opsForValue()).thenReturn(valueOps);
    when(valueOps.get(anyString())).thenReturn(Mono.empty());   // Cache miss
    when(valueOps.set(anyString(), any(), any(Duration.class))).thenReturn(Mono.just(true));
}
```

---

## Test Coverage Configuration

### Gradle (build.gradle.kts)

```kotlin
plugins { id("jacoco") }

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
            limit { minimum = "0.80".toBigDecimal() }  // 80% line coverage
        }
    }
}
```

### Maven (pom.xml)

```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <executions>
        <execution>
            <goals><goal>prepare-agent</goal></goals>
        </execution>
        <execution>
            <id>report</id>
            <phase>test</phase>
            <goals><goal>report</goal></goals>
        </execution>
        <execution>
            <id>check</id>
            <goals><goal>check</goal></goals>
            <configuration>
                <rules>
                    <rule>
                        <limits>
                            <limit>
                                <counter>LINE</counter>
                                <value>COVEREDRATIO</value>
                                <minimum>0.80</minimum>
                            </limit>
                        </limits>
                    </rule>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

---

## Common Testing Mistakes to Avoid

```java
// ❌ WRONG: Testing private methods or implementation details
assertThat(service.internalCache).isNotEmpty();

// ✅ CORRECT: Test observable behavior
StepVerifier.create(service.processOrder(request))
    .assertNext(order -> assertThat(order.status()).isEqualTo(OrderStatus.COMPLETED))
    .verifyComplete();
verify(notificationService).sendOrderConfirmation(any());

// ❌ WRONG: Tests depend on each other / shared state
@Test void test1() { repository.save(order); }
@Test void test2() { assertThat(repository.count()).isEqualTo(1); }  // Depends on test1!

// ✅ CORRECT: @BeforeEach cleanup + independent tests
@BeforeEach void setUp() { repository.deleteAll().block(); }

// ❌ WRONG: Thread.sleep() for async assertions
Thread.sleep(2000);
assertThat(result.get()).isNotNull();

// ✅ CORRECT: StepVerifier or Awaitility
StepVerifier.create(asyncOp()).expectNext(expected).verifyComplete();
// Or for MVC @Async:
await().atMost(5, SECONDS).untilAsserted(() -> assertThat(result.get()).isNotNull());

// ❌ WRONG: @SpringBootTest for unit/controller slice tests (slow)
@SpringBootTest
class OrderControllerTest { ... }

// ✅ CORRECT: Use test slices
@WebMvcTest(OrderController.class)    // MVC
@DataR2dbcTest                         // R2DBC repository
@DataJpaTest                           // JPA repository
```
