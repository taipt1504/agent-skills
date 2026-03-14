# Database, Messaging & Observability Reference

DB query optimization, transaction management, Kafka producer/consumer patterns, structured logging with MDC, Micrometer metrics, health indicators.

## Table of Contents
- [Database Query Optimization](#database-query-optimization)
- [Transaction Management](#transaction-management)
- [Kafka Producer Patterns](#kafka-producer-patterns)
- [Kafka Consumer Patterns](#kafka-consumer-patterns)
- [Structured Logging with MDC](#structured-logging-with-mdc)
- [Micrometer Metrics](#micrometer-metrics)
- [Health Indicators](#health-indicators)

---

## Database Query Optimization

### N+1 Fix — Batch Fetch and Correlate

```java
// ❌ N+1: fires a query per market
marketRepository.findAll()
    .flatMap(market -> orderRepository.findByMarketId(market.id())
        .collectList()
        .map(orders -> new MarketWithOrders(market, orders)));

// ✅ Two queries then join in memory
Mono<List<Market>> markets = marketRepository.findAll().collectList();
Mono<Map<String, List<Order>>> ordersByMarket = markets
    .flatMapMany(ms -> orderRepository.findByMarketIdIn(
        ms.stream().map(Market::id).toList()))
    .collectMultimap(Order::marketId);

Mono.zip(markets, ordersByMarket, (ms, om) ->
    ms.stream()
        .map(m -> new MarketWithOrders(m, om.getOrDefault(m.id(), List.of())))
        .toList());
```

### Projection Queries (Select Only What You Need)

```java
// Projection interface
public interface OrderSummaryProjection {
    String getId();
    String getStatus();
    BigDecimal getTotalAmount();
    Instant getCreatedAt();
}

// R2DBC — select specific columns
@Query("""
    SELECT id, status, total_amount, created_at
    FROM orders
    WHERE customer_id = :customerId
    ORDER BY created_at DESC
    LIMIT :limit
    """)
Flux<OrderSummaryProjection> findSummariesByCustomer(String customerId, int limit);
```

### Dynamic Query Builder

```java
public Flux<Order> search(OrderSearchCriteria criteria) {
    var sql = new StringBuilder("SELECT * FROM orders WHERE deleted_at IS NULL");
    var params = new LinkedHashMap<String, Object>();

    if (criteria.status() != null) {
        sql.append(" AND status = :status");
        params.put("status", criteria.status().name());
    }
    if (criteria.fromDate() != null) {
        sql.append(" AND created_at >= :fromDate");
        params.put("fromDate", criteria.fromDate());
    }
    if (criteria.customerId() != null) {
        sql.append(" AND customer_id = :customerId");
        params.put("customerId", criteria.customerId());
    }

    sql.append(" ORDER BY created_at DESC LIMIT :limit OFFSET :offset");
    params.put("limit", criteria.pageSize());
    params.put("offset", (long) criteria.page() * criteria.pageSize());

    var spec = databaseClient.sql(sql.toString());
    for (var entry : params.entrySet()) {
        spec = spec.bind(entry.getKey(), entry.getValue());
    }
    return spec.map((row, meta) -> mapToOrder(row)).all();
}
```

---

## Transaction Management

```java
// Declarative — most common
@Service @RequiredArgsConstructor
public class OrderService {

    @Transactional
    public Mono<Order> createWithInventory(CreateOrderRequest request) {
        return orderRepository.save(Order.from(request))
            .flatMap(order ->
                inventoryService.reserve(order.items())
                    .thenReturn(order))
            .flatMap(order ->
                paymentRepository.createPending(order.id(), order.totalAmount())
                    .thenReturn(order));
    }
}
```

```java
// Programmatic — for conditional transactions
@Component @RequiredArgsConstructor
public class OrderProcessor {
    private final TransactionalOperator txOperator;

    public Mono<Order> processConditionally(CreateOrderRequest request) {
        var pipeline = orderRepository.save(Order.from(request))
            .flatMap(order -> inventoryService.reserve(order.items()).thenReturn(order));

        // Only use transaction if inventory reservation is needed
        if (request.requiresInventory()) {
            return txOperator.transactional(pipeline);
        }
        return pipeline;
    }
}
```

```java
// Savepoint / nested (R2DBC with PostgreSQL)
@Transactional
public Mono<Order> createWithFallback(CreateOrderRequest request) {
    return orderRepository.save(Order.from(request))
        .flatMap(order ->
            preferredShippingService.allocate(order)
                .onErrorResume(ShippingUnavailableException.class, ex ->
                    // Fallback to standard shipping — savepoint implicit
                    standardShippingService.allocate(order))
                .thenReturn(order));
}
```

---

## Kafka Producer Patterns

### Standard Async Producer

```java
@Service @RequiredArgsConstructor @Slf4j
public class OrderEventProducer {
    private final KafkaTemplate<String, Object> kafkaTemplate;

    public Mono<Void> publish(String topic, String key, Object event) {
        return Mono.fromFuture(kafkaTemplate.send(topic, key, event))
            .doOnSuccess(result -> log.debug("Published to {}/{}: offset={}",
                result.getRecordMetadata().topic(),
                result.getRecordMetadata().partition(),
                result.getRecordMetadata().offset()))
            .onErrorMap(ex -> new MessagingException("Failed to publish event", ex))
            .then();
    }

    // With custom headers
    public Mono<Void> publishWithHeaders(String topic, String key, Object event,
                                          Map<String, String> headers) {
        return Mono.fromFuture(() -> {
            var record = new ProducerRecord<String, Object>(topic, key, event);
            headers.forEach((k, v) ->
                record.headers().add(k, v.getBytes(StandardCharsets.UTF_8)));
            return kafkaTemplate.send(record);
        }).then();
    }
}
```

### Transactional Producer (Exactly-Once)

```java
@Configuration
public class KafkaTransactionalConfig {

    @Bean
    public ProducerFactory<String, Object> transactionalProducerFactory(
            KafkaProperties props) {
        var factory = new DefaultKafkaProducerFactory<String, Object>(
            props.buildProducerProperties(null));
        factory.setTransactionIdPrefix("order-service-tx-");
        return factory;
    }

    @Bean
    public KafkaTemplate<String, Object> transactionalKafkaTemplate(
            ProducerFactory<String, Object> factory) {
        return new KafkaTemplate<>(factory);
    }
}

// Usage
@Transactional("kafkaTransactionManager")
public Mono<Void> publishTransactional(List<OrderEvent> events) {
    return Flux.fromIterable(events)
        .concatMap(e -> Mono.fromFuture(kafkaTemplate.send("orders", e.orderId(), e)))
        .then();
}
```

---

## Kafka Consumer Patterns

### Manual ACK Consumer

```java
@KafkaListener(topics = "orders.created",
               groupId = "payment-service",
               containerFactory = "manualAckContainerFactory")
public void onOrderCreated(
        @Payload OrderCreatedEvent event,
        @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
        @Header(KafkaHeaders.OFFSET) long offset,
        Acknowledgment ack) {

    log.info("Processing order {} from partition {} offset {}", event.orderId(), partition, offset);

    paymentService.initiate(event.orderId(), event.totalAmount())
        .doOnSuccess(r -> ack.acknowledge())  // ✅ ack only on success
        .doOnError(ex -> log.error("Failed to process order {}: {}", event.orderId(), ex.getMessage()))
        .subscribe();
}
```

### Dead Letter Topic (DLT)

```java
@Configuration
public class KafkaConsumerConfig {

    @Bean
    public DefaultErrorHandler errorHandler(KafkaTemplate<String, Object> kafkaTemplate) {
        var recoverer = new DeadLetterPublishingRecoverer(kafkaTemplate,
            (record, ex) -> new TopicPartition(record.topic() + ".DLT", record.partition()));

        var backOff = new ExponentialBackOff(1000L, 2.0);
        backOff.setMaxAttempts(3);

        var handler = new DefaultErrorHandler(recoverer, backOff);
        // Don't retry on business logic errors
        handler.addNotRetryableExceptions(BusinessException.class, ValidationException.class);
        return handler;
    }
}

// DLT consumer — for monitoring and reprocessing
@KafkaListener(topics = "orders.created.DLT", groupId = "dlt-monitor")
public void onOrderDLT(
        @Payload byte[] payload,
        @Header(KafkaHeaders.EXCEPTION_MESSAGE) String exMessage,
        @Header(KafkaHeaders.ORIGINAL_TOPIC) String originalTopic) {
    log.error("DLT message from {}: {}", originalTopic, exMessage);
    // Alert, store for later reprocessing, etc.
}
```

---

## Structured Logging with MDC

```java
// MDC correlation across reactive pipeline
@Component @Slf4j
public class MdcLoggingFilter implements WebFilter {

    @Override
    public Mono<WebFilterChain> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String traceId = exchange.getRequest().getHeaders()
            .getFirst("X-Trace-Id");
        if (traceId == null) traceId = UUID.randomUUID().toString();

        final String finalTraceId = traceId;
        exchange.getResponse().getHeaders().add("X-Trace-Id", finalTraceId);

        return chain.filter(exchange)
            .contextWrite(Context.of("traceId", finalTraceId))
            .doOnEach(signal -> {
                // MDC in reactive must be set per signal (not per thread)
                if (!signal.isOnComplete()) {
                    MDC.put("traceId", finalTraceId);
                    MDC.put("method", exchange.getRequest().getMethodValue());
                    MDC.put("path", exchange.getRequest().getPath().value());
                }
            });
    }
}

// MDC-aware logging helper
public class ReactiveLog {
    public static <T> Function<T, T> trace(String msg) {
        return value -> {
            log.info("[{}] {}: {}", MDC.get("traceId"), msg, value);
            return value;
        };
    }
}
```

```java
// Logback config for structured JSON logs
// logback-spring.xml
// Use logstash-logback-encoder for ELK:
// <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
```

---

## Micrometer Metrics

```java
@Service @RequiredArgsConstructor
public class OrderService {
    private final MeterRegistry registry;

    public Mono<Order> create(CreateOrderRequest request) {
        Timer.Sample sample = Timer.start(registry);

        return orderRepository.save(Order.from(request))
            .doOnSuccess(order -> {
                sample.stop(registry.timer("orders.created",
                    "status", "success",
                    "type", request.orderType().name()));
                registry.counter("orders.total",
                    "type", request.orderType().name()).increment();
                registry.gauge("orders.amount",
                    List.of(Tag.of("currency", order.getCurrency())),
                    order, o -> o.getTotalAmount().doubleValue());
            })
            .doOnError(ex -> {
                sample.stop(registry.timer("orders.created",
                    "status", "error",
                    "error", ex.getClass().getSimpleName()));
                registry.counter("orders.errors",
                    "type", ex.getClass().getSimpleName()).increment();
            });
    }
}

// Custom histogram for payment amounts
@Bean
public DistributionSummary paymentAmountSummary(MeterRegistry registry) {
    return DistributionSummary.builder("payment.amount")
        .description("Distribution of payment amounts in cents")
        .baseUnit("cents")
        .publishPercentiles(0.5, 0.95, 0.99)
        .register(registry);
}
```

---

## Health Indicators

```java
// Custom health indicator for external service
@Component @RequiredArgsConstructor
public class PaymentServiceHealthIndicator implements ReactiveHealthIndicator {
    private final WebClient paymentClient;

    @Override
    public Mono<Health> health() {
        return paymentClient.get().uri("/health")
            .retrieve()
            .toBodilessEntity()
            .map(r -> Health.up()
                .withDetail("status", r.getStatusCode().value())
                .build())
            .timeout(Duration.ofSeconds(3))
            .onErrorResume(ex -> Mono.just(
                Health.down()
                    .withDetail("error", ex.getMessage())
                    .build()));
    }
}

// Database health with query
@Component @RequiredArgsConstructor
public class DatabaseHealthIndicator implements ReactiveHealthIndicator {
    private final DatabaseClient databaseClient;

    @Override
    public Mono<Health> health() {
        return databaseClient.sql("SELECT 1").fetch().rowsUpdated()
            .map(count -> Health.up().withDetail("database", "responsive").build())
            .timeout(Duration.ofSeconds(5))
            .onErrorResume(ex -> Mono.just(Health.down(ex).build()));
    }
}
```

```yaml
# Expose health details for internal monitoring
management:
  endpoints:
    web:
      exposure:
        include: health, info, metrics, prometheus
  endpoint:
    health:
      show-details: when-authorized
      show-components: when-authorized
  health:
    livenessstate:
      enabled: true
    readinessstate:
      enabled: true
```
