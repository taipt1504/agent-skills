# API Operations & Documentation Reference

File upload/download, idempotency, bulk operations, long-running operations, and contract testing.

## Table of Contents
- [File Upload](#file-upload)
- [File Download / Streaming](#file-download--streaming)
- [Idempotency](#idempotency)
- [Bulk Operations](#bulk-operations)
- [Long-Running Operations (Async + Polling)](#long-running-operations-async--polling)
- [Contract Testing](#contract-testing)

---

## File Upload

```java
@PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
public Mono<FileUploadResponse> uploadFile(
        @RequestPart("file") Mono<FilePart> filePart,
        @RequestPart("metadata") @Valid UploadMetadataRequest metadata) {

    return filePart.flatMap(fp -> {
        // Validate
        String filename = StringUtils.cleanPath(fp.filename());
        long size = fp.headers().getContentLength();

        if (!ALLOWED_EXTENSIONS.contains(getExtension(filename).toLowerCase())) {
            return Mono.error(new BadRequestException("File type not allowed"));
        }
        if (size > MAX_SIZE_BYTES) {
            return Mono.error(new BadRequestException("File exceeds 5MB limit"));
        }

        // Store
        return fileService.store(fp, metadata)
            .map(result -> new FileUploadResponse(result.id(), result.url()));
    });
}

private static final Set<String> ALLOWED_EXTENSIONS =
    Set.of("jpg", "jpeg", "png", "gif", "pdf", "docx");
private static final long MAX_SIZE_BYTES = 5 * 1024 * 1024L;
```

```java
// Streaming to storage (avoid loading entire file into memory)
@Service @RequiredArgsConstructor
public class FileService {
    private final S3AsyncClient s3Client;

    public Mono<FileResult> store(FilePart file, UploadMetadataRequest meta) {
        String key = UUID.randomUUID() + "-" + StringUtils.cleanPath(file.filename());

        // Stream directly to S3
        return DataBufferUtils.join(file.content())
            .flatMap(buffer -> {
                byte[] bytes = new byte[buffer.readableByteCount()];
                buffer.read(bytes);
                DataBufferUtils.release(buffer);

                return Mono.fromFuture(s3Client.putObject(
                    PutObjectRequest.builder()
                        .bucket(bucketName)
                        .key(key)
                        .contentType(file.headers().getContentType().toString())
                        .build(),
                    AsyncRequestBody.fromBytes(bytes)));
            })
            .map(r -> new FileResult(key, buildUrl(key)));
    }
}
```

---

## File Download / Streaming

```java
@GetMapping("/files/{fileId}")
public Mono<ResponseEntity<Resource>> downloadFile(@PathVariable String fileId) {
    return fileService.findById(fileId)
        .switchIfEmpty(Mono.error(new NotFoundException("File not found: " + fileId)))
        .flatMap(meta -> fileService.loadResource(meta.storageKey())
            .map(resource -> ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"" + meta.originalFilename() + "\"")
                .contentType(MediaType.parseMediaType(meta.mimeType()))
                .contentLength(meta.size())
                .body(resource)));
}

// Large file streaming (reactive)
@GetMapping(value = "/files/{fileId}/stream",
            produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
public Flux<DataBuffer> streamFile(@PathVariable String fileId) {
    return fileService.stream(fileId);  // returns Flux<DataBuffer> from S3 ranges
}
```

---

## Idempotency

Safe to retry — Redis-backed deduplication with 24h TTL.

```java
@Component @RequiredArgsConstructor
public class IdempotencyFilter implements WebFilter {
    private final ReactiveRedisTemplate<String, IdempotencyRecord> redis;

    @Override
    public Mono<WebFilterChain> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String key = exchange.getRequest().getHeaders().getFirst("Idempotency-Key");
        if (key == null || !isMutation(exchange.getRequest().getMethod())) {
            return chain.filter(exchange).then(Mono.empty());
        }

        String redisKey = "idempotency:" + key;
        return redis.opsForValue().get(redisKey)
            .flatMap(cached -> {
                // Return cached response
                exchange.getResponse().setStatusCode(HttpStatus.valueOf(cached.statusCode()));
                exchange.getResponse().getHeaders().add("X-Idempotent-Replayed", "true");
                return exchange.getResponse().writeWith(
                    Mono.just(exchange.getResponse().bufferFactory()
                        .wrap(cached.body())));
            })
            .switchIfEmpty(chain.filter(exchange)
                .then(Mono.defer(() -> {
                    // Cache response for 24h
                    // Note: in practice, use ResponseBodyInterceptor to capture body
                    return redis.opsForValue().set(redisKey,
                        new IdempotencyRecord(
                            exchange.getResponse().getStatusCode().value(),
                            new byte[0]),
                        Duration.ofHours(24));
                }))
                .then(Mono.empty()));
    }

    private boolean isMutation(HttpMethod method) {
        return method == HttpMethod.POST || method == HttpMethod.PUT ||
               method == HttpMethod.PATCH || method == HttpMethod.DELETE;
    }
}
```

```java
// Simpler: idempotency at service layer
public Mono<OrderResponse> createOrder(CreateOrderRequest request, String idempotencyKey) {
    String redisKey = "idem:create-order:" + idempotencyKey;
    return redis.<String>opsForValue().get(redisKey)
        .flatMap(existingId -> orderRepository.findById(existingId).map(mapper::toResponse))
        .switchIfEmpty(Mono.defer(() ->
            orderService.create(request)
                .flatMap(order ->
                    redis.opsForValue().set(redisKey, order.getId(), Duration.ofHours(24))
                        .thenReturn(mapper.toResponse(order)))));
}
```

---

## Bulk Operations

```java
public record BulkRequest<T>(
    @NotEmpty @Size(max = 100) List<@Valid T> items
) {}

public record BulkResult<T>(
    List<BulkItemResult<T>> results,
    int successCount,
    int failureCount
) {}

public record BulkItemResult<T>(
    int index,
    boolean success,
    T data,
    String error
) {}
```

```java
@PostMapping("/bulk")
public Mono<ResponseEntity<BulkResult<OrderResponse>>> bulkCreate(
        @Valid @RequestBody BulkRequest<CreateOrderRequest> request) {

    return Flux.fromIterable(request.items())
        .index()
        .flatMap(indexed ->
            orderService.create(indexed.getT2())
                .map(order -> new BulkItemResult<>(
                    indexed.getT1().intValue(), true, mapper.toResponse(order), null))
                .onErrorResume(ex -> Mono.just(new BulkItemResult<>(
                    indexed.getT1().intValue(), false, null, ex.getMessage()))))
        .collectList()
        .map(results -> {
            int success = (int) results.stream().filter(BulkItemResult::success).count();
            var bulk = new BulkResult<>(results, success, results.size() - success);
            // 207 Multi-Status if mixed results
            HttpStatus status = bulk.failureCount() == 0
                ? HttpStatus.CREATED
                : (bulk.successCount() == 0 ? HttpStatus.BAD_REQUEST : HttpStatus.MULTI_STATUS);
            return ResponseEntity.status(status).body(bulk);
        });
}
```

---

## Long-Running Operations (Async + Polling)

```
POST /api/v1/reports → 202 Accepted + Location: /api/v1/jobs/{jobId}
GET  /api/v1/jobs/{jobId} → {status: "PROCESSING", progress: 45}
GET  /api/v1/jobs/{jobId} → {status: "DONE", resultUrl: "/api/v1/reports/{id}"}
```

```java
public record JobStatus(
    String id,
    JobState state,  // PENDING, PROCESSING, DONE, FAILED
    int progress,    // 0-100
    String resultUrl,
    String errorMessage,
    Instant createdAt,
    Instant completedAt
) {}

@PostMapping("/reports")
@ResponseStatus(HttpStatus.ACCEPTED)
public Mono<ResponseEntity<Map<String, String>>> startReport(
        @Valid @RequestBody GenerateReportRequest request) {
    return jobService.submit(request)
        .map(jobId -> ResponseEntity
            .accepted()
            .header(HttpHeaders.LOCATION, "/api/v1/jobs/" + jobId)
            .header("Retry-After", "5")
            .body(Map.of("jobId", jobId)));
}

@GetMapping("/jobs/{jobId}")
public Mono<JobStatus> getJobStatus(@PathVariable String jobId) {
    return jobService.getStatus(jobId)
        .switchIfEmpty(Mono.error(new NotFoundException("Job not found: " + jobId)));
}
```

```java
// SSE for real-time progress
@GetMapping(value = "/jobs/{jobId}/progress", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<ServerSentEvent<JobStatus>> streamProgress(@PathVariable String jobId) {
    return Flux.interval(Duration.ofSeconds(2))
        .flatMap(tick -> jobService.getStatus(jobId))
        .takeUntil(status -> status.state() == JobState.DONE ||
                             status.state() == JobState.FAILED)
        .map(status -> ServerSentEvent.<JobStatus>builder()
            .data(status)
            .event("progress")
            .build());
}
```

---

## Contract Testing

### Spring Cloud Contract (Provider-driven)

```groovy
// contracts/src/test/resources/contracts/orders/shouldCreateOrder.groovy
Contract.make {
    description "should create order"
    request {
        method POST()
        url '/api/v1/orders'
        body([
            customerId: "customer-1",
            items: [[productId: "P1", quantity: 2, unitPrice: 1000]]
        ])
        headers { contentType(applicationJson()) }
    }
    response {
        status CREATED()
        body([
            id: $(producer(regex('[a-z0-9-]+')), consumer('ord-abc')),
            status: "PENDING",
            totalAmount: 2000
        ])
        headers {
            contentType(applicationJson())
            header('Location', $(producer(url('/api/v1/orders/.*'))))
        }
    }
}
```

```java
// Provider test base class
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class OrderContractBase {

    @Autowired
    private ApplicationContext context;

    @MockBean
    private OrderService orderService;

    @BeforeEach
    void setup() {
        RestAssuredWebTestClient.applicationContextSetup(context);

        when(orderService.create(any()))
            .thenReturn(Mono.just(testOrder()));
    }
}
```

### Pact (Consumer-driven)

```java
// Consumer test
@ExtendWith(PactConsumerTestExt.class)
@PactTestFor(providerName = "order-service")
class OrderClientPactTest {

    @Pact(consumer = "payment-service")
    public RequestResponsePact createOrderPact(PactDslWithProvider builder) {
        return builder
            .given("order can be created")
            .uponReceiving("a create order request")
            .method("POST")
            .path("/api/v1/orders")
            .body(new PactDslJsonBody()
                .stringType("customerId", "c-1")
                .minArrayLike("items", 1,
                    new PactDslJsonBody()
                        .stringType("productId", "P1")
                        .integerType("quantity", 1)))
            .willRespondWith()
            .status(201)
            .body(new PactDslJsonBody()
                .stringMatcher("id", "[a-z0-9-]+", "ord-123")
                .stringValue("status", "PENDING"))
            .toPact();
    }

    @Test
    @PactTestFor(pactMethod = "createOrderPact")
    void shouldCreateOrder(MockServer mockServer) {
        var client = new OrderClient(mockServer.getUrl());
        var result = client.createOrder(testRequest());
        assertThat(result.status()).isEqualTo("PENDING");
    }
}
```
