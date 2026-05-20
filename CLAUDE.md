# CLAUDE.md — agent-skills

> Claude Code plugin for Java Spring backend development.
> Agent = Model + Harness. This file is the harness entry point.

If `PROJECT_GUIDELINES.md` exists at project root, read it FIRST — it overrides conventions below.

## How This Plugin Works

You are enhanced with **skills, hooks, and agents**. The bootstrap skill (`skills/bootstrap/SKILL.md`) loads automatically at session start and teaches you the full workflow. Trust the harness — it handles skill discovery, verification loops, context management, and observability for you.

**Your responsibilities**: triage every task into a lane, run pre-flight before every gate (1% rule), announce skills before use, never skip VERIFY + REVIEW, never self-assess (only external verification counts).

## MANDATORY Pre-flight Discovery Protocol (1% rule)

Before EVERY workflow gate (Triage, Align, Brainstorm, Plan, Spec, Execute, Review):

1. **Enumerate** ALL skills + rules with ≥1% relevance to the gate
2. **Score** each by relevance (0-100%)
3. **Decide** APPLY or SKIP per item
4. **Justify** every SKIP with concrete evidence (file path, missing dep, grep result — NOT "not relevant")
5. **Output** artifact to `.claude/memory/preflight/<gate>-<timestamp>.md`
6. **Reference** artifact during gate execution

This is non-negotiable. Workflow blocks gates without pre-flight artifact.

Cost of false positive (enumerate then SKIP) = few tokens.
Cost of false negative (miss applicable skill/rule) = technical debt, rework.

→ Bias toward over-enumeration.

Trivial lane uses light format (3-5 lines, see `skills/preflight/SKILL.md` §"Light version").

## Workflow — 5-Layer Adaptive

```
Triage (lane: trivial | standard | high-stakes)
  ├── trivial → Execute (light TDD) → Verify (compile+format) → Review S2 → Commit
  └── standard / high-stakes →
      Align (if vague / always high-stakes) → Brainstorm (if multi-path / mandatory high-stakes ≥3 options) →
      Plan → Spec → Execute (subagent dispatch per slice) → Verify → Review S1+S2 → Learn → Commit
```

Pre-flight runs before every gate. See `skills/preflight/SKILL.md` for the 6 variants.

Phase tracking (PLAN/SPEC/BUILD/VERIFY/REVIEW) still applies inside the Plan→Spec→Execute→Verify→Review portion. See `scripts/hooks/workflow-tracker.sh`.

## Tech Stack

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC · R2DBC · JPA/Hibernate · PostgreSQL · MySQL · Redis · Kafka · RabbitMQ · Lombok · Jackson · MapStruct · Resilience4j · Gradle · JUnit 5 · Testcontainers

**Architecture:** Hexagonal (Ports & Adapters) · CQRS · DDD · Event Sourcing

## Code Conventions

- **Immutability** — records, `@Value`, builders. No setters.
- **Reactive** — `Mono`/`Flux` chains. NEVER `.block()`.
- **DI** — Constructor injection (`@RequiredArgsConstructor`). No `@Autowired` on fields.
- **Size** — methods ≤50 lines, classes ≤400 lines (800 max).
- **DTOs** — Records for immutable DTOs. Never expose entities in API responses.
- **Imports** — Always `import` statements. Never inline fully-qualified class names.

## Naming

Tests: `shouldDoXWhenY` · Use cases: `CreateOrderUseCase`, `GetOrderQuery` · Events: `OrderCreatedEvent`

## Package Structure (Hexagonal)

```
com.example.{service}/
├── domain/           # Entities, value objects, domain events, repository ports
├── application/      # Use cases, services, command/query handlers
├── infrastructure/   # Adapters: DB, Kafka, gRPC, external HTTP
└── interfaces/       # Controllers, REST handlers, event listeners
```

## Workflow Gates — Non-Negotiable

Each gate produces a pre-flight artifact + a gate output artifact. See `skills/bootstrap/SKILL.md` for the full 5-layer flow.

**Lane bypass:** trivial lane skips Align/Brainstorm/Plan/Spec/Review S1 (see `rules/common/lanes.md`).

