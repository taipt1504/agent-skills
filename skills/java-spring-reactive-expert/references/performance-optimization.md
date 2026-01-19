# Performance Optimization Reference

## Table of Contents
- [Memory Optimization](#memory-optimization)
- [Schedulers Tuning](#schedulers-tuning)
- [Connection Pool Sizing](#connection-pool-sizing)
- [Metrics and Monitoring](#metrics-and-monitoring)
- [Profiling Techniques](#profiling-techniques)
- [Backpressure Optimization](#backpressure-optimization)
- [JVM Tuning](#jvm-tuning)
- [Load Testing](#load-testing)

## Memory Optimization

### Buffer Management

```java
@Configuration
public class BufferConfig {

    @Bean
    public WebFluxConfigurer webFluxConfigurer() {
        return new WebFluxConfigurer() {
            @Override
            public void configureHttpMessageCodecs(ServerCodecConfigurer configurer) {
                // Limit in-memory buffer size to prevent OOM
                configurer.defaultCodecs().maxInMemorySize(16 * 1024 * 1024); // 16MB
            }
        };
    }
}

@Service
public class StreamingService {

    // BAD: Collecting entire stream into memory
    public Mono<List<LargeObject>> badCollectAll() {
        return largeObjectFlux.collectList(); // OOM risk!
    }

    // GOOD: Process in batches
    public Flux<ProcessedBatch> goodBatchProcessing() {
        return largeObjectFlux
            .buffer(1000) // Process 1000 at a time
            .flatMap(this::processBatch, 2) // Max 2 concurrent batches
            .doOnNext(batch -> log.debug("Processed batch of size: {}", batch.size()));
    }

    // GOOD: Stream large files without loading into memory
    public Mono<Void> streamLargeFile(Path filePath, ServerHttpResponse response) {
        return DataBufferUtils.read(
                filePath,
                response.bufferFactory(),
                8192 // 8KB chunks
            )
            .doOnDiscard(DataBuffer.class, DataBufferUtils::release)
            .as(response::writeWith);
    }

    // GOOD: Process with windowing
    public Flux<WindowResult> processWithWindow() {
        return eventFlux
            .window(Duration.ofSeconds(10))
            .flatMap(window -> window
                .reduce(new WindowAccumulator(), WindowAccumulator::add)
                .map(WindowAccumulator::toResult));
    }
}
```

### DataBuffer Best Practices

```java
@Service
public class DataBufferService {

    // Always release DataBuffers
    public Mono<String> processDataBuffer(DataBuffer buffer) {
        try {
            byte[] bytes = new byte[buffer.readableByteCount()];
            buffer.read(bytes);
            return Mono.just(new String(bytes, StandardCharsets.UTF_8));
        } finally {
            DataBufferUtils.release(buffer); // Critical!
        }
    }

    // Use doOnDiscard for automatic cleanup
    public Flux<String> processStreamWithCleanup(Flux<DataBuffer> buffers) {
        return buffers
            .map(buffer -> {
                try {
                    byte[] bytes = new byte[buffer.readableByteCount()];
                    buffer.read(bytes);
                    return new String(bytes, StandardCharsets.UTF_8);
                } finally {
                    DataBufferUtils.release(buffer);
                }
            })
            .doOnDiscard(DataBuffer.class, DataBufferUtils::release);
    }

    // Using Flux.using for resource management
    public Flux<String> readFileLines(Path path) {
        return Flux.using(
            () -> Files.newBufferedReader(path),
            reader -> Flux.fromStream(reader.lines()),
            reader -> {
                try {
                    reader.close();
                } catch (IOException e) {
                    log.error("Failed to close reader", e);
                }
            }
        );
    }
}
```

### Memory-Efficient Aggregation

```java
@Service
public class AggregationService {

    // BAD: Loading all items into memory
    public Mono<Statistics> badAggregation(Flux<Item> items) {
        return items.collectList()
            .map(list -> {
                // Compute statistics from list
                return computeStats(list);
            });
    }

    // GOOD: Streaming aggregation
    public Mono<Statistics> goodAggregation(Flux<Item> items) {
        return items.reduce(
            new StatisticsAccumulator(),
            StatisticsAccumulator::add
        ).map(StatisticsAccumulator::toStatistics);
    }

    @Data
    public static class StatisticsAccumulator {
        private long count = 0;
        private double sum = 0;
        private double min = Double.MAX_VALUE;
        private double max = Double.MIN_VALUE;
        private double sumOfSquares = 0;

        public StatisticsAccumulator add(Item item) {
            double value = item.getValue();
            count++;
            sum += value;
            min = Math.min(min, value);
            max = Math.max(max, value);
            sumOfSquares += value * value;
            return this;
        }

        public Statistics toStatistics() {
            double mean = count > 0 ? sum / count : 0;
            double variance = count > 0 ? (sumOfSquares / count) - (mean * mean) : 0;
            return new Statistics(count, sum, mean, min, max, Math.sqrt(variance));
        }
    }

    // GOOD: Using scan for running statistics
    public Flux<RunningStats> streamingStats(Flux<Item> items) {
        return items.scan(
            new StatisticsAccumulator(),
            StatisticsAccumulator::add
        ).skip(1) // Skip initial empty accumulator
        .map(acc -> new RunningStats(acc.count, acc.sum / acc.count));
    }
}
```

### Object Pooling

```java
@Configuration
public class ObjectPoolConfig {

    @Bean
    public ObjectPool<StringBuilder> stringBuilderPool() {
        return new GenericObjectPool<>(new BasePooledObjectFactory<>() {
            @Override
            public StringBuilder create() {
                return new StringBuilder(1024);
            }

            @Override
            public PooledObject<StringBuilder> wrap(StringBuilder sb) {
                return new DefaultPooledObject<>(sb);
            }

            @Override
            public void passivateObject(PooledObject<StringBuilder> p) {
                p.getObject().setLength(0); // Reset for reuse
            }
        });
    }
}

@Service
@RequiredArgsConstructor
public class PooledStringService {

    private final ObjectPool<StringBuilder> pool;

    public Mono<String> buildComplexString(List<String> parts) {
        return Mono.fromCallable(() -> {
            StringBuilder sb = pool.borrowObject();
            try {
                for (String part : parts) {
                    sb.append(part);
                }
                return sb.toString();
            } finally {
                pool.returnObject(sb);
            }
        }).subscribeOn(Schedulers.boundedElastic());
    }
}
```

## Schedulers Tuning

### Custom Scheduler Configuration

```java
@Configuration
public class SchedulerConfig {

    // Custom bounded elastic for blocking operations
    @Bean
    public Scheduler blockingScheduler() {
        return Schedulers.newBoundedElastic(
            100,                    // Thread cap
            10000,                  // Queued tasks cap
            "blocking-pool",        // Thread name prefix
            60,                     // TTL in seconds
            true                    // Daemon threads
        );
    }

    // Parallel scheduler for CPU-bound work
    @Bean
    public Scheduler parallelScheduler() {
        return Schedulers.newParallel(
            "parallel-pool",
            Runtime.getRuntime().availableProcessors(),
            true
        );
    }

    // Single thread scheduler for sequential operations
    @Bean
    public Scheduler singleScheduler() {
        return Schedulers.newSingle("single-worker", true);
    }

    // Custom executor-based scheduler
    @Bean
    public Scheduler customExecutorScheduler() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);
        executor.setMaxPoolSize(50);
        executor.setQueueCapacity(1000);
        executor.setThreadNamePrefix("custom-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();

        return Schedulers.fromExecutor(executor);
    }
}

@Service
@RequiredArgsConstructor
public class SchedulerAwareService {

    private final Scheduler blockingScheduler;
    private final Scheduler parallelScheduler;

    // Use appropriate scheduler for blocking operations
    public Mono<Data> fetchFromBlockingService(String id) {
        return Mono.fromCallable(() -> blockingClient.fetch(id))
            .subscribeOn(blockingScheduler); // Offload to blocking pool
    }

    // Use parallel scheduler for CPU-intensive work
    public Flux<Result> processInParallel(Flux<Item> items) {
        return items
            .parallel()
            .runOn(parallelScheduler)
            .map(this::heavyComputation)
            .sequential();
    }

    // Avoid scheduler switching when not needed
    public Mono<Result> efficientPipeline(Request request) {
        return validate(request)     // Non-blocking
            .flatMap(this::process)  // Non-blocking
            .map(this::transform);   // Non-blocking
        // No subscribeOn/publishOn needed!
    }
}
```

### Scheduler Metrics

```java
@Component
@RequiredArgsConstructor
public class SchedulerMetrics {

    private final MeterRegistry meterRegistry;

    @PostConstruct
    public void registerMetrics() {
        // Register Reactor scheduler metrics
        Schedulers.enableMetrics();

        // Custom scheduler monitoring
        Schedulers.onScheduleHook("metrics", runnable -> {
            long start = System.nanoTime();
            return () -> {
                try {
                    runnable.run();
                } finally {
                    long duration = System.nanoTime() - start;
                    meterRegistry.timer("scheduler.task.duration")
                        .record(duration, TimeUnit.NANOSECONDS);
                }
            };
        });
    }

    @Bean
    public Scheduler monitoredScheduler() {
        Scheduler scheduler = Schedulers.newBoundedElastic(
            50, 10000, "monitored", 60, true);

        // Wrap with metrics
        return new InstrumentedScheduler(scheduler, meterRegistry);
    }
}

public class InstrumentedScheduler implements Scheduler {

    private final Scheduler delegate;
    private final Counter taskCounter;
    private final Timer taskTimer;

    public InstrumentedScheduler(Scheduler delegate, MeterRegistry registry) {
        this.delegate = delegate;
        this.taskCounter = registry.counter("scheduler.tasks.submitted");
        this.taskTimer = registry.timer("scheduler.tasks.execution");
    }

    @Override
    public Disposable schedule(Runnable task) {
        taskCounter.increment();
        return delegate.schedule(() -> {
            long start = System.nanoTime();
            try {
                task.run();
            } finally {
                taskTimer.record(System.nanoTime() - start, TimeUnit.NANOSECONDS);
            }
        });
    }

    @Override
    public Worker createWorker() {
        return delegate.createWorker();
    }
}
```

## Connection Pool Sizing

### Optimal Pool Size Calculation

```java
@Configuration
@Slf4j
public class OptimalPoolConfig {

    /*
     * Pool Size Guidelines:
     *
     * For R2DBC (async):
     * - connections = (requests/second) * (avg query time in seconds)
     * - Add 20-30% buffer for spikes
     * - Consider: DB max connections / number of app instances
     *
     * For blocking (HikariCP):
     * - connections = ((core_count * 2) + effective_spindle_count)
     * - Typically 10-20 connections per instance is optimal
     */

    @Bean
    public ConnectionFactory connectionFactory(
            @Value("${app.db.max-connections:50}") int maxConnections,
            @Value("${app.db.min-connections:10}") int minConnections) {

        // Calculate based on expected load
        int optimalMax = calculateOptimalPoolSize();
        int actualMax = Math.min(optimalMax, maxConnections);

        log.info("Configuring connection pool: min={}, max={}", minConnections, actualMax);

        ConnectionFactory connectionFactory = ConnectionFactories.get(
            ConnectionFactoryOptions.parse(dbUrl));

        return new ConnectionPool(
            ConnectionPoolConfiguration.builder()
                .connectionFactory(connectionFactory)
                .initialSize(minConnections)
                .maxSize(actualMax)
                .maxIdleTime(Duration.ofMinutes(10))
                .maxLifeTime(Duration.ofMinutes(30))
                .acquireRetry(3)
                .build()
        );
    }

    private int calculateOptimalPoolSize() {
        int cpuCores = Runtime.getRuntime().availableProcessors();
        // For I/O bound: cores * (1 + wait_time/compute_time)
        // Assuming typical DB wait/compute ratio of 10:1
        return cpuCores * 11;
    }
}
```

### Dynamic Pool Sizing

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class DynamicPoolSizer {

    private final ConnectionPool connectionPool;
    private final MeterRegistry meterRegistry;

    @Scheduled(fixedRate = 60000) // Every minute
    public void adjustPoolSize() {
        connectionPool.getMetrics().ifPresent(metrics -> {
            int acquired = metrics.acquiredSize();
            int maxSize = metrics.getMaxAllocatedSize();
            int pending = metrics.pendingAcquireSize();

            double utilizationRatio = (double) acquired / maxSize;

            log.debug("Pool stats: acquired={}, max={}, pending={}, utilization={}%",
                acquired, maxSize, pending, (int)(utilizationRatio * 100));

            // Log warnings for high utilization
            if (utilizationRatio > 0.8) {
                log.warn("Connection pool utilization high: {}%", (int)(utilizationRatio * 100));
            }

            if (pending > 0) {
                log.warn("Pending connection acquisitions: {}", pending);
            }

            // Record metrics
            meterRegistry.gauge("db.pool.utilization", utilizationRatio);
            meterRegistry.gauge("db.pool.pending", pending);
        });
    }
}
```

### HTTP Client Pool Configuration

```java
@Configuration
public class HttpClientPoolConfig {

    @Bean
    public WebClient webClient() {
        // Connection provider optimized for high throughput
        ConnectionProvider provider = ConnectionProvider.builder("optimized")
            .maxConnections(500)                    // Total connections
            .maxIdleTime(Duration.ofSeconds(20))    // Idle timeout
            .maxLifeTime(Duration.ofMinutes(5))     // Max connection lifetime
            .pendingAcquireTimeout(Duration.ofSeconds(60))
            .pendingAcquireMaxCount(1000)           // Max waiting requests
            .evictInBackground(Duration.ofSeconds(120))
            .metrics(true)
            .lifo()  // Last-in-first-out for better connection reuse
            .build();

        HttpClient httpClient = HttpClient.create(provider)
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
            .option(ChannelOption.SO_KEEPALIVE, true)
            .option(ChannelOption.TCP_NODELAY, true)
            .responseTimeout(Duration.ofSeconds(30))
            .compress(true)
            .doOnConnected(conn -> conn
                .addHandlerLast(new ReadTimeoutHandler(30))
                .addHandlerLast(new WriteTimeoutHandler(30)));

        return WebClient.builder()
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .build();
    }
}
```

## Metrics and Monitoring

### Comprehensive Metrics Configuration

```java
@Configuration
public class MetricsConfig {

    @Bean
    public MeterRegistryCustomizer<MeterRegistry> commonTags() {
        return registry -> registry.config()
            .commonTags(
                "application", "reactive-app",
                "environment", System.getenv().getOrDefault("ENV", "local")
            );
    }

    @Bean
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }

    @PostConstruct
    public void configureReactorMetrics() {
        // Enable Reactor metrics
        Schedulers.enableMetrics();
        Hooks.enableAutomaticContextPropagation();

        // Add checkpoint for debugging
        Hooks.onOperatorDebug();
    }
}

@Aspect
@Component
@RequiredArgsConstructor
public class ReactiveMetricsAspect {

    private final MeterRegistry meterRegistry;

    @Around("@annotation(timed)")
    public Object measureMono(ProceedingJoinPoint pjp, Timed timed) throws Throwable {
        Object result = pjp.proceed();

        if (result instanceof Mono<?> mono) {
            String metricName = timed.value().isEmpty()
                ? pjp.getSignature().getName()
                : timed.value();

            return mono
                .name(metricName)
                .metrics()
                .tag("class", pjp.getTarget().getClass().getSimpleName())
                .tag("method", pjp.getSignature().getName());
        }

        if (result instanceof Flux<?> flux) {
            String metricName = timed.value().isEmpty()
                ? pjp.getSignature().getName()
                : timed.value();

            return flux
                .name(metricName)
                .metrics()
                .tag("class", pjp.getTarget().getClass().getSimpleName())
                .tag("method", pjp.getSignature().getName());
        }

        return result;
    }
}
```

### Custom Business Metrics

```java
@Service
@RequiredArgsConstructor
public class BusinessMetricsService {

    private final MeterRegistry meterRegistry;
    private final Counter orderCounter;
    private final Timer orderProcessingTimer;
    private final DistributionSummary orderValueSummary;
    private final AtomicInteger activeOrders;

    public BusinessMetricsService(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;

        this.orderCounter = Counter.builder("orders.created")
            .description("Total orders created")
            .register(meterRegistry);

        this.orderProcessingTimer = Timer.builder("orders.processing.time")
            .description("Order processing duration")
            .publishPercentiles(0.5, 0.95, 0.99)
            .register(meterRegistry);

        this.orderValueSummary = DistributionSummary.builder("orders.value")
            .description("Order value distribution")
            .baseUnit("dollars")
            .publishPercentiles(0.5, 0.95, 0.99)
            .register(meterRegistry);

        this.activeOrders = meterRegistry.gauge("orders.active",
            new AtomicInteger(0));
    }

    public Mono<Order> processOrder(Order order) {
        return Mono.just(order)
            .doOnSubscribe(s -> activeOrders.incrementAndGet())
            .flatMap(this::doProcessOrder)
            .doOnSuccess(processed -> {
                orderCounter.increment();
                orderValueSummary.record(processed.getTotalValue().doubleValue());
            })
            .doFinally(signal -> activeOrders.decrementAndGet())
            .name("order.process")
            .metrics();
    }

    public void recordOrderByStatus(String status) {
        meterRegistry.counter("orders.by.status", "status", status).increment();
    }

    public void recordExternalCallLatency(String service, long durationMs) {
        Timer.builder("external.call.duration")
            .tag("service", service)
            .register(meterRegistry)
            .record(durationMs, TimeUnit.MILLISECONDS);
    }
}
```

### Health Indicators

```java
@Component
public class ReactiveHealthIndicators {

    @Bean
    public ReactiveHealthIndicator databaseHealth(ConnectionFactory connectionFactory) {
        return () -> Mono.usingWhen(
            connectionFactory.create(),
            connection -> Mono.from(connection.createStatement("SELECT 1").execute())
                .flatMap(result -> Mono.from(result.getRowsUpdated()))
                .thenReturn(Health.up().build()),
            Connection::close
        )
        .timeout(Duration.ofSeconds(5))
        .onErrorResume(e -> Mono.just(Health.down(e).build()));
    }

    @Bean
    public ReactiveHealthIndicator redisHealth(ReactiveRedisTemplate<String, String> redis) {
        return () -> redis.getConnectionFactory()
            .getReactiveConnection()
            .ping()
            .map(pong -> Health.up().withDetail("response", pong).build())
            .timeout(Duration.ofSeconds(2))
            .onErrorResume(e -> Mono.just(Health.down(e).build()));
    }

    @Bean
    public ReactiveHealthIndicator externalApiHealth(WebClient webClient) {
        return () -> webClient.get()
            .uri("/health")
            .retrieve()
            .toBodilessEntity()
            .map(response -> {
                if (response.getStatusCode().is2xxSuccessful()) {
                    return Health.up().build();
                }
                return Health.down()
                    .withDetail("status", response.getStatusCode())
                    .build();
            })
            .timeout(Duration.ofSeconds(5))
            .onErrorResume(e -> Mono.just(Health.down(e).build()));
    }
}
```

### Distributed Tracing

```java
@Configuration
public class TracingConfig {

    @Bean
    public WebFilter tracingWebFilter(Tracer tracer) {
        return (exchange, chain) -> {
            String traceId = exchange.getRequest().getHeaders()
                .getFirst("X-Trace-Id");

            if (traceId == null) {
                traceId = UUID.randomUUID().toString();
            }

            String finalTraceId = traceId;

            return chain.filter(exchange.mutate()
                    .request(exchange.getRequest().mutate()
                        .header("X-Trace-Id", traceId)
                        .build())
                    .response(exchange.getResponse())
                    .build())
                .contextWrite(Context.of("traceId", finalTraceId));
        };
    }
}

@Service
@Slf4j
public class TracedService {

    public Mono<Result> processWithTracing(Request request) {
        return Mono.deferContextual(ctx -> {
            String traceId = ctx.getOrDefault("traceId", "unknown");

            return process(request)
                .doOnSubscribe(s -> log.info("[{}] Processing started", traceId))
                .doOnSuccess(r -> log.info("[{}] Processing completed", traceId))
                .doOnError(e -> log.error("[{}] Processing failed", traceId, e));
        });
    }
}
```

## Profiling Techniques

### Reactor Debug Agent

```java
@Configuration
@Profile("debug")
public class ReactorDebugConfig {

    @PostConstruct
    public void enableDebugAgent() {
        // Enable for detailed stack traces (significant overhead!)
        ReactorDebugAgent.init();

        // Or use checkpoints for selective debugging
        Hooks.onOperatorDebug();
    }
}

@Service
public class DebuggableService {

    public Mono<Result> processWithCheckpoints(Request request) {
        return validate(request)
            .checkpoint("After validation")
            .flatMap(this::enrich)
            .checkpoint("After enrichment")
            .flatMap(this::process)
            .checkpoint("After processing")
            .flatMap(this::save)
            .checkpoint("After save");
    }

    // For production: use description-only checkpoints
    public Mono<Result> processWithLightCheckpoints(Request request) {
        return validate(request)
            .checkpoint("validation", true) // true = forceStackTrace off
            .flatMap(this::enrich)
            .checkpoint("enrichment", true)
            .flatMap(this::process)
            .checkpoint("processing", true);
    }
}
```

### Memory Profiling

```java
@Service
@Slf4j
public class MemoryProfilingService {

    private final MemoryMXBean memoryMXBean = ManagementFactory.getMemoryMXBean();

    public void logMemoryUsage(String operation) {
        MemoryUsage heapUsage = memoryMXBean.getHeapMemoryUsage();
        log.info("Memory after {}: used={}MB, committed={}MB, max={}MB",
            operation,
            heapUsage.getUsed() / 1024 / 1024,
            heapUsage.getCommitted() / 1024 / 1024,
            heapUsage.getMax() / 1024 / 1024);
    }
}
```
