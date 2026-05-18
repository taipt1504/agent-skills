---
name: summer-test
description: Summer Framework testing — PostgresTestContainer setup with Flyway, WireMockServiceManager for stub services, blackbox test configuration and test-case JSON format, and test organization patterns.
triggers:
  natural: ["summer test", "blackbox test", "summer testcontainer"]
  code: ["summer-test", "BlackboxTest", "WireMockServiceManager"]
requires: ["summer-core", "testing-workflow"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Test.java", "**/*IT.java", "**/*Spec.java"]
    code_patterns: ["io.f8a.summer.test", "AbstractBlackboxTest", "f8a.test"]
    task_keywords: ["summer test", "blackbox test", "summer testcontainer", "integration test"]
    related_skills: ["testing-workflow"]
    related_rules:
      - rules/java/testing.md
relevance_assessment: |
  HIGH 90%+: new blackbox integration test OR Summer-specific testcontainer setup
  HIGH 80%+: existing test using Summer test fixtures
  MEDIUM 40-79%: unit test for code that integrates with Summer services
  LOW 1-39%: test using vanilla Spring Boot Test (should migrate)
  ZERO: project lacks io.f8a.summer:summer-test
---

# Summer Test — Containers, WireMock & Blackbox

**Gate:** Verify summer-core loaded and `io.f8a.summer:summer-platform` in build.gradle.

**Module:** `summer-test` | **Dependency:** `testImplementation 'io.f8a.summer:summer-test'`

## PostgresTestContainer

```java
@Testcontainers
class UserServiceIntegrationTest {

    @Container
    static PostgresTestContainer postgres = PostgresTestContainer.create()
        .withDatabaseName("testdb")
        .withUsername("testuser")
        .withPassword("testpass");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", postgres::getR2dbcUrl);
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.flyway.url", postgres::getJdbcUrl);
        registry.add("spring.flyway.user", postgres::getUsername);
        registry.add("spring.flyway.password", postgres::getPassword);
    }

    @BeforeAll
    static void setup() {
        postgres.runFlywayMigrations("classpath:db/migration");
    }
}
```

Methods: `getJdbcUrl()`, `getR2dbcUrl()`, `getUsername()`, `getPassword()`, `runFlywayMigrations(path)`, `executeSqlScript(path)`, `createConnection()`. DB assertion utils (tableExists, getTableRowCount, executeUpdate, queryForString) → `references/blackbox-config.md` DatabaseTestUtils.

## WireMockServiceManager

```java
WireMockServiceManager wm = new WireMockServiceManager();
wm.startService("payment-service", 8081, "src/test/resources/blackbox/stubs/payment-service");
// ... tests ...
wm.stopAllServices();
```

## Blackbox Testing

Directory structure:
```
src/test/resources/blackbox/
├── blackbox_config.json      # Main config
├── stubs_config.json         # Stub-only config
├── stubs/                    # WireMock stubs per service
│   └── <service>/mappings/   # Request mappings
│   └── <service>/__files/    # Response templates
└── test-cases/               # Test case JSONs
```

### Test Implementation

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@TestMethodOrder(OrderAnnotation.class)
public class UserServiceBlackboxTest {
    private static WireMockServiceManager serviceManager;

    @BeforeAll
    static void setUpAll() throws Exception {
        var config = BlackboxTestUtils.loadConfiguration("src/test/resources/blackbox/blackbox_config.json");
        serviceManager = new WireMockServiceManager();
        config.getStubs().getServices().stream()
            .filter(ServiceConfig::isEnabled)
            .forEach(s -> serviceManager.startService(s.getName(), s.getPort(), s.getStubsDataPath()));
    }

    @TestFactory
    Stream<DynamicTest> crudOperations() {
        return TestCaseUtils.loadTestCases("src/test/resources/blackbox/test-cases/user-service/crud-operations.json")
            .stream()
            .map(tc -> DynamicTest.dynamicTest(tc.getName(), () -> executeTestCase(tc)));
    }

    @AfterAll
    static void tearDown() { serviceManager.stopAllServices(); }
}
```

### Standalone Stub Runner

```java
WireMockServiceManager sm = new WireMockServiceManager();
var config = StubConfigurationUtils.loadStubsConfiguration("src/test/resources/blackbox/stubs_config.json");
StubConfigurationUtils.startAllStubServices(sm, config);
```

Gradle task: `./gradlew runStubs`

## Test Authentication (@AuthRoles-Protected Endpoints)

Construct a mock `X-Userinfo` header for blackbox tests against APISIX-secured endpoints:

```java
String userInfo = Base64.getEncoder().encodeToString(
    """{"sub":"test-user","preferred_username":"test","realm_access":{"roles":["user"]}}""".getBytes()
);
webTestClient.get().uri("/api/resource")
    .header("X-Userinfo", userInfo)
    .exchange()
    .expectStatus().isOk();
```

## RANDOM_PORT vs DEFINED_PORT

`RANDOM_PORT` binds to ephemeral port. `base_url` in `blackbox_config.json` only hardcodes 8080 when using `DEFINED_PORT`. With `RANDOM_PORT`, inject via `@LocalServerPort` and build URL dynamically.

Full config JSON format + test-case JSON schema → `references/blackbox-config.md`.

## Rules

- `PostgresTestContainer.create()` for integration tests — never hardcode JDBC/R2DBC URLs
- `@DynamicPropertySource` to wire container URLs — never static config files for test DB
- `RANDOM_PORT` + `@LocalServerPort` — never hardcode port 8080 in test config
- Always call `stopAllServices()` in `@AfterAll` — port leaks break CI
- `TestCaseUtils.loadTestCases()` for blackbox tests — enables JSON-driven test data

## Related Skills

- **summer-core** — Shared types (Member, ViewableException) used in test assertions
- **summer-security** — `@AuthRoles` testing with mock `X-Userinfo` header
- **testing-workflow** — General testing patterns, StepVerifier, WebTestClient
- **database-patterns** — R2DBC test patterns, Flyway migration testing
