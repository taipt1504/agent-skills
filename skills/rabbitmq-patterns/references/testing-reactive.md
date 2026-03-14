# RabbitMQ Testing & Reactive Patterns Reference

Reactor RabbitMQ (WebFlux), Testcontainers, DLQ routing tests, and Awaitility consumer testing.

## Table of Contents
- [Reactor RabbitMQ (WebFlux)](#reactor-rabbitmq-webflux)
- [Testcontainers Integration Tests](#testcontainers-integration-tests)
- [DLQ Routing Tests](#dlq-routing-tests)
- [Awaitility Consumer Testing](#awaitility-consumer-testing)

---

## Reactor RabbitMQ (WebFlux)

Use `reactor-rabbitmq` instead of `RabbitTemplate` in reactive applications to avoid blocking.

```java
@Configuration
public class ReactiveRabbitConfig {

    @Bean
    public Sender reactiveRabbitSender(ConnectionFactory connectionFactory) {
        SenderOptions options = new SenderOptions()
            .connectionFactory(connectionFactory)
            .resourceManagementChannelMono(
                Mono.fromCallable(connectionFactory::createConnection)
                    .flatMap(conn -> Mono.fromCallable(conn::createChannel))
                    .cache());
        return RabbitFlux.createSender(options);
    }

    @Bean
    public Receiver reactiveRabbitReceiver(ConnectionFactory connectionFactory) {
        return RabbitFlux.createReceiver(
            new ReceiverOptions().connectionFactory(connectionFactory));
    }
}
```

```java
@Service @RequiredArgsConstructor
public class ReactiveOrderPublisher {
    private final Sender sender;
    private final ObjectMapper objectMapper;

    public Mono<Void> publish(OrderCreatedEvent event) {
        return Mono.fromCallable(() -> objectMapper.writeValueAsBytes(event))
            .map(body -> new OutboundMessage(ORDERS_EXCHANGE, ORDER_CREATED_KEY, body))
            .flatMap(msg -> sender.send(Mono.just(msg)))
            .doOnError(e -> log.error("Failed to publish event: {}", e.getMessage()));
    }

    public Flux<SendResult> publishBatch(Flux<OrderCreatedEvent> events) {
        return sender.sendWithPublishConfirms(
            events.map(event -> {
                try {
                    byte[] body = objectMapper.writeValueAsBytes(event);
                    return new OutboundMessageResult<>(
                        new OutboundMessage(ORDERS_EXCHANGE, ORDER_CREATED_KEY, body),
                        event);
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            })
        ).doOnNext(result -> {
            if (!result.isAck()) {
                log.error("Publish not confirmed for event: {}", result.getOutboundMessage());
            }
        });
    }
}
```

```java
// Reactive consumer
@Service @RequiredArgsConstructor
public class ReactiveOrderConsumer {
    private final Receiver receiver;

    @PostConstruct
    public void startConsuming() {
        receiver.consumeManualAck(ORDERS_CREATED_QUEUE)
            .flatMap(delivery -> processDelivery(delivery)
                .doOnSuccess(v -> delivery.ack())
                .doOnError(e -> delivery.nack(false)))  // nack without requeue → DLQ
            .subscribe(
                v -> {},
                e -> log.error("Consumer error", e));
    }

    private Mono<Void> processDelivery(AcknowledgableDelivery delivery) {
        return Mono.fromCallable(() ->
            objectMapper.readValue(delivery.getBody(), OrderCreatedEvent.class))
            .flatMap(event -> orderService.processOrderCreated(event));
    }
}
```

---

## Testcontainers Integration Tests

```java
@SpringBootTest
@Testcontainers
class OrderEventConsumerTest {

    @Container
    static RabbitMQContainer rabbitMQ = new RabbitMQContainer(
        DockerImageName.parse("rabbitmq:3.12-management"))
        .withReuse(true);

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.rabbitmq.host", rabbitMQ::getHost);
        registry.add("spring.rabbitmq.port", rabbitMQ::getAmqpPort);
        registry.add("spring.rabbitmq.username", rabbitMQ::getAdminUsername);
        registry.add("spring.rabbitmq.password", rabbitMQ::getAdminPassword);
    }

    @Autowired private RabbitTemplate rabbitTemplate;
    @Autowired private OrderRepository orderRepository;

    @Test
    void shouldProcessOrderCreatedEvent() {
        var event = new OrderCreatedEvent("order-123", "user-456", BigDecimal.TEN);

        rabbitTemplate.convertAndSend(ORDERS_EXCHANGE, ORDER_CREATED_KEY, event);

        // Wait for async consumer processing
        await().atMost(Duration.ofSeconds(5)).untilAsserted(() ->
            assertThat(orderRepository.findById("order-123")).isPresent());
    }

    @Test
    void shouldPublishWithConfirms() {
        var event = new OrderCreatedEvent("order-456", "user-789", BigDecimal.ONE);
        var correlationData = new CorrelationData("order-456");

        rabbitTemplate.convertAndSend(ORDERS_EXCHANGE, ORDER_CREATED_KEY,
            event, correlationData);

        await().atMost(Duration.ofSeconds(3)).untilAsserted(() ->
            assertThat(correlationData.getFuture().isDone()).isTrue());
    }
}
```

---

## DLQ Routing Tests

```java
@SpringBootTest
@Testcontainers
class DlqRoutingTest {

    @Container
    static RabbitMQContainer rabbitMQ = new RabbitMQContainer("rabbitmq:3.12-management");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.rabbitmq.host", rabbitMQ::getHost);
        registry.add("spring.rabbitmq.port", rabbitMQ::getAmqpPort);
    }

    @Autowired private RabbitTemplate rabbitTemplate;
    @Autowired private DlqRepository dlqRepository;

    @Test
    void shouldRouteToDeadLetterOnPermanentFailure() {
        // Send malformed payload — causes deserialization failure → DLQ
        rabbitTemplate.convertAndSend(
            ORDERS_EXCHANGE, ORDER_CREATED_KEY, "INVALID_PAYLOAD");

        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
            assertThat(dlqRepository.count()).isGreaterThan(0));
    }

    @Test
    void shouldRouteToDeadLetterAfterRetryExhaustion() {
        // Mock service to always fail
        when(orderService.processOrderCreated(any()))
            .thenThrow(new RuntimeException("Simulated permanent failure"));

        var event = new OrderCreatedEvent("order-999", "user-123", BigDecimal.TEN);
        rabbitTemplate.convertAndSend(ORDERS_EXCHANGE, ORDER_CREATED_KEY, event);

        // Wait for 3 retries + DLQ routing
        await().atMost(Duration.ofSeconds(30)).untilAsserted(() ->
            assertThat(dlqRepository.findByOriginalOrderId("order-999")).isPresent());
    }

    @Test
    void shouldVerifyDlqMessageContainsDeathHeaders() {
        rabbitTemplate.convertAndSend(ORDERS_EXCHANGE, ORDER_CREATED_KEY, "INVALID");

        await().atMost(Duration.ofSeconds(10)).untilAsserted(() -> {
            var dlqRecords = dlqRepository.findAll();
            assertThat(dlqRecords).isNotEmpty();
            assertThat(dlqRecords.getFirst().getReason()).isIn("rejected", "expired");
        });
    }
}
```

---

## Awaitility Consumer Testing

```java
@SpringBootTest
@Testcontainers
class OrderEventConsumerIntegrationTest {

    @Container
    static RabbitMQContainer rabbitMQ = new RabbitMQContainer("rabbitmq:3.12-management");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.rabbitmq.host", rabbitMQ::getHost);
        r.add("spring.rabbitmq.port", rabbitMQ::getAmqpPort);
    }

    @Autowired private RabbitTemplate rabbitTemplate;
    @SpyBean private OrderService orderService;

    @Test
    void shouldCallOrderServiceOnMessage() {
        var event = new OrderCreatedEvent("order-111", "customer-1", new BigDecimal("99.99"));

        rabbitTemplate.convertAndSend(ORDERS_EXCHANGE, ORDER_CREATED_KEY, event);

        // Use @SpyBean to verify service was called with correct data
        await().atMost(Duration.ofSeconds(5)).untilAsserted(() ->
            verify(orderService).processOrderCreated(
                argThat(e -> e.orderId().equals("order-111"))));
    }

    @Test
    void shouldProcessMultipleEventsInOrder() {
        var events = List.of(
            new OrderCreatedEvent("order-1", "c-1", BigDecimal.ONE),
            new OrderCreatedEvent("order-2", "c-2", BigDecimal.TEN),
            new OrderCreatedEvent("order-3", "c-3", new BigDecimal("100"))
        );

        events.forEach(e ->
            rabbitTemplate.convertAndSend(ORDERS_EXCHANGE, ORDER_CREATED_KEY, e));

        await().atMost(Duration.ofSeconds(10)).untilAsserted(() -> {
            var processedIds = orderRepository.findAll().stream()
                .map(Order::getId).toList();
            assertThat(processedIds).containsExactlyInAnyOrder("order-1", "order-2", "order-3");
        });
    }
}
```
