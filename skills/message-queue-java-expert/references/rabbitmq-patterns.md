# RabbitMQ Patterns Reference

## Overview

RabbitMQ is a mature, robust message broker that implements the Advanced Message Queuing Protocol (AMQP 0-9-1). This document provides a reference for RabbitMQ patterns for Java applications using Spring AMQP.

---

## Architecture Fundamentals

### RabbitMQ Components

```
Publisher -> Exchange -> [Bindings] -> Queue -> Consumer
```

- **Exchange**: Message routing agent (the mailbox)
- **Queue**: Message buffer
- **Binding**: Rules connecting exchanges to queues
- **Routing Key**: Address on the message used for routing

### Exchange Types

| Type | Routing Logic | Use Case |
|------|---------------|----------|
| **Direct** | Exact match of routing key | 1:1, Point-to-Point |
| **Topic** | Pattern match (`*` word, `#` zero+ words) | 1:N, Pub/Sub with routing |
| **Fanout** | Broadcast to all bound queues | 1:N, Broadcast |
| **Headers** | Match on message headers | Complex routing rules |

---

## Spring AMQP Configuration

### Basic Configuration

```java
@Configuration
public class RabbitConfig {

    @Bean
    public CachingConnectionFactory connectionFactory() {
        CachingConnectionFactory factory = new CachingConnectionFactory("localhost");
        factory.setUsername("guest");
        factory.setPassword("guest");
        factory.setPort(5672);
        
        // Enable publisher confirms and returns
        factory.setPublisherConfirmType(CachingConnectionFactory.ConfirmType.CORRELATED);
        factory.setPublisherReturns(true);
        
        return factory;
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(messageConverter());
        template.setMandatory(true); // Return unroutable messages
        return template;
    }

    @Bean
    public MessageConverter messageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}
```

### Topology Configuration

```java
@Configuration
public class OrderTopology {

    public static final String EXCHANGE = "orders.exchange";
    public static final String QUEUE_CREATED = "orders.created.queue";
    public static final String ROUTING_KEY_CREATED = "orders.created";

    // Exchange
    @Bean
    public TopicExchange ordersExchange() {
        return ExchangeBuilder.topicExchange(EXCHANGE)
            .durable(true)
            .build();
    }

    // Key
    @Bean
    public Queue ordersCreatedQueue() {
        return QueueBuilder.durable(QUEUE_CREATED)
            .withArgument("x-dead-letter-exchange", "dlx.exchange")
            .withArgument("x-dead-letter-routing-key", "dlq")
            .build();
    }

    // Binding
    @Bean
    public Binding bindingCreated() {
        return BindingBuilder.bind(ordersCreatedQueue())
            .to(ordersExchange())
            .with(ROUTING_KEY_CREATED);
    }
}
```

---

## Producer Patterns

### Reliable Producer (Publisher Confirms)

```java
@Service
@Slf4j
public class ReliableProducer {

    private final RabbitTemplate rabbitTemplate;

    @PostConstruct
    public void init() {
        // Callback for confirms (Ack/Nack from Broker)
        rabbitTemplate.setConfirmCallback((correlation, ack, reason) -> {
            if (ack) {
                log.info("Message confirmed: id={}",
                    correlation != null ? correlation.getId() : "null");
            } else {
                log.error("Message nacked: id={}, reason={}",
                    correlation != null ? correlation.getId() : "null", reason);
                // Handle Nack (retry, alert)
            }
        });

        // Callback for returned messages (Unroutable)
        rabbitTemplate.setReturnsCallback(returned -> {
            log.error("Message returned: replyText={}, exchange={}, routingKey={}",
                returned.getReplyText(), returned.getExchange(), returned.getRoutingKey());
        });
    }

    public void sendOrder(OrderEvent event) {
        CorrelationData correlationData = new CorrelationData(event.getOrderId());
        
        rabbitTemplate.convertAndSend(
            OrderTopology.EXCHANGE,
            "orders.created",
            event,
            correlationData
        );
    }
}
```

### Transactional Producer

