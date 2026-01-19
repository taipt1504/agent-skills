---
name: message-queue-java-expert
description: Expert guidance for message queue implementation in Java (Kafka, RabbitMQ, NATS) - patterns, best practices, và production-ready solutions
version: 1.0.0
triggers:
  - kafka java
  - rabbitmq java
  - nats java
  - message queue
  - event streaming
  - message broker
  - async messaging
  - /mq-java
tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
references:
  - references/kafka-patterns.md
  - references/rabbitmq-patterns.md
  - references/nats-patterns.md
scripts:
  - scripts/analyze-consumer-lag.py
  - scripts/benchmark-throughput.sh
---

# Message Queue Java Expert

## Mục đích

Skill này cung cấp expert guidance cho việc implement message queue systems trong Java, bao gồm:

- **Kafka**: High-throughput distributed streaming platform
- **RabbitMQ**: Feature-rich message broker với flexible routing
- **NATS**: Lightweight, high-performance messaging system

Hỗ trợ từ design decisions đến production-ready implementations với Spring Boot integration.

## Khi nào sử dụng Skill này

### Nên sử dụng khi:

1. **Thiết kế message-driven architecture** - Chọn message broker phù hợp, define message schemas
2. **Implement producers/consumers** - Code patterns cho Kafka, RabbitMQ, hoặc NATS
3. **Troubleshoot messaging issues** - Consumer lag, message loss, ordering problems
4. **Optimize performance** - Tuning throughput, latency, resource usage
5. **Handle failures** - Retry strategies, dead letter queues, exactly-once processing
6. **Migrate giữa các brokers** - Chuyển từ RabbitMQ sang Kafka hoặc ngược lại

### Không nên sử dụng khi:

1. **Simple synchronous communication** - REST/gRPC đủ cho use case
2. **Database-level concerns** - Sử dụng database-architect skill
3. **Infrastructure setup** - Sử dụng cloud-architect hoặc devops skills
4. **Non-Java implementations** - Skill này focus vào Java ecosystem

---

## Core Concepts

### Message Queue Fundamentals

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Producer   │────▶│  Message Broker │────▶│   Consumer   │
└──────────────┘     │  ┌───────────┐  │     └──────────────┘
                     │  │  Topic/   │  │
                     │  │  Queue    │  │
                     │  └───────────┘  │
                     └─────────────────┘
```

#### Terminology Mapping

| Concept | Kafka | RabbitMQ | NATS |
|---------|-------|----------|------|
| Message container | Topic | Queue | Subject |
| Grouping | Partition | - | - |
| Consumer scaling | Consumer Group | Competing Consumers | Queue Group |
| Routing | Partition Key | Exchange + Routing Key | Subject Hierarchy |
| Persistence | Log-based | Queue-based | JetStream |

### Delivery Guarantees

#### At-Most-Once (Fire and Forget)
```java
// Kafka - No acks
props.put(ProducerConfig.ACKS_CONFIG, "0");

// RabbitMQ - No confirms, no acks
channel.basicPublish(exchange, routingKey, null, message);

// NATS Core - Default behavior
connection.publish(subject, data);
```

#### At-Least-Once (Default recommendation)
```java
// Kafka - Wait for leader ack
props.put(ProducerConfig.ACKS_CONFIG, "1");
// Or all replicas
props.put(ProducerConfig.ACKS_CONFIG, "all");

// RabbitMQ - Publisher confirms + Consumer acks
channel.confirmSelect();
channel.basicConsume(queue, false, consumer); // autoAck = false

// NATS JetStream - Acknowledgments
jetStream.publish(subject, data);
```

#### Exactly-Once (Complex, use carefully)
```java
// Kafka - Idempotent producer + Transactions
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, "tx-1");

// RabbitMQ - Deduplication at application level
// NATS JetStream - Message deduplication with Nats-Msg-Id header
```

### Partitioning và Ordering

#### Kafka Partitioning Strategy
```java
// Default: Round-robin (no key) or Hash-based (with key)
producer.send(new ProducerRecord<>("topic", key, value));

// Custom partitioner
public class CustomPartitioner implements Partitioner {
    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                        Object value, byte[] valueBytes, Cluster cluster) {
        List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
        int numPartitions = partitions.size();

        // Custom logic - e.g., route by tenant
        if (key instanceof String) {
            String tenantId = extractTenantId((String) key);
            return Math.abs(tenantId.hashCode()) % numPartitions;
        }
        return Math.abs(key.hashCode()) % numPartitions;
    }
}
```

#### Ordering Guarantees

| Broker | Ordering Scope | How to Achieve |
|--------|---------------|----------------|
| Kafka | Per partition | Same partition key |
| RabbitMQ | Per queue | Single queue, single consumer |
| NATS JetStream | Per subject | Single consumer or ordered consumer |

### Consumer Groups và Scaling

```
                    Consumer Group A
                    ┌─────────────────┐
     Partition 0 ──▶│   Consumer 1    │
                    ├─────────────────┤
     Partition 1 ──▶│   Consumer 2    │
                    ├─────────────────┤
     Partition 2 ──▶│   Consumer 3    │
                    └─────────────────┘

                    Consumer Group B
                    ┌─────────────────┐
     Partition 0 ──▶│                 │
     Partition 1 ──▶│   Consumer 1    │ (receives all)
     Partition 2 ──▶│                 │
                    └─────────────────┘
```

**Scaling Rules:**
- Kafka: Max consumers = number of partitions
- RabbitMQ: Unlimited competing consumers per queue
- NATS: Queue groups distribute messages among subscribers

---

## Kafka Patterns

> Chi tiết xem: `references/kafka-patterns.md`

### Producer Patterns

#### Synchronous Producer
```java
@Service
public class KafkaSyncProducer {

    private final KafkaTemplate<String, Object> kafkaTemplate;

