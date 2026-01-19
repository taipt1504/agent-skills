# NATS Patterns Reference

## Overview

NATS is a high-performance messaging system for cloud-native applications, IoT messaging, and microservices architectures. This document covers NATS patterns for Java applications, distinguishing between Core NATS and JetStream.

---

## Architecture Fundamentals

### Core NATS vs JetStream

| Feature | Core NATS | JetStream |
|---------|-----------|-----------|
| **Semantics** | At-most-once | At-least-once / Exactly-once |
| **Persistence** | In-memory (Fire & Forget) | Disk / Memory (Persistent) |
| **Consumer API** | Push | Push & Pull |
| **Replay** | No | Yes (Time/Msg/Seq) |
| **Key-Value** | No | Yes (KV Store) |
| **Object Store** | No | Yes |

### NATS Java Client Setup

```java
@Configuration
public class NatsConfig {

    @Value("${nats.servers:nats://localhost:4222}")
    private String natsServers;

    @Bean
    public Connection natsConnection() throws IOException, InterruptedException {
        Options options = new Options.Builder()
            .servers(natsServers.split(","))
            .connectionListener((conn, type) -> {
                if (type == ConnectionListener.Events.CONNECTED) {
                    System.out.println("Connected to NATS");
                } else if (type == ConnectionListener.Events.DISCONNECTED) {
                    System.out.println("Disconnected from NATS");
                }
            })
            .maxReconnects(-1) // Infinite reconnects
            .reconnectWait(Duration.ofSeconds(2))
            .errorListener(new ErrorListener() {
                @Override
                public void errorOccurred(Connection conn, String error) {
                    System.err.println("NATS Error: " + error);
                }

                @Override
                public void exceptionOccurred(Connection conn, Exception exp) {
                    System.err.println("NATS Exception: " + exp);
                }
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

### Object Mapper for NATS

```java
@Component
public class NatsMessageSerializer {

    private final ObjectMapper objectMapper;

    public NatsMessageSerializer(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public byte[] serialize(Object object) {
        try {
            return objectMapper.writeValueAsBytes(object);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Serialization failed", e);
        }
    }

    public <T> T deserialize(byte[] data, Class<T> type) {
        try {
            return objectMapper.readValue(data, type);
        } catch (IOException e) {
            throw new RuntimeException("Deserialization failed", e);
        }
    }
}
```

---

## Core NATS Patterns

### Publish-Subscribe (1-to-N)

```java
@Service
public class PubSubService {

    private final Connection connection;
    private final NatsMessageSerializer serializer;

    // Publisher
    public void publishEvent(String subject, OrderEvent event) {
        byte[] data = serializer.serialize(event);
        connection.publish(subject, data);
    }

    // Async Subscriber
    @PostConstruct
    public void subscribe() {
        Dispatcher dispatcher = connection.createDispatcher(msg -> {
            OrderEvent event = serializer.deserialize(
                msg.getData(), OrderEvent.class);
            System.out.println("Received: " + event);
        });

        dispatcher.subscribe("orders.created");
        dispatcher.subscribe("orders.updated");
        // Wildcard subscription
        dispatcher.subscribe("orders.>");
    }
}
```

### Queue Groups (Load Balancing)

```java
@Service
public class QueueGroupWorker {

    private final Connection connection;

    @PostConstruct
    public void startWorkers() {
        // Create 3 worker threads sharing the load
        for (int i = 0; i < 3; i++) {
            Dispatcher dispatcher = connection.createDispatcher(msg -> {
                // Simulate processing
                String data = new String(msg.getData(), StandardCharsets.UTF_8);
                System.out.println("Worker processed: " + data);
            });

            // "order-processors" is the queue group name
            // Messages will be distributed randomly among members
            dispatcher.subscribe("orders.process", "order-processors");
        }
    }
}
```

### Request-Reply (Sync/Async)

```java
@Service
public class RequestReplyService {

    private final Connection connection;

