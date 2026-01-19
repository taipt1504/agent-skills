# NATS Patterns Reference

## Overview

NATS là lightweight, high-performance messaging system được thiết kế cho cloud-native applications. NATS cung cấp:

- **Core NATS**: Simple pub/sub với at-most-once delivery
- **JetStream**: Persistent messaging với at-least-once/exactly-once delivery

Document này covers NATS patterns cho Java applications.

---

## Architecture Fundamentals

### NATS vs JetStream

```
Core NATS                           JetStream
┌─────────────────────────┐         ┌─────────────────────────┐
│     In-Memory Only      │         │   Persistent Storage    │
│     Fire and Forget     │         │   Acknowledgments       │
│     At-Most-Once        │         │   At-Least-Once         │
│     No Replay           │         │   Message Replay        │
│     Queue Groups        │         │   Durable Consumers     │
│     Request-Reply       │         │   Exactly-Once          │
└─────────────────────────┘         └─────────────────────────┘

When to use Core NATS:            When to use JetStream:
- Real-time notifications         - Order processing
- Metrics/Telemetry               - Event sourcing
- Service discovery               - Audit logs
- Ephemeral data                  - Durable workflows
```

### Subject-Based Addressing

```
Subject Hierarchy Example:
orders
orders.created
orders.created.us
orders.created.eu
orders.updated
orders.cancelled

Wildcards:
* - matches single token
    orders.* matches orders.created, orders.updated
    orders.*.us matches orders.created.us, orders.updated.us

> - matches multiple tokens
    orders.> matches orders.created, orders.created.us, orders.updated.eu
```

---

## Java Client Setup

### Connection Configuration

```java
@Configuration
public class NatsConfig {

    @Value("${nats.servers}")
    private String servers;

    @Value("${nats.connection.name:default}")
    private String connectionName;

    @Bean
    public Connection natsConnection() throws IOException, InterruptedException {
        Options options = new Options.Builder()
            // Server connections
            .servers(servers.split(","))
            .connectionName(connectionName)

            // Reconnection settings
            .maxReconnects(-1)  // Unlimited reconnects
            .reconnectWait(Duration.ofSeconds(2))
            .reconnectBufferSize(8 * 1024 * 1024)  // 8MB

            // Timeouts
            .connectionTimeout(Duration.ofSeconds(5))
            .pingInterval(Duration.ofSeconds(30))
            .requestCleanupInterval(Duration.ofSeconds(5))

            // Authentication (if needed)
            // .authHandler(new AuthHandler() { ... })
            // .token("secret-token")
            // .userInfo("user", "password")

            // TLS (if needed)
            // .sslContext(sslContext)

            // Event handlers
            .connectionListener((conn, type) -> {
                log.info("NATS connection event: {} - {}", type, conn.getServerInfo());
            })
            .errorListener(new ErrorListener() {
                @Override
                public void errorOccurred(Connection conn, String error) {
                    log.error("NATS error: {}", error);
                }

                @Override
                public void exceptionOccurred(Connection conn, Exception exp) {
                    log.error("NATS exception: {}", exp.getMessage(), exp);
                }

                @Override
                public void slowConsumerDetected(Connection conn, Consumer consumer) {
                    log.warn("Slow consumer detected: {}", consumer);
                }
            })

            .build();

        Connection connection = Nats.connect(options);
        log.info("Connected to NATS: {}", connection.getServerInfo());

        return connection;
    }

    @Bean
    public JetStream jetStream(Connection connection) throws IOException {
        JetStreamOptions options = JetStreamOptions.builder()
            .requestTimeout(Duration.ofSeconds(10))
            .build();

        return connection.jetStream(options);
    }

    @Bean
    public JetStreamManagement jetStreamManagement(Connection connection)
            throws IOException {
        return connection.jetStreamManagement();
    }

    @PreDestroy
    public void closeConnection() throws InterruptedException {
        if (natsConnection != null) {
            natsConnection.close();
        }
    }
}
```

### Object Mapper Setup

