---
name: architecture-patterns
description: Hexagonal architecture, CQRS, domain events, reactive rules, saga pattern
globs: "*.java"
---

# Architecture Patterns

## Hexagonal Architecture

Dependencies flow **inward only**: Interfaces → Application → Domain ← Infrastructure

| Layer | Allowed Dependencies | Forbidden |
|-------|---------------------|-----------|
| `domain/` | Nothing (pure Java) | Spring, JPA, Kafka, Redis |
| `application/` | `domain/` only | Infrastructure, controllers |
| `infrastructure/` | `domain/`, `application/` | `interfaces/` |
| `interfaces/` | `application/`, `domain/` DTOs | Direct infra access |

Domain entities MUST NOT appear in API responses — map to DTOs at interfaces layer.

## CQRS

| Side | Responsibility | Returns |
|------|---------------|---------|
| Command | Write, state changes, events | `Mono<Void>` or `Mono<ID>` |
| Query | Read, projections | `Mono<DTO>` or `Flux<DTO>` |

Never mix read and write logic in the same handler.

## Domain Events & Outbox

- Events are **immutable records**, named `{Entity}{PastTense}Event`
- Published after successful state change; consumers must be **idempotent**
- Outbox pattern: write event to `outbox` table in SAME transaction as aggregate change

## Reactive Rules

- **NEVER** `.block()`, `.blockFirst()`, `.blockLast()`, `Thread.sleep()`, `RestTemplate`
- **NEVER** `.subscribe()` inside a reactive chain — compose with `flatMap`/`then`
- **ALWAYS** `StepVerifier` for testing — `Schedulers.boundedElastic()` for blocking I/O
- **ALWAYS** `switchIfEmpty(Mono.defer(...))` — `onErrorResume`/`onErrorMap` for errors
- **ALWAYS** `limitRate()`/`buffer()` for unbounded Flux; return `Mono<T>`/`Flux<T>` from controllers

## Saga Pattern

- Each step must have a compensating action (rollback)
- Use unique saga ID for correlation; timeout + dead letter for stuck sagas
