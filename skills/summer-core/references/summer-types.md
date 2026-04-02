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
