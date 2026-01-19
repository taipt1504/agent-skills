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

        log.info("Memory [{}]: used={}MB, committed={}MB, max={}MB",
            operation,
            heapUsage.getUsed() / (1024 * 1024),
            heapUsage.getCommitted() / (1024 * 1024),
            heapUsage.getMax() / (1024 * 1024)
        );
    }

    public <T> Mono<T> withMemoryTracking(String operation, Mono<T> mono) {
        return Mono.defer(() -> {
            logMemoryUsage(operation + " - start");
            return mono
                .doOnSuccess(r -> logMemoryUsage(operation + " - success"))
                .doOnError(e -> logMemoryUsage(operation + " - error"));
        });
    }

    // Detect memory leaks by tracking allocations
    public void trackAllocation(String category, long bytes) {
        // Use Micrometer for tracking
        Metrics.counter("memory.allocated",
                "category", category)
            .increment(bytes);
    }
}
```

### Performance Benchmarking

```java
@Service
@RequiredArgsConstructor
public class BenchmarkService {

    private final MeterRegistry meterRegistry;

    public <T> Mono<T> benchmark(String name, Mono<T> operation) {
        return Mono.defer(() -> {
            long startTime = System.nanoTime();
            long startMemory = getUsedMemory();

            return operation
                .doOnTerminate(() -> {
                    long duration = System.nanoTime() - startTime;
                    long memoryDelta = getUsedMemory() - startMemory;

                    meterRegistry.timer("benchmark.duration", "operation", name)
                        .record(duration, TimeUnit.NANOSECONDS);

                    meterRegistry.gauge("benchmark.memory", Tags.of("operation", name),
                        memoryDelta);

                    log.info("Benchmark [{}]: duration={}ms, memory={}KB",
                        name,
                        TimeUnit.NANOSECONDS.toMillis(duration),
                        memoryDelta / 1024);
                });
        });
    }

    public <T> Flux<T> benchmarkFlux(String name, Flux<T> operation) {
        return Flux.defer(() -> {
            AtomicLong count = new AtomicLong();
            long startTime = System.nanoTime();

            return operation
                .doOnNext(item -> count.incrementAndGet())
                .doOnComplete(() -> {
                    long duration = System.nanoTime() - startTime;
                    double itemsPerSecond = count.get() /
                        (duration / 1_000_000_000.0);

                    log.info("Benchmark [{}]: items={}, duration={}ms, throughput={}/s",
                        name,
                        count.get(),
                        TimeUnit.NANOSECONDS.toMillis(duration),
                        (int) itemsPerSecond);
                });
        });
    }

    private long getUsedMemory() {
        Runtime runtime = Runtime.getRuntime();
        return runtime.totalMemory() - runtime.freeMemory();
    }
}
```

## Backpressure Optimization

### Backpressure Strategies

```java
@Service
public class BackpressureOptimizedService {

    // Buffer with overflow strategy
    public Flux<Event> bufferedEvents() {
        return eventSource.asFlux()
            .onBackpressureBuffer(
                10000,                                    // Buffer size
                event -> log.warn("Dropped: {}", event),  // Overflow handler
                BufferOverflowStrategy.DROP_OLDEST        // Strategy
            );
    }

    // Drop with logging
    public Flux<Event> droppingEvents() {
        return eventSource.asFlux()
            .onBackpressureDrop(event ->
                log.debug("Dropped event due to backpressure: {}", event));
    }

    // Latest only (good for real-time updates)
    public Flux<StockPrice> latestPrices() {
        return priceSource.asFlux()
            .onBackpressureLatest();
    }

    // Rate limiting
    public Flux<Event> rateLimitedEvents() {
        return eventSource.asFlux()
            .limitRate(100);      // Request 100 at a time
    }

    // Custom rate with low tide mark
    public Flux<Event> customRateLimited() {
        return eventSource.asFlux()
            .limitRate(100, 75);  // Request 100, replenish at 75
    }

    // Sampling for high-frequency data
    public Flux<Metric> sampledMetrics() {
        return metricSource.asFlux()
            .sample(Duration.ofMillis(100));  // Sample every 100ms
    }

