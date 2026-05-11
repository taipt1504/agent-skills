---
name: summer-payment-sdk
description: Summer Framework payment-sdk — shared event DTOs, payment domain enums, Ufid/Txid prefix annotations (@JE/@TX/@SE/@Compact/@UfidPrefix/@UInt128), and the producer-routing vocabulary (Direction/ProducerId/ProducerSpec) used by Payment Service + Core-Ledger. Use when serializing or consuming events on ledger.transfer.posted, bank.notify.*, party.*, va.*, wallet.* topics, when defining Ufid-typed event fields with prefix annotations, or when materializing the producer-routing YAML.
triggers:
  natural: ["payment sdk", "ledger transfer event", "producer routing", "event subpackages", "ufid prefix annotation", "txid event field"]
  code: ["LedgerTransferEvent", "EntriesPostedEvent", "EntriesRejectedEvent", "PostEntriesCommand", "ProducerId", "ProducerSpec", "ProducerStatus", "Direction", "YamlHash", "@JE", "@TX", "@SE", "@Compact", "@UfidPrefix", "@UInt128", "LedgerOperation", "TransactionType"]
requires: ["summer-core"]
---

# Summer Payment SDK — Shared Event DTOs & Prefix Annotations

**Gate:** Verify summer-core is loaded and `io.f8a.summer:summer-platform` is in build.gradle before proceeding.

**Module:** `io.f8a.summer:summer-payment-sdk` (added 0.2.5)
**Package roots:** `io.f8a.summer.payment.{annotation, domain, event, serialize}`
**Versioning:** **Independently versioned.** The `summer-platform` BOM pins a known-good `paymentSdkVersion` per Summer release (since 0.3.3 via explicit coordinates), but consumers can override to a newer payment-sdk independently. The current top-level Gradle property is `paymentSdkVersion=0.3.4` (paired with `summer-platform:0.3.5`).
**Activation:** Manual dependency; no Spring auto-config in this module. Jackson registers the Ufid/Txid deserializers through `summer-core` and `summer-data-r2dbc`.

**This SKILL.md tracks LATEST stable (payment-sdk 0.3.4, paired with `summer-platform:0.3.5`).** For older versions load the matching overlay from [references/versions/](references/versions/).

## Why it exists

Every service that publishes or consumes `ledger.transfer.posted`, `bank.notify.transaction`, `party.*`, `va.*`, or `wallet.*` events needs the same DTOs and the same `LedgerOperation` / `TransactionType` / `TransactionChannel` enums. `summer-payment-sdk` is the shared wire-contract jar — bumping it once propagates the same record types and the same JSON shape to every consumer.

## Public API

### Event DTOs (`io.f8a.summer.payment.event.*`)

| Sub-package | Events |
|---|---|
| `event.ledger` | `LedgerTransferEvent`, `EntriesPostedEvent`, `EntriesRejectedEvent`, `PostEntriesCommand`, `LedgerEventType`, `SagaRejectionCode` |
| `event.bank` | `BankNotifyTransaction*` and related |
| `event.party` | Party (customer/account) lifecycle |
| `event.va` | Virtual-account events |
| `event.wallet` | Wallet lifecycle / status |

**The subpackages came in 0.2.9** — pre-0.2.9 every event lived flat in `io.f8a.summer.payment.event.*`. Imports must reflect the subpackage; see [versions/0.2.9.md](references/versions/0.2.9.md).

### Domain enums (`io.f8a.summer.payment.domain.*`)

`LedgerAccountCodes`, `LedgerAccountType`, `LedgerEntryDirection`, `LedgerOperation` (POST / VOID / REVERSE — `CAPTURE` was renamed `POST` in 0.2.6), `TransactionChannel`, `TransactionStatus`, `TransactionType`. **Single source of truth** for these enums across the platform — never redefine them per-service.

### Prefix annotations (`io.f8a.summer.payment.annotation.*`)

Used on `Ufid`-typed fields to control Jackson serialization. All apply to event DTOs and any service-side record that wants the same display style on the wire.

