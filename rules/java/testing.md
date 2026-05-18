---
name: testing
description: Testing rules — TDD cycle, test pyramid, ArchUnit enforcement, contract testing, Testcontainers, coverage requirements
globs: "*.java"
---

# Testing Rules

## Philosophy

Tests verify correctness and document intent. Test suite = executable specification — test names tell you what system does.

## Minimum Coverage: 80% (JaCoCo)

Meaningful coverage over vanity metrics. 80% verifying behavior beats 100% with trivial getter/setter tests. Coverage measures what's executed, not what's verified.

## Test Pyramid

| Layer | Ratio | Annotation | Speed | Tests For |
|-------|-------|-----------|-------|-----------|
| Unit | ~70% | `@ExtendWith(MockitoExtension.class)` | <100ms | Domain logic, services, value objects |
| Integration | ~20% | `@SpringBootTest` + Testcontainers | 1-10s | API endpoints, DB queries, messaging |
| E2E / Blackbox | ~10% | `@SpringBootTest(DEFINED_PORT)` + Testcontainers | 10-60s | Critical business flows, JSON-driven |

Pyramid reflects execution time and maintenance cost — not importance. Integration tests catch most production bugs; unit tests give fastest feedback.

## TDD Cycle (MANDATORY)

1. **RED** — Write test first from spec scenarios. Run it — MUST fail. Test that passes before implementation proves nothing.
2. **GREEN** — Write minimal code to pass. Resist gold-plating.
3. **REFACTOR** — Clean up while tests stay green. Run `./gradlew test jacocoTestReport` to verify coverage ≥80%.

```java
// RED: test first
@Test void shouldRejectOrderWhenInsufficientInventory() {
    StepVerifier.create(orderService.create(orderWithQuantity(100)))
        .expectError(InsufficientInventoryException.class)
        .verify();
}
// GREEN: implement until pass
// REFACTOR: clean up, tests stay green
```

## Key Rules

### Test Quality
- **Test behavior, not implementation** — test what system does, not how. Don't test private methods, getters, or setters.
- **Fix implementation, not tests** — failing test = wrong implementation (unless test has clear bug).
- **Test naming**: `should{Do}When{Condition}` — reads as spec: "should reject order when insufficient inventory"
- **Test data**: Use `TestDataFactory` with builder methods — never random values, never hardcoded magic numbers.

### Reactive Testing
- ALWAYS `StepVerifier` for reactive assertions — never `.block()` in tests (it masks timing issues and backpressure bugs)
- ALWAYS `Mono.delay()` instead of `Thread.sleep()` for timing in tests
- PREFER `BlockHound` in test suite to detect hidden blocking calls:
  ```java
  @BeforeAll
  static void installBlockHound() {
      BlockHound.install();
  }
  ```

### Database Testing
- ALWAYS Testcontainers with real database — never H2 in-memory (H2 differs: missing PostgreSQL features, different SQL syntax, no jsonb)
- ALWAYS `@DynamicPropertySource` for container URLs — never hardcode connection strings
- PREFER `.withReuse(true)` for local dev speed (containers survive test restarts)
- Use test slices (`@DataR2dbcTest`, `@DataJpaTest`) for repository tests — faster than full `@SpringBootTest`

### Test Isolation
- ALWAYS `@BeforeEach` cleanup — no shared mutable state between tests
- NEVER depend on test execution order
- NEVER use `@MockBean` in blackbox tests — use WireMock stubs for external dependencies

## ArchUnit — Architecture as Tests

Enforce architectural invariants as executable tests — prevents drift manual review misses:

```java
@AnalyzeClasses(packages = "com.example")
class ArchitectureTest {
    @ArchTest static final ArchRule domainIndependence =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat().resideInAPackage("org.springframework..");

    @ArchTest static final ArchRule noCycles =
        slices().matching("com.example.(*)..").should().beFreeOfCycles();

    @ArchTest static final ArchRule repositoriesNotCallingControllers =
        noClasses().that().haveSimpleNameEndingWith("Repository")
            .should().dependOnClassesThat().haveSimpleNameEndingWith("Controller");
}
```

Include ArchUnit in every project with >50 classes. Tests run in milliseconds, catch violations immediately.

## Contract Testing

For service-to-service communication, use Spring Cloud Contract to verify API compatibility:

- **Consumers** define expected contracts (request/response pairs)
- **Providers** verify compliance without full E2E
- `@AutoConfigureStubRunner` injects running stubs in consumer tests

Contract tests catch breaking changes at build time — not in production.

## Agent Support

- **slice-executor** — Use PROACTIVELY for new features; enforces TDD (write-tests-first)
- **slice-executor** — Use after API implementation; E2E + blackbox testing specialist

## Related Skills

- **testing-workflow** — Full TDD patterns, verification pipeline, StepVerifier examples
- **summer-test** — Summer-specific Testcontainers, WireMock, blackbox test JSON format
- **database-patterns** — @DataR2dbcTest, @DataJpaTest patterns
- **architecture** — ArchUnit enforcement rules for hexagonal architecture