```java
@Service
public class TransactionalProducer {

    private final RabbitTemplate rabbitTemplate;

    public TransactionalProducer(RabbitTemplate rabbitTemplate) {
        this.rabbitTemplate = rabbitTemplate;
        this.rabbitTemplate.setChannelTransacted(true);
    }

    @Transactional
    public void processOrder(Order order) {
        // Database operation
        orderRepository.save(order);

        // Message send - committed only if transaction commits
        rabbitTemplate.convertAndSend(
            OrderTopology.EXCHANGE,
            "orders.created",
            new OrderEvent(order)
        );
    }
}
```

### Priority Queue Producer

```java
// Configuration
@Bean
public Queue priorityQueue() {
    return QueueBuilder.durable("priority.queue")
        .withArgument("x-max-priority", 10) // Enable priority (0-10)
        .build();
}

// Producer
public void sendUrgent(String message) {
    rabbitTemplate.convertAndSend("priority.queue", message, m -> {
        m.getMessageProperties().setPriority(10); // Highest
        return m;
    });
}
```

### Delayed Message Producer

Requires `rabbitmq_delayed_message_exchange` plugin.

```java
// Configuration
@Bean
public CustomExchange delayedExchange() {
    Map<String, Object> args = new HashMap<>();
    args.put("x-delayed-type", "direct");
    return new CustomExchange("delayed.exchange", "x-delayed-message", true, false, args);
}

// Producer
public void sendDelayed(String message, Integer delayMs) {
    rabbitTemplate.convertAndSend("delayed.exchange", "key", message, m -> {
        m.getMessageProperties().setHeader("x-delay", delayMs);
        return m;
    });
}
```

---

## Consumer Patterns

### Manual Acknowledgment

```java
@Service
@Slf4j
public class ManualAckConsumer {

    @RabbitListener(queues = "orders.created.queue", ackMode = "MANUAL")
    public void receive(OrderEvent event, Channel channel, 
                        @Header(AmqpHeaders.DELIVERY_TAG) long tag) {
        try {
            log.info("Processing order: {}", event.getOrderId());
            processOrder(event);
            
            // Ack: tag, multiple=false
            channel.basicAck(tag, false);
            
        } catch (Exception e) {
            log.error("Error processing order", e);
            
            // Nack: tag, multiple=false, requeue=false (send to DLQ)
            try {
                channel.basicNack(tag, false, false);
            } catch (IOException ioException) {
                log.error("Failed to nack", ioException);
            }
        }
    }
}
```

### Batch Consumer

Requires `spring.rabbitmq.listener.simple.batch-size` configuration.

```java
// Properties
// spring.rabbitmq.listener.type=simple
// spring.rabbitmq.listener.simple.batch-size=10
// spring.rabbitmq.listener.simple.consumer-batch-enabled=true

@Service
@Slf4j
public class BatchConsumer {

    @RabbitListener(queues = "batch.queue")
    public void receiveBatch(List<Message> messages, Channel channel) {
        log.info("Received batch size: {}", messages.size());
        
        try {
            for (Message message : messages) {
                // Process each
                process(message);
            }
            
            // Ack last message implies ack all previous in batch
            long lastTag = messages.get(messages.size() - 1)
                .getMessageProperties().getDeliveryTag();
                
            channel.basicAck(lastTag, true);
            
        } catch (Exception e) {
            // Handle batch failure - basicNack(lastTag, true, true/false)
            // Note: Nacking batch with requeue=true may cause loop
        }
    }
}
```

### Competing Consumers

Simply run multiple instances of the application or configure concurrency.

```java
@Bean
public SimpleRabbitListenerContainerFactory rabbitListenerContainerFactory(
        ConnectionFactory connectionFactory) {
    SimpleRabbitListenerContainerFactory factory = 
        new SimpleRabbitListenerContainerFactory();
    factory.setConnectionFactory(connectionFactory);
    factory.setConcurrentConsumers(3); // Start 3 consumers
    factory.setMaxConcurrentConsumers(10); // Scale up to 10
    factory.setPrefetchCount(1); // Fair dispatch
    return factory;
}
```

