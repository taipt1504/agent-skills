---
name: summer-file
description: Summer Framework streaming zip exporter (0.3.5+). Use when a service produces a downloadable archive of rows (statements, ledger reports, audit extracts, settlement files). Provides ZipExporter, ExportSpec, ChunkWriter, DatedExportRow, SizeLimitedOutputStream — replaces per-service ZipOutputStream plumbing with one call. Both Iterable and Flux overloads; built-in PipedInputStream "pipe to uploader" form.
triggers:
  natural: ["zip export", "xlsx export", "streaming export", "summer file", "chunked file export"]
  code: ["ZipExporter", "ExportSpec", "ChunkWriter", "DatedExportRow", "SizeLimitedOutputStream", "io.f8a.summer.file"]
requires: ["summer-core"]
applicability:
  always: false
  triggers:
    files_match: ["**/*FileService*.java", "**/*Upload*.java", "**/*Download*.java"]
    code_patterns: ["io.f8a.summer.file", "f8a.file", "FileStorageService", "PresignedUrlService"]
    task_keywords: ["file upload", "file download", "presigned URL", "S3", "MinIO", "summer file"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 80%+: new file upload/download endpoint OR storage backend integration
  MEDIUM 40-79%: presigned URL generation, file metadata
  LOW 1-39%: service that references file URLs without storage interaction
  ZERO: project lacks io.f8a.summer:summer-file
---

# Summer File — Streaming Zip Exporter

**Gate:** Verify summer-core loaded and `io.f8a.summer:summer-platform` in build.gradle before proceeding.

**Module:** `io.f8a.summer:summer-file` (added 0.3.5)
**Package:** `io.f8a.summer.file.export`
**Activation:** Manual dependency — no Spring auto-config. Pure utility module.

**This SKILL.md tracks LATEST stable (0.3.5).** First shipped in 0.3.5; no overlays for older versions (module did not exist).


## When to reach for it

Any service streaming rows as `.zip` of `.xlsx`/`.csv`/`.json` files. Before 0.3.5 every service had its own `ZipOutputStream` + chunk + size-cap boilerplate; this replaces it with one call.

Skip when export is single small file (write directly) or format is itself an archive (e.g. SQLite dump).

## Public API

| Type | Role |
|---|---|
| `ExportRow` | Marker interface for any row type. |
| `DatedExportRow extends ExportRow` | Sub-interface with `LocalDate date()` — rows are grouped into one zip entry **per date**. |
| `ChunkWriter<R>` | Functional interface — caller owns the per-file format (xlsx, csv, …). The exporter never inspects rows. |
| `ExportSpec<R>` | Lombok `@Builder` config: `baseName`, `fileExtension` (default `.xlsx`), `maxRowsPerFile` (default 100,000), `maxZipSizeBytes` (0 disables), `chunkWriter`. |
| `ZipExporter` | Static `writeZip` / `pipeZip` — both `Iterable<R>` and `Flux<R>` overloads. |
| `SizeLimitedOutputStream` | `FilterOutputStream` that throws `IOException` past `maxBytes`. Used internally; exported for standalone use. |

## Behavior

- **Plain `ExportRow`** → flat output: `<baseName>_<seq><ext>` (`payments_1.xlsx`, `payments_2.xlsx`, …).
- **`DatedExportRow`** → grouped: `<YYYY-MM-DD>_<seq><ext>` (`2026-05-08_1.xlsx`, …). **Rows must arrive contiguous by date** — new group emitted when `date()` changes.
- `maxRowsPerFile` caps any single file. Past cap, new entry opens with next sequence suffix.
- `maxZipSizeBytes > 0` wraps output in `SizeLimitedOutputStream`, aborts with `IOException` on overflow.
- **Empty input** still emits exactly one entry (chunk writer invoked with empty list) — zip always has ≥1 file.

## Threading

- `writeZip` iterates on calling thread and may block (POI workbook serialization is synchronous).
- `Flux<R>` overload bridges via `Flux.toIterable()` — **must** run on blocking-capable scheduler (`Schedulers.boundedElastic()` or dedicated executor). Never call on Reactor event-loop thread.
- `pipeZip` schedules writer for you — preferred when downstream is an uploader.

## Stream-to-uploader pattern (`pipeZip`)

Standard "stream → upload" path without temp file or in-memory buffer. Returns `PipedInputStream` to hand to storage client.

```java
PipedInputStream in = ZipExporter.pipeZip(
    repo.streamAll(filter),                // Flux<R> — the R2DBC case
    spec,
    r -> Schedulers.boundedElastic().schedule(r));

storage.upload(bucket, key, in);
```

On completion, writer closes `PipedOutputStream`, reader sees EOF, upload finishes. If writer throws, `PipedInputStream` closes too — blocked reader unblocks with `"Pipe closed"` `IOException`.

## Minimal example — flat xlsx export

```java
record TxnRow(String id, BigDecimal amount, Instant at) implements ExportRow {}

ChunkWriter<TxnRow> xlsxWriter = (rows, out) -> {
  try (Workbook wb = new SXSSFWorkbook(100)) {
    Sheet sheet = wb.createSheet("transactions");
    int r = 0;
    Row header = sheet.createRow(r++);
    header.createCell(0).setCellValue("id");
    header.createCell(1).setCellValue("amount");
    header.createCell(2).setCellValue("at");
    for (TxnRow row : rows) {
      Row xr = sheet.createRow(r++);
      xr.createCell(0).setCellValue(row.id());
      xr.createCell(1).setCellValue(row.amount().doubleValue());
      xr.createCell(2).setCellValue(row.at().toString());
    }
    wb.write(out);     // exporter owns `out` — DO NOT close it
  }
};

ExportSpec<TxnRow> spec = ExportSpec.<TxnRow>builder()
    .baseName("transactions")
    .maxRowsPerFile(50_000)
    .maxZipSizeBytes(50L * 1024 * 1024)
    .chunkWriter(xlsxWriter)
    .build();

ZipExporter.writeZip(rows, out, spec);
```

## Date-grouped variant

Implement `DatedExportRow`, leave `baseName` unset. Output: `2026-05-07_1.xlsx`, `2026-05-08_1.xlsx`, `2026-05-08_2.xlsx`, …

```java
record DailyRow(LocalDate date, ...) implements DatedExportRow {
  @Override public LocalDate date() { return date; }
}
```

Rows must arrive in date order. For R2DBC, add `ORDER BY <date_col>, <id>` to query.

## Gradle

```gradle
implementation 'io.f8a.summer:summer-file'
```

No auto-config; small utility jar. Apache POI / OpenCSV (or whatever `ChunkWriter` uses) must be in service dependencies.

## Rules

- **Never close `OutputStream` inside `ChunkWriter`** — exporter owns lifecycle. Early close truncates zip.
- Pick `maxRowsPerFile` per downstream tool limits. Excel chokes past ~1M rows; many email systems cap at 25 MB.
- For `Flux` inputs always use blocking-capable scheduler. Event-loop threads must not block.
- Date-grouped exports must receive rows pre-sorted by `date()`. Exporter splits on changes, does not sort.
- `maxZipSizeBytes = 0` = no cap (explicit opt-out). Production exports of unknown size SHOULD set concrete cap — fail loud rather than fill disk/PVC.

## References

- **[references/versions/0.3.5.md](references/versions/0.3.5.md)** — Initial release notes (this is when the module shipped).
- **[references/export-examples.md](references/export-examples.md)** — End-to-end recipes: R2DBC → uploader; date-grouped statements; CSV writer variant.

For the full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Related Skills

- **summer-core** — Gate; `Txid` for transaction IDs printed inside the rows.
- **summer-data** — Source `Flux<R>` typically comes from R2DBC repositories.