**Skip-trivial criteria:** ≤5 lines AND 1 file AND no new behavior → trivial lane (still mandatory: pre-flight 0 + light, Execute, Verify, Review S2).

After BUILD: VERIFY runs automatically → if fail, verify/fix loop retries → REVIEW runs automatically.
**A task is NOT complete until REVIEW passes.**

## Hard Blocks

1. `.block()` in reactive code → CRITICAL, fix immediately
2. `@Autowired` field injection → use `@RequiredArgsConstructor`
3. Expose entities in API → use record DTOs
4. Log sensitive data (PII, credentials, tokens)
5. Commit secrets to git
6. Skip input validation on API boundaries
7. `SELECT *` in queries → explicit column selection
8. Write code without `/plan` + `/spec` (except trivial ≤5-line fixes)
9. Agent commits to git → FORBIDDEN, only user commits
10. Stop after BUILD without VERIFY + REVIEW → FORBIDDEN
11. **Plan/spec NOT following templates** → FORBIDDEN. Threshold rule:
    - ≤2 slices → `templates/PLAN_TEMPLATE.md` + `templates/SPEC_TEMPLATE.md` (single-file)
    - 3+ slices → `templates/PLAN_INDEX_TEMPLATE.md` + `templates/PLAN_SLICE_TEMPLATE.md` + `templates/SPEC_INDEX_TEMPLATE.md` + `templates/SPEC_SLICE_TEMPLATE.md` (split)
    Required sections per template enforced by `scripts/ci/validate-plan-spec-templates.sh`. Missing section = re-do.
12. **Slice-executor executing against plan/spec missing required sections** → FORBIDDEN. Subagent refuses, routes back to planner/spec-writer.
13. **Cross-cutting override in spec slice without ADR** → FORBIDDEN. Spec index §1 (auth/logging/error envelope/idempotency/perf) is AUTHORITATIVE. Slice override requires ADR + explicit §"Cross-cutting override" block.
14. **`/build` dispatching when split plan/spec status is `PARTIALLY_APPROVED`** → FORBIDDEN. Full feature approval required (all slices APPROVED + index APPROVED) before any slice dispatched.
15. **Code review finding without rule ID citation** → FORBIDDEN. Stage 2 reviewer MUST cite rule ID from `rules/java/code-review-*.md` per finding (`[<P0-P4>][<RULE-ID>]` e.g. `[P0][CORE-NUM-001]`, `[P0][JKS-POL-002]`, `[P1][MVC-TX-002]`). Findings without rule ID = invalid, orchestrator rejects output and re-dispatches reviewer. P4 nits may omit rule ID. Unknown ID not in catalog → mark `[NEW-RULE]`, route to evolve-rules.
16. **Slice-executor declaring slice done without applying code-review rules during REFACTOR** → FORBIDDEN. REFACTOR step MUST self-check against critical rule IDs across all 6 rule sets (CORE/MVC/RX/WFL/XCT/JKS): CORE-NUM-001, CORE-LOG-002, CORE-EXC-004, CORE-API-001, MVC-TX-001, MVC-TX-002, MVC-VAL-001, MVC-REP-004, RX-FND-001, RX-OPS-002, WFL-WC-002, JKS-OBJ-001, JKS-MOD-001, JKS-MNY-001, JKS-POL-002, JKS-POL-003, JKS-ANN-003, JKS-PRF-002, XCT-IDM-001. Cite enforced IDs in result report.
17. **Jackson polymorphic deserialization without explicit whitelist** → FORBIDDEN. `@JsonTypeInfo(use = Id.CLASS)` (JKS-POL-002) and `enableDefaultTyping()` without `PolymorphicTypeValidator` (JKS-POL-003) = RCE vulnerability (CVE-2017-7525 class). Use `Id.NAME` + `@JsonSubTypes` whitelist.
18. **BigDecimal serialized as JSON number for money** → FORBIDDEN in fintech context. `@JsonFormat(shape = JsonFormat.Shape.STRING)` on BigDecimal field, or global `WRITE_BIGDECIMAL_AS_PLAIN`. Citation: JKS-MNY-001 (P0).
19. **Plugin version bumped without syncing all 3 sources** → FORBIDDEN. `.claude-plugin/plugin.json` (canonical), `package.json`, `.claude-plugin/marketplace.json` `plugins[0].version` MUST agree. Run `bash scripts/ci/validate-version-sync.sh` before declaring release done. Detail: `rules/common/version-sync.md`.
20. **Hardcoded version banner in user-facing script** → FORBIDDEN. Scripts MUST read version dynamically from `.claude-plugin/plugin.json` (e.g. via `$PLUGIN_VERSION` variable). Per-script header comments (`# script.sh (v3.2)`) are NOT user-visible and exempt.