    public KafkaSyncProducer(KafkaTemplate<String, Object> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void sendSync(String topic, String key, Object payload) {
        try {
            SendResult<String, Object> result = kafkaTemplate
                .send(topic, key, payload)
                .get(10, TimeUnit.SECONDS);

            RecordMetadata metadata = result.getRecordMetadata();
            log.info("Sent to partition {} offset {}",
                metadata.partition(), metadata.offset());
        } catch (ExecutionException e) {
            if (e.getCause() instanceof RecordTooLargeException) {
                log.error("Message too large for topic {}", topic);
                throw new MessageSizeException(e);
            }
            throw new MessageSendException(e);
        } catch (TimeoutException e) {
            log.error("Timeout sending to topic {}", topic);
            throw new MessageTimeoutException(e);
        }
    }
}
```

#### Asynchronous Producer with Callbacks
```java
@Service
public class KafkaAsyncProducer {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final MeterRegistry meterRegistry;

    public CompletableFuture<SendResult<String, Object>> sendAsync(
            String topic, String key, Object payload) {

        return kafkaTemplate.send(topic, key, payload)
            .whenComplete((result, ex) -> {
                if (ex != null) {
                    meterRegistry.counter("kafka.send.error",
                        "topic", topic).increment();
                    log.error("Failed to send message to {}: {}",
                        topic, ex.getMessage());
                } else {
                    meterRegistry.counter("kafka.send.success",
                        "topic", topic).increment();
                    log.debug("Sent to {} partition {} offset {}",
                        topic,
                        result.getRecordMetadata().partition(),
                        result.getRecordMetadata().offset());
                }
            });
    }

    // Batch sending
    public void sendBatch(String topic, List<Message> messages) {
        List<CompletableFuture<SendResult<String, Object>>> futures =
            messages.stream()
                .map(msg -> sendAsync(topic, msg.getKey(), msg.getPayload()))
                .toList();

        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
            .join();
    }
}
```

#### Idempotent Producer Configuration
```java
@Configuration
public class KafkaProducerConfig {

    @Bean
    public ProducerFactory<String, Object> producerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG,
            StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
            JsonSerializer.class);

        // Idempotent producer settings
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, Integer.MAX_VALUE);
        props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);

        // Performance tuning
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, 16384);
        props.put(ProducerConfig.LINGER_MS_CONFIG, 5);
        props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4");
        props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, 33554432);

        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    public KafkaTemplate<String, Object> kafkaTemplate() {
        return new KafkaTemplate<>(producerFactory());
    }
}
```

### Consumer Patterns

#### Spring Kafka Consumer with Error Handling
```java
@Service
public class OrderEventConsumer {

    private final OrderService orderService;

    @KafkaListener(
        topics = "${kafka.topics.orders}",
        groupId = "${kafka.consumer.group-id}",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void handleOrderEvent(
            @Payload OrderEvent event,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset,
            @Header(KafkaHeaders.RECEIVED_TIMESTAMP) long timestamp,
            Acknowledgment ack) {

        MDC.put("partitionOffset", partition + "-" + offset);

        try {
            log.info("Processing order event: {}", event.getOrderId());
            orderService.processOrder(event);
            ack.acknowledge();

        } catch (RetryableException e) {
            log.warn("Retryable error, will retry: {}", e.getMessage());
            throw e; // Let error handler retry

        } catch (NonRetryableException e) {
            log.error("Non-retryable error, sending to DLT: {}", e.getMessage());
            ack.acknowledge(); // Don't retry, DLT handler will catch
            throw e;

        } finally {
            MDC.clear();
        }
    }

    @KafkaListener(topics = "${kafka.topics.orders}.DLT", groupId = "dlt-processor")
    public void handleDlt(
            @Payload OrderEvent event,
            @Header(KafkaHeaders.DLT_EXCEPTION_MESSAGE) String errorMessage,
            @Header(KafkaHeaders.DLT_ORIGINAL_TOPIC) String originalTopic) {

        log.error("DLT received from {}: {} - Error: {}",
            originalTopic, event, errorMessage);
        // Store in database for manual review
        deadLetterRepository.save(new DeadLetter(event, errorMessage));
    }
}
```

#### Consumer Configuration with Retry
```java
@Configuration
@EnableKafka
public class KafkaConsumerConfig {

    @Bean
    public ConsumerFactory<String, Object> consumerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,
            StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
            JsonDeserializer.class);

        // Consumer settings
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 100);
        props.put(ConsumerConfig.MAX_POLL_INTERVAL_MS_CONFIG, 300000);
        props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 30000);
        props.put(ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG, 10000);

        // Trusted packages for deserialization
        props.put(JsonDeserializer.TRUSTED_PACKAGES, "com.example.events");

        return new DefaultKafkaConsumerFactory<>(props);
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object>
            kafkaListenerContainerFactory() {

        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory());
        factory.setConcurrency(3);
        factory.getContainerProperties()
            .setAckMode(ContainerProperties.AckMode.MANUAL);

        // Error handling with retry
        factory.setCommonErrorHandler(errorHandler());

        return factory;
    }

    @Bean
    public DefaultErrorHandler errorHandler() {
        // Retry 3 times with exponential backoff
        ExponentialBackOff backOff = new ExponentialBackOff(1000L, 2.0);
        backOff.setMaxElapsedTime(10000L);

        DefaultErrorHandler handler = new DefaultErrorHandler(
            new DeadLetterPublishingRecoverer(kafkaTemplate()),
            backOff
        );

        // Don't retry these exceptions
        handler.addNotRetryableExceptions(
            DeserializationException.class,
            ValidationException.class,
            NullPointerException.class
        );

        return handler;
    }
}
```

### Exactly-Once Semantics with Transactions
```java
@Service
@Transactional
public class TransactionalKafkaService {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final OrderRepository orderRepository;