```java
@Configuration
public class NatsSerializationConfig {

    @Bean
    public ObjectMapper natsObjectMapper() {
        return new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
            .configure(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS, false);
    }
}

@Component
public class NatsMessageSerializer {

    private final ObjectMapper objectMapper;

    public byte[] serialize(Object object) {
        try {
            return objectMapper.writeValueAsBytes(object);
        } catch (JsonProcessingException e) {
            throw new SerializationException("Failed to serialize", e);
        }
    }

    public <T> T deserialize(byte[] data, Class<T> type) {
        try {
            return objectMapper.readValue(data, type);
        } catch (IOException e) {
            throw new DeserializationException("Failed to deserialize", e);
        }
    }
}
```

---

## Core NATS Patterns

### Simple Pub/Sub

```java
@Service
@Slf4j
public class NatsCorePublisher {

    private final Connection connection;
    private final NatsMessageSerializer serializer;

    // Simple publish (fire and forget)
    public void publish(String subject, Object payload) {
        byte[] data = serializer.serialize(payload);
        connection.publish(subject, data);
        log.debug("Published to {}: {} bytes", subject, data.length);
    }

    // Publish with headers
    public void publishWithHeaders(String subject, Object payload,
                                    Map<String, String> headers) {
        byte[] data = serializer.serialize(payload);

        Headers natsHeaders = new Headers();
        headers.forEach(natsHeaders::add);

        connection.publish(subject, natsHeaders, data);
    }

    // Publish with reply subject
    public void publishWithReply(String subject, String replyTo,
                                  Object payload) {
        byte[] data = serializer.serialize(payload);
        connection.publish(subject, replyTo, data);
    }
}
```

### Simple Subscribe

```java
@Service
@Slf4j
public class NatsCoreSubscriber {

    private final Connection connection;
    private final NatsMessageSerializer serializer;
    private final List<Dispatcher> dispatchers = new ArrayList<>();

    // Basic subscription
    public void subscribe(String subject, Consumer<Message> handler) {
        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                handler.accept(message);
            } catch (Exception e) {
                log.error("Error handling message on {}: {}", subject, e.getMessage());
            }
        });

        dispatcher.subscribe(subject);
        dispatchers.add(dispatcher);

        log.info("Subscribed to: {}", subject);
    }

    // Typed subscription
    public <T> void subscribe(String subject, Class<T> type,
                               Consumer<T> handler) {
        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                T payload = serializer.deserialize(message.getData(), type);
                handler.accept(payload);
            } catch (Exception e) {
                log.error("Error handling message on {}: {}", subject, e.getMessage());
            }
        });

        dispatcher.subscribe(subject);
        dispatchers.add(dispatcher);
    }

    // Wildcard subscription
    public void subscribeWildcard(String pattern, Consumer<Message> handler) {
        // pattern can be "orders.*" or "orders.>"
        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                log.debug("Received on {}: {} bytes",
                    message.getSubject(), message.getData().length);
                handler.accept(message);
            } catch (Exception e) {
                log.error("Error handling wildcard message: {}", e.getMessage());
            }
        });

        dispatcher.subscribe(pattern);
        dispatchers.add(dispatcher);

        log.info("Subscribed to pattern: {}", pattern);
    }

    @PreDestroy
    public void cleanup() {
        dispatchers.forEach(Dispatcher::unsubscribe);
    }
}
```

### Queue Groups (Load Balancing)

```java
@Service
@Slf4j
public class NatsQueueGroupSubscriber {

    private final Connection connection;
    private final NatsMessageSerializer serializer;

    // Queue group subscription - messages distributed among subscribers
    public <T> void subscribeQueue(String subject, String queueGroup,
                                    Class<T> type, Consumer<T> handler) {

        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                T payload = serializer.deserialize(message.getData(), type);
                handler.accept(payload);
            } catch (Exception e) {
                log.error("Error in queue handler: {}", e.getMessage());
            }
        });

        // Subscribe with queue group
        dispatcher.subscribe(subject, queueGroup);

        log.info("Subscribed to {} as queue group member: {}", subject, queueGroup);
    }
}

// Usage example
@Component
public class OrderProcessor {

    private final NatsQueueGroupSubscriber subscriber;

    @PostConstruct
    public void setup() {
        // All instances of this service share the work
        subscriber.subscribeQueue(
            "orders.process",
            "order-processors",
            OrderEvent.class,
            this::processOrder
        );
    }

    private void processOrder(OrderEvent event) {
        log.info("Processing order: {}", event.getOrderId());
        // Process...
    }
}
```

