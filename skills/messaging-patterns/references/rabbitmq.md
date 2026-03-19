# RabbitMQ Patterns Reference

Comprehensive RabbitMQ exchange topology, producer/consumer patterns, error handling, reactive, and production configuration.

## Table of Contents
- [Dependencies](#dependencies)
- [Exchange Topology](#exchange-topology)
- [Producer Patterns](#producer-patterns)
- [Consumer Patterns](#consumer-patterns)
- [Error Handling (Retry + DLQ)](#error-handling-retry--dlq)
- [Reactor RabbitMQ](#reactor-rabbitmq)
- [Production Configuration](#production-configuration)
- [Anti-Patterns](#anti-patterns)

---

## Dependencies

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-amqp</artifactId>
</dependency>
<!-- Reactive AMQP for WebFlux -->
<dependency>
    <groupId>io.projectreactor.rabbitmq</groupId>
    <artifactId>reactor-rabbitmq</artifactId>
</dependency>
```

---

## Exchange Topology

### Exchange Types

| Exchange | Routing | Use Case |
|----------|---------|----------|
| `Direct` | Exact key match | Point-to-point |
| `Topic` | Wildcard (`*`, `#`) | Event routing with patterns |
| `Fanout` | All bound queues | Broadcast / pub-sub |
| `Headers` | Message header matching | Complex routing without routing key |

### Full Topology with DLX

```java
@Configuration
public class RabbitMQTopologyConfig {

    public static final String ORDERS_EXCHANGE     = "orders.exchange";
    public static final String ORDERS_DLX          = "orders.dlx";
    public static final String NOTIFICATIONS_FANOUT = "notifications.fanout";
    public static final String ORDERS_CREATED_QUEUE = "orders.created";
    public static final String ORDERS_CREATED_DLQ   = "orders.created.dlq";
    public static final String ORDER_CREATED_KEY    = "order.created";

    @Bean public TopicExchange ordersExchange() {
        return ExchangeBuilder.topicExchange(ORDERS_EXCHANGE).durable(true).build();
    }
    @Bean public DirectExchange ordersDlx() {
        return ExchangeBuilder.directExchange(ORDERS_DLX).durable(true).build();
    }

    @Bean
    public Queue ordersCreatedQueue() {
        return QueueBuilder.durable(ORDERS_CREATED_QUEUE)
            .withArgument("x-dead-letter-exchange", ORDERS_DLX)
            .withArgument("x-dead-letter-routing-key", ORDERS_CREATED_QUEUE + ".dead")
            .withArgument("x-message-ttl", 30_000)     // 30s TTL per message
            .withArgument("x-max-length", 100_000)     // Prevent memory exhaustion
            .build();
    }

    @Bean public Queue ordersCreatedDlq() {
        return QueueBuilder.durable(ORDERS_CREATED_DLQ).build();
    }

    @Bean public Binding ordersCreatedBinding() {
        return BindingBuilder.bind(ordersCreatedQueue()).to(ordersExchange()).with(ORDER_CREATED_KEY);
    }
    @Bean public Binding ordersDlqBinding() {
        return BindingBuilder.bind(ordersCreatedDlq()).to(ordersDlx())
            .with(ORDERS_CREATED_QUEUE + ".dead");
    }

    // Broadcast to all consumers
    @Bean public FanoutExchange notificationsFanout() {
        return ExchangeBuilder.fanoutExchange(NOTIFICATIONS_FANOUT).durable(true).build();
    }
}
```

---

## Producer Patterns

### RabbitTemplate with Publisher Confirms and Mandatory Returns

```java
@Configuration
public class RabbitTemplateConfig {
    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory cf, MessageConverter converter) {
        var template = new RabbitTemplate(cf);
        template.setMessageConverter(converter);

        // Publisher confirms -- callback when broker acks receipt
        template.setConfirmCallback((correlationData, ack, cause) -> {
            if (!ack) log.error("Message not confirmed: {} cause={}", correlationData.getId(), cause);
        });

        // Mandatory returns -- callback when no queue matches routing key
        template.setReturnsCallback(returned ->
            log.error("Message returned: exchange={} routingKey={}",
                returned.getExchange(), returned.getRoutingKey()));
        template.setMandatory(true);
        return template;
    }

    @Bean
    public MessageConverter messageConverter(ObjectMapper objectMapper) {
        return new Jackson2JsonMessageConverter(objectMapper);
    }
}
```

### Publishing with Correlation and Persistent Delivery

```java
@Service @RequiredArgsConstructor @Slf4j
public class OrderEventPublisher {
    private final RabbitTemplate rabbitTemplate;

    public void publish(OrderCreatedEvent event) {
        rabbitTemplate.convertAndSend(
            ORDERS_EXCHANGE, ORDER_CREATED_KEY, event,
            message -> {
                var props = message.getMessageProperties();
                props.setCorrelationId(event.orderId());
                props.setDeliveryMode(MessageDeliveryMode.PERSISTENT);  // Survive restart
                props.setHeader("X-Event-Type", event.getClass().getSimpleName());
                return message;
            },
            new CorrelationData(event.orderId())
        );
    }
}
```

### Transactional Multi-Message Publish

```java
@Transactional
public void publishTransactional(Order order) {
    rabbitTemplate.invoke(ops -> {
        ops.convertAndSend(ORDERS_EXCHANGE, ORDER_CREATED_KEY, new OrderCreatedEvent(order));
        ops.convertAndSend(NOTIFICATIONS_FANOUT, "", new OrderNotificationEvent(order));
        return null;
    });
}
```

---

## Consumer Patterns

### Manual ACK Consumer Factory

```java
@Configuration
public class RabbitConsumerConfig {
    @Bean
    public SimpleRabbitListenerContainerFactory rabbitListenerContainerFactory(
            ConnectionFactory cf, MessageConverter converter) {
        var factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(cf);
        factory.setMessageConverter(converter);
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
        factory.setConcurrentConsumers(3);
        factory.setMaxConcurrentConsumers(10);
        factory.setPrefetchCount(10);              // Max unacked messages per consumer
        factory.setDefaultRequeueRejected(false);  // Don't requeue -- route to DLQ
        return factory;
    }
}
```

### Manual ACK Consumer with Error Routing

```java
@Component @RequiredArgsConstructor @Slf4j
public class OrderEventConsumer {

    @RabbitListener(queues = ORDERS_CREATED_QUEUE)
    public void handleOrderCreated(
            @Payload OrderCreatedEvent event,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
            Channel channel) throws IOException {
        try {
            orderService.processOrderCreated(event);
            channel.basicAck(deliveryTag, false);               // Ack on success

        } catch (RetryableException e) {
            log.warn("Retryable error for {}, requeueing", event.orderId(), e);
            channel.basicNack(deliveryTag, false, true);        // Requeue -- transient error

        } catch (Exception e) {
            log.error("Fatal error for {}, routing to DLQ", event.orderId(), e);
            channel.basicNack(deliveryTag, false, false);       // No requeue -> DLQ
        }
    }
}
```

### Batch Consumer

```java
@RabbitListener(queues = "analytics.events", containerFactory = "batchListenerContainerFactory")
public void handleBatch(List<Message> messages, Channel channel) throws IOException {
    try {
        analyticsService.processBatch(messages.stream().map(this::toEvent).toList());
        channel.basicAck(messages.getLast().getMessageProperties().getDeliveryTag(), true);
    } catch (Exception e) {
        channel.basicNack(messages.getLast().getMessageProperties().getDeliveryTag(), true, false);
    }
}
```

### Prefetch Tuning

| Prefetch | Use Case |
|----------|----------|
| 1 | Fair dispatch, slow consumers |
| 10-25 | General purpose (good default) |
| 50-100 | High-throughput, fast processing |
| 250+ | Batch consumers only |

---

## Error Handling (Retry + DLQ)

### Retry with Exponential Backoff then DLQ

```java
@Configuration
public class RabbitRetryConfig {
    @Bean
    public SimpleRabbitListenerContainerFactory retryListenerFactory(ConnectionFactory cf) {
        var factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(cf);
        factory.setAcknowledgeMode(AcknowledgeMode.AUTO);
        factory.setAdviceChain(
            RetryInterceptorBuilder.stateful()
                .maxAttempts(3)
                .backOffOptions(1000, 2.0, 10000)       // 1s, 2s, 4s... max 10s
                .recoverer(new RejectAndDontRequeueRecoverer())  // DLQ after exhaustion
                .build());
        return factory;
    }
}
```

### DLQ Consumer with x-death Inspection

```java
@RabbitListener(queues = ORDERS_CREATED_DLQ)
public void handleDeadLetter(
        @Payload byte[] rawPayload,
        @Header(value = "x-death", required = false) List<Map<String, ?>> xDeath,
        @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
        Channel channel) throws IOException {

    String reason = xDeath != null && !xDeath.isEmpty()
        ? (String) xDeath.getFirst().get("reason") : "unknown";
    log.error("DLQ message: reason={}", reason);
    dlqRepository.save(DlqRecord.of(rawPayload, reason));
    channel.basicAck(deliveryTag, false);   // Always ack DLQ -- prevent infinite loop
}
```

---

## Reactor RabbitMQ

Use `reactor-rabbitmq` instead of `RabbitTemplate` in WebFlux applications to avoid blocking.

### Reactive Sender and Receiver Config

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

### Reactive Publisher with Confirms

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

### Reactive Consumer with Manual Ack

```java
@Service @RequiredArgsConstructor
public class ReactiveOrderConsumer {
    private final Receiver receiver;

    @PostConstruct
    public void startConsuming() {
        receiver.consumeManualAck(ORDERS_CREATED_QUEUE)
            .flatMap(delivery -> processDelivery(delivery)
                .doOnSuccess(v -> delivery.ack())
                .doOnError(e -> delivery.nack(false)))  // nack without requeue -> DLQ
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

## Production Configuration

```yaml
spring:
  rabbitmq:
    host: ${RABBITMQ_HOST:localhost}
    port: ${RABBITMQ_PORT:5672}
    username: ${RABBITMQ_USERNAME}
    password: ${RABBITMQ_PASSWORD}
    virtual-host: ${RABBITMQ_VHOST:/}
    connection-timeout: 10s
    publisher-confirm-type: correlated    # Publisher confirms
    publisher-returns: true
    cache:
      channel:
        size: 25
        checkout-timeout: 5s
    listener:
      simple:
        acknowledge-mode: manual
        prefetch: 10
        concurrency: 3
        max-concurrency: 10
        retry:
          enabled: true
          max-attempts: 3
          initial-interval: 1s
          multiplier: 2.0
          max-interval: 10s
```

---

## Anti-Patterns

| Anti-Pattern | Fix |
|-------------|-----|
| Auto-ack without error handling | Always use MANUAL ack |
| No dead-letter queue | Configure DLX/DLQ for every queue |
| Requeue on permanent failures | `basicNack(tag, false, false)` -> DLQ |
| Unbounded queue | Set `x-max-length` on all queues |
| Direct exchange for all routing | Use Topic for flexible routing patterns |
| No publisher confirms | Configure `publisher-confirm-type: correlated` for critical messages |
| Blocking ops in WebFlux consumer | Use reactor-rabbitmq (see [Reactor RabbitMQ](#reactor-rabbitmq)) |
| No correlation ID on messages | Set `correlationId` for tracing across services |
| Infinite requeue loops | Use `defaultRequeueRejected=false` + DLQ |
| Missing x-message-ttl | Messages pile up forever if consumer dies |