    @Transactional
    public void processOrderWithTransaction(OrderEvent event) {
        kafkaTemplate.executeInTransaction(operations -> {
            // Send to multiple topics atomically
            operations.send("order-created", event.getOrderId(), event);
            operations.send("inventory-reserve", event.getOrderId(),
                new InventoryReserveEvent(event));
            operations.send("notification-send", event.getOrderId(),
                new NotificationEvent(event));

            return true;
        });
    }
}

// Configuration for transactions
@Configuration
public class KafkaTransactionConfig {

    @Bean
    public ProducerFactory<String, Object> producerFactory() {
        Map<String, Object> props = new HashMap<>();
        // ... other props
        props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG,
            "order-service-tx-" + UUID.randomUUID());

        DefaultKafkaProducerFactory<String, Object> factory =
            new DefaultKafkaProducerFactory<>(props);
        factory.setTransactionIdPrefix("order-tx-");

        return factory;
    }

    @Bean
    public KafkaTransactionManager<String, Object> kafkaTransactionManager() {
        return new KafkaTransactionManager<>(producerFactory());
    }
}
```

### Performance Tuning Checklist

| Parameter | Default | High Throughput | Low Latency |
|-----------|---------|-----------------|-------------|
| `batch.size` | 16KB | 64KB-128KB | 0 |
| `linger.ms` | 0 | 5-50ms | 0 |
| `compression.type` | none | lz4/zstd | none |
| `acks` | all | 1 | 0 |
| `buffer.memory` | 32MB | 64MB+ | 32MB |
| `max.in.flight.requests` | 5 | 5 | 1 |

---

## RabbitMQ Patterns

> Chi tiết xem: `references/rabbitmq-patterns.md`

### Exchange Types

```
Direct Exchange              Topic Exchange
┌─────────────┐              ┌─────────────┐
│   Exchange  │              │   Exchange  │
└──────┬──────┘              └──────┬──────┘
       │                            │
  routing_key                  routing_key pattern
       │                            │
       ▼                            ▼
┌─────────────┐              *.error  #.critical
│    Queue    │              /           \
└─────────────┘             ▼             ▼
                      ┌────────┐    ┌────────┐
                      │ Queue1 │    │ Queue2 │
                      └────────┘    └────────┘

Fanout Exchange              Headers Exchange
┌─────────────┐              ┌─────────────┐
│   Exchange  │              │   Exchange  │
└──────┬──────┘              └──────┬──────┘
       │                            │
  broadcast                   header matching
    /    \                     /        \
   ▼      ▼                   ▼          ▼
┌────┐  ┌────┐           format=pdf  type=report
│ Q1 │  │ Q2 │              │           │
└────┘  └────┘              ▼           ▼
                        ┌────────┐  ┌────────┐
                        │ Queue1 │  │ Queue2 │
                        └────────┘  └────────┘
```

### Spring AMQP Configuration
```java
@Configuration
public class RabbitMQConfig {

    public static final String ORDER_EXCHANGE = "order.exchange";
    public static final String ORDER_QUEUE = "order.queue";
    public static final String ORDER_ROUTING_KEY = "order.created";
    public static final String DLX_EXCHANGE = "dlx.exchange";
    public static final String DLQ_QUEUE = "order.queue.dlq";

    // Main exchange
    @Bean
    public TopicExchange orderExchange() {
        return ExchangeBuilder
            .topicExchange(ORDER_EXCHANGE)
            .durable(true)
            .build();
    }

    // Dead letter exchange
    @Bean
    public DirectExchange dlxExchange() {
        return ExchangeBuilder
            .directExchange(DLX_EXCHANGE)
            .durable(true)
            .build();
    }

    // Main queue with DLX
    @Bean
    public Queue orderQueue() {
        return QueueBuilder
            .durable(ORDER_QUEUE)
            .withArgument("x-dead-letter-exchange", DLX_EXCHANGE)
            .withArgument("x-dead-letter-routing-key", "dlq")
            .withArgument("x-message-ttl", 86400000) // 24 hours
            .build();
    }

    // Dead letter queue
    @Bean
    public Queue dlqQueue() {
        return QueueBuilder
            .durable(DLQ_QUEUE)
            .build();
    }

    // Bindings
    @Bean
    public Binding orderBinding() {
        return BindingBuilder
            .bind(orderQueue())
            .to(orderExchange())
            .with(ORDER_ROUTING_KEY);
    }

    @Bean
    public Binding dlqBinding() {
        return BindingBuilder
            .bind(dlqQueue())
            .to(dlxExchange())
            .with("dlq");
    }

    // Connection factory with retry
    @Bean
    public ConnectionFactory connectionFactory() {
        CachingConnectionFactory factory = new CachingConnectionFactory();
        factory.setHost(host);
        factory.setPort(port);
        factory.setUsername(username);
        factory.setPassword(password);
        factory.setVirtualHost(virtualHost);

        // Connection recovery
        factory.getRabbitConnectionFactory()
            .setAutomaticRecoveryEnabled(true);
        factory.getRabbitConnectionFactory()
            .setNetworkRecoveryInterval(5000);

        // Publisher confirms
        factory.setPublisherConfirmType(
            CachingConnectionFactory.ConfirmType.CORRELATED);
        factory.setPublisherReturns(true);

        return factory;
    }

    // RabbitTemplate with confirms
    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(jackson2JsonMessageConverter());
        template.setMandatory(true);

        // Confirm callback
        template.setConfirmCallback((correlationData, ack, cause) -> {
            if (!ack) {
                log.error("Message not confirmed: {}", cause);
            }
        });

        // Return callback for unroutable messages
        template.setReturnsCallback(returned -> {
            log.error("Message returned: {} - {}",
                returned.getReplyCode(),
                returned.getReplyText());
        });

        return template;
    }

    @Bean
    public MessageConverter jackson2JsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}
```

### Producer with Publisher Confirms
```java
@Service
public class RabbitMQProducer {

    private final RabbitTemplate rabbitTemplate;