### Request-Reply

```java
@Service
@Slf4j
public class NatsRequestReplyService {

    private final Connection connection;
    private final NatsMessageSerializer serializer;

    // Synchronous request-reply
    public <REQ, RES> RES request(String subject, REQ request,
                                   Class<RES> responseType,
                                   Duration timeout) {
        try {
            byte[] data = serializer.serialize(request);
            Message response = connection.request(subject, data, timeout);

            if (response == null) {
                throw new TimeoutException("No response received within " + timeout);
            }

            return serializer.deserialize(response.getData(), responseType);

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new NatsRequestException("Request interrupted", e);
        }
    }

    // Async request-reply
    public <REQ, RES> CompletableFuture<RES> requestAsync(
            String subject, REQ request, Class<RES> responseType) {

        byte[] data = serializer.serialize(request);

        return connection.request(subject, data)
            .thenApply(response -> {
                if (response == null) {
                    throw new CompletionException(
                        new TimeoutException("No response received"));
                }
                return serializer.deserialize(response.getData(), responseType);
            });
    }

    // Request with multiple responses (scatter-gather)
    public <REQ, RES> List<RES> requestMany(String subject, REQ request,
                                             Class<RES> responseType,
                                             int expectedResponses,
                                             Duration timeout) throws Exception {
        byte[] data = serializer.serialize(request);
        List<RES> responses = new ArrayList<>();
        CountDownLatch latch = new CountDownLatch(expectedResponses);

        // Create unique reply subject
        String replySubject = connection.createInbox();

        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                RES response = serializer.deserialize(
                    message.getData(), responseType);
                responses.add(response);
                latch.countDown();
            } catch (Exception e) {
                log.error("Error deserializing response", e);
            }
        });

        dispatcher.subscribe(replySubject);

        try {
            connection.publish(subject, replySubject, data);
            latch.await(timeout.toMillis(), TimeUnit.MILLISECONDS);
        } finally {
            dispatcher.unsubscribe(replySubject);
        }

        return responses;
    }
}

// Request responder
@Service
public class NatsRequestResponder {

    private final Connection connection;
    private final NatsMessageSerializer serializer;

    public <REQ, RES> void respondTo(String subject, Class<REQ> requestType,
                                      Function<REQ, RES> handler) {

        Dispatcher dispatcher = connection.createDispatcher(message -> {
            try {
                REQ request = serializer.deserialize(message.getData(), requestType);
                RES response = handler.apply(request);

                byte[] responseData = serializer.serialize(response);
                connection.publish(message.getReplyTo(), responseData);

            } catch (Exception e) {
                log.error("Error handling request on {}: {}", subject, e.getMessage());
                // Send error response
                ErrorResponse error = new ErrorResponse(e.getMessage());
                connection.publish(message.getReplyTo(),
                    serializer.serialize(error));
            }
        });

        dispatcher.subscribe(subject);
        log.info("Responding to requests on: {}", subject);
    }
}
```

---

## JetStream Patterns

### Stream Configuration