### Request-Reply (RPC)

```java
// Configuration
@Bean
public RabbitTemplate amqpTemplate(ConnectionFactory connectionFactory) {
    RabbitTemplate template = new RabbitTemplate(connectionFactory);
    template.setReplyTimeout(5000);
    return template;
}

// Client
@Service
public class RpcClient {
    @Autowired
    private RabbitTemplate rabbitTemplate;

    public OrderStatus checkStatus(String orderId) {
        Object response = rabbitTemplate.convertSendAndReceive(
            "rpc.exchange", "rpc.status", orderId);
            
        if (response == null) {
            throw new RuntimeException("RPC Timeout");
        }
        
        return (OrderStatus) response;
    }
}

// Server
@Service
public class RpcServer {

    @RabbitListener(queues = "rpc.status.queue")
    public OrderStatus processRequest(String orderId) {
        return getStatus(orderId);
        // Return value is automatically sent to replyTo queue
    }
}

// Async API variant
@Service
public class AsyncRpcServer {

    @RabbitListener(queues = "api.validation.queue")
    public OrderValidationResponse validate(OrderValidationRequest request,
                                          @Header(AmqpHeaders.CORRELATION_ID) String correlationId) {
        try {
            // Simulate complex validation
            boolean isValid = validateOrder(request);

            return OrderValidationResponse.builder()
                .orderId(request.getOrderId())
                .valid(isValid)
                .correlationId(correlationId)
                .timestamp(Instant.now())
                .build();

        } catch (Exception e) {
            return OrderValidationResponse.builder()
                .orderId(request.getOrderId())
                .valid(false)
                .error(e.getMessage())
                .correlationId(correlationId)
                .timestamp(Instant.now())
                .build();
        }
    }
}
```

---

## Dead Letter Queue Pattern

### DLQ Configuration

```java
@Configuration
public class DlqConfig {

    // Main exchange
    @Bean
    public TopicExchange mainExchange() {
        return new TopicExchange("main.exchange");
    }

    // Dead letter exchange
    @Bean
    public DirectExchange dlxExchange() {
        return new DirectExchange("dlx.exchange");
    }

    // Main queue with DLX
    @Bean
    public Queue mainQueue() {
        return QueueBuilder
            .durable("main.queue")
            .withArgument("x-dead-letter-exchange", "dlx.exchange")
            .withArgument("x-dead-letter-routing-key", "dlq")
            .build();
    }

    // Dead letter queue
    @Bean
    public Queue dlq() {
        return QueueBuilder
            .durable("main.queue.dlq")
            .withArgument("x-message-ttl", 604800000)  // 7 days
            .build();
    }

    // DLQ binding
    @Bean
    public Binding dlqBinding() {
        return BindingBuilder
            .bind(dlq())
            .to(dlxExchange())
            .with("dlq");
    }
}
```

### DLQ Consumer

```java
@Service
@Slf4j
public class DlqProcessor {

    private final DeadLetterRepository deadLetterRepository;
    private final RabbitTemplate rabbitTemplate;

    @RabbitListener(queues = "main.queue.dlq")
    public void handleDeadLetter(
            Message message,
            @Header("x-death") List<Map<String, Object>> xDeath) {

        String messageId = message.getMessageProperties().getMessageId();
        String body = new String(message.getBody(), StandardCharsets.UTF_8);

        // Extract death information
        Map<String, Object> lastDeath = xDeath.get(0);
        String reason = (String) lastDeath.get("reason");
        String originalQueue = (String) lastDeath.get("queue");
        long count = (long) lastDeath.get("count");
        Date time = (Date) lastDeath.get("time");

        log.error("Dead letter received: messageId={}, reason={}, " +
            "originalQueue={}, deathCount={}, time={}",
            messageId, reason, originalQueue, count, time);

        // Store for analysis
        DeadLetter deadLetter = DeadLetter.builder()
            .messageId(messageId)
            .body(body)
            .reason(reason)
            .originalQueue(originalQueue)
            .deathCount((int) count)
            .deathTime(time.toInstant())
            .receivedAt(Instant.now())
            .status(DeadLetterStatus.NEW)
            .build();

        deadLetterRepository.save(deadLetter);
    }

    // Retry dead letter
    public void retryDeadLetter(String messageId) {
        DeadLetter deadLetter = deadLetterRepository.findById(messageId)
            .orElseThrow(() -> new NotFoundException("Dead letter not found"));

        try {
            // Re-send to original queue
            rabbitTemplate.convertAndSend(
                "main.exchange",
                deadLetter.getOriginalQueue().replace(".queue", ""),
                deadLetter.getBody()
            );

            deadLetter.setStatus(DeadLetterStatus.RETRIED);
            deadLetter.setRetriedAt(Instant.now());
            deadLetterRepository.save(deadLetter);

        } catch (Exception e) {
            log.error("Failed to retry dead letter: {}", messageId, e);
            throw new RetryFailedException("Failed to retry", e);
        }
    }
}
```

