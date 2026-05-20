# Pre-flight Gate Mappings

> Reference for which skills + rules typically apply per gate. Not exhaustive — pre-flight must enumerate ALL skills regardless. This shows defaults the agent should expect.

## Workflow diagram (linear path)

```
REQ → BOOT → PREFLIGHT0 → TRIAGE → ALIGN → PREFLIGHT1 → BRAINSTORM
                            ↓ (trivial)              ↓
                         EXECUTE (light)        PREFLIGHT2 → PLAN
                                                    ↓
                                              PREFLIGHT3 → SPEC
                                                    ↓
                                              PREFLIGHT4 → EXECUTE
                                                    ↓
                                              PREFLIGHT5 → REVIEW
                                                    ↓
                                                  LEARN → COMMIT
```

## Trivial bypass

```
TRIAGE [trivial] → PREFLIGHT (light) → EXECUTE (light) → REVIEW (Stage 2 only) → COMMIT
```

Skipped: Align, Brainstorm, Plan, Spec, Review Stage 1.

## Per-variant defaults

### Variant 0 — Initial discovery (after Boot, before Triage)

**Skills:** ALL — filesystem walk
**Rules:** ALL — filesystem walk
**Instincts:** ALL with confidence ≥ 0.6

Output establishes baseline for later gates to reference.

### Variant 1 — Brainstorm prep

**Skills (default APPLY candidates):**
- `brainstorm` (always 100%)
- `solution-design`
- `architecture` (if architectural decision)
- Domain skills surfaced by Align output (e.g., `database-patterns` if DB choice)

**Rules:**
- `rules/common/patterns.md`
- `rules/common/lanes.md` (high-stakes requires brainstorm)

### Variant 2 — Plan prep

**Skills:**
- Planning patterns
- `coding-standards`

**Rules:**
- `rules/common/development-workflow.md`
- `rules/common/patterns.md`

### Variant 3 — Spec prep

**Skills:**
- `api-design` (if API)
- Testing patterns
- `blackbox-test` (if E2E)

**Rules:**
- `rules/common/spec-driven.md`
- `rules/java/api-design.md` (if applicable)
- `rules/java/testing.md`

### Variant 4 — Execute prep

**Skills:**
- `tdd-workflow` (or `testing-workflow`)
- Language: `java-patterns`, `coding-standards`
- Framework: pick one — `spring-webflux-patterns` OR `spring-mvc-patterns`
- Domain (pick relevant): `database-patterns`, `messaging-patterns`, `redis-patterns`, `grpc-patterns`
- Architecture: `architecture` (hexagonal)

**Rules:**
- `rules/common/coding-style.md`
- `rules/common/security.md`
- `rules/common/git-workflow.md`
- `rules/java/coding-style.md`
- `rules/java/reactive.md` (if WebFlux)
- `rules/java/security.md`
- `rules/java/observability.md`
- **`rules/java/code-review-core.md`** — CORE-* foundation (always for Java)
- **`rules/java/code-review-mvc.md`** — MVC-* (if MVC stack)
- **`rules/java/code-review-reactor.md`** — RX-* (if reactive code)
- **`rules/java/code-review-webflux.md`** — WFL-* (if WebFlux stack)
- **`rules/java/code-review-crosscut.md`** — XCT-* + checklist + severity (always)
- **`rules/java/code-review-jackson.md`** — JKS-* (if Jackson — DTO with `@JsonProperty`/`@JsonFormat`, `ObjectMapper`, or BigDecimal/date in JSON)

Execute MUST apply these during REFACTOR step. Slice-executor cites violated rule IDs (`CORE-NUM-001`, `MVC-TX-002`, `JKS-OBJ-001`, etc.) in result report.

### Variant 5 — Review prep

**Skills:**
- `security-review` (or `pentest`)
- `verification`

**Rules:**
- `rules/common/security.md`
- `rules/java/security.md`
- `rules/java/testing.md`
- **`rules/java/code-review-core.md`** — CORE-* (always for Java review)
- **`rules/java/code-review-mvc.md`** — MVC-* (if MVC stack)
- **`rules/java/code-review-reactor.md`** — RX-* (if reactive)
- **`rules/java/code-review-webflux.md`** — WFL-* (if WebFlux)
- **`rules/java/code-review-crosscut.md`** — XCT-* + PR checklist + severity P0-P4 + rule ID catalog (always)
- **`rules/java/code-review-jackson.md`** — JKS-* (if Jackson — CRITICAL for fintech: BigDecimal precision + RCE via polymorphic deser)

Code-quality-reviewer MUST cite rule IDs per finding (`[P0][CORE-NUM-001]`, `[P1][MVC-TX-002]`, `[P0][JKS-POL-002]`). Missing rule ID = invalid finding, re-do required.

## Per-lane summary

| Lane | Variants run | Format |
|---|---|---|
| Trivial | 0 (light), 5 (Stage 2 only) | light (3–5 lines) |
| Standard | 0, 1 (if multi-path), 2, 3, 4, 5 | full artifact |
| High-stakes | 0, 1 (mandatory), 2, 3, 4, 5 | full artifact + ADR |

## When mappings break

Pre-flight must still enumerate ALL skills/rules regardless of this reference. This file shows expected defaults. Edge cases (new tech, novel task) require fresh scoring.