```java
@Service
@Slf4j
public class JetStreamSetup {

    private final JetStreamManagement jsm;

    @PostConstruct
    public void setupStreams() throws Exception {
        createOrdersStream();
        createEventsStream();
    }

    private void createOrdersStream() throws Exception {
        StreamConfiguration config = StreamConfiguration.builder()
            .name("ORDERS")
            .subjects("orders.*", "orders.>")
            .retentionPolicy(RetentionPolicy.Limits)
            .maxBytes(1024 * 1024 * 1024)  // 1GB
            .maxAge(Duration.ofDays(7))
            .maxMsgSize(1024 * 1024)  // 1MB per message
            .maxMsgsPerSubject(100000)
            .replicas(3)
            .storageType(StorageType.File)
            .duplicateWindow(Duration.ofMinutes(2))  // Dedup window
            .discardPolicy(DiscardPolicy.Old)
            .build();

        try {
            jsm.addStream(config);
            log.info("Stream ORDERS created");
        } catch (JetStreamApiException e) {
            if (e.getApiErrorCode() == 10058) {  // Stream exists
                jsm.updateStream(config);
                log.info("Stream ORDERS updated");
            } else {
                throw e;
            }
        }
    }

    private void createEventsStream() throws Exception {
        // Work queue stream - messages removed after ack
        StreamConfiguration config = StreamConfiguration.builder()
            .name("EVENTS")
            .subjects("events.*")
            .retentionPolicy(RetentionPolicy.WorkQueue)
            .maxBytes(512 * 1024 * 1024)  // 512MB
            .maxAge(Duration.ofDays(1))
            .replicas(3)
            .storageType(StorageType.File)
            .build();

        try {
            jsm.addStream(config);
            log.info("Stream EVENTS created");
        } catch (JetStreamApiException e) {
            if (e.getApiErrorCode() != 10058) {
                throw e;
            }
        }
    }

    // Get stream info
    public StreamInfo getStreamInfo(String streamName) throws Exception {
        return jsm.getStreamInfo(streamName);
    }

    // Purge stream
    public void purgeStream(String streamName) throws Exception {
        jsm.purgeStream(streamName);
        log.warn("Stream {} purged", streamName);
    }

    // Purge by subject
    public void purgeBySubject(String streamName, String subject) throws Exception {
        PurgeOptions options = PurgeOptions.builder()
            .subject(subject)
            .build();
        jsm.purgeStream(streamName, options);
    }
}
```

### JetStream Publisher

```java
@Service
@Slf4j
public class JetStreamPublisher {

    private final JetStream jetStream;
    private final NatsMessageSerializer serializer;
    private final MeterRegistry meterRegistry;

    // Synchronous publish with ack
    public void publish(String subject, Object payload) {
        try {
            byte[] data = serializer.serialize(payload);

            PublishOptions options = PublishOptions.builder()
                .messageId(UUID.randomUUID().toString())  // Deduplication
                .build();

            PublishAck ack = jetStream.publish(subject, data, options);

            log.debug("Published to stream {} seq {} duplicate {}",
                ack.getStream(), ack.getSeqno(), ack.isDuplicate());

            meterRegistry.counter("nats.jetstream.publish.success",
                "subject", subject).increment();

        } catch (Exception e) {
            meterRegistry.counter("nats.jetstream.publish.error",
                "subject", subject).increment();
            throw new PublishException("Failed to publish to " + subject, e);
        }
    }

    // Publish with custom message ID (for deduplication)
    public void publishWithId(String subject, String messageId, Object payload) {
        try {
            byte[] data = serializer.serialize(payload);

            PublishOptions options = PublishOptions.builder()
                .messageId(messageId)
                .build();

            PublishAck ack = jetStream.publish(subject, data, options);

            if (ack.isDuplicate()) {
                log.warn("Duplicate message detected: {}", messageId);
            }

        } catch (Exception e) {
            throw new PublishException("Failed to publish", e);
        }
    }

    // Publish with expected stream
    public void publishToStream(String stream, String subject, Object payload) {
        try {
            byte[] data = serializer.serialize(payload);

            PublishOptions options = PublishOptions.builder()
                .messageId(UUID.randomUUID().toString())
                .expectedStream(stream)
                .build();

            jetStream.publish(subject, data, options);

        } catch (Exception e) {
            throw new PublishException("Failed to publish to stream " + stream, e);
        }
    }

    // Async publish
    public CompletableFuture<PublishAck> publishAsync(String subject,
                                                       Object payload) {
        try {
            byte[] data = serializer.serialize(payload);

            PublishOptions options = PublishOptions.builder()
                .messageId(UUID.randomUUID().toString())
                .build();

            return jetStream.publishAsync(subject, data, options);

        } catch (Exception e) {
            return CompletableFuture.failedFuture(e);
        }
    }

    // Batch async publish
    public CompletableFuture<List<PublishAck>> publishBatch(
            String subject, List<Object> payloads) {

        List<CompletableFuture<PublishAck>> futures = payloads.stream()
            .map(payload -> publishAsync(subject, payload))
            .toList();

        return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
            .thenApply(v -> futures.stream()
                .map(CompletableFuture::join)
                .toList());
    }

    // Publish with headers
    public void publishWithHeaders(String subject, Object payload,
                                    Map<String, String> headerMap) {
        try {
            byte[] data = serializer.serialize(payload);

            Headers headers = new Headers();
            headerMap.forEach(headers::add);

            NatsMessage message = NatsMessage.builder()
                .subject(subject)
                .headers(headers)
                .data(data)
                .build();

            jetStream.publish(message);

        } catch (Exception e) {
            throw new PublishException("Failed to publish with headers", e);
        }
    }
}
```