### Retry Queue Pattern (Delay + Retry)

```java
@Configuration
public class RetryQueueConfig {

    // Retry exchange
    @Bean
    public DirectExchange retryExchange() {
        return new DirectExchange("retry.exchange");
    }

    // Retry queues with different delays
    @Bean
    public Queue retryQueue1Min() {
        return QueueBuilder
            .durable("retry.1min.queue")
            .withArgument("x-dead-letter-exchange", "main.exchange")
            .withArgument("x-dead-letter-routing-key", "main")
            .withArgument("x-message-ttl", 60000)  // 1 minute
            .build();
    }

    @Bean
    public Queue retryQueue5Min() {
        return QueueBuilder
            .durable("retry.5min.queue")
            .withArgument("x-dead-letter-exchange", "main.exchange")
            .withArgument("x-dead-letter-routing-key", "main")
            .withArgument("x-message-ttl", 300000)  // 5 minutes
            .build();
    }

    @Bean
    public Queue retryQueue30Min() {
        return QueueBuilder
            .durable("retry.30min.queue")
            .withArgument("x-dead-letter-exchange", "main.exchange")
            .withArgument("x-dead-letter-routing-key", "main")
            .withArgument("x-message-ttl", 1800000)  // 30 minutes
            .build();
    }
}

@Service
public class RetryHandler {

    private final RabbitTemplate rabbitTemplate;

    public void sendToRetry(Message message, int retryCount) {
        String routingKey;

        if (retryCount <= 1) {
            routingKey = "retry.1min";
        } else if (retryCount <= 3) {
            routingKey = "retry.5min";
        } else if (retryCount <= 5) {
            routingKey = "retry.30min";
        } else {
            // Max retries exceeded, send to DLQ
            rabbitTemplate.send("dlx.exchange", "dlq", message);
            return;
        }

        // Update retry count header
        message.getMessageProperties().setHeader("x-retry-count", retryCount);

        rabbitTemplate.send("retry.exchange", routingKey, message);
    }
}
```

---

## High Availability Patterns

### Quorum Queues

```java
@Configuration
public class QuorumQueueConfig {

    @Bean
    public Queue quorumQueue() {
        return QueueBuilder
            .durable("ha.orders.queue")
            .quorum()  // Enables quorum queue
            .withArgument("x-quorum-initial-group-size", 3)
            .withArgument("x-delivery-limit", 5)  // Redelivery limit
            .withArgument("x-dead-letter-exchange", "dlx.exchange")
            .withArgument("x-dead-letter-routing-key", "dlq")
            .build();
    }
}
```

### Cluster-aware Producer

```java
@Configuration
public class ClusterAwareConfig {

    @Bean
    public ConnectionFactory connectionFactory() {
        CachingConnectionFactory factory = new CachingConnectionFactory();

        // Multiple nodes
        factory.setAddresses("rabbit1:5672,rabbit2:5672,rabbit3:5672");
        factory.setUsername("admin");
        factory.setPassword("admin");

        // Recovery
        factory.getRabbitConnectionFactory().setAutomaticRecoveryEnabled(true);
        factory.getRabbitConnectionFactory().setTopologyRecoveryEnabled(true);
        factory.getRabbitConnectionFactory().setNetworkRecoveryInterval(5000);

        return factory;
    }
}
```

