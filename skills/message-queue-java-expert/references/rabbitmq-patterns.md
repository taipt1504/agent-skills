# RabbitMQ Patterns Reference

## Overview

RabbitMQ là feature-rich message broker implement AMQP protocol, cung cấp flexible routing, reliable delivery, và mature ecosystem. Document này covers RabbitMQ patterns cho Java applications với Spring AMQP.

---

## Architecture Fundamentals

### RabbitMQ Components

```
Producer                    RabbitMQ                        Consumer
   │                          │                                │
   │    ┌─────────────────────┼─────────────────────┐          │
   │    │                     │                     │          │
   │    │  ┌──────────────────┴──────────────────┐ │          │
   │    │  │            Exchange                  │ │          │
   └────┼──┤  (direct, topic, fanout, headers)   ├─┼──────────┘
        │  └──────────┬───────────┬──────────────┘ │
        │             │  Bindings │                │
        │             ▼           ▼                │
        │      ┌──────────┐ ┌──────────┐          │
        │      │  Queue 1 │ │  Queue 2 │          │
        │      └──────────┘ └──────────┘          │
        │                                          │
        └──────────────────────────────────────────┘
```

### Exchange Types

| Type | Routing Logic | Use Case |
|------|---------------|----------|
| **Direct** | Exact routing key match | Point-to-point, task distribution |
| **Topic** | Pattern matching with wildcards | Event filtering by type/category |
| **Fanout** | Broadcast to all bound queues | Pub/Sub, notifications |
| **Headers** | Header attribute matching | Complex routing rules |

---

## Spring AMQP Configuration

### Complete Configuration

```java
@Configuration
public class RabbitMQConfig {

    @Value("${rabbitmq.host}")
    private String host;

    @Value("${rabbitmq.port}")
    private int port;

    @Value("${rabbitmq.username}")
    private String username;

    @Value("${rabbitmq.password}")
    private String password;

    @Value("${rabbitmq.virtual-host:/}")
    private String virtualHost;

    // Connection Factory
    @Bean
    public ConnectionFactory connectionFactory() {
        CachingConnectionFactory factory = new CachingConnectionFactory();
        factory.setHost(host);
        factory.setPort(port);
        factory.setUsername(username);
        factory.setPassword(password);
        factory.setVirtualHost(virtualHost);

        // Connection pooling
        factory.setCacheMode(CachingConnectionFactory.CacheMode.CHANNEL);
        factory.setChannelCacheSize(25);
        factory.setChannelCheckoutTimeout(1000);

        // Heartbeat and timeouts
        factory.getRabbitConnectionFactory().setRequestedHeartbeat(60);
        factory.getRabbitConnectionFactory().setConnectionTimeout(30000);

        // Recovery
        factory.getRabbitConnectionFactory().setAutomaticRecoveryEnabled(true);
        factory.getRabbitConnectionFactory().setNetworkRecoveryInterval(5000);

        // Publisher confirms
        factory.setPublisherConfirmType(
            CachingConnectionFactory.ConfirmType.CORRELATED);
        factory.setPublisherReturns(true);

        return factory;
    }

    // Exchanges
    @Bean
    public TopicExchange orderExchange() {
        return ExchangeBuilder
            .topicExchange("order.exchange")
            .durable(true)
            .build();
    }

    @Bean
    public DirectExchange dlxExchange() {
        return ExchangeBuilder
            .directExchange("dlx.exchange")
            .durable(true)
            .build();
    }

    @Bean
    public FanoutExchange notificationExchange() {
        return ExchangeBuilder
            .fanoutExchange("notification.exchange")
            .durable(true)
            .build();
    }

    // Queues
    @Bean
    public Queue orderQueue() {
        return QueueBuilder
            .durable("order.queue")
            .withArgument("x-dead-letter-exchange", "dlx.exchange")
            .withArgument("x-dead-letter-routing-key", "order.dlq")
            .withArgument("x-message-ttl", 86400000)  // 24 hours
            .withArgument("x-max-length", 100000)
            .withArgument("x-overflow", "reject-publish")
            .build();
    }

    @Bean
    public Queue orderDlq() {
        return QueueBuilder
            .durable("order.dlq")
            .withArgument("x-message-ttl", 604800000)  // 7 days
            .build();
    }

    @Bean
    public Queue orderRetryQueue() {
        return QueueBuilder
            .durable("order.retry.queue")
            .withArgument("x-dead-letter-exchange", "order.exchange")
            .withArgument("x-dead-letter-routing-key", "order.created")
            .withArgument("x-message-ttl", 30000)  // 30 seconds delay
            .build();
    }

    // Quorum queue for high availability
    @Bean
    public Queue highAvailabilityQueue() {
        return QueueBuilder
            .durable("ha.queue")
            .quorum()
            .withArgument("x-quorum-initial-group-size", 3)
            .withArgument("x-delivery-limit", 5)
            .build();
    }

    // Bindings
    @Bean
    public Binding orderBinding() {
        return BindingBuilder
            .bind(orderQueue())
            .to(orderExchange())
            .with("order.#");  // Matches order.created, order.updated, etc.
    }

    @Bean
    public Binding orderDlqBinding() {
        return BindingBuilder
            .bind(orderDlq())
            .to(dlxExchange())
            .with("order.dlq");
    }

    // RabbitTemplate
    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);

        template.setMessageConverter(jackson2JsonMessageConverter());
        template.setMandatory(true);  // Return unroutable messages

        // Confirm callback
        template.setConfirmCallback((correlationData, ack, cause) -> {
            if (correlationData != null) {
                if (ack) {
                    log.debug("Message confirmed: {}", correlationData.getId());
                } else {
                    log.error("Message not confirmed: {} - {}",
                        correlationData.getId(), cause);
                }
            }
        });

        // Return callback
        template.setReturnsCallback(returned -> {
            log.error("Message returned: {} - {} - {}",
                returned.getReplyCode(),
                returned.getReplyText(),
                returned.getRoutingKey());
        });

        return template;
    }

    @Bean
    public MessageConverter jackson2JsonMessageConverter() {
        Jackson2JsonMessageConverter converter =
            new Jackson2JsonMessageConverter();
        converter.setCreateMessageIds(true);
        return converter;
    }
}
```

