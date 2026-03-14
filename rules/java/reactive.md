# Reactive Programming Rules

## NEVER (Blocking Violations)

- NEVER `.block()`, `.blockFirst()`, `.blockLast()` in application code
- NEVER `Thread.sleep()` in reactive chains — use `delayElement()`
- NEVER `RestTemplate` — use `WebClient` (reactive) or `RestClient` (MVC)
- NEVER `.subscribe()` inside a reactive chain — compose with `flatMap`/`then`
- NEVER `Mono.just(expensiveCall())` — use `Mono.fromCallable()` or `Mono.defer()`
- NEVER throw exceptions in `map` — use `flatMap` + `Mono.error()`
- NEVER `SecurityContextHolder.getContext()` — use `ReactiveSecurityContextHolder`

## ALWAYS

- ALWAYS `Schedulers.boundedElastic()` for blocking I/O (`subscribeOn`)
- ALWAYS `StepVerifier` for testing reactive code — never `.block()` in tests
- ALWAYS `switchIfEmpty(Mono.defer(...))` — never `.orElse()` on Mono
- ALWAYS `onErrorResume` / `onErrorMap` for error handling in chains
- ALWAYS `limitRate()` or `buffer()` for unbounded Flux operations
- ALWAYS `onBackpressureBuffer` / `onBackpressureLatest` for hot publishers
- ALWAYS return `Mono<T>` / `Flux<T>` from WebFlux controllers — never raw types

## PREFER

- PREFER `flatMap` over `map` + `flatMap` chains — keep chains flat
- PREFER `thenReturn(value)` over `.then(Mono.just(value))`
- PREFER `Mono.fromCallable()` over `Mono.just()` for deferred computation
- PREFER `@Transactional` over manual R2DBC transaction management
- PREFER `contextWrite()` for propagating MDC/security context

## WebClient

- ALWAYS configure `responseTimeout` and `connectTimeout`
- ALWAYS `retryWhen(Retry.backoff(...))` with max retries and filter
- NEVER `retry()` without limits — causes infinite retry loops

## Detailed Patterns

For code examples and reactive anti-patterns, see:
- `skills/spring-webflux-patterns` — Mono/Flux chains, backpressure, WebClient
- `agents/spring-webflux-reviewer` — blocking detection, reactive review checklist
