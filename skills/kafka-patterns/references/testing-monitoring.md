# Kafka Testing & Monitoring Reference

EmbeddedKafka, Testcontainers, Schema Registry testing, Micrometer metrics.

## Table of Contents
- [EmbeddedKafka Tests](#embeddedkafka-tests)
- [Testcontainers + Schema Registry](#testcontainers--schema-registry)
- [Consumer Testing with Awaitility](#consumer-testing-with-awaitility)
- [Micrometer Consumer & Producer Listeners](#micrometer-consumer--producer-listeners)
- [Consumer Lag Monitor](#consumer-lag-monitor)
- [Health Indicator](#health-indicator)

---

## EmbeddedKafka Tests

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

        // Verify event was published — use consumer or KafkaTemplate listener
    }
}
```

---

## Testcontainers + Schema Registry

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

## Consumer Testing with Awaitility

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
        // Setup consumer on DLT
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

## Micrometer Consumer & Producer Listeners

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

## Consumer Lag Monitor

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
                    // Calculate lag per partition
                    // ... report to Micrometer
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

## Health Indicator

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
