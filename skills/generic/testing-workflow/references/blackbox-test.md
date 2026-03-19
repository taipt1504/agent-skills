# Blackbox Test Patterns (F8A Summer Test)

JSON-driven integration testing with Testcontainers, WireMock, and Flyway.

---

## Core Principles

- **JSON-driven**: Test cases as JSON files, no HTTP client code in test classes
- **Real database**: PostgreSQL via Testcontainers (JDBC for Flyway + R2DBC for reactive app)
- **Stub external services**: WireMock for all external HTTP dependencies, never `@MockBean`
- **Declarative**: Add tests by writing JSON files, not Java code
- **Isolation**: Each test class gets its own fresh database container

---

## Test Case JSON Structure

```json
{
  "name": "Suite Name - Category",
  "description": "What this suite tests",
  "testCases": [
    {
      "name": "Human-readable test name",
      "description": "What this specific test validates",
      "test": {
        "request": {
          "method": "POST",
          "url": "http://localhost:8080/api/v1/resources",
          "headers": {
            "Content-Type": "application/json",
            "X-Trace-ID": "test-create-success-001"
          },
          "body": {
            "name": "Test Resource",
            "type": "standard"
          }
        }
      },
      "assertions": {
        "status": 200,
        "headers": { "Content-Type": "application/json" },
        "json_path": {
          "$.status": "CREATED",
          "$.name": "Test Resource"
        }
      }
    }
  ]
}
```

## JSON Path Assertions

| Pattern | Description | Example |
|---------|-------------|---------|
| `"$.field": "value"` | Exact string match | `"$.status": "SUCCESS"` |
| `"$.field": 123` | Numeric match | `"$.total": 100` |
| `"$.field": true` | Boolean match | `"$.isActive": true` |
| `"$.field": null` | Null check | `"$.deletedAt": null` |
| `"$.array.length()": 3` | Array length | `"$.items.length()": 3` |
| `"$.array[0]": "val"` | Array element | `"$.ids[0]": "id-001"` |
| `"$.nested.field": "val"` | Nested object | `"$.data.name": "test"` |

## X-Trace-ID Convention

Format: `test-{scenario}-{sequence}` (e.g., `test-create-success-001`)

- WireMock mappings match on this header via regex to return scenario-specific responses
- Enables multiple scenarios (success, error, timeout) against the same endpoint

---

## Test Case Examples

### Success -- POST Create

```json
{
  "name": "Create Resource Success",
  "test": {
    "request": {
      "method": "POST",
      "url": "http://localhost:8080/api/v1/resources",
      "headers": { "Content-Type": "application/json", "X-Trace-ID": "test-create-success-001" },
      "body": { "name": "Test Resource", "type": "standard", "data": { "key": "value" } }
    }
  },
  "assertions": {
    "status": 200,
    "json_path": { "$.status": "CREATED", "$.name": "Test Resource" }
  }
}
```

### Error -- Missing Required Field (400)

```json
{
  "name": "Missing Required Field",
  "test": {
    "request": {
      "method": "POST",
      "url": "http://localhost:8080/api/v1/resources",
      "headers": { "Content-Type": "application/json" },
      "body": { "type": "standard" }
    }
  },
  "assertions": { "status": 400 }
}
```

### Error -- External Service Failure (via X-Trace-ID routing)

```json
{
  "name": "External Service Error",
  "test": {
    "request": {
      "method": "POST",
      "url": "http://localhost:8080/api/v1/resources",
      "headers": { "Content-Type": "application/json", "X-Trace-ID": "test-upstream-error-001" },
      "body": { "name": "Test", "type": "standard" }
    }
  },
  "assertions": {
    "status": 502,
    "json_path": { "$.error": "UPSTREAM_ERROR" }
  }
}
```

---

## WireMock Stub Patterns

### Directory Layout

```
stubs/{service-name}/
├── mappings/                  # Request matching rules
│   ├── {action}-success.json
│   └── {action}-error.json
└── __files/                   # Response body templates
    ├── {action}-success-response.json
    └── {action}-error-response.json
```

### Success Mapping (with response-template transformer)

