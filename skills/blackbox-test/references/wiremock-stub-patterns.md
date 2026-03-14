# WireMock Stub Patterns

## Directory Layout

Each external service gets its own directory under `stubs/`:

```
stubs/{service-name}/
├── mappings/                  # Request matching rules
│   ├── {action}-success.json
│   ├── {action}-error.json
│   └── ...
└── __files/                   # Response body templates
    ├── {action}-success-response.json
    ├── {action}-error-response.json
    └── ...
```

## Mapping File Structure

### Success Mapping (with response-template transformer)

```json
{
  "priority": 1,
  "request": {
    "method": "POST",
    "urlPath": "/{service-path}/{endpoint}",
    "headers": {
      "Content-Type": { "equalTo": "application/json" }
    }
  },
  "response": {
    "status": 200,
    "headers": {
      "Content-Type": "application/json",
      "X-Trace-ID": "{{request.headers.X-Trace-ID}}"
    },
    "bodyFileName": "{action}-success-response.json",
    "transformers": ["response-template"]
  }
}
```

### Scenario-Specific Mapping (route by X-Trace-ID)

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
    "headers": {
      "X-Trace-ID": { "matches": ".*-error-.*" }
    }
  },
  "response": {
    "status": 500,
    "headers": { "Content-Type": "application/json" },
    "body": "{\"code\": \"ERROR\", \"message\": \"Internal server error\"}"
  }
}
```

## Response Body Templates

Use `"transformers": ["response-template"]` to enable dynamic values in `__files/`:

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

### Available Template Helpers

| Helper                                | Usage                                    | Description              |
|---------------------------------------|------------------------------------------|--------------------------|
| `{{now}}`                             | `{{now format='yyyy-MM-dd'}}`            | Current timestamp        |
| `{{now offset='5 seconds'}}`          | `{{now offset='-1 hours' format='...'}}` | Time offset              |
| `{{jsonPath request.body '$.field'}}` | Extract field from request body          | Echo back request values |
| `{{request.headers.Header-Name}}`     | Echo request header                      | Pass through headers     |
| `{{randomValue type='UUID'}}`         | Generate UUID                            | Random unique IDs        |
| `{{request.body}}`                    | Full request body                        | Echo entire body         |

## Priority Rules

- **Lower number = higher priority** (`priority: 1` matches before `priority: 2`)
- Scenario-specific mappings (with header matchers) should have **lower priority number**
- Default/fallback mappings should have **higher priority number**
- Use `X-Trace-ID` regex patterns to differentiate success vs error scenarios

## Request Matching Options

| Matcher          | Example                             | Description            |
|------------------|-------------------------------------|------------------------|
| `urlPath`        | `"/api/v1/users"`                   | Exact path match       |
| `urlPathPattern` | `"/api/v1/users/.*"`                | Regex path match       |
| `equalTo`        | `{ "equalTo": "application/json" }` | Exact header value     |
| `matches`        | `{ "matches": ".*-success-.*" }`    | Regex header match     |
| `contains`       | `{ "contains": "Bearer" }`          | Substring header match |
| `bodyPatterns`   | `[{ "matchesJsonPath": "$.name" }]` | JSON body match        |

## Service Registration

Every external service must be registered in `blackbox_config.json`:

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
  }
}
```

- Use unique port per service (start from 8081, app uses 8080)
- `stubs_data_path` points to the directory containing `mappings/` and `__files/`
- Set `enabled: false` to skip a service during tests
