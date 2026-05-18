---
name: summer-payment-sdk
description: Summer Framework payment-sdk — shared event DTOs, payment domain enums, Ufid/Txid prefix annotations (@JE/@TX/@SE/@Compact/@UfidPrefix/@UInt128), and the producer-routing vocabulary (Direction/ProducerId/ProducerSpec) used by Payment Service + Core-Ledger. Use when serializing or consuming events on ledger.transfer.posted, bank.notify.*, party.*, va.*, wallet.* topics, when defining Ufid-typed event fields with prefix annotations, or when materializing the producer-routing YAML.
triggers:
  natural: ["payment sdk", "ledger transfer event", "producer routing", "event subpackages", "ufid prefix annotation", "txid event field"]
  code: ["LedgerTransferEvent", "EntriesPostedEvent", "EntriesRejectedEvent", "PostEntriesCommand", "ProducerId", "ProducerSpec", "ProducerStatus", "Direction", "YamlHash", "@JE", "@TX", "@SE", "@Compact", "@UfidPrefix", "@UInt128", "LedgerOperation", "TransactionType"]
requires: ["summer-core"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Payment*.java"]
    code_patterns: ["io.f8a.summer.payment", "f8a.payment", "PaymentClient", "PaymentProvider"]
    task_keywords: ["payment", "summer payment", "VNPay", "Momo", "ZaloPay", "payment provider"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: payment flow integration OR new provider OR signature/verification logic
  MEDIUM 40-79%: payment status update or webhook handler
  LOW 1-39%: order code touches paymentId without provider interaction
  ZERO: project lacks io.f8a.summer:summer-payment
---

# Summer Payment SDK — Shared Event DTOs & Prefix Annotations

**Gate:** Verify summer-core loaded and `io.f8a.summer:summer-platform` in build.gradle.

**Module:** `io.f8a.summer:summer-payment-sdk` (added 0.2.5)
**Package roots:** `io.f8a.summer.payment.{annotation, domain, event, serialize}`
**Versioning:** **Independently versioned.** `summer-platform` BOM pins `paymentSdkVersion` per Summer release (since 0.3.3 via explicit coordinates); consumers can override independently. Current: `paymentSdkVersion=0.3.4` (paired with `summer-platform:0.3.5`).
**Activation:** Manual dependency; no Spring auto-config. Jackson registers Ufid/Txid deserializers through `summer-core` and `summer-data-r2dbc`.

**Tracks LATEST stable (payment-sdk 0.3.4, paired with `summer-platform:0.3.5`).** Older versions: load matching overlay from [references/versions/](references/versions/).

## Why it exists

Every service publishing or consuming `ledger.transfer.posted`, `bank.notify.transaction`, `party.*`, `va.*`, or `wallet.*` events needs the same DTOs and enums. `summer-payment-sdk` is the shared wire-contract jar — bump it once to propagate record types and JSON shape to all consumers.

## Public API

### Event DTOs (`io.f8a.summer.payment.event.*`)

| Sub-package | Events |
|---|---|
| `event.ledger` | `LedgerTransferEvent`, `EntriesPostedEvent`, `EntriesRejectedEvent`, `PostEntriesCommand`, `LedgerEventType`, `SagaRejectionCode` |
| `event.bank` | `BankNotifyTransaction*` and related |
| `event.party` | Party (customer/account) lifecycle |
| `event.va` | Virtual-account events |
| `event.wallet` | Wallet lifecycle / status |

**Subpackages added in 0.2.9** — pre-0.2.9 events were flat in `io.f8a.summer.payment.event.*`. Imports must reflect subpackage; see [versions/0.2.9.md](references/versions/0.2.9.md).

### Domain enums (`io.f8a.summer.payment.domain.*`)

`LedgerAccountCodes`, `LedgerAccountType`, `LedgerEntryDirection`, `LedgerOperation` (POST / VOID / REVERSE — `CAPTURE` renamed `POST` in 0.2.6), `TransactionChannel`, `TransactionStatus`, `TransactionType`. **Single source of truth** — never redefine per-service.

### Prefix annotations (`io.f8a.summer.payment.annotation.*`)

Used on `Ufid`-typed fields to control Jackson serialization. Apply to event DTOs and service-side records needing same display style on wire.

| Annotation | Output format | Used for |
|---|---|---|
| `@JE` | `JE_<Crockford-Base32>` (28 chars total) | Journal entries |
| `@TX` | `TX_<Crockford-Base32>` (28 chars) | Transfers / transactions (replaces `@TXN`, removed in 0.2.6) |
| `@SE` | `SE_<Crockford-Base32>` (28 chars) | Saga executions |
| `@Compact` | 26-char Crockford Base32, no prefix | Generic compact IDs (replaces `@Hex`, removed in 0.2.6) |
| `@UfidPrefix("XX")` | `XX_<Crockford-Base32>` — custom prefix; meta-annotatable to define new aliases | Service-specific Ufid kinds |
| `@UInt128` | Unsigned 128-bit decimal string (no prefix) | TigerBeetle / `BigInteger` interop |

Display format: **hex → Crockford Base32 in 0.2.6**. `@Hex` and `@TXN` removed in 0.2.6. **`@Link` removed in 0.3.3** — use `@Compact`; replace `@Link` with `@Compact` on field and update string-side parsing expecting `LINK_`.

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

Six types under `io.f8a.summer.payment.domain.producer.*` shared between Payment Service and Core-Ledger — both materialize same routing YAML byte-identically:

| Type | Role |
|---|---|
| `Direction` (enum) | `TOPUP, WITHDRAW, TRANSFER, REFUND, CREDIT, DEBIT, FEE` — each carries its TigerBeetle transfer code, aligned with `TransactionType` codes |
| `ProducerId` (record) | `parse(String)` enforces `<channel>.<partner>.<direction>.v<N>` (external) or `internal.<flow>.<variant>.v<N>` (internal); exposes `channel()`, `partner()`, `version()`, `isInternal()` |
| `ProducerStatus` (enum) | `ACTIVE, DEPRECATED, SUNSET, ORPHANED, EMERGENCY_DISABLED` |
| `ProducerSpec` (record) | Jackson-deserialized canonical YAML row; `@JsonIgnoreProperties(ignoreUnknown = true)` lets each service ignore blocks it doesn't consume |
| `YamlHash` | SHA-256 over YAML bytes; both services hash byte-identically — used to verify both sides loaded the same revision |
| `ProducerEventFields` (constants) | `PRODUCER_ID`, `FEE_PRODUCER_ID` — wire-side field names so producer / consumer never disagree |

### Transfer ids are `Txid` since 0.3.4 (BREAKING)

`LedgerTransferEvent.Transfer.id` and `pendingId` are now `Txid` (was `Ufid`). Every consumer of `ledger.transfer.posted` **must** be on payment-sdk `0.3.4`+ to deserialize. Wire JSON is 18-digit zero-padded decimal from `Txid.toJsonValue()`, **not** UUID.

`Account.id` stays `Ufid` — TigerBeetle accounts may predate Txid cutoff and aren't all from `TxidGenerator`.

Conversion at the TigerBeetle CDC boundary:
```java
Txid txid = Txid.fromUUID(ufid.toUUID());   // throws if upper 8 bytes != 0
// or
Txid txid = Txid.from16Bytes(raw128);       // same guard
```

Guard throws when upper half is non-zero — transfer wasn't from `TxidGenerator`; surface immediately rather than silently truncate.

## Gradle

```gradle
// Use whatever paymentSdkVersion the platform BOM pins; the BOM is authoritative.
implementation 'io.f8a.summer:summer-payment-sdk'
```

BOM pins `summer-payment-sdk` via explicit coordinates since 0.3.3 — `summer-platform:0.3.5` brings `payment-sdk:0.3.4` transitively. Override **only** when adopting newer payment-sdk before platform catches up.

## Version Notes

Headline only — full detail: load matching overlay. **Payment-SDK uses own version axis** (`paymentSdkVersion` in `gradle.properties`) — these are payment-sdk versions, not platform versions.

- **0.3.4** — `LedgerTransferEvent.Transfer.{id, pendingId}` → `Txid` (BREAKING). [→](references/versions/0.3.4.md)
- **0.3.3** — `@Link` removed (use `@Compact`); producer-routing vocabulary added. [→](references/versions/0.3.3.md)
- **0.3.1** — minor; `@Link` existed briefly, removed in 0.3.3.
- **0.2.9** — events split into subpackages `event.{ledger,bank,party,va,wallet}` (BREAKING imports); `CustomerInfoEvent` expanded. [→](references/versions/0.2.9.md)
- **0.2.8** — `Ufid.toBase32()` / `fromBase32()` / `fromUInt128()`; `@JsonCreator` accepts UUID/Base32/display; `UfidUInt128Deserializer`. [→](references/versions/0.2.8.md)
- **0.2.6** — `@TXN`→`@TX`, `@Hex`→`@Compact` (BREAKING); `LedgerOperation.CAPTURE`→`POST`. [→](references/versions/0.2.6.md)
- **0.2.5** — module introduced; `@JE`, `@TXN`, `@SE`, `@UfidPrefix`, `@Hex`; payment domain enums. [→](references/versions/0.2.5.md)

For full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Rules

- **Never redefine** `LedgerOperation` / `TransactionType` / `TransactionChannel` / `LedgerAccountType` / `LedgerEntryDirection` per-service — drift means events won't deserialize on consumer side.
- **Never use `@Hex`, `@TXN`, or `@Link`** — removed in 0.2.6 (`@Hex` / `@TXN`) and 0.3.3 (`@Link`). Use `@Compact` / `@TX` / `@Compact`.
- **`Account.id` is `Ufid`, transfer ids are `Txid`** (since 0.3.4). Don't conflate.
- **Wire JSON for `Txid` is 18-digit zero-padded decimal**, not UUID. Legacy UUID consumers fail loudly — bump to payment-sdk 0.3.4+.
- **Platform BOM is authoritative** for `paymentSdkVersion`. Override only when intentionally adopting newer payment-sdk ahead of platform bump.
- **Producer-routing YAML hashing** (`YamlHash`) must match byte-identically between Payment Service and Core-Ledger. Pin same `paymentSdkVersion` to avoid hash mismatches at boot.

## References

- **[references/event-types.md](references/event-types.md)** — Map of every event DTO, topic, and which fields are `Ufid` vs `Txid`.
- **[references/versions/](references/versions/)** — Per-version overlays (0.2.5 → 0.3.4).

## Related Skills

- **summer-core** — `Ufid` and `Txid` types, `@TxidConverter`, `MachineIdResolver`.
- **summer-data** — R2DBC `UfidConverter` / `TxidConverter` / `TxidUuidConverter` (auto-registered).
- **summer-kafka** — consumers apply LSN-watermark idempotency via `OutboxConsumerIdempotency`.
- **summer-rest** — controllers hand-craft event payloads via `OutboxService.saveEvent`.