### Listener Container Configuration

```java
@Configuration
public class RabbitListenerConfig {

    @Bean
    public SimpleRabbitListenerContainerFactory
            rabbitListenerContainerFactory(ConnectionFactory connectionFactory) {

        SimpleRabbitListenerContainerFactory factory =
            new SimpleRabbitListenerContainerFactory();

        factory.setConnectionFactory(connectionFactory);
        factory.setMessageConverter(new Jackson2JsonMessageConverter());

        // Concurrency
        factory.setConcurrentConsumers(3);
        factory.setMaxConcurrentConsumers(10);

        // Prefetch
        factory.setPrefetchCount(10);

        // Acknowledgment
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);

        // Error handling
        factory.setDefaultRequeueRejected(false);
        factory.setErrorHandler(new ConditionalRejectingErrorHandler(
            new DefaultExceptionStrategy() {
                @Override
                public boolean isFatal(Throwable t) {
                    // Don't retry these
                    return t instanceof ValidationException ||
                           t instanceof JsonParseException;
                }
            }
        ));

        // Retry
        factory.setAdviceChain(retryInterceptor());

        return factory;
    }

    @Bean
    public RetryOperationsInterceptor retryInterceptor() {
        return RetryInterceptorBuilder
            .stateless()
            .maxAttempts(3)
            .backOffOptions(1000, 2.0, 10000)
            .recoverer(new RejectAndDontRequeueRecoverer())
            .build();
    }

    // Container for priority messages
    @Bean
    public SimpleRabbitListenerContainerFactory
            priorityListenerContainerFactory(ConnectionFactory connectionFactory) {

        SimpleRabbitListenerContainerFactory factory =
            new SimpleRabbitListenerContainerFactory();

        factory.setConnectionFactory(connectionFactory);
        factory.setMessageConverter(new Jackson2JsonMessageConverter());
        factory.setConcurrentConsumers(5);
        factory.setPrefetchCount(1);  // Lower prefetch for fairness
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);

        return factory;
    }
}
```

