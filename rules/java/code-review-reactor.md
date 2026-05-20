---
name: code-review-reactor
description: Project Reactor (reactive) code review rules — fundamentals, operator selection, threading/schedulers, context propagation, subscription lifecycle, common pitfalls, testing. Rule IDs RX-*. Load for reactive code. Cite by ID in review.
globs: "*.java"
applicability:
  always: false
  triggers:
    files_match: ["**/*.java"]
    code_patterns: ["Mono", "Flux", "Schedulers", "Reactor", "reactive"]
    task_keywords: ["reactor", "reactive", "Mono", "Flux", "StepVerifier", "backpressure"]
    related_rules:
      - rules/java/code-review-core.md
      - rules/java/reactive.md
relevance_assessment: |
  HIGH 95%+: code uses Mono/Flux (verified: grep "Mono<\\|Flux<" in diff)
  MEDIUM 40%: project has reactive deps but diff doesn't touch reactive code directly
  ZERO: pure servlet/blocking code
---

# Code Review — Project Reactor (`RX-*`)

> Reactive fundamentals. Load when code uses Mono/Flux. Cite ID in review (`[P0][RX-FND-001]`).

## 3.1. Reactive Fundamentals (`RX-FND`)

### RX-FND-001 — Never block the event loop

Reactor (Netty) runs on a small fixed pool (= CPU core count). Blocking 1 thread → loses 1/N throughput.

**Bad**: `User user = mono.block();` inside a reactive chain
**Good**: `return userRepository.findById(id).flatMap(user -> doSomething(user));`

When you MUST use a blocking library:
```java
return Mono.fromCallable(() -> blockingApi.call())
    .subscribeOn(Schedulers.boundedElastic());
```

### RX-FND-002 — Mono.fromCallable instead of Mono.just for expensive ops

**Bad**: `Mono.just(expensiveDbCall());` — `expensiveDbCall()` evaluates IMMEDIATELY at Mono creation
**Good**: `Mono.fromCallable(() -> expensiveDbCall());` — deferred

Use `fromCallable` or `defer` for dynamic/side-effecting code.

### RX-FND-003 — Hot vs cold publisher

**Cold** (default): each subscribe re-executes from the start.
**Hot**: shared, multicast — via `cache()`, `share()`, `Sinks`.

```java
Mono<String> hot = cold.cache();   // share result
hot.subscribe();   // logs "called" first time
hot.subscribe();   // no log, returns cached
```

Use hot only when truly needed.

## 3.2. Operator Selection (`RX-OPS`)

### RX-OPS-001 — flatMap vs map

| Operator | When |
|----------|------|
| `map(T -> R)` | Sync transform, does not return Publisher |
| `flatMap(T -> Mono<R>)` | Async transform, order doesn't matter |
| `concatMap(T -> Mono<R>)` | Async transform, preserve order (sequential) |
| `flatMapSequential` | Parallel execute, ordered output |

**Common mistake — nested Mono<Mono<User>>**:
```java
// ❌ map returns Mono → adds another wrap layer
.map(id -> userRepository.findById(id));
// ✅
.flatMap(id -> userRepository.findById(id));
```

### RX-OPS-002 — switchIfEmpty with defer

**Bad — eager**: `.switchIfEmpty(Mono.error(new NotFoundException(id)));` — `new NotFoundException` is created on EVERY subscribe.

**Good — lazy**: `.switchIfEmpty(Mono.defer(() -> Mono.error(new NotFoundException(id))));`

### RX-OPS-003 — Error handling operators

| Operator | Effect |
|----------|--------|
| `onErrorResume(e -> Mono.just(fallback))` | Recover with fallback Mono |
| `onErrorReturn(fallback)` | Recover with value |
| `onErrorMap(e -> new BizException(e))` | Transform exception type |
| `onErrorComplete()` | Swallow error, complete empty |
| `doOnError(e -> log.error(...))` | Side effect, does NOT recover |

**Common mistake**: returning a value from `doOnError` is ignored. `doOnError` is side-effect only; use `onErrorResume` to recover.

### RX-OPS-004 — then, thenReturn, thenMany

```java
.then(otherMono)         // wait source complete, return otherMono's value
.thenReturn(value)        // wait, return sync value
.thenMany(flux)          // wait, return Flux
.thenEmpty(completable)   // wait, return Mono<Void>
```

```java
return repository.save(entity)
    .then(eventPublisher.publish(event))
    .thenReturn(entity);
```

## 3.3. Threading & Schedulers (`RX-SCH`)

### RX-SCH-001 — subscribeOn vs publishOn

- `subscribeOn`: affects WHERE the source emits (upstream). Only the first invocation takes effect.
- `publishOn`: affects WHERE downstream operators run. Can be used multiple times.

```java
source
    .map(x -> a(x))           // runs on subscribeOn's thread
    .publishOn(scheduler1)
    .map(x -> b(x))           // runs on scheduler1
    .subscribeOn(schedulerS); // affects upstream subscription (a)
```

### RX-SCH-002 — Scheduler choice

| Scheduler | Use for |
|-----------|---------|
| `Schedulers.parallel()` | CPU-bound, default = core count |
| `Schedulers.boundedElastic()` | Wrap blocking I/O, max 10×core threads |
| `Schedulers.single()` | Serialize work, 1 thread |
| `Schedulers.immediate()` | Caller thread, no switch |

