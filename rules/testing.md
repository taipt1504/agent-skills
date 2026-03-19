---
name: testing
description: Testing requirements — coverage, test types, TDD cycle, agent support
globs: "*.java"
---

# Testing Requirements

## Minimum Coverage: 80% (JaCoCo)

## Test Types (ALL required)

1. **Unit Tests** — Individual functions, utilities, domain logic
2. **Integration Tests** — API endpoints, database operations (Testcontainers)
3. **Blackbox Tests** — End-to-end API tests (JSON-driven, WireMock, Testcontainers)
4. **E2E Tests** — Critical API flows (WebTestClient + Testcontainers)

## TDD Cycle (MANDATORY)

1. Write test first from spec scenarios (RED)
2. Run test — it MUST fail
3. Write minimal implementation (GREEN)
4. Run test — it MUST pass
5. Refactor while tests stay green (IMPROVE)
6. Verify coverage (80%+)

## Key Rules

- ALWAYS `StepVerifier` for reactive tests — NEVER `.block()` in tests
- ALWAYS test data via factory methods — not random/hardcoded values
- ALWAYS check test isolation — no shared mutable state
- Fix implementation, not tests (unless tests are wrong)
- Test method naming: `should{Do}When{Condition}`

## Agent Support

- **implementer** — Use PROACTIVELY for new features; enforces write-tests-first (TDD)
- **test-runner** — Use after API implementation; E2E + blackbox testing specialist
