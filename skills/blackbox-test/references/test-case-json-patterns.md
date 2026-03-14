# Test Case JSON Patterns

## Structure

Each JSON file contains a test suite with one or more test cases:

```json
{
  "name": "Suite Name - Category",
  "description": "Brief description of what this suite tests",
  "testCases": [
    {
      "name": "Human-readable test name",
      "description": "What this specific test validates",
      "test": {
        "request": {
          "method": "POST|GET|PUT|DELETE|PATCH",
          "url": "http://localhost:{app-port}/api/v1/{endpoint}",
          "headers": {
            "Content-Type": "application/json",
            "X-Trace-ID": "test-{scenario}-{seq}"
          },
          "body": {}
        }
      },
      "assertions": {
        "status": 200,
        "headers": {
          "Content-Type": "application/json"
        },
        "json_path": {
          "$.field": "expected_value"
        }
      }
    }
  ]
}
```

## JSON Path Assertions

| Pattern                   | Description        | Example                 |
|---------------------------|--------------------|-------------------------|
| `"$.field": "value"`      | Exact string match | `"$.status": "SUCCESS"` |
| `"$.field": 123`          | Numeric match      | `"$.total": 100`        |
| `"$.field": true`         | Boolean match      | `"$.isActive": true`    |
| `"$.field": null`         | Null check         | `"$.deletedAt": null`   |
| `"$.array.length()": 3`   | Array length       | `"$.items.length()": 3` |
| `"$.array[0]": "val"`     | Array element      | `"$.ids[0]": "id-001"`  |
| `"$.nested.field": "val"` | Nested object      | `"$.data.name": "test"` |

## X-Trace-ID Convention

`X-Trace-ID` header routes requests to scenario-specific WireMock stubs:

- Format: `test-{scenario}-{sequence}` (e.g., `test-create-success-001`)
- WireMock mappings match on this header via regex to return scenario-specific responses
- Enables multiple scenarios (success, error, timeout) against the same endpoint

## Examples

### Success — POST Create

```json
{
  "name": "Create Resource Success",
  "description": "Should create a new resource and return 200",
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
        "type": "standard",
        "data": { "key": "value" }
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
```

### Success — GET by ID

```json
{
  "name": "Get Resource by ID",
  "test": {
    "request": {
      "method": "GET",
      "url": "http://localhost:8080/api/v1/resources/RES-001-TEST",
      "headers": { "Content-Type": "application/json" }
    }
  },
  "assertions": {
    "status": 200,
    "json_path": {
      "$.id": "RES-001-TEST",
      "$.status": "ACTIVE"
    }
  }
}
```

### Error — Missing Required Field (400)

```json
{
  "name": "Missing Required Field",
  "description": "Should return 400 when required field is missing",
  "test": {
    "request": {
      "method": "POST",
      "url": "http://localhost:8080/api/v1/resources",
      "headers": { "Content-Type": "application/json" },
      "body": { "type": "standard" }
    }
  },
  "assertions": {
    "status": 400
  }
}
```

### Error — Not Found (404)

```json
{
  "name": "Resource Not Found",
  "test": {
    "request": {
      "method": "GET",
      "url": "http://localhost:8080/api/v1/resources/NON-EXISTENT",
      "headers": { "Content-Type": "application/json" }
    }
  },
  "assertions": {
    "status": 404
  }
}
```

### Error — External Service Failure (via X-Trace-ID routing)

```json
{
  "name": "External Service Error",
  "description": "Should handle upstream service failure gracefully",
  "test": {
    "request": {
      "method": "POST",
      "url": "http://localhost:8080/api/v1/resources",
      "headers": {
        "Content-Type": "application/json",
        "X-Trace-ID": "test-upstream-error-001"
      },
      "body": { "name": "Test", "type": "standard" }
    }
  },
  "assertions": {
    "status": 502,
    "json_path": { "$.error": "UPSTREAM_ERROR" }
  }
}
```

## File Organization

Organize test case files by domain and scenario:

```
test-cases/{app-name}/
├── common/                         # Cross-cutting (health, templates, shared)
│   ├── health-check.json
│   └── template-crud.json
├── {domain-a}/                     # e.g., orders, payments, users
│   ├── {domain-a}-success.json
│   ├── {domain-a}-validation.json
│   └── {domain-a}-error.json
└── {domain-b}/
    └── {variant}/                  # Optional: provider/variant-specific
        ├── {variant}-success.json
        └── {variant}-error.json
```

- Group by **domain** first, then by **scenario type** (success, validation, error)
- Use **variant subdirectories** when the same domain has multiple implementations/providers
- Each JSON file can contain multiple related test cases in the `testCases` array