---

## Monitoring and Metrics

### Micrometer Integration

```java
@Configuration
public class RabbitMetricsConfig {

    @Bean
    public MicrometerGauge micrometerGauge(MeterRegistry registry) {
        return new MicrometerGauge(registry, "rabbitmq");
    }
}

@Service
public class RabbitMetricsService {

    private final MeterRegistry registry;
    private final RabbitAdmin rabbitAdmin;

    @Scheduled(fixedRate = 60000)
    public void collectQueueMetrics() {
        for (String queueName : List.of("order.queue", "order.dlq")) {
            QueueInformation info = rabbitAdmin.getQueueInfo(queueName);

            if (info != null) {
                registry.gauge("rabbitmq.queue.message.count",
                    Tags.of("queue", queueName),
                    info.getMessageCount());

                registry.gauge("rabbitmq.queue.consumer.count",
                    Tags.of("queue", queueName),
                    info.getConsumerCount());
            }
        }
    }

    public void recordMessageSent(String exchange, String routingKey,
                                   boolean success) {
        registry.counter("rabbitmq.messages.sent",
            "exchange", exchange,
            "routingKey", routingKey,
            "success", String.valueOf(success)
        ).increment();
    }

    public void recordMessageProcessed(String queue, long processingTimeMs,
                                        boolean success) {
        registry.timer("rabbitmq.messages.processed",
            "queue", queue,
            "success", String.valueOf(success)
        ).record(processingTimeMs, TimeUnit.MILLISECONDS);
    }
}
```

### Health Check

```java
@Component
public class RabbitHealthIndicator implements HealthIndicator {

    private final RabbitTemplate rabbitTemplate;

    @Override
    public Health health() {
        try {
            rabbitTemplate.execute(channel -> {
                // Check connection is alive
                return channel.isOpen();
            });
            return Health.up().build();
        } catch (Exception e) {
            return Health.down()
                .withException(e)
                .build();
        }
    }
}
```

---

## Common Issues and Solutions

### Issue: Messages Stuck in Unacked State

**Symptoms:** Messages remain unacknowledged

**Solution:**
```java
// Ensure proper ack/nack in all code paths
@RabbitListener(queues = "queue")
public void handle(Message msg, Channel channel,
                   @Header(AmqpHeaders.DELIVERY_TAG) long tag) {
    try {
        process(msg);
        channel.basicAck(tag, false);
    } catch (Exception e) {
        // Always ack or reject
        channel.basicReject(tag, false);
    }
}
```

### Issue: Connection Recovery Not Working

**Symptoms:** Consumer stops after network issues

**Solution:**
```java
// Enable recovery in connection factory
factory.getRabbitConnectionFactory().setAutomaticRecoveryEnabled(true);
factory.getRabbitConnectionFactory().setTopologyRecoveryEnabled(true);

// Set recovery interval
factory.getRabbitConnectionFactory().setNetworkRecoveryInterval(5000);
```

### Issue: Memory Alarms on Broker

**Symptoms:** Publishers blocked

**Solution:**
```java
// Set queue limits
.withArgument("x-max-length", 100000)
.withArgument("x-overflow", "reject-publish")

// Or use TTL
.withArgument("x-message-ttl", 86400000)
```

---

## Best Practices Checklist

### Producer
- [ ] Use publisher confirms for reliable delivery
- [ ] Set message persistence for durability
- [ ] Include correlation ID and message ID
- [ ] Handle returned/unroutable messages
- [ ] Implement connection recovery

### Consumer
- [ ] Use manual acknowledgment
- [ ] Implement idempotency
- [ ] Handle redeliveries appropriately
- [ ] Set up dead letter queues
- [ ] Configure appropriate prefetch

### Operations
- [ ] Use quorum queues for HA
- [ ] Monitor queue depths
- [ ] Set queue limits to prevent memory issues
- [ ] Implement health checks
- [ ] Document exchange/queue topology

