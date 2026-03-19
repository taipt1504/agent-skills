# Testing & Monitoring Reference

EmbeddedKafka, Testcontainers for Kafka and RabbitMQ, Awaitility, consumer lag monitoring, health indicators, and Micrometer metrics.

## Table of Contents
- [Kafka: EmbeddedKafka Tests](#kafka-embeddedkafka-tests)
- [Kafka: Testcontainers + Schema Registry](#kafka-testcontainers--schema-registry)
- [Kafka: Consumer Testing with Awaitility](#kafka-consumer-testing-with-awaitility)
- [RabbitMQ: Testcontainers Tests](#rabbitmq-testcontainers-tests)
- [RabbitMQ: DLQ Routing Tests](#rabbitmq-dlq-routing-tests)
- [RabbitMQ: Awaitility Consumer Testing](#rabbitmq-awaitility-consumer-testing)
- [Monitoring: Kafka Consumer Lag](#monitoring-kafka-consumer-lag)
- [Monitoring: Kafka Health Indicator](#monitoring-kafka-health-indicator)
- [Monitoring: Micrometer Metrics (Kafka)](#monitoring-micrometer-metrics-kafka)
- [Monitoring: RabbitMQ Health and Metrics](#monitoring-rabbitmq-health-and-metrics)

---

## Kafka: EmbeddedKafka Tests

Fast, in-process Kafka for unit/integration tests. No Docker required.

```java
@SpringBootTest
@EmbeddedKafka(
    partitions = 3,
    topics = {"order-events", "order-events.DLT"},
    brokerProperties = {
        "auto.create.topics.enable=false",
        "transaction.state.log.replication.factor=1",
        "transaction.state.log.min.isr=1"
    }
)
class OrderEventProducerTest {

    @Autowired
    private OrderEventProducer producer;

    @Autowired
    private EmbeddedKafkaBroker embeddedKafka;

    @Test
    void shouldSendOrderEvent() throws Exception {
        // Setup consumer to verify
        Map<String, Object> consumerProps = KafkaTestUtils.consumerProps(
            "test-group", "true", embeddedKafka);
        consumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        var consumer = new DefaultKafkaConsumerFactory<String, String>(consumerProps)
            .createConsumer();
        embeddedKafka.consumeFromAnEmbeddedTopic(consumer, "order-events");

        // Act
        producer.sendOrderEvent("order-1", new OrderCreatedEvent("order-1", "customer-1"));

        // Assert
        var records = KafkaTestUtils.getRecords(consumer, Duration.ofSeconds(5));
        assertThat(records.count()).isEqualTo(1);
        var record = records.iterator().next();
        assertThat(record.key()).isEqualTo("order-1");
        consumer.close();
    }
}

// Producer test with @MockBean for dependency isolation
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = "order-events")
class OrderServiceKafkaTest {

    @Autowired
    private OrderService orderService;

    @MockBean
    private PaymentPort paymentPort;

    @Test
    void shouldPublishEventOnOrderCreation() {
        when(paymentPort.processPayment(any(), any(), any()))
            .thenReturn(Mono.just(PaymentResult.success("tx-123")));

        StepVerifier.create(orderService.createOrder(validCommand()))
            .expectNextMatches(r -> r.status() == OrderStatus.CONFIRMED)
            .verifyComplete();
    }
}
```

---

## Kafka: Testcontainers + Schema Registry

For full integration tests with real Kafka and Schema Registry.

```java
@SpringBootTest
@Testcontainers
@ActiveProfiles("integration")
class AvroOrderEventTest {

    @Container
    static final KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0"))
        .withNetwork(Network.newNetwork());

    @Container
    static final GenericContainer<?> schemaRegistry = new GenericContainer<>(
        DockerImageName.parse("confluentinc/cp-schema-registry:7.5.0"))
        .dependsOn(kafka)
        .withNetwork(kafka.getNetwork())
        .withNetworkAliases("schema-registry")
        .withEnv("SCHEMA_REGISTRY_HOST_NAME", "schema-registry")
        .withEnv("SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS",
            "PLAINTEXT://" + kafka.getNetworkAliases().get(0) + ":9092")
        .withExposedPorts(8081)
        .waitingFor(Wait.forHttp("/subjects").forStatusCode(200));

    @DynamicPropertySource
    static void kafkaProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
        registry.add("spring.kafka.producer.properties.schema.registry.url",
            () -> "http://" + schemaRegistry.getHost() + ":" + schemaRegistry.getMappedPort(8081));
        registry.add("spring.kafka.consumer.properties.schema.registry.url",
            () -> "http://" + schemaRegistry.getHost() + ":" + schemaRegistry.getMappedPort(8081));
    }

    @Autowired
    private ReactiveKafkaProducerTemplate<String, OrderEvent> producer;

    @Test
    void shouldSerializeDeserializeAvroEvent() {
        OrderEvent event = OrderEvent.newBuilder()
            .setOrderId("order-1")
            .setCustomerId("customer-1")
            .setStatus(OrderStatus.ORDER_STATUS_CREATED)
            .build();

        StepVerifier.create(producer.send("order-events", event.getOrderId(), event))
            .expectNextCount(1)
            .verifyComplete();
    }
}
```

---

## Kafka: Consumer Testing with Awaitility

```java
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = "order-events")
class OrderConsumerIntegrationTest {

    @Autowired
    private KafkaTemplate<String, Object> kafkaTemplate;

    @SpyBean
    private OrderConsumer orderConsumer;  // spy on actual consumer

    @Test
    void shouldProcessOrderEvent() throws Exception {
        var event = new OrderCreatedEvent("order-1", "customer-1", Money.of(100, "USD"));
        kafkaTemplate.send("order-events", "order-1", event);

        // Wait for async processing
        await().atMost(Duration.ofSeconds(10))
            .untilAsserted(() ->
                verify(orderConsumer, times(1)).handleOrderCreated(any()));
    }

    @Test
    void shouldSendToDeadLetterOnFailure() {
        var dlqRecords = new ArrayList<ConsumerRecord<String, Object>>();
        // ... setup DLT consumer

        when(orderConsumer.handleOrderCreated(any()))
            .thenThrow(new RuntimeException("Processing failed"));

        kafkaTemplate.send("order-events", "order-1", invalidEvent);

        await().atMost(Duration.ofSeconds(30))
            .until(() -> !dlqRecords.isEmpty());
        assertThat(dlqRecords.get(0).key()).isEqualTo("order-1");
    }
}
```

---

## RabbitMQ: Testcontainers Tests

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

## RabbitMQ: DLQ Routing Tests

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
        // Send malformed payload -- causes deserialization failure -> DLQ
        rabbitTemplate.convertAndSend(
            ORDERS_EXCHANGE, ORDER_CREATED_KEY, "INVALID_PAYLOAD");

        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
            assertThat(dlqRepository.count()).isGreaterThan(0));
    }

    @Test
    void shouldRouteToDeadLetterAfterRetryExhaustion() {
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

## RabbitMQ: Awaitility Consumer Testing

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

---

## Monitoring: Kafka Consumer Lag

```java
@Component @RequiredArgsConstructor @Slf4j
public class KafkaConsumerLagMonitor {
    private final KafkaAdmin kafkaAdmin;
    private final MeterRegistry meterRegistry;
    private final String groupId;
    private final String bootstrapServers;

    @Scheduled(fixedDelay = 30_000)
    public void reportConsumerLag() {
        try (AdminClient adminClient = AdminClient.create(
                Map.of(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers))) {

            adminClient.listConsumerGroupOffsets(groupId)
                .partitionsToOffsetAndMetadata()
                .thenApply(offsets -> {
                    Set<TopicPartition> partitions = offsets.keySet();
                    return adminClient.listOffsets(partitions.stream()
                        .collect(Collectors.toMap(p -> p, p -> OffsetSpec.latest())));
                })
                .thenAccept(endOffsets -> endOffsets.all().thenAccept(latestOffsets -> {
                    // Calculate lag per partition and report to Micrometer
                }));

        } catch (Exception ex) {
            log.error("Failed to get consumer lag", ex);
        }
    }

    // Simpler: use Micrometer Kafka Binder for Spring Boot
    // Add: io.micrometer:micrometer-registry-prometheus
    // Metrics auto-exposed: kafka.consumer.records-lag, kafka.consumer.fetch-rate, etc.
}
```

---

## Monitoring: Kafka Health Indicator

```java
@Component @RequiredArgsConstructor
public class KafkaHealthIndicator implements HealthIndicator {
    private final KafkaAdmin kafkaAdmin;

    @Override
    public Health health() {
        try {
            var adminClient = AdminClient.create(kafkaAdmin.getConfigurationProperties());
            adminClient.describeCluster().clusterId().get(5, TimeUnit.SECONDS);
            adminClient.close();
            return Health.up().withDetail("kafka", "Connected").build();
        } catch (Exception ex) {
            return Health.down(ex).withDetail("kafka", ex.getMessage()).build();
        }
    }
}
```

---

## Monitoring: Micrometer Metrics (Kafka)

### Producer and Consumer Listeners

```java
@Configuration
public class KafkaMetricsConfig {

    @Bean
    public ProducerListener<String, Object> kafkaProducerListener(MeterRegistry registry) {
        return new ProducerListener<>() {
            @Override
            public void onSuccess(ProducerRecord<String, Object> record,
                                  RecordMetadata metadata) {
                registry.counter("kafka.producer.success",
                    "topic", record.topic()).increment();
            }

            @Override
            public void onError(ProducerRecord<String, Object> record,
                                RecordMetadata metadata, Exception ex) {
                registry.counter("kafka.producer.error",
                    "topic", record.topic(),
                    "exception", ex.getClass().getSimpleName()).increment();
            }
        };
    }

    // Consumer timing metric
    @Bean
    public RecordInterceptor<String, Object> timedRecordInterceptor(MeterRegistry registry) {
        return new RecordInterceptor<>() {
            private Timer.Sample sample;

            @Override
            public ConsumerRecord<String, Object> intercept(
                    ConsumerRecord<String, Object> record, Consumer<String, Object> consumer) {
                sample = Timer.start(registry);
                return record;
            }

            @Override
            public void afterRecord(ConsumerRecord<String, Object> record,
                                    Consumer<String, Object> consumer) {
                if (sample != null)
                    sample.stop(registry.timer("kafka.consumer.process.time",
                        "topic", record.topic(),
                        "group", consumer.groupMetadata().groupId()));
            }
        };
    }
}
```

---

## Monitoring: RabbitMQ Health and Metrics

### Spring Boot Actuator (auto-configured)

RabbitMQ health is auto-configured when `spring-boot-starter-amqp` is on the classpath.

```yaml
management:
  health:
    rabbit:
      enabled: true
  endpoints:
    web:
      exposure:
        include: health,metrics,prometheus
```

### Key Micrometer Metrics for RabbitMQ

Spring AMQP auto-registers these metrics when Micrometer is present:

| Metric | Description |
|--------|-------------|
| `rabbitmq.connections` | Active connection count |
| `rabbitmq.channels` | Active channel count |
| `rabbitmq.published` | Messages published (counter) |
| `rabbitmq.consumed` | Messages consumed (counter) |
| `rabbitmq.acknowledged` | Messages acknowledged (counter) |
| `rabbitmq.rejected` | Messages rejected (counter) |
| `rabbitmq.failed` | Publish failures (counter) |

### Custom Queue Depth Monitor

```java
@Component @RequiredArgsConstructor @Slf4j
public class RabbitQueueDepthMonitor {
    private final RabbitAdmin rabbitAdmin;
    private final MeterRegistry meterRegistry;

    @Scheduled(fixedDelay = 30_000)
    public void reportQueueDepth() {
        List<String> queues = List.of(ORDERS_CREATED_QUEUE, ORDERS_CREATED_DLQ);
        for (String queue : queues) {
            QueueInformation info = rabbitAdmin.getQueueInfo(queue);
            if (info != null) {
                meterRegistry.gauge("rabbitmq.queue.depth",
                    Tags.of("queue", queue),
                    info.getMessageCount());
                if (queue.endsWith(".dlq") && info.getMessageCount() > 0) {
                    log.warn("DLQ {} has {} messages", queue, info.getMessageCount());
                }
            }
        }
    }
}
```

### Alerting Recommendations

| Metric | Alert Threshold | Action |
|--------|----------------|--------|
| Kafka consumer lag | > 10,000 records | Scale consumers or investigate slow processing |
| Kafka producer error rate | > 1% | Check broker health, network connectivity |
| RabbitMQ queue depth | > 50,000 | Scale consumers, check for stuck messages |
| RabbitMQ DLQ depth | > 0 | Investigate failed messages, fix root cause |
| Consumer processing time | p99 > 5s | Optimize handler, increase concurrency |
| Connection count | Near pool limit | Increase pool size or reduce connection churn |
