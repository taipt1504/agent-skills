---
name: testing-workflow
description: >
  Unified testing workflow: TDD (RED/GREEN/REFACTOR), blackbox integration testing
  with F8A Summer Test (JSON-driven test cases, WireMock, Testcontainers), and
  7-phase verification pipeline (compile, unit, integration, coverage, security,
  static analysis, diff review). Use when writing or modifying tests, configuring
  JaCoCo coverage, running verification pipelines, using StepVerifier, MockMvc,
  WebTestClient, or setting up Testcontainers.
triggers:
  natural: ["write test", "tdd", "coverage", "testcontainers", "step verifier"]
  code: ["*Test.java", "StepVerifier", "@SpringBootTest", "Testcontainers"]
---

# Testing Workflow

## TDD Cycle

**RED** -- write a failing test. **GREEN** -- minimal code to pass. **REFACTOR** -- clean up, tests stay green.

```java
// RED: write test first
@Test void shouldCreateOrderWhenValidInput() {
    StepVerifier.create(orderService.create(validCommand))
        .assertNext(o -> assertThat(o.getStatus()).isEqualTo(OrderStatus.PENDING))
        .verifyComplete();
}
// GREEN: ./gradlew test  -> implement until pass
// REFACTOR: ./gradlew test jacocoTestReport  -> clean up, verify coverage >= 80%
```

## Test Pyramid

| Type | Annotation | Speed | Use For |
|------|-----------|-------|---------|
| Unit | `@ExtendWith(MockitoExtension.class)` | Fast | Service/domain logic |
| Controller (WebFlux) | `@SpringBootTest + @AutoConfigureWebTestClient` | Medium | API contracts |
| Controller (MVC) | `@WebMvcTest` | Medium | API contracts, auth |
| Repository (R2DBC) | `@DataR2dbcTest` | Medium | DB queries |
| Repository (JPA) | `@DataJpaTest` | Medium | JPA queries |
| Blackbox | `@SpringBootTest(DEFINED_PORT) + @Testcontainers` | Slow | Full-stack JSON-driven |
| E2E | `@SpringBootTest + @Testcontainers` | Slow | Full flows |

**Ratio:** unit > integration > E2E. Coverage minimum: **80% line coverage** (JaCoCo).

## Verification Pipeline (7 Phases)

| Phase | What | Gate |
|-------|------|------|
| 1. Compile | Build sources + tests | STOP on fail |
| 2. Unit Tests | Fast tests | STOP on fail |
| 3. Integration | Testcontainers tests | STOP on fail |
| 4. Coverage | JaCoCo check | BLOCK < 60% |
| 5. Security | OWASP + secrets scan | BLOCK CRITICAL |
| 6. Static Analysis | .block(), @Autowired, debug stmts | CRITICAL: .block() |
| 7. Diff Review | Changed files review | Manual |

For full commands per phase, see references/verification-pipeline.md.

## Quick Verification Modes

| Mode | Phases | Use Case |
|------|--------|----------|
| `quick` | 1-2 | During development |
| `standard` | 1-4 | Before committing |
| `full` | 1-7 | Before PR / release |
| `security` | 5-6 | Security-focused review |

## Naming & Organization

- Test methods: `shouldDoXWhenY` (e.g., `shouldReturnOrderWhenIdExists`)
- Files: `src/test/java/{unit,integration,e2e,blackbox}/`
- Blackbox JSON: `src/test/resources/blackbox/test-cases/{app}/{domain}/`
- Shared data: `TestDataFactory.java` with builder methods (no random/hardcoded values)

## Key Rules

- **StepVerifier** for all reactive assertions (never `Thread.sleep`)
- **Testcontainers** with `.withReuse(true)` for local speed
- **No `@MockBean`** in blackbox tests -- use WireMock stubs
- **No H2** -- always real DB via Testcontainers
- **`@BeforeEach` cleanup** -- independent tests, no shared state
- **Test slices** (`@WebMvcTest`, `@DataR2dbcTest`) over `@SpringBootTest` for unit/slice tests

## References

Load as needed for full patterns and code examples:

- **[references/tdd-patterns.md](references/tdd-patterns.md)** -- Unit tests (JUnit 5 + Mockito + StepVerifier), WebFlux/MVC integration tests, R2DBC/JPA repository tests, Kafka tests, mocking patterns, JaCoCo config, common mistakes
- **[references/blackbox-test.md](references/blackbox-test.md)** -- JSON-driven test cases (F8A Summer Test), test case structure, JSON path assertions, WireMock stub patterns, test class template, file organization
- **[references/verification-pipeline.md](references/verification-pipeline.md)** -- Full 7-phase pipeline detail, commands per phase, static analysis checks, diff review process

## Related Skills

- **summer-test** — Summer-specific Testcontainers, WireMock, blackbox test JSON format
- **spring-patterns** — StepVerifier (WebFlux) and MockMvc (MVC) test patterns
- **database-patterns** — @DataR2dbcTest, @DataJpaTest, Flyway migration testing
- **coding-standards** — Test naming conventions (shouldDoXWhenY)