---

## Producer Patterns

### Reliable Producer with Confirms

```java
@Service
@Slf4j
public class ReliableRabbitProducer {

    private final RabbitTemplate rabbitTemplate;
    private final MeterRegistry meterRegistry;

    public void sendWithConfirm(String exchange, String routingKey,
                                 Object message) {
        String messageId = UUID.randomUUID().toString();
        CorrelationData correlationData = new CorrelationData(messageId);

        rabbitTemplate.convertAndSend(
            exchange,
            routingKey,
            message,
            msg -> {
                MessageProperties props = msg.getMessageProperties();
                props.setMessageId(messageId);
                props.setTimestamp(new Date());
                props.setDeliveryMode(MessageDeliveryMode.PERSISTENT);
                props.setContentType("application/json");
                return msg;
            },
            correlationData
        );

        // Wait for confirm
        try {
            CorrelationData.Confirm confirm =
                correlationData.getFuture().get(5, TimeUnit.SECONDS);

            if (confirm.isAck()) {
                meterRegistry.counter("rabbitmq.send.confirmed").increment();
                log.debug("Message confirmed: {}", messageId);
            } else {
                meterRegistry.counter("rabbitmq.send.nacked").increment();
                throw new MessageNotConfirmedException(
                    "Message nacked: " + confirm.getReason());
            }
        } catch (TimeoutException e) {
            meterRegistry.counter("rabbitmq.send.timeout").increment();
            throw new MessageSendException("Confirm timeout for: " + messageId, e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new MessageSendException("Interrupted", e);
        } catch (ExecutionException e) {
            throw new MessageSendException("Execution error", e);
        }
    }

    // Async with CompletableFuture
    public CompletableFuture<Boolean> sendAsync(String exchange,
                                                 String routingKey,
                                                 Object message) {
        String messageId = UUID.randomUUID().toString();
        CorrelationData correlationData = new CorrelationData(messageId);

        rabbitTemplate.convertAndSend(exchange, routingKey, message,
            correlationData);

        return correlationData.getFuture()
            .thenApply(confirm -> {
                if (!confirm.isAck()) {
                    log.error("Message not acked: {}", confirm.getReason());
                }
                return confirm.isAck();
            });
    }

    // Batch sending
    public void sendBatch(String exchange, String routingKey,
                          List<Object> messages) {
        List<CompletableFuture<Boolean>> futures = new ArrayList<>();

        for (Object message : messages) {
            futures.add(sendAsync(exchange, routingKey, message));
        }

        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
            .join();

        long confirmed = futures.stream()
            .filter(f -> {
                try {
                    return f.get();
                } catch (Exception e) {
                    return false;
                }
            })
            .count();

        log.info("Batch complete: {}/{} confirmed",
            confirmed, messages.size());
    }
}
```

### Transactional Producer

```java
@Service
public class TransactionalRabbitProducer {

    private final RabbitTemplate rabbitTemplate;

    public void sendInTransaction(String exchange, String routingKey,
                                   List<Object> messages) {
        rabbitTemplate.invoke(operations -> {
            for (Object message : messages) {
                operations.convertAndSend(exchange, routingKey, message);
            }
            return null;
        });
        // All messages sent atomically
    }

    // Mixed transaction with database
    @Transactional
    public void processAndSend(Order order) {
        // Database operation
        orderRepository.save(order);

        // RabbitMQ send in same transaction context
        rabbitTemplate.convertAndSend("order.exchange", "order.created", order);

        // If database commit fails, message won't be sent
    }
}
```

### Priority Messages

```java
@Service
public class PriorityRabbitProducer {

    private final RabbitTemplate rabbitTemplate;

    public void sendWithPriority(String exchange, String routingKey,
                                  Object message, int priority) {
        rabbitTemplate.convertAndSend(
            exchange,
            routingKey,
            message,
            msg -> {
                msg.getMessageProperties().setPriority(priority);
                return msg;
            }
        );
    }

    public void sendHighPriority(Object message) {
        sendWithPriority("order.exchange", "order.urgent", message, 10);
    }

    public void sendNormalPriority(Object message) {
        sendWithPriority("order.exchange", "order.normal", message, 5);
    }

    public void sendLowPriority(Object message) {
        sendWithPriority("order.exchange", "order.batch", message, 1);
    }
}

// Priority queue configuration
@Bean
public Queue priorityQueue() {
    return QueueBuilder
        .durable("priority.queue")
        .withArgument("x-max-priority", 10)
        .build();
}
```