    // Requester
    public UserProfile getUserProfile(String userId, Duration timeout) {
        try {
            CompletableFuture<Message> future =
                connection.request("users.get", userId.getBytes());

            Message response = future.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
            return deserialize(response.getData());

        } catch (Exception e) {
            throw new RuntimeException("Request timeout or failed", e);
        }
    }

    // Responder
    @PostConstruct
    public void startResponder() {
        Dispatcher dispatcher = connection.createDispatcher(msg -> {
            String userId = new String(msg.getData());
            UserProfile profile = findUser(userId);

            // Send reply to the inbox specified in the request
            connection.publish(msg.getReplyTo(), serialize(profile));
        });

        dispatcher.subscribe("users.get");
    }
}
```

---

## JetStream Patterns

### Stream Configuration

```java
@Service
public class StreamSetupService {

    private final JetStreamManagement jsm;

    @PostConstruct
    public void createOrderStream() throws IOException, JetStreamApiException {
        StreamConfiguration streamConfig = StreamConfiguration.builder()
            .name("ORDERS")
            .subjects("orders.*")
            .storageType(StorageType.File)
            .replicas(1)
            .retentionPolicy(RetentionPolicy.WorkQueue) // or Limits
            .maxAge(Duration.ofDays(7))
            .maxBytes(1024 * 1024 * 1024) // 1GB
            .build();

        try {
            // Update if exists, create if not
            StreamInfo streamInfo = jsm.getStreamInfo("ORDERS");
            jsm.updateStream(streamConfig);
        } catch (JetStreamApiException e) {
            if (e.getErrorCode() == 404) {
                jsm.addStream(streamConfig);
            } else {
                throw e;
            }
        }
    }
}
```

### JetStream Publisher

```java
@Service
public class JetStreamPublisher {

    private final JetStream jetStream;
    private final NatsMessageSerializer serializer;

    // Sync publish with confirmation
    public void publishOrder(OrderEvent event) throws IOException, JetStreamApiException {
        byte[] data = serializer.serialize(event);
        
        PublishAck ack = jetStream.publish("orders.created", data);

        if (ack.isDuplicate()) {
            // Handle duplicate
        }
        
        System.out.println("Published seq: " + ack.getSeq());
    }

    // Async publish
    public CompletableFuture<PublishAck> publishAsync(OrderEvent event) {
        byte[] data = serializer.serialize(event);
        return jetStream.publishAsync("orders.created", data);
    }
}
```

### JetStream Push Consumer

```java
@Service
@Slf4j
public class JetStreamPushConsumer {

    private final JetStream jetStream;
    private final NatsMessageSerializer serializer;

    @PostConstruct
    public void startPushConsumer() throws IOException, JetStreamApiException {
        // Durable push consumer
        PushSubscribeOptions options = PushSubscribeOptions.builder()
            .durable("order-processor-push")
            .deliverSubject("orders.push.inbox") // Optional
            .build();

        Dispatcher dispatcher = jetStream.createDispatcher();

        jetStream.subscribe("orders.created", dispatcher, this::handleMessage, false, options);
    }

    private void handleMessage(Message message) {
        try {
            OrderEvent event = serializer.deserialize(
                message.getData(), OrderEvent.class);
            
            processOrder(event);
            
            // Must acknowledge
            message.ack();

        } catch (Exception e) {
            log.error("Error: {}", e.getMessage());
            message.nak();
        }
    }
}
```

### JetStream Pull Consumer

```java
@Service
@Slf4j
public class JetStreamPullConsumer {

    private final JetStream jetStream;
    private final NatsMessageSerializer serializer;
    private volatile boolean running = true;
    private ExecutorService executor;

    @PostConstruct
    public void startPullConsumer() throws IOException, JetStreamApiException {
        PullSubscribeOptions options = PullSubscribeOptions.builder()
            .durable("order-processor-pull")
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

## Monitoring and Metrics

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

