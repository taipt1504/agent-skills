---
name: message-queue-java-expert
description: Expert guidance for message queue implementation in Java (Kafka, RabbitMQ, NATS) - patterns, best practices, and production-ready solutions
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

## Purpose

This skill provides expert guidance for implementing message queue systems in Java, including:

- **Kafka**: High-throughput distributed streaming platform
- **RabbitMQ**: Feature-rich message broker with flexible routing
- **NATS**: Lightweight, high-performance messaging system

Supports everything from design decisions to production-ready implementations with Spring Boot integration.

## When to Use this Skill

### Use when:

1. **Designing message-driven architecture** - Choosing suitable message broker, defining message schemas
2. **Implementing producers/consumers** - Code patterns for Kafka, RabbitMQ, or NATS
3. **Troubleshooting messaging issues** - Consumer lag, message loss, ordering problems
4. **Optimizing performance** - Tuning throughput, latency, resource usage
5. **Handling failures** - Retry strategies, dead letter queues, exactly-once processing
6. **Migrating between brokers** - Switching from RabbitMQ to Kafka or vice versa

### Do NOT use when:

1. **Simple synchronous communication** - REST/gRPC is sufficient
2. **Database-level concerns** - Use database-architect skill
3. **Infrastructure setup** - Use cloud-architect or devops skills
4. **Non-Java implementations** - This skill focuses on Java ecosystem

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

### Partitioning and Ordering

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

### Consumer Groups and Scaling

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

> See details in: `references/kafka-patterns.md`

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

> See details in: `references/rabbitmq-patterns.md`

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
    // ...
}
```
