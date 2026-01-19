# Kafka Patterns Reference

## Overview

Apache Kafka là distributed streaming platform được thiết kế cho high-throughput, fault-tolerant messaging. Document này cung cấp deep-dive vào Kafka patterns cho Java applications.

---

## Architecture Fundamentals

### Kafka Cluster Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              Kafka Cluster               │
                    │  ┌─────────┐ ┌─────────┐ ┌─────────┐   │
                    │  │Broker 1 │ │Broker 2 │ │Broker 3 │   │
                    │  │(Leader) │ │(Follower)│ │(Follower)│  │
                    │  └────┬────┘ └────┬────┘ └────┬────┘   │
                    │       │           │           │         │
                    │  ┌────┴───────────┴───────────┴────┐   │
                    │  │         Topic: orders            │   │
                    │  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐   │   │
                    │  │  │ P0 │ │ P1 │ │ P2 │ │ P3 │   │   │
                    │  │  └────┘ └────┘ └────┘ └────┘   │   │
                    │  └──────────────────────────────────┘   │
                    └─────────────────────────────────────────┘
                                       │
               ┌───────────────────────┼───────────────────────┐
               │                       │                       │
        ┌──────┴──────┐         ┌──────┴──────┐         ┌──────┴──────┐
        │  Producer   │         │  Consumer   │         │  Consumer   │
        │  (Order     │         │  Group A    │         │  Group B    │
        │   Service)  │         │  (3 inst.)  │         │  (2 inst.)  │
        └─────────────┘         └─────────────┘         └─────────────┘
```

### Partition và Replication

```java
// Topic configuration
@Configuration
public class KafkaTopicConfig {

    @Bean
    public NewTopic ordersTopic() {
        return TopicBuilder.name("orders")
            .partitions(12)      // Number of partitions
            .replicas(3)         // Replication factor
            .config(TopicConfig.RETENTION_MS_CONFIG, "604800000")  // 7 days
            .config(TopicConfig.CLEANUP_POLICY_CONFIG, "delete")
            .config(TopicConfig.MIN_IN_SYNC_REPLICAS_CONFIG, "2")
            .config(TopicConfig.COMPRESSION_TYPE_CONFIG, "lz4")
            .build();
    }

    // Compacted topic for state
    @Bean
    public NewTopic orderStateTopic() {
        return TopicBuilder.name("order-state")
            .partitions(12)
            .replicas(3)
            .config(TopicConfig.CLEANUP_POLICY_CONFIG, "compact")
            .config(TopicConfig.MIN_CLEANABLE_DIRTY_RATIO_CONFIG, "0.1")
            .config(TopicConfig.SEGMENT_MS_CONFIG, "3600000")  // 1 hour
            .build();
    }
}
```

---

## Producer Patterns

### Basic Producer Configuration

```java
@Configuration
public class KafkaProducerConfig {

    @Value("${spring.kafka.bootstrap-servers}")
    private String bootstrapServers;

    @Bean
    public Map<String, Object> producerConfigs() {
        Map<String, Object> props = new HashMap<>();

        // Connection
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.CLIENT_ID_CONFIG, "order-service-producer");

        // Serialization
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG,
            StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
            JsonSerializer.class);

        // Reliability
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.RETRIES_CONFIG, Integer.MAX_VALUE);
        props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);

        // Performance
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, 32768);  // 32KB
        props.put(ProducerConfig.LINGER_MS_CONFIG, 20);
        props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, 67108864);  // 64MB
        props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4");

        // Timeouts
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 30000);
        props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 120000);

        return props;
    }

    @Bean
    public ProducerFactory<String, Object> producerFactory() {
        return new DefaultKafkaProducerFactory<>(producerConfigs());
    }

    @Bean
    public KafkaTemplate<String, Object> kafkaTemplate() {
        KafkaTemplate<String, Object> template =
            new KafkaTemplate<>(producerFactory());

        // Global send interceptor
        template.setProducerInterceptor(new ProducerInterceptor<>() {
            @Override
            public ProducerRecord<String, Object> onSend(
                    ProducerRecord<String, Object> record) {
                // Add tracing headers
                record.headers().add("trace-id",
                    MDC.get("traceId").getBytes(StandardCharsets.UTF_8));
                record.headers().add("timestamp",
                    String.valueOf(System.currentTimeMillis())
                        .getBytes(StandardCharsets.UTF_8));
                return record;
            }

            @Override
            public void onAcknowledgement(RecordMetadata metadata,
                                          Exception exception) {
                if (exception != null) {
                    log.error("Send failed: {}", exception.getMessage());
                }
            }

            @Override
            public void close() {}

            @Override
            public void configure(Map<String, ?> configs) {}
        });

        return template;
    }
}
```

### Transactional Producer

```java
@Configuration
public class KafkaTransactionalConfig {

