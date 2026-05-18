---
slice_id: <NN>
slice_title: <Slice title — matches index.md row>
parent_spec: ../index.md
parent_plan_slice: ../../plans/<feature>/slices/<NN>-<slug>.md
status: DRAFT | APPROVED | REVISED
scenario_count: <N>
service: <name>
---

# Spec Slice <NN> — <Slice Title>

> **Template version:** v1.0 (templates/SPEC_SLICE_TEMPLATE.md)
> **Parent:** `../index.md`
> **Cross-cutting authority:** §0 below references `../index.md §1`. Override forbidden without ADR.

---

## 0. Cross-cutting reference

Cross-cutting concerns (auth, logging, error envelope, idempotency, performance budget) live in `../index.md §1`. This slice inherits ALL of them.

**Inherited from index §1:**
- §1.1 Common inputs (caller, correlation ID, locale)
- §1.2 Auth (if endpoint slice)
- §1.3 Idempotency (if mutation slice)
- §1.4 Logging / MDC
- §1.5 Error envelope (RFC 7807) + common error codes
- §1.6 Performance budget (high-stakes)

### Cross-cutting override `[FORBIDDEN unless ADR justifies]`

If THIS slice MUST deviate from index §1 — DO NOT inline override here. Instead:
1. Write an ADR documenting the deviation
2. Reference ADR ID in this section
3. State exact deviation + scope

Example (rare):
```
ADR-0099: This slice uses HMAC-SHA256 instead of JWT auth (legacy webhook signature compat).
Override: §1.2 Auth — bearer JWT replaced by `X-Hmac-Signature` header for THIS slice only.
```

---

## 1. Inputs (slice-specific)

Inputs unique to this slice (beyond cross-cutting §1.1).

### Request

```http
<METHOD> <path>
Content-Type: application/json
```

### Request body

```json
{
  "<field>": "<type>"
}
```

Field rules:

- `<field>: <Type>` (<required | optional>, constraints: <e.g., "max 255", "regex ^[a-z]+$", "enum X|Y|Z">)

### Query / path / header params

| Param | Location | Type | Required | Constraint |
|---|---|---|---|---|
| `<name>` | path | UUID | yes | UUID v4 |
| `<name>` | query | int | no | `@Min(0) @Max(100)`, default 20 |

---

## 2. Outputs / Side Effects (slice-specific)

### Response (success)

```json
{
  "<field>": "<type>"
}
```

Field-by-field description.

### Side effects

For each side effect produced by THIS slice:

#### DB writes

- Table `<name>`: INSERT / UPDATE / DELETE with conditions
- Transactional boundary: <entire request | per-record>

#### Events emitted

- Topic: `<bounded-context>.<aggregate>.<category>.v<N>`
- Event type: `<EventTypeName>`
- Payload: <reference DTO record>
- Publish strategy: outbox (`rules/summer/messaging.md`) | direct (justify)

#### External calls

- Service: `<name>`, endpoint: `<method> <path>`
- Timeout: <ms>, retry: <strategy>

---

## 3. Contracts / Invariants (slice-specific)

Invariants unique to THIS slice (beyond cross-cutting defaults).

- **<Invariant>:** <description>

---

## 4. Error Cases (slice-specific)

Errors NOT covered by cross-cutting `INVALID_INPUT/UNAUTHORIZED/...` (index §1.5).

| ID | Trigger | Status / Exception | Error code | Message | Log severity |
|---|---|---|---|---|---|
| E<N>.1 | <slice-specific condition> | 422 / `<DomainException>` | `<error-code>` | "<msg>" | WARN |

Cross-cutting errors apply automatically (validation, auth, etc.) — do NOT redefine here.

---

## 5. Scenarios (test specifications)

Each scenario maps 1:1 to a future test case. Stage 1 review verifies.

| ID | Name (`shouldDoXWhenY`) | Setup | Action | Expected |
|---|---|---|---|---|
| S<NN>.1 | `shouldReturn<X>When<Y>` | <setup> | <action> | <expected> |
| S<NN>.2 | `shouldReject<X>When<Y>` | <setup> | <action> | <error from §4 or cross-cutting> |

Minimum per slice:
- 1 happy path
- 2 failure / edge cases
- 1 scenario per slice-specific error in §4

---

## 6. SDD ↔ TDD mapping

| Scenario | Test class | Test method |
|---|---|---|
| S<NN>.1 | `<Class>Test` | `shouldReturnXWhenY` |
| S<NN>.2 | `<Class>Test` | `shouldRejectXWhenY` |

---

## 7. Slice-level out of scope `[OPTIONAL]`

Non-goals specific to this slice (beyond feature-wide §3 in index).

- <Non-goal>

---

## Revision history

- YYYY-MM-DD: <change>

---

> **Validation:** sections 0-6 mandatory. Section 7 optional. Validator checks frontmatter (`slice_id`, `slice_title`, `parent_spec`, `parent_plan_slice`, `status`, `scenario_count`) + cross-cutting reference presence + override discipline.