    // Throttling with timeout
    public Flux<Event> throttledEvents() {
        return eventSource.asFlux()
            .throttleFirst(Duration.ofMillis(100));
    }
}
```

### Adaptive Backpressure

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class AdaptiveBackpressureService {

    private final AtomicInteger currentDemand = new AtomicInteger(100);
    private final AtomicLong processedCount = new AtomicLong();
    private final AtomicLong errorCount = new AtomicLong();

    public Flux<Result> processWithAdaptiveBackpressure(Flux<Item> items) {
        return items
            .limitRequest(currentDemand.get())
            .flatMap(item -> processItem(item)
                .doOnSuccess(r -> processedCount.incrementAndGet())
                .doOnError(e -> {
                    errorCount.incrementAndGet();
                    adjustDemand();
                }))
            .doOnComplete(this::adjustDemand);
    }

    private void adjustDemand() {
        long processed = processedCount.get();
        long errors = errorCount.get();
        double errorRate = processed > 0 ? (double) errors / processed : 0;

        int current = currentDemand.get();
        int newDemand;

        if (errorRate > 0.1) {
            // High error rate: reduce demand
            newDemand = Math.max(10, current / 2);
            log.info("Reducing demand due to high error rate: {} -> {}", current, newDemand);
        } else if (errorRate < 0.01 && current < 1000) {
            // Low error rate: increase demand
            newDemand = Math.min(1000, (int)(current * 1.5));
            log.info("Increasing demand due to low error rate: {} -> {}", current, newDemand);
        } else {
            newDemand = current;
        }

        currentDemand.set(newDemand);
        processedCount.set(0);
        errorCount.set(0);
    }
}
```

## JVM Tuning

### Recommended JVM Options

```bash
# Memory settings for reactive applications
JAVA_OPTS="
  -Xms2g
  -Xmx2g
  -XX:+UseZGC
  -XX:+ZGenerational
  -XX:MaxGCPauseMillis=10
  -XX:+UseStringDeduplication
"

# For lower memory footprint
JAVA_OPTS="
  -Xms512m
  -Xmx512m
  -XX:+UseSerialGC
  -XX:MaxRAMPercentage=75.0
"

# For high throughput
JAVA_OPTS="
  -Xms4g
  -Xmx4g
  -XX:+UseG1GC
  -XX:MaxGCPauseMillis=200
  -XX:G1HeapRegionSize=16m
  -XX:+ParallelRefProcEnabled
"

# Netty optimizations
JAVA_OPTS="
  -Dio.netty.eventLoopThreads=16
  -Dio.netty.allocator.type=pooled
  -Dio.netty.leakDetection.level=disabled
"

# Reactor optimizations
JAVA_OPTS="
  -Dreactor.schedulers.defaultPoolSize=16
  -Dreactor.schedulers.defaultBoundedElasticSize=100
"
```

### Container-Optimized Configuration

```java
@Configuration
public class ContainerOptimizedConfig {

    @PostConstruct
    public void optimizeForContainer() {
        // Detect container memory limits
        long maxMemory = Runtime.getRuntime().maxMemory();
        int availableProcessors = Runtime.getRuntime().availableProcessors();

        log.info("Container resources: maxMemory={}MB, cpus={}",
            maxMemory / (1024 * 1024), availableProcessors);

        // Adjust scheduler sizes based on available resources
        int optimalParallelism = Math.max(2, availableProcessors);
        System.setProperty("reactor.schedulers.defaultPoolSize",
            String.valueOf(optimalParallelism));
    }

    @Bean
    public Scheduler containerOptimizedScheduler() {
        int cpus = Runtime.getRuntime().availableProcessors();
        return Schedulers.newBoundedElastic(
            cpus * 10,           // Thread cap based on CPU
            cpus * 1000,         // Queue cap
            "container-pool"
        );
    }
}
```

## Load Testing

### Gatling Script for Reactive Endpoints

