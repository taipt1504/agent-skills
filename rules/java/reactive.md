---
name: reactive
description: Reactive programming rules — no .block(), backpressure handling, scheduler discipline, reactive error handling. CRITICAL for WebFlux projects.
globs: "*.java"
applicability:
  always: false
  triggers:
    files_match: ["**/*.java"]
    code_patterns: ["Mono", "Flux", "WebClient", "RouterFunction", "ReactiveSecurityContextHolder", "Schedulers", "@EnableWebFlux"]
    task_keywords: ["webflux", "reactive", "Mono", "Flux", "backpressure"]
---

# Reactive Rules

## HARD BLOCK — No `.block()`

NEVER `.block()` / `.blockOptional()` / `.blockFirst()` / `.blockLast()` in:
- Controllers, services in reactive chain
- Security filters (blocks Netty event loop → total outage)
- Reactive transaction boundaries, Kafka consumer callbacks

Exception: top-level test code with explicit timeout only.

```java
// BAD
User user = userRepository.findById(id).block();

// GOOD
return userRepository.findById(id).flatMap(this::process);
```

## No JPA in Reactive Chain

`JpaRepository` blocks the event loop inside `Mono`/`Flux`. Use:
- R2DBC (relational), ReactiveMongoRepository (Mongo), Spring Data Redis Reactive (Redis)

Unavoidable blocking dep: wrap with `Schedulers.boundedElastic()` (bounded thread budget).

```java
return Mono.fromCallable(() -> blockingRepo.findById(id))
    .subscribeOn(Schedulers.boundedElastic());
```

## Backpressure

`Flux` consumers must handle backpressure:
- `.onBackpressureBuffer(int max, BufferOverflowStrategy)` — bounded buffer
- `.onBackpressureDrop()` — drop with handler
- `.onBackpressureLatest()` — keep latest

NEVER unbounded `.onBackpressureBuffer()` — OOM risk.

## Scheduler Discipline

| Operation | Scheduler |
|---|---|
| CPU-bound | `Schedulers.parallel()` |
| Blocking I/O (legacy) | `Schedulers.boundedElastic()` (bounded thread budget) |
| Async I/O (reactive) | default (Netty event loop) |
| Test | `Schedulers.immediate()` or `VirtualTimeScheduler` |

NEVER `Schedulers.elastic()` (unbounded, deprecated).

## Error Handling in Reactive Chain

- `onErrorResume` / `onErrorMap` on every chain
- NEVER `throw` in `map()` — use `flatMap` + `Mono.error()`
- `doOnError(e -> log.error("...", e))` before transforming
- `switchIfEmpty(Mono.error(...))` for not-found cases

See `rules/java/coding-style.md` §"Reactive Error Handling" for examples.

## Context Propagation

`Mono`/`Flux` carry Reactor Context (not ThreadLocal). For MDC / SecurityContext:
- `Mono.deferContextual` to read
- `.contextWrite(Context.of(key, value))` to write
- NEVER `ThreadLocal` directly — lost across operator boundaries

```java
return Mono.deferContextual(ctx -> {
    String userId = ctx.get("userId");
    return service.process(userId);
}).contextWrite(Context.of("userId", id));
```

## Testing

- `StepVerifier` for `Mono`/`Flux` assertions
- `VirtualTimeScheduler` for time-based operators (`delay`, `interval`)
- `.expectNoEvent(Duration)` to assert silence
- `WebTestClient` for endpoints

## Related

- `rules/java/coding-style.md` — error handling, imports
- `rules/java/security.md` — reactive security filters
- `skills/spring-webflux-patterns` — WebFlux deep dive
