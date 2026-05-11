# `summer-payment-sdk` — Event Type Map

The wire contract for events crossing service boundaries on the eWallet platform. Every entry below is shipped from `io.f8a.summer:summer-payment-sdk`. Field-level `Ufid` / `Txid` columns reflect payment-sdk 0.3.4 (paired with `summer-platform:0.3.5`).

## Ledger (`io.f8a.summer.payment.event.ledger`)

| DTO | Direction | Topic | Notable fields | Id type |
|---|---|---|---|---|
| `LedgerTransferEvent` | core-ledger → consumers | `ledger.transfer.posted` (and `.voided`, `.reversed`) | `transfer.id`, `transfer.pendingId`, `transfer.amount`, `transfer.code`, `accounts.debit`, `accounts.credit` | `Txid` (id, pendingId, 0.3.4+); `Ufid` (Account.id) |
| `EntriesPostedEvent` | core-ledger → consumers | `ledger.entries.posted` | `journalEntryId`, `transferId`, `entries[]` | `@JE Ufid`, `@TX Ufid`/`Txid` |
| `EntriesRejectedEvent` | core-ledger → consumers | `ledger.entries.rejected` | `journalEntryId`, `code` (`SagaRejectionCode`), `reason` | `@JE Ufid` |
| `PostEntriesCommand` | producer → core-ledger | `ledger.entries.post` | `journalEntryId`, `entries[]`, `producerId` | `@JE Ufid` |
| `LedgerEventType` (enum) | discriminator | n/a | `POSTED, VOIDED, REVERSED, REJECTED` | — |
| `SagaRejectionCode` (enum) | embedded | n/a | `INSUFFICIENT_BALANCE, ACCOUNT_NOT_FOUND, …` | — |

## Bank (`io.f8a.summer.payment.event.bank`)

| DTO | Direction | Topic | Notable fields | Id type |
|---|---|---|---|---|
| `BankNotifyTransaction` (and sub-types) | bank-ms → orchestrator/wallet | `bank.notify.transaction` | `bankTxId`, `requestId`, `status`, `amount` | service-local |

## Party (`io.f8a.summer.payment.event.party`)

| DTO | Direction | Topic | Notable fields | Id type |
|---|---|---|---|---|
| `CustomerInfoEvent` | party → consumers | `party.customer.info` | `customerId`, `kind` (`CustomerInfoEventType`), `payload` | `Ufid` |
| `CustomerInfoEventType` (enum) | discriminator | n/a | `CREATED, KYC_UPGRADED, BLOCKED, …` | — |

## VA — Virtual Account (`io.f8a.summer.payment.event.va`)

Virtual-account lifecycle: creation, activation, suspension, closure. Topic patterns vary by service consumption.

## Wallet (`io.f8a.summer.payment.event.wallet`)

Wallet lifecycle and status; topics consumed primarily by reporting and AML.

## Domain enums (`io.f8a.summer.payment.domain`)

Cross-event vocabulary; **never** redefine per-service:

| Enum | Values |
|---|---|
| `LedgerOperation` | `POST, VOID, REVERSE` (note: `CAPTURE` was renamed `POST` in 0.2.6) |
| `LedgerEntryDirection` | `DEBIT, CREDIT` |
| `LedgerAccountType` | `USER_WALLET, USER_SAVINGS, SYS_SETTLEMENT, …` (see Javadoc for the full classification table) |
| `LedgerAccountCodes` | int codes paired with `LedgerAccountType` |
| `TransactionType` | wire-level TX type for cross-flow reporting (aligned with `Direction` since 0.3.3) |
| `TransactionChannel` | `MOBILE_APP, USSD, KIOSK, …` |
| `TransactionStatus` | `PENDING, POSTED, REVERSED, FAILED` |

## Producer-routing (`io.f8a.summer.payment.domain.producer`) — 0.3.3+

| Type | Role |
|---|---|
| `Direction` | `TOPUP, WITHDRAW, TRANSFER, REFUND, CREDIT, DEBIT, FEE` — carries TB transfer code |
| `ProducerId` | `<channel>.<partner>.<direction>.v<N>` parser/builder |
| `ProducerStatus` | `ACTIVE, DEPRECATED, SUNSET, ORPHANED, EMERGENCY_DISABLED` |
| `ProducerSpec` | Jackson-deserialized YAML row (`@JsonIgnoreProperties(ignoreUnknown = true)`) |
| `YamlHash` | SHA-256 over YAML bytes — byte-identical across services |
| `ProducerEventFields` | wire field-name constants (`PRODUCER_ID`, `FEE_PRODUCER_ID`) |

## Annotations recap

| Annotation | Wire format | Removed in |
|---|---|---|
| `@JE` | `JE_<Crockford-Base32>` | — |
| `@TX` | `TX_<Crockford-Base32>` | — (replaced `@TXN` in 0.2.6) |
| `@SE` | `SE_<Crockford-Base32>` | — |
| `@Compact` | 26-char Crockford Base32, no prefix | — (replaced `@Hex` in 0.2.6) |
| `@UfidPrefix("XX")` | `XX_<Crockford-Base32>` | — |
| `@UInt128` | unsigned 128-bit decimal | — |
| `@Hex` | — | **removed 0.2.6** → `@Compact` |
| `@TXN` | — | **removed 0.2.6** → `@TX` |
| `@Link` | — | **removed 0.3.3** → `@Compact` |

## Identifier policy

- **Wallet / Account ids → `Ufid`.** Stable 128-bit. Persist as UUID (or as the platform-native u128 wire format for TigerBeetle accounts).
- **Transfer / Journal-entry ids → `Txid`** (since payment-sdk 0.3.4 for `Transfer`). 59-bit, fits BIGINT, sortable by mint time, 18-digit decimal on the wire. Mint via `TxidGenerator.next()`; persist as BIGINT (greenfield) or UUID (legacy schemas) — controlled per service by `summer.r2dbc.txid-column-type`.
- **Saga-execution ids → `@SE Ufid`.** Long-lived state needs the 128-bit collision-safe space.
- **Producer ids → strings.** `ProducerId` is a parsed string, not a Ufid — versioned (`...v1`, `...v2`) and human-readable.
