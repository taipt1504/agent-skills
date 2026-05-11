# Summer Shared Types — Reference

## Member (Authenticated User)

```java
// Access in reactive handler
public Mono<ResponseEntity<Profile>> getProfile() {
    return ReactiveSecurityContextHolder.getContext()
        .map(ctx -> (Member) ctx.getAuthentication().getPrincipal())
        .map(member -> ResponseEntity.ok(new Profile(
            member.getId(), member.getUsername(),
            member.getGivenName(), member.getFamilyName(),
            member.getEmail(), member.getAuthorities()
        )));
}

// With CallerAware mixin (recommended)
public class MyHandler implements CallerAware {
    public Mono<Order> handle(CreateOrderRequest req) {
        return getCaller()  // Mono<Member>
            .flatMap(caller -> createOrder(req, caller.getId()));
    }
}
```

Fields: `id` (String), `username`, `givenName`, `familyName`, `email`, `authorities` (Collection<GrantedAuthority>).

## Password Value Object

```java
// Entity field
@ValidPassword  // validation annotation
private Password password;

// Creating
Password pw = Password.of("raw-password");
// R2DBC converter auto-registered — stores hashed in DB

// Verifying
boolean matches = password.matches("raw-input");
```

Rules: never log raw passwords, always use `@ValidPassword` for validation, R2DBC converter handles hashing transparently.

## PhoneNumber Value Object

```java
@ValidPhoneNumber
private PhoneNumber phoneNumber;

PhoneNumber phone = PhoneNumber.of("+84901234567");
String formatted = phone.getValue();  // normalized format
```

R2DBC converter auto-registered. Validates format on construction.

## ViewableException (HTTP Exceptions)

```java
// From CommonExceptions enum
throw CommonExceptions.RESOURCE_NOT_FOUND.toException()
    .detail("Resource not found")
    .detailValue("id", orderId);

// Custom exception enum (recommended pattern)
@Getter @RequiredArgsConstructor
public enum OrderExceptions implements IntoViewableException {
    ORDER_NOT_FOUND("order.not.found", HttpStatus.NOT_FOUND),
    ORDER_ALREADY_PAID("order.already.paid", HttpStatus.CONFLICT);

    public static final String PREFIX = "ord";
    private final String code;
    private final HttpStatus httpStatus;

    @Override
    public ViewableException toException() {
        return new ViewableException(PREFIX + "." + code, httpStatus);
    }
}
```

`SummerGlobalExceptionHandler` catches ViewableException and returns `JsonErrorResponse` with: code, message, traceId, timestamp, details.

## JsonErrorResponse

```json
{
  "code": "ord.order.not.found",
  "message": "Order not found",
  "traceId": "abc123",
  "timestamp": "2026-04-02T10:00:00Z",
  "details": {"id": "ORD-001"}
}
```

Auto-serialized by `SummerGlobalExceptionHandler`. The `details` field is a `Map<String, Object>` populated from `.detailValue()` calls.

## CommonExceptions Quick Reference

| Enum | HTTP Status |
|------|-------------|
| `RESOURCE_NOT_FOUND` | 404 |
| `INVALID_REQUEST` | 400 |
| `VALIDATION_ERROR` | 422 |
| `UNAUTHORIZED` | 401 |
| `ACCESS_DENIED` / `FORBIDDEN` | 403 |
| `CONFLICT` | 409 |
| `RATE_LIMIT_EXCEEDED` | 429 |
| `INTERNAL_SERVER_ERROR` | 500 |
| `SERVICE_UNAVAILABLE` | 503 |
| `TIMEOUT` | 504 |

## Identifier Types — `Ufid` vs `Txid`

Two distinct identifier needs, two distinct value types. Treat them as different domain concepts; the type system enforces it.

| | `Ufid` (0.2.5+) | `Txid` (0.3.5+) |
|---|---|---|
| **Width** | 128-bit | 59-bit (fits 18 decimal digits) |
| **Use for** | Internal canonical keys: account ids, wallet ids, party ids, saga executions, journal entries | Human-facing reference numbers: transaction receipts, support-call quotables |
| **Mint via** | `Ufid.generate()` (any host) | `TxidGenerator.next()` (one bean per JVM) |
| **Display format** | UUID (`@JsonValue`) or 26-char Crockford Base32 (`@Compact`) or prefixed (`@JE` / `@TX` / `@SE` / `@UfidPrefix`) | 18-digit zero-padded decimal |
| **DB column** | `UUID` (standard) | `BIGINT` (greenfield) or `UUID` with MSB=0 (legacy) — controlled by `summer.r2dbc.txid-column-type` |
| **TigerBeetle wire** | u128 little-endian | u128 little-endian, **upper 8 bytes always zero** |
| **Sortable by mint time** | No (random) | Yes (timestamp in high bits) |
| **Collision space** | 128 bits | 4096 IDs/ms/machine × 64 machines = 262k/ms cluster-wide |
| **Header used** | n/a | `Txid.getMachineId()` — 0..63 by default |

### `Txid` quick reference

```java
// Mint
Txid txid = txidGen.next();

// Display
String display = txid.toString();         // "000123456789012345"
String json   = txid.toJsonValue();       // same

// Encodings
long  asBigInt  = txid.toLong();          // BIGINT column
UUID  asUuid    = txid.toUUID();          // UUID column (MSB = 0)
byte[] tbId     = txid.as16Bytes();       // TigerBeetle u128 (LE, high 8 bytes = 0)

// Decode for debugging
Instant when    = txid.getInstant();
int  machineId  = txid.getMachineId();    // 0..63
int  sequence   = txid.getSequence();     // 0..4095

// Parse — both padded and unpadded accepted
Txid parsed = Txid.fromString("000123456789012345");
Txid parsed = Txid.fromString("123456");
```

### When `Txid.from*` throws

Every `from*` constructor throws `IllegalArgumentException` if the upper 64 bits of the source value are non-zero. A `Txid` minted by `TxidGenerator` always has the upper half zero, so a non-zero half means the value came from elsewhere (legacy data, manual insert, foreign service) — surface the bug rather than silently truncating.

### `TxidGenerator` wiring patterns

| Environment | Identity source | Wiring |
|---|---|---|
| Kubernetes StatefulSet | Pod ordinal from `HOSTNAME=<svc>-<n>` | `new TxidGenerator(MachineIdResolver.resolve())` |
| Deployment with stable per-pod config | `SUMMER_TXID_MACHINE_ID` env / `summer.txid.machine-id` system property | `new TxidGenerator(MachineIdResolver.resolve())` |
| Deployment (autoscaled), Cloud Run | Redis slot lease (self-healing) | `new TxidGenerator(redisMachineIdReservation)` (the reservation is a `Supplier<Long>`) |

`MachineIdResolver.resolve()` **throws** if no static source is set — never silently hashes the hostname. Two pods with the same machineId is silent ID corruption.

`RedisMachineIdReservation` re-acquires a fresh slot atomically if its TTL ever lapses (GC pause, network partition, Redis restart). The generator picks up the new id on its next `next()` call without a pod restart. Use `isHealthy()` as a Kubernetes liveness probe.