```json
{
  "priority": 1,
  "request": {
    "method": "POST",
    "urlPath": "/{service-path}/{endpoint}",
    "headers": {
      "Content-Type": { "equalTo": "application/json" },
      "X-Trace-ID": { "matches": ".*-success-.*" }
    }
  },
  "response": {
    "status": 200,
    "headers": { "Content-Type": "application/json" },
    "bodyFileName": "{action}-success-response.json",
    "transformers": ["response-template"]
  }
}
```

### Error Mapping

```json
{
  "priority": 2,
  "request": {
    "method": "POST",
    "urlPath": "/{service-path}/{endpoint}",
    "headers": { "X-Trace-ID": { "matches": ".*-error-.*" } }
  },
  "response": {
    "status": 500,
    "body": "{\"code\": \"ERROR\", \"message\": \"Internal server error\"}"
  }
}
```

### Response Body Template (in `__files/`)

```json
{
  "code": "SUCCESS",
  "data": {
    "requestTime": "{{now format='yyyy-MM-dd HH:mm:ss'}}",
    "id": "{{jsonPath request.body '$.id'}}",
    "traceId": "{{request.headers.X-Trace-ID}}"
  }
}
```

### Template Helpers

| Helper | Description |
|--------|-------------|
| `{{now format='yyyy-MM-dd'}}` | Current timestamp |
| `{{now offset='5 seconds'}}` | Time offset |
| `{{jsonPath request.body '$.field'}}` | Extract from request body |
| `{{request.headers.Header-Name}}` | Echo request header |
| `{{randomValue type='UUID'}}` | Generate UUID |

### Priority Rules

- Lower number = higher priority (`priority: 1` matches before `priority: 2`)
- Scenario-specific mappings (with header matchers) get lower priority number
- Default/fallback mappings get higher priority number

### Request Matching Options

| Matcher | Example |
|---------|---------|
| `urlPath` | `"/api/v1/users"` (exact) |
| `urlPathPattern` | `"/api/v1/users/.*"` (regex) |
| `equalTo` | `{ "equalTo": "application/json" }` |
| `matches` | `{ "matches": ".*-success-.*" }` |
| `contains` | `{ "contains": "Bearer" }` |
| `bodyPatterns` | `[{ "matchesJsonPath": "$.name" }]` |

---

## Test Class Template

```java
@SpringBootTest(
    classes = {MainApplication}.class,
    webEnvironment = SpringBootTest.WebEnvironment.DEFINED_PORT)
@ActiveProfiles({"test"})
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class {Feature}BlackboxTest {

  private static final Logger logger = LoggerFactory.getLogger({Feature}BlackboxTest.class);
  private static WireMockServiceManager serviceManager;

  private static final String CONFIG_PATH =
      System.getProperty("blackbox.config.path",
          "src/test/resources/blackbox/blackbox_config.json");
  private static final String TEST_CASES_PATH =
      System.getProperty("blackbox.test.cases.{feature}",
          "src/test/resources/blackbox/test-cases/{app-name}/{domain}/{feature}");

  @Container
  static PostgresTestContainer postgres =
      PostgresTestContainer.create()
          .withDatabaseName("test_db")
          .withUsername("testuser")
          .withPassword("testpass");

  @DynamicPropertySource
  static void configureProperties(DynamicPropertyRegistry registry) {
    registry.add("spring.datasource.url", postgres::getJdbcUrl);
    registry.add("spring.datasource.username", postgres::getUsername);
    registry.add("spring.datasource.password", postgres::getPassword);
    registry.add("spring.r2dbc.url", postgres::getR2dbcUrl);
    registry.add("spring.r2dbc.username", postgres::getUsername);
    registry.add("spring.r2dbc.password", postgres::getPassword);
    registry.add("spring.flyway.url", postgres::getJdbcUrl);
    registry.add("spring.flyway.user", postgres::getUsername);
    registry.add("spring.flyway.password", postgres::getPassword);
    registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
    registry.add("spring.flyway.enabled", () -> "true");
  }

  @BeforeAll
  static void setUpAll() throws Exception {
    serviceManager = new WireMockServiceManager();
    BlackboxTestConfig config = StubConfigurationUtils.loadBlackboxConfiguration(CONFIG_PATH);
    StubConfigurationUtils.startAllStubServices(serviceManager, config.getStubs());
    StubConfigurationUtils.waitForServicesReady(serviceManager, 30);
  }

  @AfterAll
  static void tearDownAll() {
    if (serviceManager != null) { serviceManager.stopAllServers(); }
  }

  @BeforeEach
  void setUp() { StubConfigurationUtils.resetAllStubs(serviceManager); }

  @Test
  @Order(1)
  @DisplayName("Should verify database setup")
  void testInitialDataExists() {
    assertTrue(DatabaseTestUtils.tableExists(postgres, "{table_name}"));
    assertEquals({expected_count},
        DatabaseTestUtils.getTableRowCount(postgres, "{table_name}"));
  }

  @TestFactory
  @DisplayName("{Feature} Tests")
  @Order(2)
  Stream<DynamicTest> run{Feature}TestCases() throws IOException {
    List<TestCaseInfo> testCases = TestCaseUtils.scanTestCasesRecursively(TEST_CASES_PATH);
    return testCases.stream()
        .map(testCase -> DynamicTest.dynamicTest(
            testCase.getDisplayName(),
            () -> executeTestCase(testCase)));
  }
}
```