**Do NOT use**:
- `Schedulers.elastic()` — deprecated, unbounded
- `Schedulers.newSingle/newParallel/newBoundedElastic` per call — creates new threads, no reuse

### RX-SCH-003 — Limit scheduler switches

Every `publishOn` = context switch = overhead. 1-2 switches per chain is fine; more → revisit design.

## 3.4. Context Propagation (`RX-CTX`)

### RX-CTX-001 — MDC does not auto-propagate

**Bad**: `MDC.put("traceId", "abc");` then `.map(x -> { log.info("found"); ... })` — traceId NOT in log (thread switch).

**Good — Reactor Context**:
```java
return repository.findById(id)
    .contextWrite(Context.of("traceId", "abc"))
    .doOnNext(x -> { /* access via ContextView */ });

// Reactor 3.5+: bridge Context → MDC automatically:
Hooks.enableAutomaticContextPropagation();
```

Or use `micrometer-context-propagation`.

### RX-CTX-002 — Security context

`SecurityContextHolder.getContext()` (sync) does **NOT work** in reactive. Use `ReactiveSecurityContextHolder`:

```java
return ReactiveSecurityContextHolder.getContext()
    .map(SecurityContext::getAuthentication)
    .flatMap(auth -> doSomething(auth.getName()));
```

## 3.5. Subscription & Lifecycle (`RX-SUB`)

### RX-SUB-001 — Chain does not execute until subscribed

```java
Mono<Void> mono = doSomething();   // ❌ does not run
mono.subscribe();                   // ✅ runs now
```

Returning Mono/Flux from controller/service → framework subscribes automatically.

### RX-SUB-002 — Fire-and-forget with error handler

**Bad**: `backgroundTask.subscribe();` — errors silently swallowed

**Good**:
```java
backgroundTask.subscribe(
    null,
    error -> log.error("background task failed", error),
    () -> log.debug("background task done")
);
```

Or use `.doOnError(...)` in the chain before `.subscribe()`.

## 3.6. Common Pitfalls (`RX-PIT`)

### RX-PIT-001 — map returning a Publisher

```java
.map(id -> repo.findById(id))   // ❌ Mono<Mono<User>>
.flatMap(id -> repo.findById(id))   // ✅ Mono<User>
```

### RX-PIT-002 — doOnNext with async side effect

```java
.doOnNext(user -> auditClient.log(user))   // ❌ log() returns Mono but is not awaited
.flatMap(user -> auditClient.log(user).thenReturn(user))   // ✅ awaited
```

`doOnNext` runs only sync code. Async side effects need `flatMap` to await.

### RX-PIT-003 — Mono.just with computation

```java
.flatMap(x -> Mono.just(database.save(x)))   // ❌ save() executes at Mono creation
.flatMap(x -> Mono.fromCallable(() -> database.save(x)))   // ✅ deferred
```

### RX-PIT-004 — filter then switchIfEmpty for validation

```java
return loadOrder(id)
    .filter(o -> o.getStatus() == DRAFT)
    .switchIfEmpty(Mono.defer(() -> 
        Mono.error(new InvalidStateException("not in DRAFT"))));
```

Common guard-clause pattern.

### RX-PIT-005 — block in test

**Bad**: `User user = service.find(id).block();` — blocking, doesn't test reactive behavior

**Good — StepVerifier**:
```java
StepVerifier.create(service.find(id))
    .expectNextMatches(u -> u.getName().equals("X"))
    .verifyComplete();
```

## 3.7. Testing Reactive (`RX-TST`)

### RX-TST-001 — StepVerifier for assertions

```java
StepVerifier.create(service.process(req))
    .expectNext(expectedResult)
    .verifyComplete();

StepVerifier.create(service.process(invalidReq))
    .expectError(ValidationException.class)
    .verify();

StepVerifier.create(service.process(req))
    .assertNext(result -> {
        assertThat(result.getId()).isNotBlank();
        assertThat(result.getAmount()).isEqualByComparingTo("100");
    })
    .verifyComplete();
```

### RX-TST-002 — VirtualTimeScheduler for tests with delay

```java
StepVerifier.withVirtualTime(() -> 
        Mono.delay(Duration.ofHours(1)).thenReturn("done"))
    .thenAwait(Duration.ofHours(1))   // skip 1h of virtual time
    .expectNext("done")
    .verifyComplete();
```

Tests run in ms instead of real hours.

### RX-TST-003 — TestPublisher for controlled emission

```java
TestPublisher<String> publisher = TestPublisher.create();
Flux<String> flux = publisher.flux();

StepVerifier.create(flux)
    .then(() -> publisher.next("a"))
    .expectNext("a")
    .then(() -> publisher.error(new RuntimeException("x")))
    .expectError(RuntimeException.class)
    .verify();
```

## Related

- `rules/java/code-review-core.md` — CORE-* foundation rules
- `rules/java/code-review-webflux.md` — WFL-* WebFlux-specific (uses Reactor)
- `rules/java/reactive.md` — no-`.block()` hard block + scheduler discipline
- `skills/spring-webflux-patterns` — WebFlux implementation patterns
