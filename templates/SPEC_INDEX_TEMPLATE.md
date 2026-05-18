---
status: DRAFT
feature: <kebab-case-feature-slug>
service: <service-name>
lane: <trivial | standard | high-stakes>
slice_count: <N>
slice_decomposition: split
plan: ../plans/<feature>/index.md
created: YYYY-MM-DD
phase: SPEC
---

# Spec — <Feature Title>

> **Template version:** v1.0 (templates/SPEC_INDEX_TEMPLATE.md)
> **Shape:** SPLIT — slice scenarios in `slices/<NN>-<title>.md` files
> **Authority:** §1 Cross-cutting is AUTHORITATIVE — per-slice specs MUST reference, NEVER override without explicit slice-level §"Cross-cutting override" + ADR reference.
> **Validation:** `scripts/ci/validate-plan-spec-templates.sh`.

---

## 1. Cross-cutting (applies to ALL slices)

Cross-cutting concerns defined ONCE here. Per-slice spec MUST contain `## Cross-cutting reference` pointing to this section. Slice override requires explicit §"Cross-cutting override" block + ADR.

### 1.1 Inputs (common)

Inputs shared across slices:

- **Authenticated caller:** `<source — e.g., RequestContext.fromSecurityContext()>`
- **Correlation ID:** `X-Request-Id` header or auto-generated UUID
- **Locale:** `Accept-Language` header
- **Tenant context:** <if multi-tenant — source + propagation>

### 1.2 Auth `[OPTIONAL — required for endpoint specs]`

- **Authentication:** <bearer JWT | mTLS | OAuth client_credentials | session>
- **Authorization (RBAC):** required roles / permissions
- **@AuthRoles annotation (Summer):** `@AuthRoles({"<role-code>"})`
- **Audit:** caller propagated via `RequestContext` (see `rules/summer/audit.md` if Summer)

### 1.3 Idempotency `[OPTIONAL — required for mutation specs]`

- **Idempotency key source:** <header `Idempotency-Key` | client UUID | natural key>
- **Replay behavior:** identical response on retry within `<window>`
- **Storage:** dedup table `<name>` with TTL `<duration>`

### 1.4 Logging (MDC mandatory)

Required structured fields beyond defaults (`requestId`, `userId`):

| Field | Source | Example |
|---|---|---|
| `<feature.entityId>` | <source> | `"abc-123"` |

Sensitive data masking (`rules/common/security.md`):
- Never log: passwords, tokens, full PII payloads
- Mask: card numbers, phone, email (configurable per env)

### 1.5 Error envelope (RFC 7807)

Shared error response shape for all slices:

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

Common error codes (slice-specific errors in per-slice §4):

| Code | Status | Trigger |
|---|---|---|
| `INVALID_INPUT` | 400 | Bean Validation fails |
| `UNAUTHORIZED` | 401 | Auth missing/invalid |
| `FORBIDDEN` | 403 | Authz check fails |
| `NOT_FOUND` | 404 | Entity missing |
| `CONFLICT` | 409 | Idempotency replay mismatch OR business conflict |
| `INTERNAL_ERROR` | 500 | Unexpected — log + alert |

### 1.6 Performance budget `[OPTIONAL — required for high-stakes]`

- Throughput target: <req/s>
- Latency: p50 <ms>, p95 <ms>, p99 <ms>
- Resource ceiling: memory <MB>, CPU <% of core>
- Load test reference: `<path-to-load-test-script>`

---

## 2. Slice index

Authoritative list of slice specs. Validator cross-checks.

| # | Slice spec file | Title | Scenarios | Status |
|---|---|---|---|---|
| 01 | [slices/01-<slug>.md](slices/01-<slug>.md) | <title> | <count> | DRAFT \| APPROVED \| REVISED |
| 02 | [slices/02-<slug>.md](slices/02-<slug>.md) | ... | ... | ... |
| 03 | [slices/03-<slug>.md](slices/03-<slug>.md) | ... | ... | ... |

---

## 3. Out of scope (aggregate)

Feature-wide non-goals. Slice-level non-goals in slice files.

- <Non-goal 1>
- <Non-goal 2>

---

## 4. References

- Plan: `../plans/<feature>/index.md`
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
- `APPROVED` → all slices APPROVED + user confirms aggregate
- `PARTIALLY_APPROVED` → mixed slice states
- `REVISED` → revision in progress

`/build` requires `status: APPROVED` AND all slices APPROVED. PARTIALLY_APPROVED blocks dispatch.

### Revision history `[OPTIONAL]`

- YYYY-MM-DD: <change>

---

> **Validation:** §1 (1.1+1.4+1.5 mandatory; 1.2+1.3+1.6 conditional), §2, §3, §4 mandatory. Cross-cutting authority enforced — slice override requires ADR.
