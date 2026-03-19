# Summer Test — Blackbox Config & Test-Case JSON Format

## Main Configuration (`blackbox_config.json`)

```json
{
  "application": {
    "name": "user-service",
    "base_url": "http://localhost:8080",
    "health_endpoint": "/actuator/health",
    "startup_timeout_seconds": 60
  },
  "stubs": {
    "services": [
      {
        "name": "external-user-service",
        "port": 8091,
        "stubs_data_path": "src/test/resources/blackbox/stubs/user-service",
        "enabled": true,
        "startup_delay_ms": 1000
      },
      {
        "name": "payment-service",
        "port": 8092,
        "stubs_data_path": "src/test/resources/blackbox/stubs/payment-service",
        "enabled": true
      }
    ]
  },
  "test_cases": {
    "root_path": "src/test/resources/blackbox/test-cases",
    "file_patterns": [".*\\.json$"],
    "timeout_seconds": 30,
    "recursive_scan": true,
    "parallel_execution": false,
    "retry_attempts": 2
  }
}
```

## Stub-Only Configuration (`stubs_config.json`)

```json
{
  "services": [
    {
      "name": "external-user-service",
      "port": 8091,
      "stubs_data_path": "src/test/resources/blackbox/stubs/user-service",
      "enabled": true
    },
    {
      "name": "payment-service",
      "port": 8092,
      "stubs_data_path": "src/test/resources/blackbox/stubs/payment-service",
      "enabled": true
    }
  ]
}
```

## Test-Case JSON Format

### CRUD Operations Example

```json
{
  "test_suite": "User CRUD Operations",
  "setup": {
    "stubs": [
      {
        "service": "external-user-service",
        "stub_file": "get-user-success.json"
      }
    ]
  },
  "tests": [
    {
      "name": "Create User Success",
      "description": "Should create a new user successfully",
      "test": {
        "method": "POST",
        "url": "http://localhost:8080/api/users",
        "headers": {
          "Content-Type": "application/json",
          "X-Request-ID": "test-create-user-001"
        },
        "body": {
          "name": "John Doe",
          "email": "john.doe@example.com"
        }
      },
      "assertions": {
        "status_code": 201,
        "headers": {
          "Content-Type": "application/json"
        },
        "json": {
          "$.success": true,
          "$.data.id": {"type": "string", "pattern": "^[a-f0-9-]{36}$"},
          "$.data.name": "John Doe",
          "$.data.email": "john.doe@example.com",
          "$.data.status": "ACTIVE"
        },
        "response_time_ms": 1000
      },
      "post_actions": [
        {
          "type": "store_variable",
          "name": "created_user_id",
          "json_path": "$.data.id"
        }
      ]
    },
    {
      "name": "Get User Success",
      "description": "Should retrieve user by ID",
      "test": {
        "method": "GET",
        "url": "http://localhost:8080/api/users/${created_user_id}",
        "headers": {
          "Accept": "application/json"
        }
      },
      "assertions": {
        "status_code": 200,
        "json": {
          "$.success": true,
          "$.data.id": "${created_user_id}",
          "$.data.name": "John Doe"
        }
      }
    }
  ]
}
```

### Validation Tests Example

```json
{
  "test_suite": "Input Validation Tests",
  "tests": [
    {
      "name": "Create User - Missing Name",
      "test": {
        "method": "POST",
        "url": "http://localhost:8080/api/users",
        "headers": {"Content-Type": "application/json"},
        "body": {
          "email": "test@example.com"
        }
      },
      "assertions": {
        "status_code": 400,
        "json": {
          "$.success": false,
          "$.message": {"type": "string", "contains": "Name is required"}
        }
      }
    },
    {
      "name": "Create User - Invalid Email",
      "test": {
        "method": "POST",
        "url": "http://localhost:8080/api/users",
        "headers": {"Content-Type": "application/json"},
        "body": {
          "name": "John Doe",
          "email": "invalid-email"
        }
      },
      "assertions": {
        "status_code": 400,
        "json": {
          "$.success": false,
          "$.message": {"type": "string", "contains": "Invalid email format"}
        }
      }
    }
  ]
}
```

## WireMock Stub Files

### Request Mapping (`stubs/<service>/mappings/<name>.json`)

```json
{
  "request": {
    "method": "GET",
    "urlPattern": "/users/([a-zA-Z0-9]+)",
    "headers": {
      "Content-Type": { "equalTo": "application/json" }
    }
  },
  "response": {
    "status": 200,
    "headers": { "Content-Type": "application/json" },
    "bodyFileName": "user-success-response.json",
    "transformers": ["response-template"],
    "delayDistribution": {
      "type": "lognormal",
      "median": 50,
      "sigma": 0.1
    }
  }
}
```

### Response Template (`stubs/<service>/__files/<name>.json`)

```json
{
  "id": "{{request.pathSegments.[1]}}",
  "username": "testuser_{{request.pathSegments.[1]}}",
  "email": "{{request.pathSegments.[1]}}@example.com",
  "status": "ACTIVE",
  "createdAt": "{{now format='yyyy-MM-dd HH:mm:ss'}}",
  "metadata": {
    "source": "wiremock",
    "requestId": "{{randomValue length=12 type='ALPHANUMERIC'}}"
  }
}
```

### Error Scenario

```json
{
  "request": {
    "method": "GET",
    "urlPattern": "/users/error.*"
  },
  "response": {
    "status": 404,
    "headers": { "Content-Type": "application/json" },
    "body": "{\"error\":\"User not found\",\"code\":\"USER_NOT_FOUND\"}"
  }
}
```

## PostgresTestContainer — Advanced Usage

```java
@SpringBootTest
@Testcontainers
class DatabaseIntegrationTest {

    @Container
    static PostgresTestContainer postgres = PostgresTestContainer.create();

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
    static void initDatabase() {
        postgres.runFlywayMigrations("classpath:db/migration");
        postgres.executeSqlScript("classpath:test-data.sql");
    }
}
```

### Database Test Utilities

```java
// Check table exists
DatabaseTestUtils.tableExists(postgres, "users");

// Get row count
DatabaseTestUtils.getTableRowCount(postgres, "users");

// Execute update
DatabaseTestUtils.executeUpdate(postgres,
    "INSERT INTO users (name, email) VALUES (?, ?)", "Test", "test@example.com");

// Query for value
DatabaseTestUtils.queryForString(postgres,
    "SELECT name FROM users WHERE id = ?", userId);
```

## Gradle Tasks

```gradle
test {
    useJUnitPlatform()
    systemProperty 'junit.jupiter.execution.parallel.enabled', 'false'
    systemProperty 'spring.profiles.active', 'blackbox-test'
}

task blackboxTest(type: Test) {
    useJUnitPlatform()
    include '**/blackbox/**'
    systemProperty 'spring.profiles.active', 'blackbox-test'
    reports {
        html.destination = file("$buildDir/reports/blackbox-tests")
        junitXml.destination = file("$buildDir/test-results/blackbox-tests")
    }
}

task runStubs(type: JavaExec) {
    classpath = sourceSets.test.runtimeClasspath
    mainClass = 'your.package.stubs.StandaloneStubsRunner'
    description = 'Run WireMock stubs for development'
}
```

Run: `./gradlew test` | `./gradlew blackboxTest` | `./gradlew runStubs`