    @Bean
    public ProducerFactory<String, Object> transactionalProducerFactory() {
        Map<String, Object> props = producerConfigs();
        props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG,
            "order-service-tx-" + InetAddress.getLocalHost().getHostName());

        DefaultKafkaProducerFactory<String, Object> factory =
            new DefaultKafkaProducerFactory<>(props);
        factory.setTransactionIdPrefix("order-tx-");

        return factory;
    }

    @Bean
    public KafkaTransactionManager<String, Object> kafkaTransactionManager(
            ProducerFactory<String, Object> producerFactory) {
        return new KafkaTransactionManager<>(producerFactory);
    }
}

@Service
public class TransactionalOrderService {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final OrderRepository orderRepository;

    // Transactional send - all or nothing
    @Transactional("kafkaTransactionManager")
    public void processOrder(Order order) {
        // Send to multiple topics atomically
        kafkaTemplate.send("order-created", order.getId(),
            new OrderCreatedEvent(order));
        kafkaTemplate.send("inventory-reserve", order.getId(),
            new InventoryReserveCommand(order));
        kafkaTemplate.send("audit-log", order.getId(),
            new AuditEvent("ORDER_CREATED", order));
    }

    // Mixed transaction - Kafka + Database
    @Transactional
    public void createOrderWithTransaction(CreateOrderRequest request) {
        // Save to database
        Order order = orderRepository.save(Order.from(request));

        // Send to Kafka in same transaction context
        kafkaTemplate.executeInTransaction(operations -> {
            operations.send("orders", order.getId(), order);
            return true;
        });
    }
}
```

### Custom Partitioner

```java
public class TenantAwarePartitioner implements Partitioner {

    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                        Object value, byte[] valueBytes, Cluster cluster) {
        List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
        int numPartitions = partitions.size();

        if (key == null) {
            // Random partition for null keys
            return ThreadLocalRandom.current().nextInt(numPartitions);
        }

        // Extract tenant from key (format: tenantId:entityId)
        String keyStr = (String) key;
        String tenantId = keyStr.contains(":") ?
            keyStr.split(":")[0] : keyStr;

        // Consistent hashing for tenant
        return Math.abs(tenantId.hashCode()) % numPartitions;
    }

    @Override
    public void close() {}

    @Override
    public void configure(Map<String, ?> configs) {}
}

// Usage
props.put(ProducerConfig.PARTITIONER_CLASS_CONFIG,
    TenantAwarePartitioner.class);
```

### High-Throughput Producer

```java
@Service
public class HighThroughputProducer {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final ExecutorService executor =
        Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors());

    // Batch sending with parallel partitions
    public CompletableFuture<Void> sendBatch(String topic,
                                             List<KeyValue<String, Object>> records) {
        // Group by partition key prefix
        Map<String, List<KeyValue<String, Object>>> grouped = records.stream()
            .collect(Collectors.groupingBy(kv -> extractPartitionKey(kv.key())));

        // Send each group in parallel
        List<CompletableFuture<Void>> futures = grouped.values().stream()
            .map(group -> CompletableFuture.runAsync(() -> {
                for (KeyValue<String, Object> kv : group) {
                    kafkaTemplate.send(topic, kv.key(), kv.value());
                }
            }, executor))
            .toList();

        return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]));
    }

    // Fire and forget for metrics/logs
    public void sendFireAndForget(String topic, String key, Object value) {
        kafkaTemplate.send(topic, key, value);
        // No callback, no waiting
    }

    // Async with callback
    public void sendWithCallback(String topic, String key, Object value,
                                 BiConsumer<RecordMetadata, Exception> callback) {
        kafkaTemplate.send(topic, key, value)
            .whenComplete((result, ex) -> {
                if (ex != null) {
                    callback.accept(null, (Exception) ex);
                } else {
                    callback.accept(result.getRecordMetadata(), null);
                }
            });
    }
}
```

---

## Consumer Patterns

### Basic Consumer Configuration

```java
@Configuration
@EnableKafka
public class KafkaConsumerConfig {

