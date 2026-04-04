---
name: summer-test
description: Summer Framework testing — PostgresTestContainer setup with Flyway, WireMockServiceManager for stub services, blackbox test configuration and test-case JSON format, and test organization patterns.
triggers:
  natural: ["summer test", "blackbox test", "summer testcontainer"]
  code: ["summer-test", "BlackboxTest", "WireMockServiceManager"]
requires: ["summer-core", "testing-workflow"]
---

# Summer Test — Containers, WireMock & Blackbox

**Gate:** Verify summer-core is loaded and io.f8a.summer:summer-platform is in build.gradle before proceeding.

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

Methods: `getJdbcUrl()`, `getR2dbcUrl()`, `getUsername()`, `getPassword()`, `runFlywayMigrations(path)`, `executeSqlScript(path)`, `createConnection()`.

For database assertion utilities (tableExists, getTableRowCount, executeUpdate, queryForString), see `references/blackbox-config.md` — DatabaseTestUtils section.

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

`@SpringBootTest(webEnvironment = RANDOM_PORT)` binds to an ephemeral port. The `base_url` in `blackbox_config.json` must use `http://localhost:8080` only when the app runs on a fixed port (`DEFINED_PORT`). With `RANDOM_PORT`, inject the actual port via `@LocalServerPort` and construct the base URL dynamically — do not hardcode 8080 in config.

See `references/blackbox-config.md` for full config JSON format and test-case JSON schema.

## Rules

- Always use `PostgresTestContainer.create()` for integration tests — never hardcode JDBC/R2DBC URLs.
- Always use `@DynamicPropertySource` to wire container URLs — never rely on static config files for test DB.
- Always use `RANDOM_PORT` with `@LocalServerPort` — never hardcode port 8080 in test config.
- Never start WireMock stubs without calling `stopAllServices()` in `@AfterAll` — port leaks break CI.
- Always use `TestCaseUtils.loadTestCases()` for blackbox tests — enables JSON-driven test data.

## Related Skills

- **summer-core** — Shared types (Member, ViewableException) used in test assertions
- **summer-security** — `@AuthRoles` testing with mock `X-Userinfo` header
- **testing-workflow** — General testing patterns, StepVerifier, WebTestClient
- **database-patterns** — R2DBC test patterns, Flyway migration testing
