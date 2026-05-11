# `summer-file` — Recipes

## 1. R2DBC stream → object-storage upload

The most common pattern in the eWallet platform. The repository streams rows as `Flux<R>`; `pipeZip` hands you a `PipedInputStream` you forward to the uploader.

```java
@Service
@RequiredArgsConstructor
public class StatementExportService {

  private final StatementRepository repo;
  private final ObjectStorage storage;     // your S3/GCS/MinIO wrapper

  public Mono<String> exportStatement(StatementFilter filter, String bucket, String key) {
    Flux<StatementRow> rows = repo.streamByFilter(filter)
        .sort(Comparator.comparing(StatementRow::date)
            .thenComparing(StatementRow::id));   // date-grouped requires ordered input

    ExportSpec<StatementRow> spec = ExportSpec.<StatementRow>builder()
        .fileExtension(".xlsx")
        .maxRowsPerFile(50_000)
        .maxZipSizeBytes(50L * 1024 * 1024)
        .chunkWriter(StatementXlsxWriter::write)
        .build();

    return Mono.fromCallable(() -> ZipExporter.pipeZip(
            rows, spec,
            r -> Schedulers.boundedElastic().schedule(r)))
        .flatMap(in -> storage.upload(bucket, key, in))
        .subscribeOn(Schedulers.boundedElastic())
        .thenReturn(key);
  }
}
```

`StatementRow` implements `DatedExportRow` — the zip emits one xlsx per business date.

## 2. Date-grouped daily report

```java
public record DailyReportRow(LocalDate date, String account, BigDecimal balance)
    implements DatedExportRow {
  @Override public LocalDate date() { return date; }
}
```

Output (sorted by `date`):
```
2026-05-08_1.xlsx
2026-05-09_1.xlsx
2026-05-09_2.xlsx   // crossed maxRowsPerFile mid-day
2026-05-10_1.xlsx
```

## 3. CSV writer instead of xlsx

```java
ChunkWriter<TxnRow> csvWriter = (rows, out) -> {
  try (var w = new BufferedWriter(new OutputStreamWriter(out, UTF_8))) {
    w.write("id,amount,at\n");
    for (TxnRow r : rows) {
      w.write(r.id() + "," + r.amount() + "," + r.at() + "\n");
    }
    w.flush();           // do NOT close out — exporter owns its lifecycle
  }
};

ExportSpec<TxnRow> spec = ExportSpec.<TxnRow>builder()
    .baseName("transactions")
    .fileExtension(".csv")
    .chunkWriter(csvWriter)
    .build();
```

## 4. Standalone `SizeLimitedOutputStream`

Use directly when you want a size cap on a non-zip stream (e.g. capped log/audit dump):

```java
try (var capped = new SizeLimitedOutputStream(rawOut, 25L * 1024 * 1024)) {
  writeAudit(capped);
} catch (IOException e) {
  // "Size limit exceeded: 25000000 bytes" — propagate to the caller.
}
```

## 5. Empty result still produces a zip

By design — the resulting zip carries one entry with whatever the `ChunkWriter` emits for an empty list (typically the header row). This avoids consumers needing to special-case "no data":

```java
ZipExporter.writeZip(List.of(), out, spec);   // zip with one xlsx, header only
```

## Gotchas

- **Never close the `OutputStream` from inside the `ChunkWriter`.** The exporter wraps it (`SizeLimitedOutputStream`, ZIP entry) and needs to close those wrappers itself when the entry completes. Closing early truncates the zip.
- **`DatedExportRow` requires ordered input.** The exporter splits on `date()` changes — out-of-order rows produce duplicate `<date>_N.xlsx` entries within the same zip and crash `ZipOutputStream` ("duplicate entry: 2026-05-08_1.xlsx").
- **Reactor schedulers.** `pipeZip` already schedules onto the executor you pass; `writeZip(Flux, ...)` does not. If you call the `Flux` form of `writeZip` directly from a webflux handler, wrap it in `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`.
- **Streaming repositories must commit-read.** Long-running `Flux` queries hold a DB cursor. For PostgreSQL R2DBC make sure the connection is wrapped in a read-only transaction so the cursor stays valid across the upload.