### Placeholders

| Placeholder | Example |
|-------------|---------|
| `{MainApplication}` | `NotificationGatewayMsApplication` |
| `{Feature}` | `Payment` (PascalCase) |
| `{feature}` | `payment` (lowercase) |
| `{domain}` | `sms`, `order` |
| `{app-name}` | `notification-gateway` |
| `{table_name}` | `orders` |
| `{expected_count}` | `5` |

---

## File Organization

```
src/test/
├── java/
│   ├── blackbox/                              # All blackbox test classes
│   │   ├── {Feature}BlackboxTest.java
│   │   └── {domain}/
│   │       └── {Variant}BlackboxTest.java
│   └── unit/
│
└── resources/
    ├── application-test.yml
    ├── blackbox/
    │   ├── blackbox_config.json
    │   ├── stubs/{service-name}/
    │   │   ├── mappings/*.json
    │   │   └── __files/*.json
    │   └── test-cases/{app-name}/
    │       ├── common/
    │       └── {domain}/
    │           └── {variant}/
    └── db/migration/                          # Test-only Flyway migrations
```

## blackbox_config.json

```json
{
  "stubs": {
    "services": [
      {
        "name": "{service-name}",
        "port": 8081,
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

## Naming Conventions

| Item | Pattern | Example |
|------|---------|---------|
| Test class | `{Feature}BlackboxTest` | `PaymentBlackboxTest` |
| Test case JSON | `{feature}-{scenario}.json` | `payment-create-success.json` |
| WireMock mapping | `{action}-{scenario}.json` | `charge-success.json` |
| WireMock response | `{action}-{scenario}-response.json` | `charge-success-response.json` |
| Test SQL migration | `V{N}__{Description}.sql` | `V10_1__Insert_Test_Payment_Data.sql` |

## F8A Summer Test API

| Class | Usage |
|-------|-------|
| `TestExecutionUtils.executeTestCase(testCase)` | Execute HTTP request + validate assertions |
| `TestCaseUtils.scanTestCasesRecursively(path)` | Scan directory for JSON test cases |
| `StubConfigurationUtils.loadBlackboxConfiguration(path)` | Load config |
| `StubConfigurationUtils.startAllStubServices(mgr, stubs)` | Start WireMock services |
| `StubConfigurationUtils.waitForServicesReady(mgr, timeout)` | Wait for stubs |
| `StubConfigurationUtils.resetAllStubs(mgr)` | Reset to clean state |
| `WireMockServiceManager` | Manages WireMock lifecycle |
| `PostgresTestContainer.create()` | Create PostgreSQL container |
| `DatabaseTestUtils.tableExists(container, table)` | Check table existence |
| `DatabaseTestUtils.getTableRowCount(container, table)` | Count rows |

## Key Rules

1. **No `@MockBean`** -- stub external HTTP via WireMock only
2. **No H2** -- always PostgreSQL Testcontainers
3. **`@BeforeEach`** must call `StubConfigurationUtils.resetAllStubs(serviceManager)`
4. **`@Order(1)`** for DB verification, `@Order(2+)` for `@TestFactory`
5. **App on `DEFINED_PORT`** (8080), stubs on 8081+
6. **Dual DB connection**: JDBC for Flyway, R2DBC for reactive app
7. **`X-Trace-ID`** header routes requests to scenario-specific stubs
8. Each test class starts its own container -- no cross-contamination
