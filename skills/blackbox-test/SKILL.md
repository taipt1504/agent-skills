---
name: blackbox-test
description: >
  Standard for writing black box integration tests in Spring Boot WebFlux projects using the F8A Summer Test framework.
  Use when asked to: (1) create new blackbox/integration test classes, (2) add JSON test cases for API endpoints,
  (3) create WireMock stubs for external services, (4) add test data migrations,
  or any task involving end-to-end API testing with JSON-driven test cases, Testcontainers, and WireMock.
---

# Blackbox Test Standard

## Core Principles

- **JSON-driven**: Test cases defined as JSON files, no HTTP client code in test classes
- **Real database**: PostgreSQL via Testcontainers (JDBC for Flyway + R2DBC for reactive app)
- **Stub external services**: WireMock for all external HTTP dependencies, never `@MockBean`
- **Declarative**: Add tests by writing JSON files, not Java code
- **Isolation**: Each test class gets its own fresh database container

## Technology Stack

- **JUnit 5** — `@TestFactory` + `DynamicTest` for dynamic test generation
- **F8A Summer Test** (`io.f8a.summer:summer-test`) — test execution, case scanning, stub management, database utilities
- **Testcontainers** — `PostgresTestContainer` (F8A wrapper)
- **WireMock** — via `WireMockServiceManager` (F8A wrapper)
- **Flyway** — schema + test data migrations (JDBC)

## Directory Structure

```
src/test/
├── java/
│   ├── blackbox/                              # All blackbox test classes
│   │   ├── {Feature}BlackboxTest.java         # Feature-level or common tests
│   │   └── {domain}/
│   │       └── {Variant}BlackboxTest.java     # Domain/variant-specific tests
│   └── unit/                                  # Unit tests (no Spring context)
│
└── resources/
    ├── application-test.yml                   # Main test profile
    ├── application-{variant}.yml              # Variant/override profiles (optional)
    ├── blackbox/
    │   ├── blackbox_config.json               # Stub services + test case scan config
    │   ├── stubs/
    │   │   └── {service-name}/
    │   │       ├── mappings/*.json            # WireMock request matchers
    │   │       └── __files/*.json             # Response body templates
    │   └── test-cases/
    │       └── {app-name}/
    │           ├── common/                    # Shared/cross-cutting test cases
    │           └── {domain}/                  # Domain-specific test cases
    │               └── {variant}/             # Variant-specific (optional)
    └── db/migration/                          # Test-only Flyway migrations
```

## Workflow: Adding Tests

### Step 1 — Write test case JSON

Place in appropriate path under `src/test/resources/blackbox/test-cases/`.
See [references/test-case-json-patterns.md](references/test-case-json-patterns.md).

### Step 2 — Create WireMock stubs (if new external behavior needed)

Place mappings in `stubs/{service-name}/mappings/`, response bodies in `__files/`.
See [references/wiremock-stub-patterns.md](references/wiremock-stub-patterns.md).

### Step 3 — Register new stub service (if new external service)

Add to `blackbox_config.json` → `stubs.services[]`:

```json
{ "name": "{service-name}", "port": {port}, "stubs_data_path": "src/test/resources/blackbox/stubs/{service-name}", "enabled": true }
```

### Step 4 — Create or update Java test class

See [references/test-class-template.md](references/test-class-template.md).

### Step 5 — Add test data (if needed)

Create Flyway SQL migration in `src/test/resources/db/migration/` with a version that won't conflict with main
migrations.

## Naming Conventions

| Item               | Pattern                             | Example                               |
|--------------------|-------------------------------------|---------------------------------------|
| Test class         | `{Feature}BlackboxTest`             | `PaymentBlackboxTest`                 |
| Test case JSON     | `{feature}-{scenario}.json`         | `payment-create-success.json`         |
| WireMock mapping   | `{action}-{scenario}.json`          | `charge-success.json`                 |
| WireMock response  | `{action}-{scenario}-response.json` | `charge-success-response.json`        |
| Test SQL migration | `V{N}__{Description}.sql`           | `V10_1__Insert_Test_Payment_Data.sql` |
| Override profile   | `application-{variant}.yml`         | `application-stripe-priority.yml`     |

## Required Annotations

```java
@SpringBootTest(classes = {MainApplication}.class, webEnvironment = SpringBootTest.WebEnvironment.DEFINED_PORT)
@ActiveProfiles({"test"})            // add variant profile if needed
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
```

## Key Rules

1. **No `@MockBean`** — stub external HTTP services via WireMock only
2. **No H2** — always use PostgreSQL Testcontainers
3. **`@BeforeEach`** must call `StubConfigurationUtils.resetAllStubs(serviceManager)` for clean state
4. **`@Order(1)`** for database verification test, `@Order(2+)` for `@TestFactory` methods
5. **App on `DEFINED_PORT`** (default 8080), stubs on separate ports (8081+)
6. **Flyway** scans `classpath:db/migration` — picks up both main + test migrations automatically
7. **Test case JSON** scanned via `TestCaseUtils.scanTestCasesRecursively(path)`
8. **`X-Trace-ID`** header routes requests to scenario-specific WireMock stubs
9. **Each test class** starts its own PostgresTestContainer — fresh DB per class, no cross-contamination
10. **Dual DB connection**: JDBC (`spring.datasource.*`, `spring.flyway.*`) for Flyway, R2DBC (`spring.r2dbc.*`) for
    reactive app

## blackbox_config.json Structure

```json
{
  "stubs": {
    "services": [
      {
        "name": "{service-name}",
        "port": {port},
        "stubs_data_path": "src/test/resources/blackbox/stubs/{service-name}",
        "enabled": true
      }
    ]
  },
  "test_cases": {
    "root_path": "src/test/resources/blackbox/test-cases",
    "file_patterns": [".*\\.json$"],
    "timeout_seconds": 30,
    "recursive_scan": true
  }
}
```

## F8A Summer Test Library API Reference

| Class                                                              | Usage                                                |
|--------------------------------------------------------------------|------------------------------------------------------|
| `TestExecutionUtils.executeTestCase(testCase)`                     | Execute HTTP request + validate assertions from JSON |
| `TestCaseUtils.scanTestCasesRecursively(path)`                     | Scan directory for JSON test case files              |
| `StubConfigurationUtils.loadBlackboxConfiguration(path)`           | Load `blackbox_config.json`                          |
| `StubConfigurationUtils.startAllStubServices(manager, stubs)`      | Start all WireMock services                          |
| `StubConfigurationUtils.waitForServicesReady(manager, timeoutSec)` | Wait for stubs to be ready                           |
| `StubConfigurationUtils.resetAllStubs(manager)`                    | Reset all stubs to clean state                       |
| `WireMockServiceManager`                                           | Manages WireMock server lifecycle                    |
| `PostgresTestContainer.create()`                                   | Create PostgreSQL container                          |
| `DatabaseTestUtils.tableExists(container, table)`                  | Check table existence                                |
| `DatabaseTestUtils.getTableRowCount(container, table)`             | Count rows in table                                  |
| `BlackboxTestConfig`                                               | POJO for `blackbox_config.json`                      |
| `TestCaseInfo`                                                     | POJO for individual test case metadata               |