    @Bean
    public Map<String, Object> consumerConfigs() {
        Map<String, Object> props = new HashMap<>();

        // Connection
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "order-service");
        props.put(ConsumerConfig.CLIENT_ID_CONFIG, "order-service-consumer");

        // Deserialization
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,
            StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
            JsonDeserializer.class);
        props.put(JsonDeserializer.TRUSTED_PACKAGES, "com.example.*");
        props.put(JsonDeserializer.TYPE_MAPPINGS,
            "orderEvent:com.example.events.OrderEvent," +
            "paymentEvent:com.example.events.PaymentEvent");

        // Offset management
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);

        // Poll configuration
        props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 500);
        props.put(ConsumerConfig.MAX_POLL_INTERVAL_MS_CONFIG, 300000);
        props.put(ConsumerConfig.FETCH_MIN_BYTES_CONFIG, 1);
        props.put(ConsumerConfig.FETCH_MAX_WAIT_MS_CONFIG, 500);

        // Session management
        props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 30000);
        props.put(ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG, 10000);

        // Isolation level for transactions
        props.put(ConsumerConfig.ISOLATION_LEVEL_CONFIG, "read_committed");

        return props;
    }

    @Bean
    public ConsumerFactory<String, Object> consumerFactory() {
        return new DefaultKafkaConsumerFactory<>(consumerConfigs());
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object>
            kafkaListenerContainerFactory() {

        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();

        factory.setConsumerFactory(consumerFactory());
        factory.setConcurrency(4);  // Number of consumer threads

        // Acknowledgment
        factory.getContainerProperties()
            .setAckMode(ContainerProperties.AckMode.MANUAL_IMMEDIATE);
        factory.getContainerProperties()
            .setCommitLogLevel(LogIfLevelEnabled.Level.DEBUG);

        // Error handling
        factory.setCommonErrorHandler(kafkaErrorHandler());

        // Batch listener
        factory.setBatchListener(false);

        // Consumer interceptor
        factory.setRecordInterceptor(new RecordInterceptor<>() {
            @Override
            public ConsumerRecord<String, Object> intercept(
                    ConsumerRecord<String, Object> record,
                    Consumer<String, Object> consumer) {
                // Extract tracing
                Header traceHeader = record.headers().lastHeader("trace-id");
                if (traceHeader != null) {
                    MDC.put("traceId",
                        new String(traceHeader.value(), StandardCharsets.UTF_8));
                }
                return record;
            }

            @Override
            public void afterRecord(ConsumerRecord<String, Object> record,
                                    Consumer<String, Object> consumer) {
                MDC.clear();
            }
        });

        return factory;
    }

    @Bean
    public DefaultErrorHandler kafkaErrorHandler() {
        // Exponential backoff
        ExponentialBackOffWithMaxRetries backOff =
            new ExponentialBackOffWithMaxRetries(5);
        backOff.setInitialInterval(1000);
        backOff.setMultiplier(2.0);
        backOff.setMaxInterval(30000);

        DefaultErrorHandler handler = new DefaultErrorHandler(
            (record, exception) -> {
                log.error("Failed to process record after retries: topic={}, " +
                    "partition={}, offset={}, exception={}",
                    record.topic(), record.partition(), record.offset(),
                    exception.getMessage());
                // Send to DLT manually if needed
            },
            backOff
        );

        // Non-retryable exceptions
        handler.addNotRetryableExceptions(
            DeserializationException.class,
            ClassCastException.class,
            NullPointerException.class,
            IllegalArgumentException.class
        );

        return handler;
    }
}
```

### Batch Consumer

```java
@Configuration
public class BatchConsumerConfig {

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object>
            batchListenerContainerFactory(
                ConsumerFactory<String, Object> consumerFactory) {

        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();

        factory.setConsumerFactory(consumerFactory);
        factory.setBatchListener(true);
        factory.setConcurrency(4);

        factory.getContainerProperties()
            .setAckMode(ContainerProperties.AckMode.MANUAL);

        // Batch error handler
        factory.setBatchErrorHandler(new BatchLoggingErrorHandler());

        return factory;
    }
}

