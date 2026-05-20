---
name: code-review-core
description: Core Java code review rules — null handling, equality, numeric/money, exceptions, resources, immutability, collections, concurrency, logging, API design. Rule IDs CORE-*. Always loaded for Java projects. Cite by ID in review.
globs: "*.java"
applicability:
  always: false
  triggers:
    files_match: ["**/*.java"]
    task_keywords: ["java", "review", "code review", "BigDecimal", "money", "fintech"]
    related_rules:
      - rules/java/coding-style.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 95%+: any Java file in diff (universally applicable foundation rules)
  ZERO: non-Java task
---

# Code Review — Core Java (`CORE-*`)

> Foundation rules. Apply to ALL Java code. Cite ID in review comments (`[P1][CORE-NUM-001]`).

## 1.1. Null handling (`CORE-NUL`)

### CORE-NUL-001 — Never return null for collection/array

**Bad**
```java
public List<Order> findOrders(String userId) {
    if (userId == null) return null;  // ❌
    return repository.findByUser(userId);
}
```

**Good**
```java
public List<Order> findOrders(String userId) {
    if (userId == null) return List.of();   // ✅ empty collection
    return repository.findByUser(userId);
}
```

**Rationale**: Caller forced to null-check, easy NPE. Empty collection iterates, streams, no meaningful memory cost.

### CORE-NUL-002 — Optional only for return type

**Bad**
```java
public void notify(Optional<String> email) { ... }     // ❌ parameter
private Optional<String> email;                          // ❌ field
```

**Good**
```java
public Optional<User> findById(String id) { ... }       // ✅ return type
```

Field `Optional` wastes memory, serializes poorly. Parameter `Optional` forces caller to wrap unnecessarily.

### CORE-NUL-003 — Annotate nullability explicitly

```java
public @NonNull User loadUser(@NonNull String id, @Nullable String tenantId) {
    Objects.requireNonNull(id, "id");
}
```

Annotation standard: JSpecify (recommended) | Spring `org.springframework.lang.*` | JetBrains. Stay consistent project-wide — do not mix flavors.

### CORE-NUL-004 — Defensive null-check at public boundary

```java
public Transaction post(Transfer transfer) {
    Objects.requireNonNull(transfer, "transfer");
    Objects.requireNonNull(transfer.amount(), "transfer.amount");
}
```

Public API: fail fast. Internal/private method: trust caller.

## 1.2. Equality & Hashing (`CORE-EQH`)

### CORE-EQH-001 — equals and hashCode go together

Override `equals()` → MUST override `hashCode()`. Use Lombok `@EqualsAndHashCode(onlyExplicitlyIncluded = true)` to control fields.

### CORE-EQH-002 — Use Objects.equals() for null-safe compare

**Bad**: `user.getEmail().equals(otherEmail)` — NPE if email null
**Good**: `Objects.equals(user.getEmail(), otherEmail)`

### CORE-EQH-003 — Prefer record for value object

```java
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
    }
}
```

Record auto-generates `equals`, `hashCode`, `toString`, accessors. Compact constructor for validation. Immutable by default.

### CORE-EQH-004 — BigDecimal: equals vs compareTo

**Bad**: `new BigDecimal("1.0").equals(new BigDecimal("1.00"))` → `false` (different scale)
**Good**: `new BigDecimal("1.0").compareTo(new BigDecimal("1.00")) == 0` → `true`

For **value** equality use `compareTo`. For **representation** equality use `equals`.

## 1.3. Numeric & Money (`CORE-NUM`)

### CORE-NUM-001 — Never use double/float for money

**Bad**: `double balance = 0.1 + 0.2;` → `0.30000000000000004`
**Good**: `BigDecimal balance = new BigDecimal("0.1").add(new BigDecimal("0.2"));` → `0.3`

IEEE 754 floating point cannot represent decimals exactly. In fintech, 1-cent drift = critical bug.

### CORE-NUM-002 — Divide must use MathContext or RoundingMode

**Bad**: `a.divide(b)` → ArithmeticException if result does not terminate
**Good**: `a.divide(b, 2, RoundingMode.HALF_EVEN)` or `a.divide(b, MathContext.DECIMAL64)`