### Push-Based Consumer

```java
@Service
@Slf4j
public class JetStreamPushConsumer {

    private final JetStream jetStream;
    private final Connection connection;
    private final NatsMessageSerializer serializer;
    private JetStreamSubscription subscription;

    @PostConstruct
    public void start() throws Exception {
        ConsumerConfiguration consumerConfig = ConsumerConfiguration.builder()
            .durable("order-processor")
            .deliverPolicy(DeliverPolicy.All)
            .ackPolicy(AckPolicy.Explicit)
            .ackWait(Duration.ofSeconds(30))
            .maxDeliver(3)
            .maxAckPending(1000)
            .filterSubject("orders.created")
            .build();

        PushSubscribeOptions options = PushSubscribeOptions.builder()
            .stream("ORDERS")
            .configuration(consumerConfig)
            .build();

        Dispatcher dispatcher = connection.createDispatcher();

        subscription = jetStream.subscribe(
            "orders.created",
            dispatcher,
            this::handleMessage,
            false,  // autoAck = false
            options
        );

        log.info("Push consumer started for orders.created");
    }

    private void handleMessage(Message message) {
        String subject = message.getSubject();
        MessageMetaData meta = message.metaData();

        log.info("Received: subject={}, stream={}, seq={}, deliveryCount={}",
            subject, meta.getStream(), meta.streamSequence(),
            meta.deliveredCount());

        try {
            OrderEvent event = serializer.deserialize(
                message.getData(), OrderEvent.class);

            processOrder(event);

            message.ack();
            log.debug("Acknowledged message seq {}", meta.streamSequence());

        } catch (RetryableException e) {
            log.warn("Retryable error, will be redelivered: {}", e.getMessage());
            message.nak();  // Negative ack - redelivery

        } catch (Exception e) {
            log.error("Non-retryable error: {}", e.getMessage());

            if (meta.deliveredCount() >= 3) {
                // Max retries, terminate
                message.term();
                log.error("Max retries exceeded, terminated message");
            } else {
                message.nak();
            }
        }
    }

    private void processOrder(OrderEvent event) {
        // Processing logic
    }

    @PreDestroy
    public void stop() throws InterruptedException {
        if (subscription != null) {
            subscription.drain(Duration.ofSeconds(10));
            subscription.unsubscribe();
        }
    }
}
```

### Pull-Based Consumer

```java
@Service
@Slf4j
public class JetStreamPullConsumer {

    private final JetStream jetStream;
    private final NatsMessageSerializer serializer;
    private volatile boolean running = true;
    private ExecutorService executor;

    @PostConstruct
    public void start() throws Exception {
        ConsumerConfiguration consumerConfig = ConsumerConfiguration.builder()
            .durable("batch-processor")
            .deliverPolicy(DeliverPolicy.All)
            .ackPolicy(AckPolicy.Explicit)
            .ackWait(Duration.ofMinutes(1))
            .maxAckPending(5000)
            .build();

        PullSubscribeOptions options = PullSubscribeOptions.builder()
            .stream("ORDERS")
            .configuration(consumerConfig)
            .build();

        JetStreamSubscription subscription =
            jetStream.subscribe("orders.*", options);

        executor = Executors.newSingleThreadExecutor();
        executor.submit(() -> pollLoop(subscription));
    }

    private void pollLoop(JetStreamSubscription subscription) {
        while (running) {
            try {
                // Fetch batch of messages
                List<Message> messages = subscription.fetch(100,
                    Duration.ofSeconds(1));

                if (messages.isEmpty()) {
                    continue;
                }

                log.info("Fetched {} messages", messages.size());

                for (Message message : messages) {
                    try {
                        processMessage(message);
                        message.ack();
                    } catch (Exception e) {
                        log.error("Error processing: {}", e.getMessage());
                        message.nak();
                    }
                }

            } catch (Exception e) {
                log.error("Error in poll loop: {}", e.getMessage());
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
    }

    private void processMessage(Message message) {
        OrderEvent event = serializer.deserialize(
            message.getData(), OrderEvent.class);
        // Process...
    }

    @PreDestroy
    public void stop() {
        running = false;
        if (executor != null) {
            executor.shutdown();
        }
    }
}

// Advanced pull with iterate
@Service
public class IteratingPullConsumer {

    private final JetStream jetStream;

    public void consumeWithIterator() throws Exception {
        PullSubscribeOptions options = PullSubscribeOptions.builder()
            .stream("ORDERS")
            .durable("iterator-consumer")
            .build();

        JetStreamSubscription subscription =
            jetStream.subscribe("orders.*", options);

        // Use iterator for continuous processing
        Iterator<Message> iterator = subscription.iterate(100,
            Duration.ofSeconds(30));

        while (iterator.hasNext()) {
            Message message = iterator.next();
            try {
                processMessage(message);
                message.ack();
            } catch (Exception e) {
                message.nakWithDelay(Duration.ofSeconds(5));
            }
        }
    }
}
```