@Service
public class BatchOrderConsumer {

    private final OrderRepository orderRepository;

    @KafkaListener(
        topics = "orders",
        containerFactory = "batchListenerContainerFactory"
    )
    public void handleBatch(
            List<ConsumerRecord<String, OrderEvent>> records,
            Acknowledgment ack) {

        log.info("Received batch of {} records", records.size());

        try {
            // Process in batches for database efficiency
            List<Order> orders = records.stream()
                .map(record -> Order.from(record.value()))
                .toList();

            orderRepository.saveAll(orders);

            ack.acknowledge();

            log.info("Processed {} orders", orders.size());

        } catch (Exception e) {
            log.error("Batch processing failed", e);
            // Don't ack - will be retried
            throw e;
        }
    }

    // Batch with partition awareness
    @KafkaListener(
        topics = "orders",
        containerFactory = "batchListenerContainerFactory"
    )
    public void handleBatchWithPartition(
            List<ConsumerRecord<String, OrderEvent>> records,
            @Header(KafkaHeaders.RECEIVED_PARTITION) List<Integer> partitions,
            @Header(KafkaHeaders.OFFSET) List<Long> offsets,
            Acknowledgment ack) {

        // Group by partition for ordered processing within partition
        Map<Integer, List<ConsumerRecord<String, OrderEvent>>> byPartition =
            records.stream()
                .collect(Collectors.groupingBy(ConsumerRecord::partition));

        for (var entry : byPartition.entrySet()) {
            int partition = entry.getKey();
            List<ConsumerRecord<String, OrderEvent>> partitionRecords =
                entry.getValue();

            // Process partition records in order
            for (var record : partitionRecords) {
                processOrderInOrder(record.value());
            }
        }

        ack.acknowledge();
    }
}
```

### Seek và Replay

```java
@Service
public class ReplayableConsumer implements ConsumerSeekAware {

    private ConsumerSeekCallback seekCallback;

    @Override
    public void registerSeekCallback(ConsumerSeekCallback callback) {
        this.seekCallback = callback;
    }

    // Seek to beginning for replay
    public void replayFromBeginning(String topic, int partition) {
        seekCallback.seekToBeginning(topic, partition);
    }

    // Seek to specific offset
    public void seekToOffset(String topic, int partition, long offset) {
        seekCallback.seek(topic, partition, offset);
    }

    // Seek to timestamp
    public void seekToTimestamp(String topic, long timestamp) {
        seekCallback.seekToTimestamp(
            Collections.singletonList(new TopicPartition(topic, 0)),
            timestamp
        );
    }

    @KafkaListener(topics = "orders", id = "replayable-consumer")
    public void handleOrder(OrderEvent event,
                           @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
                           @Header(KafkaHeaders.OFFSET) long offset) {
        log.info("Processing: partition={}, offset={}", partition, offset);
        processOrder(event);
    }
}

// Replay controller endpoint
@RestController
@RequestMapping("/api/replay")
public class ReplayController {

    private final ReplayableConsumer consumer;
    private final KafkaListenerEndpointRegistry registry;

    @PostMapping("/from-beginning")
    public ResponseEntity<String> replayFromBeginning(
            @RequestParam String topic,
            @RequestParam int partition) {

        // Stop consumer
        registry.getListenerContainer("replayable-consumer").stop();

        // Seek to beginning
        consumer.replayFromBeginning(topic, partition);

        // Restart consumer
        registry.getListenerContainer("replayable-consumer").start();

        return ResponseEntity.ok("Replay started from beginning");
    }