| Annotation | Output format | Used for |
|---|---|---|
| `@JE` | `JE_<Crockford-Base32>` (28 chars total) | Journal entries |
| `@TX` | `TX_<Crockford-Base32>` (28 chars) | Transfers / transactions (replaces `@TXN`, removed in 0.2.6) |
| `@SE` | `SE_<Crockford-Base32>` (28 chars) | Saga executions |
| `@Compact` | 26-char Crockford Base32, no prefix | Generic compact IDs (replaces `@Hex`, removed in 0.2.6) |
| `@UfidPrefix("XX")` | `XX_<Crockford-Base32>` — custom prefix; meta-annotatable to define new aliases | Service-specific Ufid kinds |
| `@UInt128` | Unsigned 128-bit decimal string (no prefix) | TigerBeetle / `BigInteger` interop |

Display format switched **hex → Crockford Base32 in 0.2.6**. `@Hex` and `@TXN` are gone since 0.2.6. **`@Link` was removed in 0.3.3** — use `@Compact` instead; the `LINK_` prefix discriminator is no longer carried as a separate annotation (replace `@Link` with `@Compact` on the field and update string-side parsing that expected `LINK_`).

```java
public record LedgerTransferRequest(
    @TX Ufid transferId,
    @JE Ufid journalEntryId,
    @Compact Ufid linkedTransferId,    // was @Link Ufid — pre-0.3.3
    @UfidPrefix("WAL") Ufid walletId,
    LedgerOperation operation,
    BigDecimal amount,
    Instant occurredAt) {}
```

### Producer-routing vocabulary (0.3.3+)

Six types under `io.f8a.summer.payment.domain.producer.*` shared between Payment Service and Core-Ledger so both materialize the same routing YAML byte-identically:

| Type | Role |
|---|---|
| `Direction` (enum) | `TOPUP, WITHDRAW, TRANSFER, REFUND, CREDIT, DEBIT, FEE` — each carries its TigerBeetle transfer code, aligned with `TransactionType` codes |
| `ProducerId` (record) | `parse(String)` enforces `<channel>.<partner>.<direction>.v<N>` (external) or `internal.<flow>.<variant>.v<N>` (internal); exposes `channel()`, `partner()`, `version()`, `isInternal()` |
| `ProducerStatus` (enum) | `ACTIVE, DEPRECATED, SUNSET, ORPHANED, EMERGENCY_DISABLED` |
| `ProducerSpec` (record) | Jackson-deserialized canonical YAML row; `@JsonIgnoreProperties(ignoreUnknown = true)` lets each service ignore blocks it doesn't consume |
| `YamlHash` | SHA-256 over YAML bytes; both services hash byte-identically — used to verify both sides loaded the same revision |
| `ProducerEventFields` (constants) | `PRODUCER_ID`, `FEE_PRODUCER_ID` — wire-side field names so producer / consumer never disagree |

### Transfer ids are `Txid` since 0.3.4 (BREAKING)

`LedgerTransferEvent.Transfer.id` and `pendingId` are now `Txid` (was `Ufid`). Every consumer of `ledger.transfer.posted` (and friends) **must** be on payment-sdk `0.3.4`+ to deserialize the new format. The wire JSON is the 18-digit zero-padded decimal string from `Txid.toJsonValue()`, **not** a UUID.

`Account.id` stays `Ufid` — TigerBeetle accounts can predate the Txid cutoff and aren't all generated by `TxidGenerator`.

Conversion at the TigerBeetle CDC boundary:
```java
Txid txid = Txid.fromUUID(ufid.toUUID());   // throws if upper 8 bytes != 0
// or
Txid txid = Txid.from16Bytes(raw128);       // same guard
```

The guard intentionally throws when the upper half is non-zero — that means the transfer wasn't generated by `TxidGenerator` and is a bug worth surfacing immediately rather than silently truncating.

## Gradle

```gradle
// Use whatever paymentSdkVersion the platform BOM pins; the BOM is authoritative.
implementation 'io.f8a.summer:summer-payment-sdk'
```