### Consumer Groups (Queue Groups in JetStream)

```java
@Service
@Slf4j
public class JetStreamQueueConsumer {

    private final JetStream jetStream;
    private final Connection connection;
    private final NatsMessageSerializer serializer;

    @PostConstruct
    public void start() throws Exception {
        ConsumerConfiguration consumerConfig = ConsumerConfiguration.builder()
            .deliverPolicy(DeliverPolicy.All)
            .ackPolicy(AckPolicy.Explicit)
            .ackWait(Duration.ofSeconds(30))
            .maxDeliver(3)
            .build();

        // Push subscribe with queue group
        PushSubscribeOptions options = PushSubscribeOptions.builder()
            .stream("ORDERS")
            .configuration(consumerConfig)
            .build();

        // All instances with same queue group share messages
        String queueGroup = "order-processors";

        jetStream.subscribe(
            "orders.created",
            queueGroup,  // Queue group name
            connection.createDispatcher(),
            this::handleMessage,
            false,
            options
        );

        log.info("Joined queue group: {}", queueGroup);
    }

    private void handleMessage(Message message) {
        try {
            OrderEvent event = serializer.deserialize(
                message.getData(), OrderEvent.class);
            processOrder(event);
            message.ack();
        } catch (Exception e) {
            log.error("Error: {}", e.getMessage());
            message.nak();
        }
    }
}
```

### Ordered Consumer

```java
@Service
@Slf4j
public class JetStreamOrderedConsumer {

    private final JetStream jetStream;
    private final NatsMessageSerializer serializer;

    public void startOrderedConsumer() throws Exception {
        // Ordered consumer ensures messages are delivered in order
        // even across reconnections

        OrderedConsumerConfiguration config =
            OrderedConsumerConfiguration.builder()
                .filterSubject("orders.created")
                .build();

        OrderedConsumerContext context = jetStream.orderedConsume(
            "ORDERS", config);

        // Process messages in order
        while (true) {
            Message message = context.next(Duration.ofSeconds(1));
            if (message != null) {
                processInOrder(message);
                // No manual ack needed - ordered consumer handles it
            }
        }
    }

    private void processInOrder(Message message) {
        OrderEvent event = serializer.deserialize(
            message.getData(), OrderEvent.class);
        log.info("Processing in order: seq={}",
            message.metaData().streamSequence());
        // Process...
    }
}
```

---

## Key-Value Store

JetStream provides a key-value store built on streams.

