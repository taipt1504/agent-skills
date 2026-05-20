# Jackson Review Workflow

> Load this reference when reviewing Java code that uses Jackson (ObjectMapper, `@Json*`, `JsonParser`, BigDecimal/date in JSON). Drives priority-ordered scan and output format for the Jackson dimension of Stage 2 review.
> Companion rule file: `rules/java/code-review-jackson.md` (JKS-* full bodies).

## Table of Contents
1. [Trigger conditions](#trigger-conditions)
2. [Scope clarification](#scope-clarification)
3. [Priority-ordered scan](#priority-ordered-scan)
4. [Output format](#output-format)
5. [Context-specific guidance](#context-specific-guidance)
6. [Workflow examples](#workflow-examples)
7. [Do / Don't](#do--dont)

## Trigger conditions

Apply this workflow when any of:
- User requests "review Jackson", "audit JSON code", "review DTO".
- Diff contains `ObjectMapper`, `JsonMapper`, `@JsonProperty`, `@JsonCreator`, `@JsonTypeInfo`, `@JsonFormat`, `mapper.readValue`, `mapper.writeValueAsString`.
- User asks about Jackson best practice for fintech/money/date/polymorphic event.
- Security audit of JSON deserialization (CVE concern).
- Jackson version migration or DTO refactor.

## Scope clarification

If user did not paste code directly, confirm:
- Which file/folder to review (e.g. `src/main/java/io/f8a/party/dto/`).
- Context: REST API · Kafka event · internal service · file import.
- Severity floor: P0 only · P0+P1 · all severities.

If user pasted code inline, skip clarification and review immediately.

## Priority-ordered scan

Always load `rules/java/code-review-jackson.md` first — never review from memory. Walk categories in this order so that P0 findings surface first.

### P1. Security (P0 default)

1. `enableDefaultTyping`, `activateDefaultTyping` → check `JKS-POL-003`.
2. `@JsonTypeInfo(use = Id.CLASS)` → flag `JKS-POL-002` (RCE — CVE-2017-7525 class).
3. Field names containing `password`, `secret`, `token`, `cvv`, `pin`, `ssn` → verify `@JsonIgnore` or `@JsonProperty(access = WRITE_ONLY)` (`JKS-ANN-003`, `JKS-SEC-004`).
4. `readValue` with untrusted input → verify size limit (`JKS-SEC-003`, `JKS-SEC-005`).
5. Sensitive fields serialized without masking → `JKS-SEC-004`.
6. Error responses leaking stack trace / class names → `JKS-ERR-004`.

### P2. Money / Precision (P0 — fintech)

1. `BigDecimal` field in DTO → verify `@JsonFormat(shape = STRING)` or global `WRITE_BIGDECIMAL_AS_PLAIN` (`JKS-MNY-001`).
2. Deserialization config: `USE_BIG_DECIMAL_FOR_FLOATS` enabled (`JKS-MNY-002`).
3. Money scale normalization at API boundary (`JKS-MNY-003`).
4. Currency-specific scale (VND=0, USD=2, JPY=0) — `JKS-MNY-004`.

### P3. ObjectMapper lifecycle (P1)

1. `new ObjectMapper()` inside a service / component / DTO method → `JKS-OBJ-001`.
2. `mapper.enable(...)` / `mapper.disable(...)` at runtime → `JKS-OBJ-002` (shared instance mutation).
3. `new ObjectMapper()` followed by `.registerModule(...)` chain → suggest builder (`JKS-OBJ-003`).
4. Direct `ObjectMapper` instead of `JsonMapper.builder()` → `JKS-OBJ-004`.

### P4. Date / Time (P1)

1. `java.util.Date` field → migrate to `Instant` / `LocalDate` (`JKS-TIM-005`).
2. `LocalDateTime` / `Instant` field without `JavaTimeModule` registered → `JKS-MOD-001`.
3. `WRITE_DATES_AS_TIMESTAMPS` not disabled → `JKS-MOD-002`, `JKS-TIM-006`.
4. Picking the wrong type: event/audit needs `Instant`, business date needs `LocalDate`, user-facing needs `ZonedDateTime`/`OffsetDateTime` (`JKS-TIM-002..004`).

### P5. Annotation correctness (P2)

1. Field vs getter annotation conflict → `JKS-ANN-009`.
2. Non-record immutable class missing `@JsonCreator` → `JKS-ANN-006`.
3. Enum with custom serialization but no `@JsonValue` → `JKS-ANN-007`.
4. `@JsonInclude` inclusion strategy inconsistent across DTOs → `JKS-ANN-004`.
5. Backward compatibility: rename without `@JsonAlias` → `JKS-ANN-008`, `JKS-VER-001`.

### P6. Error handling (P2)

1. `catch (JsonProcessingException e) { return "..."; }` silent swallow → `JKS-ERR-001`.
2. Validation logic inside `@JsonCreator` / compact constructor instead of Bean Validation → `JKS-ERR-003`.
3. Error message leaks class name / stack trace → `JKS-ERR-004`.
4. Exception type not distinguished (`JsonParseException` vs `JsonMappingException`) → `JKS-ERR-002`.

### P7. Performance (P2-P3)

1. Repeated `mapper.readValue` with the same type → suggest cached `ObjectReader` (`JKS-PRF-001`).
2. `mapper.readValue(json, List.class)` → use `TypeReference` (`JKS-PRF-002`).
3. `Map<String, Object>` on hot path → strong-typed POJO (`JKS-PRF-004`).
4. Large batch via `readValue(file, List.class)` → streaming via `JsonParser` (`JKS-STR-001`).

## Output format

```markdown
## Jackson Review

**Scope:** <file/folder>
**Severity floor:** <P0 only | P0+P1 | all>
**Rules loaded:** rules/java/code-review-jackson.md (65 rules)

### Summary

| Severity | Count |
|---|---|
| P0 | <n> |
| P1 | <n> |
| P2 | <n> |
| P3 | <n> |

### Findings

#### [P0][JKS-MNY-001] BigDecimal serialized as JSON number — `Money.java:15`

**Issue:** Field `amount` has no `@JsonFormat(shape = STRING)`. Serializes as JSON number → JavaScript clients lose precision for values > 2^53.

**Current:**
\`\`\`java
public record Money(BigDecimal amount, String currency) {}
\`\`\`

**Suggested:**
\`\`\`java
public record Money(
    @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount,
    String currency
) {}
\`\`\`

**Rationale:** Critical for payment/ledger. JSON number = IEEE 754 double in JavaScript. String preserves exact representation.

**Reference:** `rules/java/code-review-jackson.md#jks-mny-001`

---

#### [P1][JKS-OBJ-001] `new ObjectMapper()` inside service — `OrderService.java:42`

... (same format)

### Action items (in fix priority)

1. **[P0][JKS-MNY-001]** `@JsonFormat(shape = STRING)` on `Money.amount`.
2. **[P0][JKS-ANN-003]** `@JsonIgnore` on `User.passwordHash`.
3. **[P1][JKS-OBJ-001]** Inject `ObjectMapper` instead of `new` in `OrderService`.
4. **[P1][JKS-MOD-001]** Register `JavaTimeModule` in `JacksonConfig`.
5. **[P2][JKS-TIM-005]** Replace `java.util.Date` with `Instant` in audit DTOs.

### Recommended config (if multiple lifecycle/config issues found)

Cite `rules/java/code-review-jackson.md §16` Spring Boot config block. Suggest paste into project `JacksonConfig`.
```

## Context-specific guidance

### Payment gateway / e-wallet

- Must check: `JKS-MNY-001` (BigDecimal as string), `JKS-SEC-004` (mask card/PII), `JKS-POL-002` (no `Id.CLASS`).
- Recommend separate `ObjectMapper`: external API (snake_case) vs internal Kafka event (camelCase) — `JKS-SPR-003`.
- Grep pattern for money fields:
  ```
  BigDecimal\s+(amount|balance|fee|total|price)
  → require @JsonFormat(shape = STRING) or global WRITE_BIGDECIMAL_AS_PLAIN
  ```

### SIMO report / batch processing

- Must check: `JKS-STR-001` (streaming for large file), `JKS-PRF-005`.
- File import endpoint → NDJSON streaming (`JKS-STR-002`).

### Kafka event consumer

- Must check: `JKS-SEC-002` (FAIL_ON_UNKNOWN lenient for schema evolution), `JKS-POL-002` (no `Id.CLASS`), `JKS-VER-001` (`@JsonAlias` on rename).
- Polymorphic event → `JKS-POL-001` with explicit `@JsonSubTypes`.

### Public REST API

- Must check: `JKS-SEC-002` (strict mode — reject unknown fields), `JKS-SEC-003` (size limit), `JKS-ANN-003` (write/read-only access), `JKS-ERR-004` (no stack trace leak).
- DTOs require round-trip test (`JKS-TST-002`) and golden file (`JKS-TST-004`).

## Workflow examples

### Example 1 — user pastes a single file

User: "Review this file per Jackson best practices"
```java
public class OrderDto {
    private String id;
    private BigDecimal amount;
    private Date createdAt;
    private String password;

    public String toJson() {
        ObjectMapper mapper = new ObjectMapper();
        return mapper.writeValueAsString(this);
    }
}
```

Findings: `[P0][JKS-ANN-003]` password leak, `[P0][JKS-MNY-001]` BigDecimal precision, `[P1][JKS-OBJ-001]` `new ObjectMapper()` per call, `[P1][JKS-MOD-001]` date without `JavaTimeModule`, `[P2][JKS-TIM-005]` `java.util.Date` migration.

### Example 2 — user audits security, P0 only

Filter to P0 rules: `JKS-POL-002`, `JKS-POL-003`, `JKS-MNY-001`, `JKS-ANN-003`, `JKS-MOD-001`, `JKS-SEC-001`, `JKS-SEC-004`. Highlight CVE-related findings (default typing class).

### Example 3 — Jackson version migration

Highlight breaking changes by version:
- 2.10: builder API (`JKS-OBJ-003`).
- 2.12: record support (`JKS-REC-001`).
- 2.15: `StreamReadConstraints` defaults (`JKS-SEC-003`).
- 2.16: sealed class support (`JKS-POL-004`).

Suggest test plan: round-trip + golden file. Suggest config refactor to builder.

## Do / Don't

### Do

- Cite rule ID on every finding — `[<P0-P4>][<RULE-ID>]`.
- Provide concrete code suggestion, not generic advice.
- Distinguish severity clearly — P0 (must fix pre-merge) vs P3 (suggestion).
- Reference file:line accurately when available.
- Group findings by severity so P0 surfaces first.
- Mention context-specific rules (payment → `JKS-MNY-*`, Kafka → `JKS-SEC-002`).
- Suggest a test (`@JsonTest`, `JKS-TST-002` round-trip) when the finding is testable.

### Don't

- Do not flag style preference unless it conflicts with a `JKS-*` rule.
- Do not invent new rule IDs ad hoc — only cite IDs present in `code-review-jackson.md`. If a new pattern emerges, mark `[NEW-RULE]` and route to evolve-rules.
- Do not suggest deprecated API (e.g. `setPropertyNamingStrategy`, `enableDefaultTyping`).
- Do not over-weight P3 findings — keep them as suggestions, not blockers.
- Do not review non-Jackson code in this workflow — defer to `references/review-workflow.md` for CORE/MVC/RX/WFL/XCT dimensions.