```scala
// build.sbt or pom.xml dependency: gatling-charts-highcharts

class ReactiveApiSimulation extends Simulation {

  val httpProtocol = http
    .baseUrl("http://localhost:8080")
    .acceptHeader("application/json")
    .contentTypeHeader("application/json")

  val users = scenario("Users API")
    .exec(
      http("Get all users")
        .get("/api/users")
        .check(status.is(200))
    )
    .pause(1)
    .exec(
      http("Create user")
        .post("/api/users")
        .body(StringBody("""{"name": "Test", "email": "test@example.com"}"""))
        .check(status.is(201))
        .check(jsonPath("$.id").saveAs("userId"))
    )
    .pause(500.millis)
    .exec(
      http("Get user by ID")
        .get("/api/users/${userId}")
        .check(status.is(200))
    )

  val streaming = scenario("SSE Streaming")
    .exec(
      sse("Connect to event stream")
        .connect("/api/events/stream")
        .await(30.seconds)(
          sse.checkMessage("event received")
            .check(regex("data:(.*)").count.gte(5))
        )
    )

  setUp(
    users.inject(
      rampUsers(100).during(30.seconds),
      constantUsersPerSec(50).during(2.minutes),
      rampUsersPerSec(50).to(200).during(1.minute)
    ),
    streaming.inject(
      rampUsers(50).during(30.seconds)
    )
  ).protocols(httpProtocol)
    .assertions(
      global.responseTime.percentile(95).lt(500),
      global.successfulRequests.percent.gt(99)
    )
}
```

### K6 Load Test Script

```javascript
// k6 run reactive-load-test.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const apiTrend = new Trend('api_duration');

export const options = {
  stages: [
    { duration: '30s', target: 100 },  // Ramp up
    { duration: '2m', target: 100 },   // Stay at 100
    { duration: '30s', target: 200 },  // Ramp to 200
    { duration: '2m', target: 200 },   // Stay at 200
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    errors: ['rate<0.01'],
  },
};

export default function () {
  const baseUrl = 'http://localhost:8080/api';

  // Test GET endpoint
  let response = http.get(`${baseUrl}/users`);
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  errorRate.add(response.status !== 200);
  apiTrend.add(response.timings.duration);

  sleep(1);

  // Test POST endpoint
  const payload = JSON.stringify({
    name: `User-${__VU}-${__ITER}`,
    email: `user${__VU}${__ITER}@test.com`,
  });

  response = http.post(`${baseUrl}/users`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(response, {
    'created status': (r) => r.status === 201,
  });
  errorRate.add(response.status !== 201);

  sleep(0.5);
}
```

### Spring Boot Test with WebTestClient

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
public class PerformanceIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void loadTestUserEndpoint() {
        int concurrentRequests = 100;
        int totalRequests = 1000;

        Flux.range(0, totalRequests)
            .parallel(concurrentRequests)
            .runOn(Schedulers.boundedElastic())
            .flatMap(i -> webTestClient.get()
                .uri("/api/users")
                .exchange()
                .returnResult(UserDto.class)
                .getResponseBody()
                .collectList()
                .elapsed()
                .map(tuple -> tuple.getT1()))
            .sequential()
            .collectList()
            .as(StepVerifier::create)
            .assertNext(durations -> {
                double avgMs = durations.stream()
                    .mapToLong(Long::valueOf)
                    .average()
                    .orElse(0);

                long p95 = durations.stream()
                    .sorted()
                    .skip((long)(durations.size() * 0.95))
                    .findFirst()
                    .orElse(0L);

                assertThat(avgMs).isLessThan(100);
                assertThat(p95).isLessThan(500);
            })
            .verifyComplete();
    }

    @Test
    void streamingEndpointPerformance() {
        Duration testDuration = Duration.ofSeconds(30);
        AtomicLong eventCount = new AtomicLong();

        webTestClient.get()
            .uri("/api/events/stream")
            .accept(MediaType.TEXT_EVENT_STREAM)
            .exchange()
            .expectStatus().isOk()
            .returnResult(Event.class)
            .getResponseBody()
            .take(testDuration)
            .doOnNext(event -> eventCount.incrementAndGet())
            .blockLast();

        double eventsPerSecond = eventCount.get() / testDuration.getSeconds();
        assertThat(eventsPerSecond).isGreaterThan(100);
    }
}
```
