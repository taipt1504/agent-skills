---
name: testing-workflow
description: >
  Unified testing workflow — TDD (RED/GREEN/REFACTOR), blackbox integration testing with
  F8A Summer Test (JSON test cases, WireMock, Testcontainers), and 7-phase verification
  pipeline. Use when writing unit or integration tests, generating test scaffolds, configuring
  JaCoCo coverage thresholds, using StepVerifier for reactive tests, MockMvc/WebTestClient
  for API tests, or setting up Testcontainers. Includes scripts/generate-test-scaffold.sh.
triggers:
  natural: ["write test", "tdd", "coverage", "testcontainers", "step verifier"]
  code: ["*Test.java", "StepVerifier", "@SpringBootTest", "Testcontainers"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Test.java", "**/*IT.java", "**/*Spec.java", "**/*Mock*.java"]
    code_patterns: ["@Test", "@WebMvcTest", "@WebFluxTest", "@SpringBootTest", "MockMvc", "WebTestClient", "StepVerifier", "Testcontainers"]
    task_keywords: ["test", "TDD", "unit test", "integration test", "coverage", "mock", "JUnit", "Mockito", "Testcontainers"]
    related_rules:
      - rules/java/testing.md
      - rules/common/spec-driven.md
relevance_assessment: |
  HIGH 100%: BUILD phase (TDD mandatory)
  HIGH 90%+: any test file edit
  HIGH 80%+: production code change (new tests required to maintain 80%+ coverage)
  MEDIUM 40-79%: refactor without behavior change (existing tests must stay green)
  LOW 1-39%: documentation-only change
  ZERO: trivial typo fix in non-test, non-production file
---

# Testing Workflow

## TDD Cycle

**RED** — failing test. **GREEN** — minimal code to pass. **REFACTOR** — clean up, tests stay green.

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

**Ratio:** unit > integration > E2E. Min coverage: **80% line** (JaCoCo).

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

Full commands per phase → `references/verification-pipeline.md`.

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
- **No `@MockBean`** in blackbox tests — use WireMock stubs
- **No H2** — always real DB via Testcontainers
- **`@BeforeEach` cleanup** — independent tests, no shared state
- **Test slices** (`@WebMvcTest`, `@DataR2dbcTest`) over `@SpringBootTest` for unit/slice tests

## References

- **[references/tdd-patterns.md](references/tdd-patterns.md)** — Unit tests (JUnit 5 + Mockito + StepVerifier), WebFlux/MVC, R2DBC/JPA, Kafka, mocking, JaCoCo, common mistakes
- **[references/blackbox-test.md](references/blackbox-test.md)** — JSON-driven test cases (F8A Summer Test), structure, JSON path assertions, WireMock stubs, template, file org
- **[references/verification-pipeline.md](references/verification-pipeline.md)** — 7-phase detail, commands, static analysis, diff review

## Related Skills

- **summer-test** — Summer-specific Testcontainers, WireMock, blackbox test JSON format
- **spring-webflux-patterns** — StepVerifier (WebFlux) and MockMvc (MVC) test patterns
- **database-patterns** — @DataR2dbcTest, @DataJpaTest, Flyway migration testing
- **coding-standards** — Test naming conventions (shouldDoXWhenY)
