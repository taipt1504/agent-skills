# CONTEXT.md — Project shared language

> Domain vocabulary, architecture decisions, naming conventions, tech-stack specifics.
> Persists in git. Updated by Align gate when new terminology surfaces.
> Loaded by SessionStart hook into agent context.

## Domain vocabulary

Project-specific terms, acronyms, custom verbs. One bullet per term. Concise.

Example format:
- **<Term>**: <definition in 1-2 sentences>
- **<Acronym>**: <full form + meaning>

(Populated during `/align` sessions.)

## Architecture decisions

Pointer to `docs/adr/` for full ADRs. Summary one-liners here for quick reference.

Example:
- ADR-0001: Use PostgreSQL for primary store (vs MySQL). Reasoning: JSON support, partial indexes.
- ADR-0002: Adopt hexagonal architecture for domain boundaries.

## Naming conventions

Project-specific naming rules beyond CLAUDE.md defaults.

Example:
- Use case classes: `<Verb><Noun>UseCase` (e.g., `CreateOrderUseCase`)
- Domain events: `<Noun><PastVerb>Event` (e.g., `OrderCreatedEvent`)
- Database tables: `snake_case`, plural (e.g., `merchant_users`)

## Tech stack specifics

Versions and config choices that affect implementation.

Example:
- Java 21 (Loom virtual threads enabled)
- Spring Boot 3.5.x with Spring WebFlux
- PostgreSQL 16 + R2DBC
- Kafka 3.7 + Avro schemas via Confluent Schema Registry
- Testcontainers for integration tests

## Cross-service contracts (if microservices)

API contracts, event schemas, shared libraries.

Example:
- Auth API: OpenAPI spec at `docs/api/auth-v1.yaml`
- Payment events: Avro schemas at `schemas/payment/`
- Common DTOs: `com.example.shared:common-dtos:2.4.0`