    public void sendWithConfirm(String exchange, String routingKey,
                                Object message) {
        CorrelationData correlationData = new CorrelationData(
            UUID.randomUUID().toString());

        rabbitTemplate.convertAndSend(
            exchange,
            routingKey,
            message,
            msg -> {
                msg.getMessageProperties().setDeliveryMode(
                    MessageDeliveryMode.PERSISTENT);
                msg.getMessageProperties().setContentType("application/json");
                msg.getMessageProperties().setMessageId(
                    correlationData.getId());
                return msg;
            },
            correlationData
        );

        // Wait for confirm
        try {
            CorrelationData.Confirm confirm =
                correlationData.getFuture().get(5, TimeUnit.SECONDS);
            if (!confirm.isAck()) {
                throw new MessageNotConfirmedException(
                    "Message not confirmed: " + confirm.getReason());
            }
        } catch (Exception e) {
            throw new MessageSendException("Failed to confirm message", e);
        }
    }

    // Async version
    public CompletableFuture<Boolean> sendAsync(String exchange,
                                                 String routingKey,
                                                 Object message) {
        CorrelationData correlationData = new CorrelationData(
            UUID.randomUUID().toString());

        rabbitTemplate.convertAndSend(exchange, routingKey, message,
            correlationData);

        return correlationData.getFuture()
            .thenApply(CorrelationData.Confirm::isAck);
    }
}
```

### Consumer with Manual Acknowledgment
```java
@Service
public class RabbitMQConsumer {

    @RabbitListener(
        queues = "${rabbitmq.queues.orders}",
        containerFactory = "rabbitListenerContainerFactory"
    )
    public void handleOrder(
            @Payload OrderEvent event,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
            @Header(AmqpHeaders.REDELIVERED) boolean redelivered,
            Channel channel) throws IOException {

        try {
            log.info("Processing order: {}", event.getOrderId());

            if (redelivered) {
                log.warn("Redelivered message for order: {}",
                    event.getOrderId());
            }

            orderService.process(event);

            // Acknowledge success
            channel.basicAck(deliveryTag, false);

        } catch (RetryableException e) {
            log.warn("Retryable error, requeueing: {}", e.getMessage());
            // Requeue for retry
            channel.basicNack(deliveryTag, false, !redelivered);

        } catch (Exception e) {
            log.error("Non-retryable error, rejecting: {}", e.getMessage());
            // Don't requeue - will go to DLQ
            channel.basicReject(deliveryTag, false);
        }
    }
}

@Configuration
public class RabbitListenerConfig {

    @Bean
    public SimpleRabbitListenerContainerFactory
            rabbitListenerContainerFactory(ConnectionFactory connectionFactory) {

        SimpleRabbitListenerContainerFactory factory =
            new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setMessageConverter(new Jackson2JsonMessageConverter());
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
        factory.setPrefetchCount(10);
        factory.setConcurrentConsumers(3);
        factory.setMaxConcurrentConsumers(10);

        // Retry configuration
        factory.setAdviceChain(RetryInterceptorBuilder
            .stateless()
            .maxAttempts(3)
            .backOffOptions(1000, 2.0, 10000)
            .recoverer(new RejectAndDontRequeueRecoverer())
            .build()
        );

        return factory;
    }
}
```

### Request-Reply Pattern (RPC)
```java
@Service
public class RabbitRpcClient {

    private final RabbitTemplate rabbitTemplate;

    public OrderResponse sendAndReceive(OrderRequest request) {
        return (OrderResponse) rabbitTemplate.convertSendAndReceive(
            "rpc.exchange",
            "order.validate",
            request,
            message -> {
                message.getMessageProperties()
                    .setReplyTo("order.response.queue");
                message.getMessageProperties()
                    .setCorrelationId(UUID.randomUUID().toString());
                message.getMessageProperties()
                    .setExpiration("30000"); // 30 second timeout
                return message;
            }
        );
    }

    // Async RPC
    public CompletableFuture<OrderResponse> sendAndReceiveAsync(
            OrderRequest request) {

        return rabbitTemplate.convertSendAndReceiveAsType(
            "rpc.exchange",
            "order.validate",
            request,
            new ParameterizedTypeReference<OrderResponse>() {}
        );
    }
}

@Service
public class RabbitRpcServer {

    @RabbitListener(queues = "order.validate.queue")
    public OrderResponse handleValidation(OrderRequest request) {
        log.info("Validating order: {}", request.getOrderId());

        boolean valid = orderValidator.validate(request);

        return OrderResponse.builder()
            .orderId(request.getOrderId())
            .valid(valid)
            .timestamp(Instant.now())
            .build();
    }
}
```

---

## NATS Patterns

> Chi tiết xem: `references/nats-patterns.md`

### Core NATS vs JetStream

| Feature | Core NATS | JetStream |
|---------|-----------|-----------|
| Persistence | No | Yes |
| Replay | No | Yes |
| Acknowledgments | No | Yes |
| Exactly-once | No | Yes |
| Consumer groups | Queue groups | Durable consumers |
| Use case | Real-time, ephemeral | Durable messaging |

### NATS Java Client Setup
```java
@Configuration
public class NatsConfig {

    @Value("${nats.servers}")
    private String servers;

    @Bean
    public Connection natsConnection() throws IOException, InterruptedException {
        Options options = new Options.Builder()
            .servers(servers.split(","))
            .connectionName("order-service")
            .maxReconnects(-1)  // Infinite reconnects
            .reconnectWait(Duration.ofSeconds(2))
            .connectionTimeout(Duration.ofSeconds(5))
            .pingInterval(Duration.ofSeconds(30))
            .reconnectBufferSize(8 * 1024 * 1024)  // 8MB buffer
            .errorListener(new ErrorListener() {
                @Override
                public void errorOccurred(Connection conn, String error) {
                    log.error("NATS error: {}", error);
                }

                @Override
                public void exceptionOccurred(Connection conn, Exception exp) {
                    log.error("NATS exception", exp);
                }

                @Override
                public void slowConsumerDetected(Connection conn, Consumer consumer) {
                    log.warn("Slow consumer detected");
                }
            })
            .connectionListener((conn, type) -> {
                log.info("NATS connection event: {}", type);
            })
            .build();

        return Nats.connect(options);
    }

