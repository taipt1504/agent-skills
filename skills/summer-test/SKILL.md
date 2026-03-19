---
name: summer-test
description: >
  Summer Framework testing — PostgresTestContainer setup with Flyway,
  WireMockServiceManager for stub services, blackbox test configuration
  and test-case JSON format, and test organization patterns.
triggers:
  - PostgresTestContainer
  - WireMockServiceManager
  - blackbox_config.json
  - blackbox test
  - summer test
  - summer-test
  - StandaloneStubsRunner
  - StubConfigurationUtils
  - BlackboxTestUtils
---

# Summer Test — Containers, WireMock & Blackbox

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

See `references/blackbox-config.md` for full config JSON format and test-case JSON schema.
