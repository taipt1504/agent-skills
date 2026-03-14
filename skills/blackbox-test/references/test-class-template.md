# Blackbox Test Class Template

## Standard Template

```java
package blackbox.{domain};

import static io.f8a.summer.test.utils.TestExecutionUtils.executeTestCase;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import {main.package}.{MainApplication};
import io.f8a.summer.test.config.BlackboxTestConfig;
import io.f8a.summer.test.database.DatabaseTestUtils;
import io.f8a.summer.test.database.PostgresTestContainer;
import io.f8a.summer.test.utils.StubConfigurationUtils;
import io.f8a.summer.test.utils.TestCaseUtils;
import io.f8a.summer.test.utils.TestCaseUtils.TestCaseInfo;
import io.f8a.summer.test.wiremock.WireMockServiceManager;
import java.io.IOException;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

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

  static {
    try {
      if (!postgres.isRunning()) {
        postgres.start();
      }
    } catch (Exception e) {
      // During AOT processing, container may not be available
    }
  }

  @DynamicPropertySource
  static void configureProperties(DynamicPropertyRegistry registry) {
    try {
      if (!postgres.isRunning()) {
        postgres.start();
      }
      registry.add("spring.datasource.url", postgres::getJdbcUrl);
      registry.add("spring.datasource.username", postgres::getUsername);
      registry.add("spring.datasource.password", postgres::getPassword);
      registry.add("spring.r2dbc.url", postgres::getR2dbcUrl);
      registry.add("spring.r2dbc.username", postgres::getUsername);
      registry.add("spring.r2dbc.password", postgres::getPassword);
      registry.add("spring.flyway.url", postgres::getJdbcUrl);
      registry.add("spring.flyway.user", postgres::getUsername);
      registry.add("spring.flyway.password", postgres::getPassword);
    } catch (Exception e) {
      // AOT fallback
      registry.add("spring.datasource.url", () -> "jdbc:postgresql://localhost:5432/test_db");
      registry.add("spring.datasource.username", () -> "testuser");
      registry.add("spring.datasource.password", () -> "testpass");
      registry.add("spring.r2dbc.url", () -> "r2dbc:postgresql://localhost:5432/test_db");
      registry.add("spring.r2dbc.username", () -> "testuser");
      registry.add("spring.r2dbc.password", () -> "testpass");
      registry.add("spring.flyway.url", () -> "jdbc:postgresql://localhost:5432/test_db");
      registry.add("spring.flyway.user", () -> "testuser");
      registry.add("spring.flyway.password", () -> "testpass");
    }
    registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
    registry.add("spring.flyway.enabled", () -> "true");
  }

  @BeforeAll
  static void setUpAll() throws Exception {
    serviceManager = new WireMockServiceManager();
    BlackboxTestConfig config = StubConfigurationUtils.loadBlackboxConfiguration(CONFIG_PATH);
    StubConfigurationUtils.startAllStubServices(serviceManager, config.getStubs());
    StubConfigurationUtils.waitForServicesReady(serviceManager, 30);
    assertTrue(postgres.isRunning(), "PostgreSQL container should be running");
  }

  @AfterAll
  static void tearDownAll() {
    if (serviceManager != null) {
      serviceManager.stopAllServers();
    }
  }

  @BeforeEach
  void setUp() {
    StubConfigurationUtils.resetAllStubs(serviceManager);
  }

  @Test
  @Order(1)
  @DisplayName("Should verify database setup")
  void testInitialDataExists() {
    // Verify tables created by Flyway migrations exist
    assertTrue(DatabaseTestUtils.tableExists(postgres, "{table_name}"));
    // Verify expected test data count
    int count = DatabaseTestUtils.getTableRowCount(postgres, "{table_name}");
    assertEquals({expected_count}, count, "Should have {expected_count} initial records");
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

## Placeholders to Replace

| Placeholder         | Description                       | Example                            |
|---------------------|-----------------------------------|------------------------------------|
| `{main.package}`    | Main app package                  | `io.f8a.notification`              |
| `{MainApplication}` | Spring Boot main class            | `NotificationGatewayMsApplication` |
| `{Feature}`         | PascalCase feature name           | `Payment`, `CmcTelecom`            |
| `{feature}`         | lowercase feature key             | `payment`, `cmc-telecom`           |
| `{domain}`          | Domain subdirectory               | `sms`, `payment`, `order`          |
| `{app-name}`        | App identifier in test-cases path | `notification-gateway`             |
| `{table_name}`      | Table to verify in database       | `orders`, `sms_templates`          |
| `{expected_count}`  | Expected row count                | `5`                                |

## Variant-Specific Profile Override

When testing with a specific config variant (e.g., different provider priority), add the profile:

```java
@ActiveProfiles({"test", "{variant}"})
```

Optionally inject `Environment` to verify config:

```java
@Autowired private Environment environment;

// Inside testInitialDataExists():
String value = environment.getProperty("{config.key}");
assertEquals("{expected}", value, "Config should be overridden for this test suite");
```

Create `application-{variant}.yml` with the override values.