```java
@Service
@Slf4j
public class NatsKeyValueService {

    private final Connection connection;
    private KeyValue bucket;

    @PostConstruct
    public void setup() throws Exception {
        KeyValueManagement kvm = connection.keyValueManagement();

        KeyValueConfiguration config = KeyValueConfiguration.builder()
            .name("order-state")
            .maxBucketSize(100 * 1024 * 1024)  // 100MB
            .maxHistoryPerKey(5)
            .ttl(Duration.ofDays(7))
            .replicas(3)
            .storageType(StorageType.File)
            .build();

        try {
            kvm.create(config);
        } catch (JetStreamApiException e) {
            // Bucket exists
        }

        bucket = connection.keyValue("order-state");
    }

    public void put(String key, Object value) throws Exception {
        byte[] data = serialize(value);
        bucket.put(key, data);
    }

    public <T> T get(String key, Class<T> type) throws Exception {
        KeyValueEntry entry = bucket.get(key);
        if (entry == null) {
            return null;
        }
        return deserialize(entry.getValue(), type);
    }

    public void delete(String key) throws Exception {
        bucket.delete(key);
    }

    // Watch for changes
    public void watch(String keyPattern, Consumer<KeyValueEntry> handler)
            throws Exception {
        KeyValueWatcher watcher = bucket.watch(keyPattern,
            new KeyValueWatcher() {
                @Override
                public void watch(KeyValueEntry entry) {
                    handler.accept(entry);
                }

                @Override
                public void endOfData() {
                    log.info("Initial data loaded");
                }
            },
            KeyValueWatchOption.UPDATES_ONLY
        );
    }

    // Get history
    public List<KeyValueEntry> getHistory(String key) throws Exception {
        List<KeyValueEntry> history = new ArrayList<>();
        bucket.history(key).forEach(history::add);
        return history;
    }
}
```

---

## Object Store

For storing large binary objects.

```java
@Service
@Slf4j
public class NatsObjectStoreService {

    private final Connection connection;
    private ObjectStore store;

    @PostConstruct
    public void setup() throws Exception {
        ObjectStoreManagement osm = connection.objectStoreManagement();

        ObjectStoreConfiguration config = ObjectStoreConfiguration.builder()
            .name("documents")
            .maxBucketSize(1024 * 1024 * 1024)  // 1GB
            .replicas(3)
            .storageType(StorageType.File)
            .build();

        try {
            osm.create(config);
        } catch (JetStreamApiException e) {
            // Store exists
        }

        store = connection.objectStore("documents");
    }

    public ObjectInfo put(String name, InputStream inputStream,
                          ObjectMeta meta) throws Exception {
        return store.put(name, inputStream);
    }

    public ObjectInfo putFile(String name, Path filePath) throws Exception {
        ObjectMeta meta = ObjectMeta.builder(name)
            .description("Uploaded file")
            .build();

        try (InputStream is = Files.newInputStream(filePath)) {
            return store.put(meta, is);
        }
    }

    public InputStream get(String name) throws Exception {
        return store.get(name).getInputStream();
    }

    public void delete(String name) throws Exception {
        store.delete(name);
    }

    public List<ObjectInfo> list() throws Exception {
        List<ObjectInfo> objects = new ArrayList<>();
        store.getList().forEach(objects::add);
        return objects;
    }
}
```

---

## Error Handling Patterns

### Retry with Delay

```java
@Service
@Slf4j
public class ResilientConsumer {

    private final JetStream jetStream;
    private final NatsMessageSerializer serializer;

    private void handleWithRetry(Message message) {
        MessageMetaData meta = message.metaData();
        int deliveryCount = (int) meta.deliveredCount();

        try {
            OrderEvent event = serializer.deserialize(
                message.getData(), OrderEvent.class);
            processOrder(event);
            message.ack();

        } catch (RetryableException e) {
            log.warn("Retry attempt {}: {}", deliveryCount, e.getMessage());

            // Exponential backoff
            Duration delay = calculateBackoff(deliveryCount);

            if (deliveryCount >= 5) {
                // Max retries, send to DLQ
                sendToDeadLetter(message, e);
                message.term();
            } else {
                // Nak with delay
                message.nakWithDelay(delay);
            }

        } catch (Exception e) {
            log.error("Non-retryable error: {}", e.getMessage());
            sendToDeadLetter(message, e);
            message.term();
        }
    }

    private Duration calculateBackoff(int attempt) {
        // 1s, 2s, 4s, 8s, 16s
        long delayMs = (long) (1000 * Math.pow(2, attempt - 1));
        return Duration.ofMillis(Math.min(delayMs, 30000));
    }

    private void sendToDeadLetter(Message message, Exception error) {
        try {
            Headers headers = new Headers();
            headers.add("error", error.getMessage());
            headers.add("original-subject", message.getSubject());
            headers.add("original-stream", message.metaData().getStream());

            NatsMessage dlqMessage = NatsMessage.builder()
                .subject("deadletter.orders")
                .headers(headers)
                .data(message.getData())
                .build();

            jetStream.publish(dlqMessage);

        } catch (Exception e) {
            log.error("Failed to send to DLQ", e);
        }
    }
}
```

