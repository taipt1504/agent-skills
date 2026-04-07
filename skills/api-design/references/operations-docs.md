# API Operations & Documentation Reference

File upload/download, idempotency, bulk operations, and long-running operations.

## Table of Contents
- [File Upload](#file-upload)
- [File Download / Streaming](#file-download--streaming)
- [Idempotency](#idempotency)
- [Bulk Operations](#bulk-operations)
- [Long-Running Operations (Async + Polling)](#long-running-operations-async--polling)

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

Safe to retry — Redis-backed deduplication with 24h TTL. Implement at the service layer to keep the response body fully captured:

```java
// Service-layer idempotency (recommended)
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
POST /api/reports/v1 → 202 Accepted + Location: /api/jobs/v1/{jobId}
GET  /api/jobs/v1/{jobId} → {status: "PROCESSING", progress: 45}
GET  /api/jobs/v1/{jobId} → {status: "DONE", resultUrl: "/api/reports/v1/{id}"}
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
            .header(HttpHeaders.LOCATION, "/api/jobs/v1/" + jobId)
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

For contract testing patterns (Spring Cloud Contract, Pact), see the `testing-workflow` skill.