### Delayed Messages

```java
@Configuration
public class DelayedExchangeConfig {

    // Requires rabbitmq_delayed_message_exchange plugin
    @Bean
    public CustomExchange delayedExchange() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-delayed-type", "direct");
        return new CustomExchange(
            "delayed.exchange",
            "x-delayed-message",
            true,
            false,
            args
        );
    }
}

@Service
public class DelayedMessageProducer {

    private final RabbitTemplate rabbitTemplate;

    // Using delayed exchange plugin
    public void sendDelayed(Object message, Duration delay) {
        rabbitTemplate.convertAndSend(
            "delayed.exchange",
            "delayed.routing.key",
            message,
            msg -> {
                msg.getMessageProperties()
                    .setDelay((int) delay.toMillis());
                return msg;
            }
        );
    }

    // Using TTL + DLX pattern (no plugin needed)
    public void sendDelayedViaTtl(Object message, long delayMs) {
        rabbitTemplate.convertAndSend(
            "delay.exchange",  // Routes to delay queue
            "delay." + delayMs,
            message,
            msg -> {
                msg.getMessageProperties().setExpiration(String.valueOf(delayMs));
                return msg;
            }
        );
        // Delay queue has DLX that routes to actual processing queue
    }
}
```

---

## Consumer Patterns

### Manual Acknowledgment Consumer

```java
@Service
@Slf4j
public class ManualAckConsumer {

    private final OrderService orderService;

    @RabbitListener(
        queues = "${rabbitmq.queues.orders}",
        containerFactory = "rabbitListenerContainerFactory"
    )
    public void handleOrder(
            @Payload OrderEvent event,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
            @Header(AmqpHeaders.REDELIVERED) boolean redelivered,
            @Header(AmqpHeaders.MESSAGE_ID) String messageId,
            Channel channel) throws IOException {

        MDC.put("messageId", messageId);

        try {
            log.info("Processing order: {}, redelivered: {}",
                event.getOrderId(), redelivered);

            // Check if already processed (idempotency)
            if (orderService.isProcessed(messageId)) {
                log.info("Already processed, acknowledging");
                channel.basicAck(deliveryTag, false);
                return;
            }

            // Process
            orderService.process(event, messageId);

            // Acknowledge
            channel.basicAck(deliveryTag, false);
            log.info("Order processed successfully");

        } catch (RetryableException e) {
            log.warn("Retryable error: {}", e.getMessage());

            if (redelivered) {
                // Already retried, send to DLQ
                log.error("Redelivery failed, rejecting to DLQ");
                channel.basicReject(deliveryTag, false);
            } else {
                // Requeue for retry
                channel.basicNack(deliveryTag, false, true);
            }

        } catch (Exception e) {
            log.error("Non-retryable error, rejecting to DLQ", e);
            channel.basicReject(deliveryTag, false);

        } finally {
            MDC.clear();
        }
    }
}
```

### Batch Consumer