### Circuit Breaker Integration

```java
@Service
@Slf4j
public class CircuitBreakerConsumer {

    private final JetStream jetStream;
    private final CircuitBreaker circuitBreaker;

    public CircuitBreakerConsumer(JetStream jetStream,
                                   CircuitBreakerRegistry registry) {
        this.jetStream = jetStream;
        this.circuitBreaker = registry.circuitBreaker("order-processor",
            CircuitBreakerConfig.custom()
                .failureRateThreshold(50)
                .waitDurationInOpenState(Duration.ofSeconds(30))
                .slidingWindowSize(10)
                .build()
        );
    }

    private void handleWithCircuitBreaker(Message message) {
        try {
            circuitBreaker.executeRunnable(() -> {
                processMessage(message);
                message.ack();
            });

        } catch (CallNotPermittedException e) {
            log.warn("Circuit breaker open, requeueing message");
            message.nakWithDelay(Duration.ofSeconds(30));

        } catch (Exception e) {
            log.error("Processing failed: {}", e.getMessage());
            message.nak();
        }
    }
}
```

---

## Monitoring và Metrics

```java
@Service
@Slf4j
public class NatsMetricsService {

    private final Connection connection;
    private final JetStreamManagement jsm;
    private final MeterRegistry registry;

    @Scheduled(fixedRate = 30000)
    public void collectMetrics() throws Exception {
        // Connection stats
        Statistics stats = connection.getStatistics();
        registry.gauge("nats.connection.in_msgs", stats.getInMsgs());
        registry.gauge("nats.connection.out_msgs", stats.getOutMsgs());
        registry.gauge("nats.connection.in_bytes", stats.getInBytes());
        registry.gauge("nats.connection.out_bytes", stats.getOutBytes());
        registry.gauge("nats.connection.reconnects", stats.getReconnects());

        // Stream stats
        for (String streamName : List.of("ORDERS", "EVENTS")) {
            try {
                StreamInfo info = jsm.getStreamInfo(streamName);
                StreamState state = info.getStreamState();

                registry.gauge("nats.stream.messages",
                    Tags.of("stream", streamName),
                    state.getMsgCount());
                registry.gauge("nats.stream.bytes",
                    Tags.of("stream", streamName),
                    state.getByteCount());
                registry.gauge("nats.stream.consumers",
                    Tags.of("stream", streamName),
                    state.getConsumerCount());

            } catch (Exception e) {
                log.warn("Failed to get stream info for {}", streamName);
            }
        }

        // Consumer stats
        for (ConsumerInfo consumer : jsm.getConsumers("ORDERS")) {
            String consumerName = consumer.getName();
            registry.gauge("nats.consumer.pending",
                Tags.of("stream", "ORDERS", "consumer", consumerName),
                consumer.getNumPending());
            registry.gauge("nats.consumer.ack_pending",
                Tags.of("stream", "ORDERS", "consumer", consumerName),
                consumer.getNumAckPending());
            registry.gauge("nats.consumer.redelivered",
                Tags.of("stream", "ORDERS", "consumer", consumerName),
                consumer.getRedelivered());
        }
    }
}
```

---

## Best Practices Checklist

### Core NATS
- [ ] Handle reconnection events
- [ ] Use queue groups for load balancing
- [ ] Implement request timeouts
- [ ] Monitor slow consumers
- [ ] Use appropriate subject hierarchies

### JetStream
- [ ] Configure appropriate retention policies
- [ ] Set message deduplication window
- [ ] Use durable consumers for reliability
- [ ] Implement proper acknowledgment handling
- [ ] Monitor consumer lag (pending messages)
- [ ] Use pull consumers for batch processing
- [ ] Configure max delivery attempts
- [ ] Implement dead letter handling

### Operations
- [ ] Set up monitoring and alerting
- [ ] Configure stream replication for HA
- [ ] Plan capacity based on retention
- [ ] Document subject naming conventions
- [ ] Test failure scenarios
