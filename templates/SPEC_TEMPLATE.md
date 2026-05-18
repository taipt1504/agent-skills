---
status: DRAFT
feature: <kebab-case-feature-slug>
service: <service-name>
lane: <trivial | standard | high-stakes>
plan: ../plans/<feature>.md
created: YYYY-MM-DD
phase: SPEC
---

# Spec — <Feature Title>

> **Template version:** v1.0 (templates/SPEC_TEMPLATE.md)
> **Conformance:** ALL required sections below MUST be present. Optional sections marked `[OPTIONAL]`.
> Validation: `scripts/ci/validate-plan-spec-templates.sh`

---

## 1. Inputs

Describe every input the feature consumes. Types, validation rules, valid ranges, sources.

### <Input source 1 — e.g., HTTP request body>

- `<field>: <Type>` (<required | optional>, <constraints — e.g., "max 255", "regex `[a-z]+`", "enum X|Y|Z">)
- `<field>: <Type>` (...)

### <Input source 2 — e.g., Kafka event payload>

- ...

### Configuration

- `<config.key>: <Type>` (default `<value>`, env var `<NAME>` overrides)

### Runtime context

- Authenticated caller: `<source — e.g., RequestContext.fromSecurityContext>`
- Correlation ID: from `X-Request-Id` header or auto-generated
- Locale: from `Accept-Language` header

---

## 2. Outputs / Side Effects

### Outputs (response, return value)

```json
{
  "<field>": "<type>",
  "<field>": "<type>"
}
```

Field-by-field description.

### Side effects

For each side effect (DB write, event publish, external call, log entry):

#### DB

- Table `<name>`: INSERT / UPDATE / DELETE with conditions
- Transactional boundary: <entire request | per-record>

#### Events (if applicable)

- Topic: `<bounded-context>.<aggregate>.<category>.v<N>`
- Event type: `<EventTypeName>`
- Payload schema: <reference DTO record>
- Publish strategy: outbox (see `rules/summer/messaging.md`) | direct (justify)

#### External calls

- Service: `<name>`, endpoint: `<method> <path>`
- Timeout: <ms>, retry policy: <strategy>

#### Logging (MDC mandatory)

Required structured log fields: `requestId`, `userId`, `<feature-specific keys>`.

---

## 3. Contracts / Invariants

Conditions that MUST hold for every valid execution.

- **<Invariant 1>:** <description in plain language>
- **<Invariant 2>:** <description>

**Examples:**
- Created entity has `createdAt` and `createdBy` non-null
- Updates preserve `createdAt` and `createdBy` unchanged
- Aggregate version monotonically increases per modification
- Idempotency key, if provided, MUST produce identical response on retry

---

## 4. Error Cases

For each error path, define: trigger condition, HTTP status (or exception type), error code, user-facing message, log severity.

| ID | Trigger | Status / Exception | Error code | Message | Log severity |
|---|---|---|---|---|---|
| E1 | <condition> | 400 / `ValidationException` | `INVALID_INPUT` | "<user-facing>" | WARN |
| E2 | <condition> | 404 / `NotFoundException` | `<entity>_NOT_FOUND` | "<msg>" | INFO |
| E3 | <condition> | 409 / `ConflictException` | `<resource>_CONFLICT` | "<msg>" | WARN |
| E4 | <condition> | 500 / `<DomainException>` | `<error-code>` | "<msg>" | ERROR |

Error response body shape (RFC 7807):

```json
{
  "type": "https://example.com/problems/<error-code>",
  "title": "<title>",
  "status": <code>,
  "detail": "<detail>",
  "instance": "/<request-path>",
  "traceId": "<from MDC>"
}
```

---

## 5. Scenarios (test specifications)

Each scenario maps 1:1 to a future test case. Stage 1 review verifies this mapping.

| ID | Name (`shouldDoXWhenY`) | Setup | Action | Expected |
|---|---|---|---|---|
| S1 | `shouldReturn<X>When<Y>` | <setup> | <action> | <expected outcome> |
| S2 | `shouldReject<X>When<Y>` | <setup> | <action> | <expected error from §4> |

Minimum:
- 1 happy path per slice
- 2 failure / edge cases per slice (null, boundary, invalid)
- For each error case in §4: 1 scenario

---

## 6. SDD ↔ TDD mapping

Confirms every spec scenario produces a test case.

| Scenario ID | Test class | Test method | Slice |
|---|---|---|---|
| S1 | `<Class>Test` | `shouldReturnXWhenY` | 1 |
| S2 | `<Class>Test` | `shouldRejectXWhenY` | 1 |

---

## 7. Auth `[OPTIONAL — required for endpoint specs]`

- Authentication: <bearer JWT | mTLS | OAuth client_credentials>
- Authorization (RBAC): required roles / permissions
- @AuthRoles annotation (Summer): `@AuthRoles({"<role-code>"})`
- Audit: caller propagated via `RequestContext` (see `rules/summer/audit.md` if Summer)

---

## 8. Idempotency `[OPTIONAL — required for mutation specs]`

- Idempotency key source: <header `Idempotency-Key` | client-generated UUID | natural key>
- Replay behavior: identical response (200 with original payload) on retry within <window>
- Storage: dedup table `<name>` with TTL <duration>

---

## 9. Performance `[OPTIONAL — required for high-stakes specs]`

- Throughput target: <req/s>
- Latency: p50 <ms>, p95 <ms>, p99 <ms>
- Resource ceiling: memory <MB>, CPU <% of core>
- Load test reference: `<path-to-load-test-script>`

---

## 10. Logging (MDC mandatory)

Required structured fields beyond defaults (`requestId`, `userId`):

| Field | Source | Example | Used by |
|---|---|---|---|
| `<feature.entityId>` | <source> | `"abc-123"` | dashboards, alerts |

Sensitive data masking (rules/common/security.md):
- Never log: passwords, tokens, full request bodies with PII
- Mask: card numbers, phone, email (configurable per env)

---

## 11. Out of scope

Explicit non-goals for this spec. Anything that might look in-scope but is deliberately excluded.

- <Non-goal 1>
- <Non-goal 2>

---

## 12. References

- Plan: `<path>`
- Align artifact: `<path>`
- Brainstorm artifact: `<path>`
- ADR: `<path>` (high-stakes)
- Pre-flight 3 artifact: `.claude/memory/preflight/spec-<ts>.md`
- Related specs (cross-feature): <list>
- External API contracts: <openapi.yaml paths>

---

## Approval

Status transitions:
- `DRAFT` → user reviews
- `APPROVED` → user confirms via "yes" / "approve" / "proceed"
- `REVISED` → updated per user feedback

### Revision history `[OPTIONAL — auto-appended]`

- YYYY-MM-DD: <what changed and why>

---

> **Template validation:** This spec MUST contain sections 1-6 + 10-12 (mandatory). Sections 7-9 are conditional per feature type. `scripts/ci/validate-plan-spec-templates.sh` enforces. Mismatch = workflow violation.
