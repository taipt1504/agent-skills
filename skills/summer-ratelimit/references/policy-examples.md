# Summer Rate Limiting — Policy Examples

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

## Per-User Rate Limiting

Use the authenticated user ID as the `identifier` in `RateLimitKey`:

```java
return rateLimiterService
    .acquire(new RateLimitKey(member.getId(), "orders:create"))
    .then(orderService.create(req));
```

Policy config:
```yaml
f8a:
  rate-limiter:
    policies:
      orders:create:
        strategy: fixed-window
        limit: 10
        window: 60s
```

## Per-IP Rate Limiting

Extract IP from the request and use it as identifier:

```java
String ip = exchange.getRequest().getRemoteAddress().getAddress().getHostAddress();
return rateLimiterService
    .acquire(new RateLimitKey(ip, "auth:otp"))
    .then(otpService.send());
```

Policy config:
```yaml
f8a:
  rate-limiter:
    policies:
      auth:otp:
        strategy: fixed-window
        limit: 5
        window: 300s
```

## Per-Endpoint with Token Bucket (Burst Handling)

Token bucket allows short bursts above the average rate:

```yaml
f8a:
  rate-limiter:
    policies:
      search:query:
        strategy: token-bucket
        limit: 60                       # bucket capacity
        window: 60s                     # refill period
        token-bucket-refill-rate: 1     # tokens/sec refill rate
```

## Call-Site Limit/Window Override

Override `limit` and `window` at call site (strategy remains as configured in policy):

```java
// Allow 3 attempts per 10 minutes, overriding policy defaults
return rateLimiterService
    .acquire(new RateLimitKey(ip, "auth:otp"), 3, Duration.ofMinutes(10))
    .then(otpService.send());
```

Note: only `limit` and `window` can be overridden at call site. `strategy` is always taken from the named policy config.