**Rounding modes for fintech**:
- `HALF_EVEN` (banker's rounding) — accounting standard, IEEE 754 default
- `HALF_UP` — familiar to business users
- `DOWN` — fee/commission (round toward zero, protects customer)

### CORE-NUM-003 — Integer overflow in critical arithmetic

**Bad**: `long total = a + b;` silent overflow. `int days = (int) longValue;` silent truncation.
**Good**: `Math.addExact(a, b)` / `Math.toIntExact(longValue)` → throw `ArithmeticException`.

Apply to all arithmetic in ledger, balance, total amount paths.

### CORE-NUM-004 — Money type wrapper

Large projects: use custom `Money` type instead of raw `BigDecimal`.

```java
public record Money(BigDecimal amount, Currency currency) {
    public Money add(Money other) {
        requireSameCurrency(other);
        return new Money(amount.add(other.amount), currency);
    }
}
```

Prevents bugs like adding VND + USD or mismatched scale.

## 1.4. Exceptions (`CORE-EXC`)

### CORE-EXC-001 — Do not catch Exception/Throwable except at top-level

**Bad**: `catch (Exception e)` swallows everything
**Good**: `catch (IOException e) { throw new BusinessException("X_FAILED", e); }`

Top-level boundary (controller advice, message listener wrapper) may catch `Throwable` — exception, not a pattern.

### CORE-EXC-002 — Do not ignore exceptions

**Bad**: `catch (ParseException ignored) {}` → silent failure
**Good**: `catch (ParseException e) { log.debug("parse failed, using default: {}", e.getMessage()); }`

Even when ignoring, log at debug/trace so it's debuggable later.

### CORE-EXC-003 — Do not use exceptions for control flow

**Bad**: `try { return Integer.parseInt(s); } catch (NumberFormatException e) { return 0; }`
**Good**: `if (s != null && s.matches("-?\\d+")) return Integer.parseInt(s); return 0;`

Exceptions are expensive (stack trace), hard to debug, design smell.

### CORE-EXC-004 — Wrap checked exception at service boundary

Service returning `IOException`, `SQLException` to controller = leak. Wrap as business exception with `ErrorCode` enum (code + HTTP status + message).

### CORE-EXC-005 — Custom exception extends RuntimeException

In modern Spring apps, checked exceptions are mostly noise. Domain exceptions stay unchecked. Reserve checked exceptions for clearly recoverable cases.

## 1.5. Resource management (`CORE-RES`)

### CORE-RES-001 — try-with-resources for AutoCloseable

```java
try (InputStream in = Files.newInputStream(path)) {
    process(in);
}   // ✅ auto-close, suppressed exception preserved correctly
```

### CORE-RES-002 — ExecutorService must shutdown

```java
@PreDestroy
public void shutdown() {
    executor.shutdown();
    try {
        if (!executor.awaitTermination(10, TimeUnit.SECONDS)) executor.shutdownNow();
    } catch (InterruptedException e) {
        executor.shutdownNow();
        Thread.currentThread().interrupt();
    }
}
```

Without shutdown → JVM cannot exit, threads leak across context reloads.

## 1.6. Immutability & State (`CORE-IMM`)

### CORE-IMM-001 — Final by default

Non-final fields require explicit justification. Helps reason about thread safety.

### CORE-IMM-002 — Defensive copy for collection field

**Good**
```java
public Order(List<LineItem> items) {
    this.items = List.copyOf(items);    // ✅ defensive copy + immutable
}
public List<LineItem> getItems() { return items; }   // ✅ already immutable
```

`List.copyOf` since Java 10+. For mutable internal: `new ArrayList<>(items)` and expose `Collections.unmodifiableList(items)`.

### CORE-IMM-003 — Static mutable is a code smell

Requires explicit justification, thread-safety guarantee, documentation. In Spring apps, prefer singleton beans with instance fields over static state.

## 1.7. Collections & Streams (`CORE-COL`)

### CORE-COL-001 — computeIfAbsent instead of check-then-put

```java
map.computeIfAbsent(key, k -> new ArrayList<>()).add(order);
```

### CORE-COL-002 — No side effects in stream map/filter

**Bad**: `.map(x -> { audit.log(x); return transform(x); })` — side effect inside map
**Good**: `.peek(audit::log).map(this::transform)` — peek reserved for debug/audit

### CORE-COL-003 — No parallel stream without benchmark

`parallelStream()` shares the common ForkJoinPool. Small workloads → overhead exceeds benefit. Blocking I/O → global contention.

Use only when: benchmarked faster, CPU-bound stateless, order doesn't matter.

### CORE-COL-004 — Unmodifiable collector

`.collect(Collectors.toUnmodifiableList())` (Java 10+). Default for method return value. If caller needs to mutate → caller copies.

### CORE-COL-005 — Complex nested stream → refactor

3+ levels of nested stream become unreadable and undebuggable. Extract a named method, or use a loop if it reads clearer.

## 1.8. Concurrency (`CORE-CON`)

### CORE-CON-001 — Shared mutable state must be synchronized

Every field shared across threads must use:
- `synchronized`
- `java.util.concurrent.locks.Lock`
- Atomic class (`AtomicLong`, `AtomicReference`)
- `volatile` (visibility only, not compound actions)
- Immutability

### CORE-CON-002 — ConcurrentHashMap > synchronizedMap

`ConcurrentHashMap` uses lock striping, scales with concurrent access. `synchronizedMap` uses a coarse lock.

### CORE-CON-003 — Do not hold lock during external call

```java
synchronized (this) {
    httpClient.post(url, payload);   // ❌ lock held for seconds
}
```

External calls under a lock = recipe for deadlock and cascade failure.

### CORE-CON-004 — ThreadLocal must remove

```java
try {
    threadLocal.set(value);
    process();
} finally {
    threadLocal.remove();   // ✅ avoid memory leak in thread pool
}
```

Servlet containers and Reactor schedulers use thread pools. Not removing → leak across requests, cross-request data pollution.

## 1.9. Logging (`CORE-LOG`)

### CORE-LOG-001 — SLF4J parameterized, no string concat

**Bad**: `log.info("user " + userId + " did " + action);` — concatenates even when log level disabled
**Good**: `log.info("user={} action={}", userId, action);` — lazy format

### CORE-LOG-002 — Never log sensitive data

Forbidden in logs:
- Password, OTP, PIN
- Full card number (PCI-DSS) — mask 6+4 or tokenize
- CVV — never
- JWT, session token, API key — truncated or hashed only
- Full national ID — mask
- Phone, email per data governance policy

Centralize mask logic (`Mask.pan(...)`, `Mask.email(...)`).

### CORE-LOG-003 — Correct log level semantics

| Level | When |
|-------|------|
| TRACE | Verbose debug, per-step |
| DEBUG | Development info, off in prod |
| INFO | Business event (order placed) |
| WARN | Recoverable issue (retry succeeded) |
| ERROR | Requires intervention (DB down) |

`ERROR` logs must contain actionable info for on-call.

### CORE-LOG-004 — Structured logging with consistent keys

```java
log.info("operation={} outcome={} applicationId={} duration_ms={}",
         "submit", "success", appId, durationMs);
```

Greppable, parseable by Logstash/Fluentd, queryable in Kibana.

### CORE-LOG-005 — MDC for correlation ID

Set in filter/interceptor, clear in finally:

```java
try {
    MDC.put("traceId", traceId);
    MDC.put("requestId", requestId);
    chain.doFilter(request, response);
} finally {
    MDC.clear();
}
```

Enables cross-service tracing.

## 1.10. API Design (`CORE-API`)

### CORE-API-001 — Method size guideline

Method ≤ 50 lines body. Class ≤ 400 lines (800 absolute max). Exceeding requires justification.

> Plugin canonical (per `CLAUDE.md §Code Conventions`). Tightened from doc original (~30/~300) to match existing harness rule.

**Severity mapping**:
- Method 50-80 lines OR class 400-600 lines → `[P3][CORE-API-001]`
- Method >80 lines OR class >600 lines → `[P2][CORE-API-001]`
- Class >800 lines (absolute max breach) → `[P1][CORE-API-001]`

### CORE-API-002 — Single Responsibility per method

A method should have one reason to change. If two distinct reasons → split.

### CORE-API-003 — Parameter count

≤ 3: OK. 4: reconsider. 5+: group into a parameter object.

```java
// Bad: void create(String name, String email, String phone, String address, String city, String country);
// Good: void create(CustomerInfo info);
```

### CORE-API-004 — Boolean parameter is a smell

**Bad**: `notify(user, true);` — what does true mean?
**Good**: `notify(user, NotifyMode.EMAIL);` — self-documenting

Or split into two methods: `notifyByEmail()`, `notifyBySms()`.

### CORE-API-005 — Builder for objects with many fields

Lombok `@Builder` for immutable objects with 5+ fields or optional fields.

## Related

- `rules/java/code-review-mvc.md` — Spring MVC rules (MVC-*)
- `rules/java/code-review-reactor.md` — Reactor (RX-*)
- `rules/java/code-review-webflux.md` — WebFlux (WFL-*)
- `rules/java/code-review-crosscut.md` — XCT-* + PR checklist + severity P0-P4
- `rules/java/coding-style.md` — Lombok, DI, error handling
- `rules/java/security.md` — Spring Security patterns