## Always

1. Constructor injection (`@RequiredArgsConstructor`)
2. Bean Validation on API boundaries (`@Valid`)
3. Records for immutable DTOs
4. `StepVerifier` for reactive tests
5. Domain exceptions (not generic `RuntimeException`)
6. Parameterized queries (never string concatenation)
7. Structured logging with MDC context
8. 80%+ test coverage (JaCoCo)
9. Announce skill before use: "Using skill: {name} for {reason}"
10. Drive workflow to completion — never stop at BUILD
11. **Plan + Spec via templates** — pick shape per threshold (≤2 slices = single-file, 3+ = split). Copy template structure verbatim. Fill required sections.
12. **Validate template conformance** before user approval: `bash scripts/ci/validate-plan-spec-templates.sh --plan <path> --spec <path>` (path is `.md` for single-file, directory for split)
13. **Split shape: cross-cutting in `spec_index §1` is AUTHORITATIVE** — slices reference, never override w/o ADR
14. **Split shape: `/build` requires full approval** — all slices + indices APPROVED, NOT PARTIALLY_APPROVED
15. **Code review rule ID citation mandatory** — every Stage 2 finding tagged `[<P0-P4>][<RULE-ID>]`. Rule IDs from `rules/java/code-review-{core,mvc,reactor,webflux,crosscut,jackson}.md`. Catalog: `rules/java/code-review-crosscut.md §8` + jackson §17.
16. **REFACTOR step self-checks code-review rules** — slice-executor verifies critical IDs (CORE-NUM-001, CORE-LOG-002, MVC-TX-001/002, RX-FND-001, WFL-WC-002, JKS-OBJ-001/MOD-001/MNY-001/POL-002/POL-003/ANN-003, XCT-IDM-001) before reporting slice done.
17. **Unified code-review skill** — `skills/coding-standards/SKILL.md` (aka code-review) loads all 6 rule sets (CORE/MVC/RX/WFL/XCT/JKS) and enforces rule ID citation. Always loaded for Java tasks.
18. **Plugin version is single-source** — `.claude-plugin/plugin.json` `version` is canonical. `package.json` + `.claude-plugin/marketplace.json` `plugins[0].version` mirror it. User-facing scripts (banner, log) read dynamically — never hardcode. Validator: `scripts/ci/validate-version-sync.sh` (wired into `run-all.sh`).

## Harness Awareness

- **Hooks** enforce rules automatically — quality gates, skill routing, verify/fix loops, context budget, observability traces. You don't need to manage these manually.
- **Context budget** is monitored. Act on compact-advisor warnings promptly.
- **State lives on disk**, not in context: `workflow-state.json`, `verify-fix-state.json`, `build-checkpoint.json`, `session-metrics.json`. Read from disk when resuming.
- **Verification is external**: tests, compile, lint determine pass/fail. Never trust self-assessment.

## Repo Scripts — Required Prompts

Some scripts in `scripts/` rely on paths outside this repo. Before invoking them, ASK the user for the path instead of trusting built-in auto-detect fallbacks (those assume one developer's checkout layout and produce misleading results elsewhere).

- `scripts/ci/check-summer-version-coverage.sh` — ask: "Which Summer CHANGELOG should I use? (path, or `auto` for fallback)". Pass via `--changelog PATH`. Auto-detect fallback only if user explicitly opts in.
