---
name: summer-ratelimit
description: >
  Summer Framework rate limiting (v0.2.2+ ONLY) — fixed-window, sliding-window, token-bucket
  strategies with Redis or in-memory storage. acquire() for auto-429, tryAcquire() for manual
  control. Use when implementing rate limiting in Summer Framework projects — per-user, per-IP,
  per-tenant, or global rate limits with RateLimiterService. Includes distributed Redis patterns
  and multi-tenant tiered policy configuration.
triggers:
  natural: ["rate limiter", "summer rate limit", "token bucket"]
  code: ["RateLimiterService", "f8a.rate-limiter"]
requires: ["summer-core", "redis-patterns"]
applicability:
  always: false
  triggers:
    files_match: ["**/*RateLimit*.java", "**/*Throttle*.java"]
    code_patterns: ["io.f8a.summer.ratelimit", "RateLimiterService", "f8a.rate-limiter"]
    task_keywords: ["rate limit", "throttle", "token bucket", "summer rate limit", "OTP rate limit"]
    related_skills: ["redis-patterns"]
    related_rules:
      - rules/common/security.md
relevance_assessment: |
  HIGH 80%+: new rate-limited endpoint OR rate config change
  MEDIUM 40-79%: rate-limit key strategy refactor
  LOW 1-39%: endpoint that should be rate-limited but currently isn't
  ZERO: project lacks io.f8a.summer:summer-rate-limiter
---

# Summer Rate Limiting — v0.2.2+ Only

**Gate:** Verify summer-core loaded and `io.f8a.summer:summer-platform` in build.gradle before proceeding.

**Module:** `summer-ratelimit-autoconfigure` | **Config:** `f8a.rate-limiter` | **Prereq:** Summer >= 0.2.2 only.

```gradle
implementation 'io.f8a.summer:summer-ratelimit-autoconfigure'
```

## Three Strategies

| Strategy | Description |
|---|---|
| `fixed-window` | Resets counter at fixed intervals |
| `sliding-window` | Rolling time window for smoother limits |
| `token-bucket` | Refills tokens at steady rate; handles bursts |

## Usage

### `acquire()` — throws 429 automatically

```java
@RequiredArgsConstructor
public class OrderController {
    private final RateLimiterService rateLimiterService;

    public Mono<Order> createOrder(String userId, CreateOrderRequest req) {
        return rateLimiterService
            .acquire(new RateLimitKey(userId, "orders:create"))
            .then(orderService.create(req));
    }

    // Custom limit/window at call site (still uses scope's strategy)
    public Mono<Void> sendOtp(String ip) {
        return rateLimiterService
            .acquire(new RateLimitKey(ip, "auth:otp"), 3, Duration.ofMinutes(10))
            .then(otpService.send());
    }
}
```

429 error response:
```json
{ "code": "com.rate.limit.exceeded", "details": [
    { "field": "limit", "value": "10" },
    { "field": "resetAt", "value": "1741123456" }
]}
```

### `tryAcquire()` — returns `RateLimitResult` for manual handling

```java
public Mono<Order> getOrder(String userId, String orderId, ServerWebExchange exchange) {
    return rateLimiterService
        .tryAcquire(new RateLimitKey(userId, "orders:read"))
        .flatMap(result -> {
            exchange.getResponse().getHeaders().set("X-RateLimit-Remaining",
                String.valueOf(result.remaining()));
            if (!result.allowed()) {
                return Mono.error(CommonExceptions.RATE_LIMIT_EXCEEDED.toException());
            }
            return orderService.getById(orderId);
        });
}
```

`RateLimitResult` record: `allowed()`, `limit()`, `remaining()`, `resetAt()`.

## Types

| Type | Package | Purpose |
|---|---|---|
| `RateLimiterService` | `core.ratelimit` | Main service: `acquire()` / `tryAcquire()` |
| `RateLimitKey` | `core.ratelimit` | Key record: `identifier` + `policyKey` |
| `RateLimitResult` | `core.ratelimit` | Result record: `allowed`, `limit`, `remaining`, `resetAt` |

## Configuration

```yaml
f8a:
  rate-limiter:
    key-prefix: "ratelimit:"            # global storage key prefix
    storage-type: redis                 # "redis" (default) or "memory"
    default-policy:                     # fallback for unmatched scopes
      strategy: token-bucket
      limit: 100
      window: 60s
      token-bucket-refill-rate: 0       # tokens/sec (0 = auto: limit/windowSec)
    policies:                           # named per-scope policies
      users:read:
        strategy: sliding-window
        limit: 1000
        window: 3600s
      orders:create:
        strategy: fixed-window
        limit: 10
        window: 60s
      auth:otp:
        strategy: fixed-window
        limit: 5
        window: 300s
```

## Storage

- **Redis** (default): Atomic Lua scripts. Auto-detected when `spring-boot-starter-data-redis-reactive` on classpath.
- **Memory**: In-process fallback (`storage-type: memory`). Dev/testing only.

WARNING: `storage-type: memory` NOT cluster-safe, resets on restart. Use Redis in production — in-memory silently produces incorrect limits in multi-instance deployments.

## Strategy Override

`strategy` is per named policy — not overridable at call site. Only `limit` and `window` can be overridden via `acquire(key, limit, window)` / `tryAcquire(key, limit, window)`.

See `references/policy-examples.md` for per-user, per-IP, per-endpoint examples.

## Rules

- Use `acquire()` for standard endpoints — auto-429 safer than manual handling
- Redis storage in production — `memory` NOT cluster-safe
- Named policies for auth/write scopes — never rely solely on default-policy
- Never override strategy at call site — per-policy only; `limit` and `window` are overridable
- Verify Summer >= 0.2.2 — module absent in earlier versions

## Related Skills

- **summer-core** — CommonExceptions.RATE_LIMIT_EXCEEDED for manual error handling
- **summer-rest** — Controllers using RateLimiterService with BaseController pattern
- **redis-patterns** — Redis configuration for rate limit storage backend
- **spring-security** — Rate limiting as part of security defense-in-depth