    @Bean
    public JetStream jetStream(Connection connection) throws IOException {
        return connection.jetStream();
    }

    @Bean
    public JetStreamManagement jetStreamManagement(Connection connection)
            throws IOException {
        return connection.jetStreamManagement();
    }
}
```

### Core NATS Pub/Sub
```java
@Service
public class NatsCoreService {

    private final Connection connection;
    private final ObjectMapper objectMapper;

    // Simple publish
    public void publish(String subject, Object payload) {
        try {
            byte[] data = objectMapper.writeValueAsBytes(payload);
            connection.publish(subject, data);
        } catch (JsonProcessingException e) {
            throw new SerializationException("Failed to serialize payload", e);
        }
    }

    // Request-Reply
    public <T> T request(String subject, Object request, Class<T> responseType) {
        try {
            byte[] data = objectMapper.writeValueAsBytes(request);
            Message response = connection.request(subject, data,
                Duration.ofSeconds(5));

            if (response == null) {
                throw new TimeoutException("No response received");
            }

            return objectMapper.readValue(response.getData(), responseType);
        } catch (Exception e) {
            throw new NatsRequestException("Request failed", e);
        }
    }

    // Subscribe with queue group (load balanced)
    public void subscribeQueue(String subject, String queueGroup,
                               Consumer<Message> handler) {
        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                handler.accept(message);
            } catch (Exception e) {
                log.error("Error handling message on {}: {}",
                    subject, e.getMessage());
            }
        });

        dispatcher.subscribe(subject, queueGroup);
    }

    // Subscribe to wildcard subjects
    public void subscribeWildcard(String subject, Consumer<Message> handler) {
        // Supports:
        // - Single token wildcard: orders.* matches orders.created, orders.updated
        // - Multi token wildcard: orders.> matches orders.created.us, orders.updated.eu

        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                handler.accept(message);
            } catch (Exception e) {
                log.error("Error handling message: {}", e.getMessage());
            }
        });

        dispatcher.subscribe(subject);
    }
}
```

### JetStream Producer
```java
@Service
public class JetStreamProducer {

    private final JetStream jetStream;
    private final ObjectMapper objectMapper;

    public void publish(String subject, Object payload) {
        try {
            byte[] data = objectMapper.writeValueAsBytes(payload);

            PublishOptions options = PublishOptions.builder()
                .messageId(UUID.randomUUID().toString())  // For deduplication
                .expectedStream("ORDERS")
                .build();

            PublishAck ack = jetStream.publish(subject, data, options);

            log.info("Published to stream {} seq {}",
                ack.getStream(), ack.getSeqno());

        } catch (Exception e) {
            throw new PublishException("Failed to publish", e);
        }
    }

    // Async publish
    public CompletableFuture<PublishAck> publishAsync(String subject,
                                                       Object payload) {
        try {
            byte[] data = objectMapper.writeValueAsBytes(payload);
            return jetStream.publishAsync(subject, data);
        } catch (JsonProcessingException e) {
            return CompletableFuture.failedFuture(e);
        }
    }
}
```

### JetStream Consumer
```java
@Service
public class JetStreamConsumer {

    private final JetStream jetStream;
    private final ObjectMapper objectMapper;

    @PostConstruct
    public void startConsumer() {
        try {
            // Push-based consumer
            PushSubscribeOptions options = PushSubscribeOptions.builder()
                .stream("ORDERS")
                .durable("order-processor")
                .deliverSubject("order-deliver")
                .configuration(ConsumerConfiguration.builder()
                    .ackPolicy(AckPolicy.Explicit)
                    .ackWait(Duration.ofSeconds(30))
                    .maxDeliver(3)
                    .filterSubject("orders.created")
                    .build())
                .build();

            jetStream.subscribe("orders.created", "order-group",
                jetStream.getConnection().createDispatcher(),
                this::handleMessage,
                false,  // Don't auto-ack
                options);

        } catch (Exception e) {
            throw new ConsumerSetupException("Failed to setup consumer", e);
        }
    }

    private void handleMessage(Message message) {
        try {
            OrderEvent event = objectMapper.readValue(
                message.getData(), OrderEvent.class);

            log.info("Processing order: {}", event.getOrderId());

            orderService.process(event);

            message.ack();

        } catch (RetryableException e) {
            log.warn("Retryable error, will be redelivered: {}", e.getMessage());
            message.nak();  // Negative ack - will be redelivered

        } catch (Exception e) {
            log.error("Non-retryable error: {}", e.getMessage());
            message.term();  // Terminate - won't be redelivered
        }
    }

    // Pull-based consumer for batch processing
    public void pullConsumer() throws Exception {
        PullSubscribeOptions options = PullSubscribeOptions.builder()
            .stream("ORDERS")
            .durable("batch-processor")
            .configuration(ConsumerConfiguration.builder()
                .ackPolicy(AckPolicy.Explicit)
                .maxAckPending(1000)
                .build())
            .build();

        JetStreamSubscription subscription =
            jetStream.subscribe("orders.*", options);

        while (true) {
            List<Message> messages = subscription.fetch(100,
                Duration.ofSeconds(1));

            for (Message message : messages) {
                try {
                    processMessage(message);
                    message.ack();
                } catch (Exception e) {
                    message.nak();
                }
            }
        }
    }
}
```

### Stream và Consumer Setup
```java
@Service
public class JetStreamSetup {

    private final JetStreamManagement jsm;

