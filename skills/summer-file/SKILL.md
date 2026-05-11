---
name: summer-file
description: Summer Framework streaming zip exporter (0.3.5+). Use when a service produces a downloadable archive of rows (statements, ledger reports, audit extracts, settlement files). Provides ZipExporter, ExportSpec, ChunkWriter, DatedExportRow, SizeLimitedOutputStream — replaces per-service ZipOutputStream plumbing with one call. Both Iterable and Flux overloads; built-in PipedInputStream "pipe to uploader" form.
triggers:
  natural: ["zip export", "xlsx export", "streaming export", "summer file", "chunked file export"]
  code: ["ZipExporter", "ExportSpec", "ChunkWriter", "DatedExportRow", "SizeLimitedOutputStream", "io.f8a.summer.file"]
requires: ["summer-core"]
---

# Summer File — Streaming Zip Exporter

**Gate:** Verify summer-core is loaded and `io.f8a.summer:summer-platform` is in build.gradle before proceeding.

**Module:** `io.f8a.summer:summer-file` (added 0.3.5)
**Package:** `io.f8a.summer.file.export`
**Activation:** Manual dependency — no Spring auto-config. Pure utility module.

**This SKILL.md tracks LATEST stable (0.3.5).** First shipped in 0.3.5; no overlays for older versions (module did not exist).

## When to reach for it

Any service that streams rows out as `.zip` of `.xlsx`/`.csv`/`.json` files. Before 0.3.5 every service grew its own `ZipOutputStream` + per-file chunk + size-cap code; replace that boilerplate with one call.

Skip it when the export is a single small file (just write the file directly) or when the format is itself an archive (e.g. SQLite dump).

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
- **`DatedExportRow`** → grouped output: `<YYYY-MM-DD>_<seq><ext>` (`2026-05-08_1.xlsx`, `2026-05-08_2.xlsx`, …). **Rows must arrive contiguous by date** — the exporter emits a new group as soon as `date()` changes.
- `maxRowsPerFile` caps any single inside-file. Past the cap, a new entry opens with the next sequence suffix.
- `maxZipSizeBytes > 0` wraps the output in a `SizeLimitedOutputStream` and aborts with `IOException` on overflow.
- An **empty input** still emits exactly one entry (the chunk writer is invoked with an empty list) — the resulting zip always has at least one file, typically the header row.

## Threading

- `writeZip` iterates on the calling thread and may block (POI workbook serialization is synchronous).
- The `Flux<R>` overload bridges internally via `Flux.toIterable()` and **must** run on a blocking-capable scheduler (`Schedulers.boundedElastic()` or a dedicated executor). Never call it on a Reactor event-loop thread.
- `pipeZip` schedules the writer for you — preferred whenever the downstream is an uploader.

## Stream-to-uploader pattern (`pipeZip`)

The standard "stream → upload" path without a temp file or in-memory buffer. Returns a `PipedInputStream` you hand to your storage client.

```java
PipedInputStream in = ZipExporter.pipeZip(
    repo.streamAll(filter),                // Flux<R> — the R2DBC case
    spec,
    r -> Schedulers.boundedElastic().schedule(r));

storage.upload(bucket, key, in);
```

On clean completion the writer closes its `PipedOutputStream`, the reader sees EOF, and the upload finishes. If the writer throws, the `PipedInputStream` is closed too so a blocked reader unblocks with `"Pipe closed"` `IOException` and the failure propagates.

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

Implement `DatedExportRow` and leave `baseName` unset. Output becomes `2026-05-07_1.xlsx`, `2026-05-08_1.xlsx`, `2026-05-08_2.xlsx`, …

```java
record DailyRow(LocalDate date, ...) implements DatedExportRow {
  @Override public LocalDate date() { return date; }
}
```

Order requirement: rows must come out of the source in date order. For R2DBC, add `ORDER BY <date_col>, <id>` to the query.

## Gradle

```gradle
implementation 'io.f8a.summer:summer-file'
```

No auto-config; the module is a small utility jar. Apache POI / OpenCSV (or whatever your `ChunkWriter` uses) must be brought in by the service.

## Rules

- **Never close the `OutputStream` from inside a `ChunkWriter`** — the exporter owns its lifecycle. Closing it early truncates the zip.
- Pick `maxRowsPerFile` based on what downstream tools can open. Excel chokes past ~1M rows; many email systems cap attachments at 25 MB.
- For `Flux` inputs always pick a blocking-capable scheduler. Reactor event-loop threads must not block.
- Date-grouped exports must receive rows pre-sorted by `date()`. The exporter does not sort; it splits on changes.
- Treat `maxZipSizeBytes = 0` as "no cap" (the explicit opt-out), but production exports of unknown size should pick a concrete cap to fail loud rather than fill a disk or PVC.

## References

- **[references/versions/0.3.5.md](references/versions/0.3.5.md)** — Initial release notes (this is when the module shipped).
- **[references/export-examples.md](references/export-examples.md)** — End-to-end recipes: R2DBC → uploader; date-grouped statements; CSV writer variant.

For the full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Related Skills

- **summer-core** — Gate; `Txid` for transaction IDs printed inside the rows.
- **summer-data** — Source `Flux<R>` typically comes from R2DBC repositories.