    @PostMapping("/from-timestamp")
    public ResponseEntity<String> replayFromTimestamp(
            @RequestParam String topic,
            @RequestParam @DateTimeFormat(iso = ISO.DATE_TIME)
                LocalDateTime timestamp) {

        long epochMilli = timestamp.toInstant(ZoneOffset.UTC).toEpochMilli();

        registry.getListenerContainer("replayable-consumer").stop();
        consumer.seekToTimestamp(topic, epochMilli);
        registry.getListenerContainer("replayable-consumer").start();

        return ResponseEntity.ok("Replay started from " + timestamp);
    }
}
```

### Consumer with State Store

```java
@Service
public class StatefulOrderConsumer {

    private final ConcurrentMap<String, OrderState> stateStore =
        new ConcurrentHashMap<>();
    private final KafkaTemplate<String, Object> kafkaTemplate;

    @KafkaListener(topics = "order-events")
    public void handleOrderEvent(
            OrderEvent event,
            @Header(KafkaHeaders.RECEIVED_KEY) String orderId,
            Acknowledgment ack) {

        // Get or create state
        OrderState state = stateStore.computeIfAbsent(
            orderId, k -> new OrderState(orderId));

        // Apply event to state
        OrderState newState = state.apply(event);
        stateStore.put(orderId, newState);

        // Publish state change to compacted topic
        kafkaTemplate.send("order-state", orderId, newState);

        ack.acknowledge();
    }

    // State recovery on startup
    @PostConstruct
    public void recoverState() {
        // Read from compacted state topic
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "state-recovery-" +
            UUID.randomUUID());
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,
            StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
            JsonDeserializer.class);

        try (KafkaConsumer<String, OrderState> consumer =
                new KafkaConsumer<>(props)) {
            consumer.subscribe(Collections.singletonList("order-state"));

            // Read all state
            boolean done = false;
            while (!done) {
                ConsumerRecords<String, OrderState> records =
                    consumer.poll(Duration.ofMillis(1000));

                if (records.isEmpty()) {
                    done = true;
                } else {
                    for (var record : records) {
                        if (record.value() != null) {
                            stateStore.put(record.key(), record.value());
                        } else {
                            stateStore.remove(record.key());  // Tombstone
                        }
                    }
                }
            }
        }

        log.info("Recovered {} states", stateStore.size());
    }
}
```

---

## Error Handling Patterns

### Dead Letter Topic (DLT)

```java
@Configuration
public class DltConfig {

    @Bean
    public DeadLetterPublishingRecoverer deadLetterPublishingRecoverer(
            KafkaTemplate<String, Object> kafkaTemplate) {

        return new DeadLetterPublishingRecoverer(kafkaTemplate,
            (record, exception) -> {
                // Custom DLT topic naming
                String originalTopic = record.topic();
                return new TopicPartition(
                    originalTopic + ".DLT",
                    record.partition()
                );
            });
    }

    @Bean
    public DefaultErrorHandler errorHandler(
            DeadLetterPublishingRecoverer recoverer) {

        DefaultErrorHandler handler = new DefaultErrorHandler(
            recoverer,
            new FixedBackOff(1000L, 3L)
        );

        // Exceptions that go directly to DLT
        handler.addNotRetryableExceptions(
            DeserializationException.class,
            ValidationException.class
        );

        return handler;
    }
}

// DLT consumer for manual review
@Service
public class DltConsumer {

    private final DeadLetterRepository deadLetterRepository;

    @KafkaListener(topics = "${kafka.topics.orders}.DLT",
                   groupId = "dlt-processor")
    public void handleDlt(
            @Payload byte[] payload,
            @Header(KafkaHeaders.DLT_EXCEPTION_MESSAGE) String errorMessage,
            @Header(KafkaHeaders.DLT_EXCEPTION_FQCN) String exceptionClass,
            @Header(KafkaHeaders.DLT_ORIGINAL_TOPIC) String originalTopic,
            @Header(KafkaHeaders.DLT_ORIGINAL_PARTITION) int originalPartition,
            @Header(KafkaHeaders.DLT_ORIGINAL_OFFSET) long originalOffset,
            @Header(KafkaHeaders.DLT_ORIGINAL_TIMESTAMP) long originalTimestamp) {

        DeadLetter deadLetter = DeadLetter.builder()
            .payload(new String(payload, StandardCharsets.UTF_8))
            .errorMessage(errorMessage)
            .exceptionClass(exceptionClass)
            .originalTopic(originalTopic)
            .originalPartition(originalPartition)
            .originalOffset(originalOffset)
            .originalTimestamp(Instant.ofEpochMilli(originalTimestamp))
            .receivedAt(Instant.now())
            .status(DeadLetterStatus.NEW)
            .build();

        deadLetterRepository.save(deadLetter);

        log.error("DLT received: topic={}, partition={}, offset={}, error={}",
            originalTopic, originalPartition, originalOffset, errorMessage);
    }
}
```

### Retry với Custom Logic

```java
@Service
public class RetryableOrderConsumer {

