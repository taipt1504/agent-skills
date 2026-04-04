# Summer Rate Limiting — Policy Examples & Advanced Patterns

> Read when: configuring rate limit policies, implementing custom rate limiting logic, or choosing between strategies.

## Full Configuration Reference

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

## Strategy Comparison

| Strategy | Burst Handling | Memory | Accuracy | Best For |
|----------|---------------|--------|----------|----------|
| **Fixed Window** | Window-edge burst (2× limit) | Low (1 counter) | Approximate | Simple API limits |
| **Sliding Window** | Smooth, no edge bursts | Medium (2 counters) | High | User-facing APIs |
| **Token Bucket** | Controlled bursts up to capacity | Low (2 values) | High | Bursty traffic patterns |

### Fixed Window

Resets counter at fixed intervals. Simple but allows 2× burst at window boundaries.

```yaml
orders:create:
  strategy: fixed-window
  limit: 10
  window: 60s
```

### Sliding Window

Weighted average of current + previous window. Smooth rate enforcement, no boundary spikes.

```yaml
users:read:
  strategy: sliding-window
  limit: 1000
  window: 3600s
```

### Token Bucket

Tokens refill continuously. Allows short bursts up to bucket capacity while maintaining average rate.

```yaml
search:query:
  strategy: token-bucket
  limit: 60                       # bucket capacity
  window: 60s                     # refill period
  token-bucket-refill-rate: 1     # tokens/sec refill rate (0 = auto)
```

## Per-User Rate Limiting

Use the authenticated user ID as the `identifier` in `RateLimitKey`:

```java
return rateLimiterService
    .acquire(new RateLimitKey(member.getId(), "orders:create"))
    .then(orderService.create(req));
```

## Per-IP Rate Limiting

Extract IP from the request and use it as identifier:

```java
String ip = exchange.getRequest().getRemoteAddress().getAddress().getHostAddress();
return rateLimiterService
    .acquire(new RateLimitKey(ip, "auth:otp"))
    .then(otpService.send());
```

## Per-Tenant Rate Limiting (Multi-Tenant)

```java
return rateLimiterService
    .acquire(new RateLimitKey(tenantId, "api:global"))
    .then(handleRequest(req));
```

With tiered limits per plan:

```yaml
f8a:
  rate-limiter:
    policies:
      api:global:free:
        strategy: sliding-window
        limit: 100
        window: 3600s
      api:global:pro:
        strategy: sliding-window
        limit: 10000
        window: 3600s
```

```java
String scope = "api:global:" + tenant.getPlan().name().toLowerCase();
return rateLimiterService
    .acquire(new RateLimitKey(tenantId, scope))
    .then(handleRequest(req));
```

## Call-Site Limit/Window Override

Override `limit` and `window` at call site (strategy remains as configured in policy):

```java
// Allow 3 attempts per 10 minutes, overriding policy defaults
return rateLimiterService
    .acquire(new RateLimitKey(ip, "auth:otp"), 3, Duration.ofMinutes(10))
    .then(otpService.send());
```

Note: only `limit` and `window` can be overridden at call site. `strategy` is always from the named policy.

## Manual Control with tryAcquire()

Use `tryAcquire()` when you need custom response logic instead of auto-429:

```java
return rateLimiterService
    .tryAcquire(new RateLimitKey(userId, "export:csv"))
    .flatMap(result -> {
        if (result.isAllowed()) {
            return exportService.generateCsv(userId);
        }
        return Mono.error(new TooManyRequestsException(
            "Export limit reached. Retry after " + result.getRetryAfterSeconds() + "s"
        ));
    });
```

### RateLimitResult Fields

| Field | Type | Description |
|-------|------|-------------|
| `allowed` | boolean | Whether the request is permitted |
| `remaining` | long | Remaining quota in current window |
| `retryAfterSeconds` | long | Seconds until next available slot |
| `limit` | long | Total limit for the policy |

## Distributed Rate Limiting (Redis)

### Redis Key Structure

```
ratelimit:{scope}:{identifier}      # fixed-window counter
ratelimit:{scope}:{identifier}:prev # sliding-window previous counter
ratelimit:{scope}:{identifier}:ts   # token-bucket last refill timestamp
ratelimit:{scope}:{identifier}:tkn  # token-bucket current tokens
```

### Cluster Considerations

- All rate limit operations use Redis Lua scripts for atomicity
- In Redis Cluster, keys for the same scope+identifier hash to the same slot
- Cross-datacenter: each DC maintains independent counters (eventual consistency)
- For global limits across DCs, use `limit / numDCs` per datacenter

### Redis Failover Handling

```yaml
f8a:
  rate-limiter:
    storage-type: redis
    fallback-on-error: allow          # "allow" or "deny" when Redis is down
    redis-timeout: 100ms              # timeout per Redis call
```

When `fallback-on-error: allow`, requests pass through if Redis is unreachable — prioritizing availability over strictness.

## WebFilter Integration (Global Rate Limiting)

Apply rate limiting to all requests via WebFilter:

```java
@Component @Order(Ordered.HIGHEST_PRECEDENCE + 10)
@RequiredArgsConstructor
public class GlobalRateLimitFilter implements WebFilter {
    private final RateLimiterService rateLimiterService;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String ip = exchange.getRequest().getRemoteAddress()
            .getAddress().getHostAddress();
        return rateLimiterService
            .acquire(new RateLimitKey(ip, "global:request"))
            .then(chain.filter(exchange));
    }
}
```

## Response Headers

`acquire()` auto-injects standard rate limit response headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 42
X-RateLimit-Reset: 1700000060
Retry-After: 30
```

## Common Policy Templates

```yaml
# Login brute-force protection
auth:login:
  strategy: fixed-window
  limit: 5
  window: 900s          # 5 attempts per 15 min

# File upload throttle
upload:file:
  strategy: token-bucket
  limit: 10
  window: 3600s
  token-bucket-refill-rate: 0   # auto: ~1 upload per 6 min

# Search anti-abuse
search:query:
  strategy: sliding-window
  limit: 120
  window: 60s           # 2 req/sec average, smooth

# Webhook delivery (outbound)
webhook:deliver:
  strategy: token-bucket
  limit: 50
  window: 60s
  token-bucket-refill-rate: 5   # 5/sec sustained, 50 burst
```