    @PostConstruct
    public void setupStreams() throws Exception {
        // Create stream
        StreamConfiguration streamConfig = StreamConfiguration.builder()
            .name("ORDERS")
            .subjects("orders.*", "orders.>")
            .retentionPolicy(RetentionPolicy.Limits)
            .maxBytes(1024 * 1024 * 1024)  // 1GB
            .maxAge(Duration.ofDays(7))
            .maxMsgSize(1024 * 1024)  // 1MB per message
            .replicas(3)
            .storageType(StorageType.File)
            .duplicateWindow(Duration.ofMinutes(2))  // Dedup window
            .build();

        try {
            jsm.addStream(streamConfig);
            log.info("Stream ORDERS created");
        } catch (JetStreamApiException e) {
            if (e.getErrorCode() == 10058) {  // Stream exists
                jsm.updateStream(streamConfig);
                log.info("Stream ORDERS updated");
            } else {
                throw e;
            }
        }

        // Create consumer
        ConsumerConfiguration consumerConfig = ConsumerConfiguration.builder()
            .durable("order-service")
            .deliverPolicy(DeliverPolicy.All)
            .ackPolicy(AckPolicy.Explicit)
            .ackWait(Duration.ofSeconds(30))
            .maxDeliver(3)
            .maxAckPending(1000)
            .filterSubject("orders.created")
            .build();

        jsm.addOrUpdateConsumer("ORDERS", consumerConfig);
    }
}
```

---

## Common Patterns

### Event Sourcing Integration

```java
@Service
public class EventSourcedOrderService {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final OrderEventStore eventStore;

    @Transactional
    public Order createOrder(CreateOrderCommand command) {
        // Create domain event
        OrderCreatedEvent event = OrderCreatedEvent.builder()
            .orderId(UUID.randomUUID().toString())
            .customerId(command.getCustomerId())
            .items(command.getItems())
            .timestamp(Instant.now())
            .version(1)
            .build();

        // Store event
        eventStore.append(event);

        // Publish to Kafka for other services
        kafkaTemplate.send("order-events", event.getOrderId(), event);

        // Rebuild aggregate from events
        return Order.replay(eventStore.getEvents(event.getOrderId()));
    }

    public Order getOrder(String orderId) {
        List<OrderEvent> events = eventStore.getEvents(orderId);
        return Order.replay(events);
    }
}

// Aggregate reconstruction
public class Order {
    private String id;
    private String status;
    private List<OrderItem> items;
    private int version;

    public static Order replay(List<OrderEvent> events) {
        Order order = new Order();
        for (OrderEvent event : events) {
            order.apply(event);
        }
        return order;
    }

    private void apply(OrderEvent event) {
        if (event instanceof OrderCreatedEvent created) {
            this.id = created.getOrderId();
            this.status = "CREATED";
            this.items = created.getItems();
        } else if (event instanceof OrderConfirmedEvent) {
            this.status = "CONFIRMED";
        } else if (event instanceof OrderShippedEvent shipped) {
            this.status = "SHIPPED";
        }
        this.version = event.getVersion();
    }
}
```

### Saga Pattern

```java
// Choreography-based Saga
@Service
public class OrderSagaOrchestrator {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final OrderRepository orderRepository;

    @KafkaListener(topics = "order-created")
    public void handleOrderCreated(OrderCreatedEvent event) {
        // Step 1: Reserve inventory
        kafkaTemplate.send("inventory-reserve",
            new ReserveInventoryCommand(event.getOrderId(), event.getItems()));
    }

    @KafkaListener(topics = "inventory-reserved")
    public void handleInventoryReserved(InventoryReservedEvent event) {
        // Step 2: Process payment
        kafkaTemplate.send("payment-process",
            new ProcessPaymentCommand(event.getOrderId(), event.getAmount()));
    }

    @KafkaListener(topics = "payment-completed")
    public void handlePaymentCompleted(PaymentCompletedEvent event) {
        // Step 3: Confirm order
        Order order = orderRepository.findById(event.getOrderId()).orElseThrow();
        order.confirm();
        orderRepository.save(order);

        kafkaTemplate.send("order-confirmed",
            new OrderConfirmedEvent(event.getOrderId()));
    }

    // Compensation handlers
    @KafkaListener(topics = "inventory-reservation-failed")
    public void handleInventoryFailed(InventoryReservationFailedEvent event) {
        // Compensate: Cancel order
        Order order = orderRepository.findById(event.getOrderId()).orElseThrow();
        order.cancel("Inventory not available");
        orderRepository.save(order);

        kafkaTemplate.send("order-cancelled",
            new OrderCancelledEvent(event.getOrderId(), "Inventory not available"));
    }

    @KafkaListener(topics = "payment-failed")
    public void handlePaymentFailed(PaymentFailedEvent event) {
        // Compensate: Release inventory and cancel order
        kafkaTemplate.send("inventory-release",
            new ReleaseInventoryCommand(event.getOrderId()));

        Order order = orderRepository.findById(event.getOrderId()).orElseThrow();
        order.cancel("Payment failed");
        orderRepository.save(order);
    }
}
```

### Outbox Pattern

```java
@Entity
@Table(name = "outbox_events")
public class OutboxEvent {
    @Id
    private String id;

    @Column(name = "aggregate_type")
    private String aggregateType;

    @Column(name = "aggregate_id")
    private String aggregateId;

    @Column(name = "event_type")
    private String eventType;

    @Column(columnDefinition = "jsonb")
    private String payload;

    @Column(name = "created_at")
    private Instant createdAt;

    @Column(name = "published")
    private boolean published;
}

@Service
@Transactional
public class OrderServiceWithOutbox {

    private final OrderRepository orderRepository;
    private final OutboxRepository outboxRepository;