    private final OrderService orderService;
    private final RetryTemplate retryTemplate;

    @PostConstruct
    public void initRetryTemplate() {
        retryTemplate = RetryTemplate.builder()
            .maxAttempts(3)
            .exponentialBackoff(1000, 2.0, 10000)
            .retryOn(RetryableException.class)
            .notRetryOn(ValidationException.class)
            .withListener(new RetryListenerSupport() {
                @Override
                public <T, E extends Throwable> void onError(
                        RetryContext context, RetryCallback<T, E> callback,
                        Throwable throwable) {
                    log.warn("Retry attempt {} failed: {}",
                        context.getRetryCount(), throwable.getMessage());
                }
            })
            .build();
    }

    @KafkaListener(topics = "orders")
    public void handleOrder(OrderEvent event, Acknowledgment ack) {
        try {
            retryTemplate.execute(context -> {
                orderService.process(event);
                return null;
            }, context -> {
                // Recovery callback after all retries exhausted
                log.error("All retries exhausted for order: {}",
                    event.getOrderId());
                deadLetterService.send(event, context.getLastThrowable());
                return null;
            });

            ack.acknowledge();
        } catch (Exception e) {
            // Should not reach here with recovery callback
            log.error("Unexpected error", e);
        }
    }
}
```

---

## Performance Tuning

### Producer Tuning

| Parameter | Low Latency | High Throughput | Balanced |
|-----------|-------------|-----------------|----------|
| `acks` | 1 | all | all |
| `batch.size` | 0 | 128KB | 32KB |
| `linger.ms` | 0 | 50-100 | 20 |
| `compression.type` | none | lz4 | lz4 |
| `buffer.memory` | 32MB | 128MB | 64MB |
| `max.block.ms` | 1000 | 60000 | 30000 |

### Consumer Tuning

| Parameter | Low Latency | High Throughput | Balanced |
|-----------|-------------|-----------------|----------|
| `fetch.min.bytes` | 1 | 1MB | 1KB |
| `fetch.max.wait.ms` | 0 | 500 | 100 |
| `max.poll.records` | 1 | 1000 | 500 |
| `max.partition.fetch.bytes` | 256KB | 10MB | 1MB |

### JVM Tuning for Kafka

```bash
# Producer-heavy applications
JAVA_OPTS="-Xms4g -Xmx4g -XX:+UseG1GC -XX:MaxGCPauseMillis=20"

# Consumer-heavy applications
JAVA_OPTS="-Xms2g -Xmx2g -XX:+UseG1GC -XX:MaxGCPauseMillis=50"

# Enable GC logging for analysis
JAVA_OPTS="$JAVA_OPTS -Xlog:gc*:file=/var/log/gc.log:time,tags:filecount=5,filesize=10M"
```

---

## Monitoring và Metrics

### Micrometer Metrics

```java
@Configuration
public class KafkaMetricsConfig {

    @Bean
    public MicrometerConsumerListener<String, Object> consumerListener(
            MeterRegistry registry) {
        return new MicrometerConsumerListener<>(registry);
    }

    @Bean
    public MicrometerProducerListener<String, Object> producerListener(
            MeterRegistry registry) {
        return new MicrometerProducerListener<>(registry);
    }
}

// Custom metrics
@Service
public class KafkaMetricsService {

    private final MeterRegistry registry;
    private final AtomicLong lastCommitTime = new AtomicLong();