The BOM pins `summer-payment-sdk` via explicit coordinates (`io.f8a.summer:summer-payment-sdk:${paymentSdkVersion}`) since 0.3.3, so `summer-platform:0.3.5` brings `payment-sdk:0.3.4` transitively. Override **only** when adopting a newer payment-sdk before the platform catches up.

## Version Notes

Headline only — load the matching overlay for full per-version detail. **Payment-SDK uses its own version axis** (`paymentSdkVersion` in upstream `gradle.properties`), so these are payment-sdk versions not platform versions.

- **0.3.4** (paired with summer-platform 0.3.5) — `LedgerTransferEvent.Transfer.{id, pendingId}` is now `Txid` (BREAKING). See [versions/0.3.4.md](references/versions/0.3.4.md).
- **0.3.3** (paired with summer-platform 0.3.3) — `@Link` removed (use `@Compact`); producer-routing vocabulary added (`Direction`, `ProducerId`, `ProducerSpec`, etc.). See [versions/0.3.3.md](references/versions/0.3.3.md).
- **0.3.1** — (covered in matrix; minor — `@Link` annotation existed briefly, removed again in 0.3.3).
- **0.2.9** — event classes split into domain subpackages: `event.ledger`, `event.bank`, `event.party`, `event.va`, `event.wallet` (BREAKING imports); `CustomerInfoEvent` / `CustomerInfoEventType` expanded. See [versions/0.2.9.md](references/versions/0.2.9.md).
- **0.2.8** — `Ufid.toBase32()` / `fromBase32()` / `fromUInt128()`; default `@JsonCreator` accepts UUID/Base32/display; `UfidUInt128Deserializer`. See [versions/0.2.8.md](references/versions/0.2.8.md).
- **0.2.6** — annotation renames `@TXN`→`@TX`, `@Hex`→`@Compact` (BREAKING); `LedgerOperation.CAPTURE`→`POST`. See [versions/0.2.6.md](references/versions/0.2.6.md).
- **0.2.5** — module introduced; `@JE`, `@TXN`, `@SE`, `@UfidPrefix`, `@Hex` annotations (pre-rename names); shared payment domain enums. See [versions/0.2.5.md](references/versions/0.2.5.md).

For the full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Rules

- **Never redefine** `LedgerOperation` / `TransactionType` / `TransactionChannel` / `LedgerAccountType` / `LedgerEntryDirection` per-service. They live in `summer-payment-sdk` for a reason — drift here means events that won't deserialize on the consumer side.
- **Never use `@Hex`, `@TXN`, or `@Link`** in new code. They were removed in 0.2.6 (`@Hex` / `@TXN`) and 0.3.3 (`@Link`). Use `@Compact` / `@TX` / `@Compact` respectively.
- **`Account.id` is `Ufid`, transfer ids are `Txid`** in event payloads (since 0.3.4). Don't conflate the two.
- **Wire JSON for `Txid` is 18-digit zero-padded decimal**, not UUID. Consumers parsing legacy UUID transfer ids will fail loudly — bump payment-sdk to 0.3.4+.
- **The platform BOM is authoritative** for `paymentSdkVersion`. Override only when intentionally adopting a newer payment-sdk ahead of the next platform bump.
- **Producer-routing YAML hashing** (`YamlHash`) must match byte-identically between Payment Service and Core-Ledger. Both services should pin the same `paymentSdkVersion` to avoid hash mismatches at boot.

## References

- **[references/event-types.md](references/event-types.md)** — Detailed map of every event DTO, the topic it rides on, and which fields are `Ufid` vs `Txid`.
- **[references/versions/](references/versions/)** — Per-version overlays (0.2.5 → 0.3.4).

## Related Skills

- **summer-core** — `Ufid` and `Txid` value types, `@TxidConverter`, `MachineIdResolver`.
- **summer-data** — R2DBC `UfidConverter` / `TxidConverter` / `TxidUuidConverter` (auto-registered).
- **summer-kafka** — consumers of these events apply LSN-watermark idempotency via `OutboxConsumerIdempotency`.
- **summer-rest** — controllers that hand-craft event payloads via `OutboxService.saveEvent`.