    public Order createOrder(CreateOrderCommand command) {
        // Create order
        Order order = Order.create(command);
        orderRepository.save(order);

        // Create outbox event in same transaction
        OutboxEvent outboxEvent = OutboxEvent.builder()
            .id(UUID.randomUUID().toString())
            .aggregateType("Order")
            .aggregateId(order.getId())
            .eventType("OrderCreated")
            .payload(toJson(new OrderCreatedEvent(order)))
            .createdAt(Instant.now())
            .published(false)
            .build();
        outboxRepository.save(outboxEvent);

        return order;
    }
}

// Outbox publisher (separate process)
@Service
public class OutboxPublisher {

    private final OutboxRepository outboxRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;

    @Scheduled(fixedDelay = 100)
    @Transactional
    public void publishOutboxEvents() {
        List<OutboxEvent> events = outboxRepository
            .findTop100ByPublishedFalseOrderByCreatedAtAsc();

        for (OutboxEvent event : events) {
            try {
                String topic = event.getAggregateType().toLowerCase() + "-events";
                kafkaTemplate.send(topic, event.getAggregateId(),
                    event.getPayload()).get();

                event.setPublished(true);
                outboxRepository.save(event);

            } catch (Exception e) {
                log.error("Failed to publish outbox event {}: {}",
                    event.getId(), e.getMessage());
                break;  // Stop processing, will retry on next run
            }
        }
    }

    // Cleanup old events
    @Scheduled(cron = "0 0 * * * *")  // Every hour
    @Transactional
    public void cleanupOldEvents() {
        Instant cutoff = Instant.now().minus(Duration.ofDays(7));
        outboxRepository.deleteByPublishedTrueAndCreatedAtBefore(cutoff);
    }
}
```

### Idempotent Consumer

```java
@Entity
@Table(name = "processed_messages")
public class ProcessedMessage {
    @Id
    private String messageId;

    @Column(name = "processed_at")
    private Instant processedAt;

    @Column(name = "result")
    private String result;
}

@Service
public class IdempotentOrderConsumer {

    private final ProcessedMessageRepository processedMessageRepository;
    private final OrderService orderService;

    @KafkaListener(topics = "orders")
    @Transactional
    public void handleOrder(
            @Payload OrderEvent event,
            @Header(KafkaHeaders.RECEIVED_KEY) String key,
            @Header("message-id") String messageId) {

        // Check if already processed
        if (processedMessageRepository.existsById(messageId)) {
            log.info("Message {} already processed, skipping", messageId);
            return;
        }

        // Process the message
        String result = orderService.process(event);

        // Mark as processed
        ProcessedMessage processed = new ProcessedMessage();
        processed.setMessageId(messageId);
        processed.setProcessedAt(Instant.now());
        processed.setResult(result);
        processedMessageRepository.save(processed);
    }

    // Cleanup old records
    @Scheduled(cron = "0 0 2 * * *")  // 2 AM daily
    @Transactional
    public void cleanupOldRecords() {
        Instant cutoff = Instant.now().minus(Duration.ofDays(30));
        processedMessageRepository.deleteByProcessedAtBefore(cutoff);
    }
}
```

### Message Deduplication

```java
@Service
public class DeduplicatingProducer {

    private final KafkaTemplate<String, Object> kafkaTemplate;

    public void send(String topic, String key, Object payload,
                     String deduplicationId) {
        ProducerRecord<String, Object> record =
            new ProducerRecord<>(topic, key, payload);

        // Add deduplication header
        record.headers().add("dedup-id",
            deduplicationId.getBytes(StandardCharsets.UTF_8));
        record.headers().add("timestamp",
            String.valueOf(System.currentTimeMillis())
                .getBytes(StandardCharsets.UTF_8));

        kafkaTemplate.send(record);
    }

    // Generate deterministic dedup ID
    public String generateDedupId(String entityType, String entityId,
                                   String operation) {
        return String.format("%s-%s-%s", entityType, entityId, operation);
    }
}

// Redis-based deduplication
@Service
public class RedisDeduplicatingConsumer {

    private final StringRedisTemplate redisTemplate;
    private final Duration deduplicationWindow = Duration.ofHours(24);

    @KafkaListener(topics = "orders")
    public void handleOrder(
            @Payload OrderEvent event,
            @Header("dedup-id") byte[] dedupIdBytes) {

        String dedupId = new String(dedupIdBytes, StandardCharsets.UTF_8);
        String redisKey = "dedup:" + dedupId;

        // Try to set with NX (only if not exists)
        Boolean isNew = redisTemplate.opsForValue()
            .setIfAbsent(redisKey, "1", deduplicationWindow);

        if (Boolean.FALSE.equals(isNew)) {
            log.info("Duplicate message detected: {}", dedupId);
            return;
        }

        try {
            processOrder(event);
        } catch (Exception e) {
            // Remove dedup key on failure so message can be reprocessed
            redisTemplate.delete(redisKey);
            throw e;
        }
    }
}
```

---

## Anti-patterns và Best Practices

### Anti-patterns cần tránh

#### 1. Large Messages
```java
// BAD: Sending large payloads
public void sendOrder(Order order) {
    // Order contains binary images, large documents
    kafkaTemplate.send("orders", order);  // Can be several MB
}

// GOOD: Use claim check pattern
public void sendOrder(Order order) {
    // Store large data in object storage
    String documentUrl = s3Service.upload(order.getDocuments());
    String imageUrl = s3Service.upload(order.getImages());

    // Send lightweight message with references
    OrderMessage message = OrderMessage.builder()
        .orderId(order.getId())
        .documentUrl(documentUrl)
        .imageUrl(imageUrl)
        .metadata(order.getMetadata())
        .build();

    kafkaTemplate.send("orders", message);
}
```

#### 2. Blocking in Message Handlers
```java
// BAD: Blocking call in consumer
@KafkaListener(topics = "orders")
public void handleOrder(OrderEvent event) {
    // Blocking HTTP call
    OrderDetails details = restTemplate.getForObject(
        "http://external-api/orders/" + event.getId(),
        OrderDetails.class
    );  // Can block for seconds

    processOrder(details);
}