```java
@Service
public class BatchRabbitConsumer {

    private final OrderRepository orderRepository;

    @RabbitListener(
        queues = "order.batch.queue",
        containerFactory = "batchListenerContainerFactory"
    )
    public void handleBatch(List<Message> messages, Channel channel)
            throws IOException {

        log.info("Received batch of {} messages", messages.size());

        List<Long> toAck = new ArrayList<>();
        List<Long> toReject = new ArrayList<>();

        for (Message message : messages) {
            long deliveryTag = message.getMessageProperties().getDeliveryTag();

            try {
                OrderEvent event = deserialize(message);
                orderRepository.save(Order.from(event));
                toAck.add(deliveryTag);

            } catch (Exception e) {
                log.error("Failed to process message: {}", e.getMessage());
                toReject.add(deliveryTag);
            }
        }

        // Acknowledge successful
        if (!toAck.isEmpty()) {
            // Ack up to the highest tag (multiple = true)
            long maxTag = Collections.max(toAck);
            channel.basicAck(maxTag, true);
        }

        // Reject failed
        for (Long tag : toReject) {
            channel.basicReject(tag, false);
        }
    }
}

@Configuration
public class BatchListenerConfig {

    @Bean
    public SimpleRabbitListenerContainerFactory
            batchListenerContainerFactory(ConnectionFactory connectionFactory) {

        SimpleRabbitListenerContainerFactory factory =
            new SimpleRabbitListenerContainerFactory();

        factory.setConnectionFactory(connectionFactory);
        factory.setBatchListener(true);
        factory.setBatchSize(100);
        factory.setConsumerBatchEnabled(true);
        factory.setReceiveTimeout(5000L);  // Wait up to 5s to fill batch
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);

        return factory;
    }
}
```

### Competing Consumers

```java
@Service
public class CompetingConsumer {

    // Multiple instances of this service will compete for messages
    @RabbitListener(
        queues = "work.queue",
        concurrency = "3-10"  // Dynamic scaling
    )
    public void handleWork(WorkItem work, Channel channel,
                           @Header(AmqpHeaders.DELIVERY_TAG) long tag)
            throws IOException {

        try {
            log.info("Processing work item: {}", work.getId());

            // Simulate work
            processWork(work);

            channel.basicAck(tag, false);

        } catch (Exception e) {
            log.error("Work failed: {}", e.getMessage());
            channel.basicNack(tag, false, true);  // Requeue
        }
    }

    private void processWork(WorkItem work) {
        // Processing logic
    }
}
```

---

## Request-Reply Pattern (RPC)

### RPC Client

```java
@Service
public class RabbitRpcClient {

    private final RabbitTemplate rabbitTemplate;

    // Synchronous RPC
    public OrderValidationResponse validateOrder(OrderValidationRequest request) {
        Object response = rabbitTemplate.convertSendAndReceive(
            "rpc.exchange",
            "order.validate",
            request,
            message -> {
                message.getMessageProperties()
                    .setReplyTo("order.validation.reply");
                message.getMessageProperties()
                    .setCorrelationId(UUID.randomUUID().toString());
                message.getMessageProperties()
                    .setExpiration("30000");  // 30 second timeout
                return message;
            }
        );

        if (response == null) {
            throw new RpcTimeoutException("No response received");
        }

        return (OrderValidationResponse) response;
    }

    // Async RPC with callback
    public void validateOrderAsync(OrderValidationRequest request,
                                    Consumer<OrderValidationResponse> callback) {
        String correlationId = UUID.randomUUID().toString();

        // Store callback for later
        pendingCallbacks.put(correlationId, callback);

        rabbitTemplate.convertAndSend(
            "rpc.exchange",
            "order.validate",
            request,
            message -> {
                message.getMessageProperties()
                    .setReplyTo("order.validation.reply");
                message.getMessageProperties()
                    .setCorrelationId(correlationId);
                return message;
            }
        );
    }

    @RabbitListener(queues = "order.validation.reply")
    public void handleReply(
            @Payload OrderValidationResponse response,
            @Header(AmqpHeaders.CORRELATION_ID) String correlationId) {

        Consumer<OrderValidationResponse> callback =
            pendingCallbacks.remove(correlationId);

        if (callback != null) {
            callback.accept(response);
        }
    }
}
```

### RPC Server

```java
@Service
public class RabbitRpcServer {

    private final OrderValidationService validationService;

    @RabbitListener(queues = "order.validate.queue")
    public OrderValidationResponse handleValidation(
            @Payload OrderValidationRequest request,
            @Header(AmqpHeaders.CORRELATION_ID) String correlationId) {

        log.info("Validating order: {}, correlationId: {}",
            request.getOrderId(), correlationId);

        try {
            boolean valid = validationService.validate(request);

            return OrderValidationResponse.builder()
                .orderId(request.getOrderId())
                .valid(valid)
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

## Monitoring và Metrics

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

## Common Issues và Solutions

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
