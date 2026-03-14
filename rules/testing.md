# Testing Requirements

## Minimum Test Coverage: 80%

Test Types (ALL required):

1. **Unit Tests** - Individual functions, utilities, components
2. **Integration Tests** - API endpoints, database operations
3. **Blackbox Tests** - End-to-end API tests for all implemented endpoints
4. **E2E Tests** - Critical user flows (Playwright)

## Test-Driven Development

MANDATORY workflow:

1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
5. Refactor (IMPROVE)
6. Verify coverage (80%+)

## Blackbox Testing (API Implementation)

MANDATORY for all API endpoint tasks:

1. After implementing API endpoints, spawn **blackbox-test-runner** agent
2. Agent uses **blackbox-test** skill automatically
3. Writes JSON-driven test cases with WireMock stubs and Testcontainers
4. Runs full cycle: analyze → write → run → fix → verify 100% pass

## Troubleshooting Test Failures

1. Use **tdd-guide** agent
2. Check test isolation
3. Verify mocks are correct
4. Fix implementation, not tests (unless tests are wrong)

## Agent Support

- **tdd-guide** - Use PROACTIVELY for new features, enforces write-tests-first
- **blackbox-test-runner** - Use PROACTIVELY after API implementation, uses `blackbox-test` skill
- **e2e-runner** - Playwright E2E testing specialist