// GOOD: Use async or cache
@KafkaListener(topics = "orders")
public void handleOrder(OrderEvent event) {
    // Check cache first
    OrderDetails details = cache.get(event.getId());
    if (details == null) {
        // Queue for async enrichment
        enrichmentQueue.add(event.getId());
        // Process with available data
        processOrderBasic(event);
        return;
    }
    processOrder(details);
}
```

#### 3. Missing Idempotency
```java
// BAD: Non-idempotent consumer
@KafkaListener(topics = "payments")
public void handlePayment(PaymentEvent event) {
    paymentService.processPayment(event);  // Might charge twice on retry
}

// GOOD: Idempotent consumer
@KafkaListener(topics = "payments")
@Transactional
public void handlePayment(
        PaymentEvent event,
        @Header("message-id") String messageId) {

    if (paymentRepository.existsByMessageId(messageId)) {
        log.info("Payment already processed: {}", messageId);
        return;
    }

    Payment payment = paymentService.processPayment(event);
    payment.setMessageId(messageId);
    paymentRepository.save(payment);
}
```

#### 4. Improper Error Handling
```java
// BAD: Swallowing errors
@KafkaListener(topics = "orders")
public void handleOrder(OrderEvent event) {
    try {
        orderService.process(event);
    } catch (Exception e) {
        log.error("Error processing order", e);
        // Message is acknowledged, error is lost
    }
}

// GOOD: Proper error handling with DLQ
@KafkaListener(topics = "orders")
public void handleOrder(OrderEvent event, Acknowledgment ack) {
    try {
        orderService.process(event);
        ack.acknowledge();
    } catch (RetryableException e) {
        log.warn("Retryable error, will retry: {}", e.getMessage());
        throw e;  // Let error handler retry
    } catch (Exception e) {
        log.error("Non-retryable error, sending to DLQ: {}", e.getMessage());
        ack.acknowledge();  // Ack so it goes to DLT
        throw e;
    }
}
```

#### 5. Not Handling Poison Messages
```java
// BAD: Poison message blocks queue
@RabbitListener(queues = "orders")
public void handleOrder(OrderEvent event) {
    orderService.process(event);  // Keeps failing, message requeued forever
}

// GOOD: Handle poison messages
@RabbitListener(queues = "orders")
public void handleOrder(
        OrderEvent event,
        @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
        @Header(name = "x-death", required = false) List<Map<String, Object>> xDeath,
        Channel channel) throws IOException {

    int retryCount = getRetryCount(xDeath);

    if (retryCount >= MAX_RETRIES) {
        log.error("Max retries exceeded for order: {}", event.getOrderId());
        channel.basicReject(deliveryTag, false);  // Send to DLQ
        return;
    }

    try {
        orderService.process(event);
        channel.basicAck(deliveryTag, false);
    } catch (Exception e) {
        channel.basicNack(deliveryTag, false, true);  // Requeue
    }
}
```

### Best Practices Checklist

#### Design Phase
- [ ] Xác định delivery guarantee cần thiết (at-most-once, at-least-once, exactly-once)
- [ ] Define message schema với versioning strategy
- [ ] Plan cho message ordering requirements
- [ ] Design idempotent consumers từ đầu
- [ ] Plan dead letter queue strategy
- [ ] Define retention policies

#### Producer
- [ ] Sử dụng async sending với proper callbacks
- [ ] Implement retry với exponential backoff
- [ ] Set appropriate timeouts
- [ ] Monitor send success/failure rates
- [ ] Use compression cho large messages
- [ ] Include correlation IDs trong headers

#### Consumer
- [ ] Implement idempotency
- [ ] Use manual acknowledgments
- [ ] Handle poison messages
- [ ] Monitor consumer lag
- [ ] Set appropriate poll/fetch sizes
- [ ] Implement graceful shutdown

#### Operations
- [ ] Monitor queue depth và consumer lag
- [ ] Set up alerting cho anomalies
- [ ] Plan capacity cho peak loads
- [ ] Test failure scenarios
- [ ] Document runbooks cho common issues
- [ ] Regular review của DLQ messages

---

## Workflow khi sử dụng Skill

1. **Analyze Requirements**
   - Xác định throughput và latency requirements
   - Xác định ordering và delivery guarantees cần thiết
   - Review existing infrastructure

2. **Choose Message Broker**
   - Kafka: High throughput, log-based, replay capability
   - RabbitMQ: Flexible routing, traditional queuing, mature ecosystem
   - NATS: Lightweight, low latency, cloud-native

3. **Design Message Contracts**
   - Define message schemas
   - Plan versioning strategy
   - Document message flows

4. **Implement với Patterns**
   - Sử dụng appropriate producer patterns
   - Implement idempotent consumers
   - Add proper error handling

5. **Test và Validate**
   - Unit tests với embedded brokers
   - Integration tests
   - Chaos testing cho failure scenarios

6. **Monitor và Optimize**
   - Set up metrics và alerting
   - Monitor consumer lag
   - Tune performance parameters

---

## Scripts và Tools

### Analyze Consumer Lag
```bash
# Run consumer lag analysis
python scripts/analyze-consumer-lag.py --bootstrap-server localhost:9092 --group order-service

# Output example:
# Topic: orders, Partition: 0, Current Offset: 1000, End Offset: 1050, Lag: 50
```

### Benchmark Throughput
```bash
# Run throughput benchmark
./scripts/benchmark-throughput.sh --broker kafka --messages 100000 --size 1024

# Output example:
# Messages: 100000
# Size: 1KB
# Duration: 5.2s
# Throughput: 19230 msg/s
# Latency p50: 2ms, p99: 15ms
```

## Tài liệu tham khảo

- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Spring Kafka Reference](https://docs.spring.io/spring-kafka/reference/)
- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [Spring AMQP Reference](https://docs.spring.io/spring-amqp/reference/)
- [NATS Documentation](https://docs.nats.io/)
- [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/)