    public void recordMessageProcessed(String topic, long processingTimeMs,
                                       boolean success) {
        Timer.builder("kafka.message.processing.time")
            .tag("topic", topic)
            .tag("success", String.valueOf(success))
            .register(registry)
            .record(processingTimeMs, TimeUnit.MILLISECONDS);
    }

    public void recordConsumerLag(String topic, String groupId, long lag) {
        registry.gauge("kafka.consumer.lag",
            Tags.of("topic", topic, "group", groupId),
            lag);
    }

    public void recordCommitTime() {
        lastCommitTime.set(System.currentTimeMillis());
        registry.gauge("kafka.consumer.last.commit.time",
            lastCommitTime);
    }
}
```

### Key Metrics to Monitor

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `kafka.consumer.lag` | Messages behind | > 10000 |
| `kafka.producer.record-send-rate` | Messages/sec | < expected |
| `kafka.producer.record-error-rate` | Errors/sec | > 0 |
| `kafka.consumer.fetch-rate` | Fetches/sec | Too low |
| `kafka.producer.request-latency-avg` | Avg latency | > 100ms |

---

## Testing Patterns

### Embedded Kafka for Tests

```java
@SpringBootTest
@EmbeddedKafka(
    partitions = 3,
    topics = {"orders", "orders.DLT"},
    brokerProperties = {
        "listeners=PLAINTEXT://localhost:9092",
        "auto.create.topics.enable=false"
    }
)
class OrderConsumerTest {

    @Autowired
    private KafkaTemplate<String, Object> kafkaTemplate;

    @Autowired
    private EmbeddedKafkaBroker embeddedKafka;

    @SpyBean
    private OrderService orderService;

    @Test
    void shouldProcessOrder() throws Exception {
        // Arrange
        OrderEvent event = new OrderEvent("order-1", "item-1", 100);

        // Act
        kafkaTemplate.send("orders", event.getOrderId(), event).get();

        // Assert
        await().atMost(10, TimeUnit.SECONDS)
            .untilAsserted(() -> {
                verify(orderService).process(event);
            });
    }

    @Test
    void shouldSendToDltOnNonRetryableError() throws Exception {
        // Arrange
        doThrow(new ValidationException("Invalid order"))
            .when(orderService).process(any());

        OrderEvent event = new OrderEvent("order-1", "item-1", -1);

        // Act
        kafkaTemplate.send("orders", event.getOrderId(), event).get();

        // Assert - verify sent to DLT
        Consumer<String, Object> consumer = createConsumer("orders.DLT");
        embeddedKafka.consumeFromEmbeddedTopics(consumer, "orders.DLT");

        ConsumerRecords<String, Object> records =
            consumer.poll(Duration.ofSeconds(10));

        assertThat(records.count()).isEqualTo(1);
    }
}
```

### Testcontainers for Integration Tests

```java
@Testcontainers
@SpringBootTest
class KafkaIntegrationTest {

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0")
    ).withKraft();

    @DynamicPropertySource
    static void kafkaProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }

    @Test
    void testKafkaIntegration() {
        // Test with real Kafka
    }
}
```

---

## Common Issues và Solutions

### Issue: Consumer Rebalancing Too Frequent

**Symptoms:** Frequent "Attempt to heartbeat failed" logs

**Solution:**
```java
props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 45000);
props.put(ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG, 15000);
props.put(ConsumerConfig.MAX_POLL_INTERVAL_MS_CONFIG, 600000);
props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 100);  // Reduce if processing is slow
```

### Issue: Producer Buffer Full

**Symptoms:** `BufferExhaustedException`

**Solution:**
```java
props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, 134217728);  // 128MB
props.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, 60000);
// Or implement backpressure in application
```

### Issue: Deserialization Errors

**Symptoms:** Messages failing to deserialize

**Solution:**
```java
// Use ErrorHandlingDeserializer
props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,
    ErrorHandlingDeserializer.class);
props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
    ErrorHandlingDeserializer.class);
props.put(ErrorHandlingDeserializer.KEY_DESERIALIZER_CLASS,
    StringDeserializer.class);
props.put(ErrorHandlingDeserializer.VALUE_DESERIALIZER_CLASS,
    JsonDeserializer.class);
```
