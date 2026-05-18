# Example: Pre-flight Artifact for Brainstorm Gate (variant 1)

> **This file is a TEMPLATE / EXAMPLE.** Live artifacts go to `.claude/memory/preflight/brainstorm-<timestamp>.md` in the workspace, not in the plugin tree.

## Context

**Task:** "Migrate event publishing from sync REST calls to Kafka outbox pattern"
**Lane:** High-stakes
**Gate:** Brainstorm (variant 1)
**Date:** 2026-05-16T09:14:00Z
**Pre-flight 0 reference:** `.claude/memory/preflight/initial-1747380000.md`

## Skills enumeration (total: 26)

### APPLY (8)

| Skill | Score | Action |
|---|---|---|
| brainstorm | 100% | Run tournament process, generate ≥3 options (mandatory high-stakes) |
| architecture | 90% | Hexagonal boundary impact: outbox lives in infrastructure adapter |
| messaging-patterns | 95% | Kafka producer patterns, outbox table schema, idempotency |
| database-patterns | 85% | Outbox table design, transactional consistency with domain writes |
| api-design | 60% | Event envelope schema, versioning, backward compat |
| observability-patterns | 70% | Outbox dispatcher metrics, dead-letter handling, lag monitoring |
| pentest | 50% | Event payload may contain PII — review for sensitive data leak |
| solution-design | 80% | Document decision options + trade-offs for ADR |

### SKIP (18) — concrete justifications

| Skill | Reason |
|---|---|
| api-docs-datatype-sync | No OpenAPI changes in this task (events only, no REST) |
| caller-aware-audit-pattern | Outbox writer inherits caller context from domain transaction |
| cluster-event-standards | APPLIES (already in messaging-patterns) — not separately enumerated |
| coding-standards | Generic style covered by gate 4 (Execute), not brainstorm |
| deployment-patterns | No deployment topology change in this brainstorm |
| grpc-patterns | No gRPC in this scope (verified: `grep -rln '@GrpcService' src/` = 0 results) |
| no-jsonnode-response | DTO typing rule applies in Execute gate, not brainstorm |
| redis-patterns | No caching layer change in proposed solutions |
| spring-mvc-patterns | Project uses WebFlux (verified application.yml `spring.main.web-application-type: reactive`) |
| spring-security | Outbox runs as system principal, no authn change |
| spring-webflux-patterns | Applies to Execute, not brainstorm of design alternatives |
| summer-data | Project uses Summer (verified) — already covered by messaging-patterns in brainstorm context |
| summer-file | No file storage involved |
| summer-kafka | APPLIES — moved to APPLY actually. *Correction noted, see addendum* |
| summer-payment-sdk | No payment SDK touched |
| summer-ratelimit | No rate limiting decisions in brainstorm |
| summer-rest | No REST endpoint design in this brainstorm |
| testing-workflow | Applies to Execute, not brainstorm |
| triage | Already ran (lane=high-stakes set) |

> **Addendum:** During brainstorm, surfaced that `summer-kafka` is the canonical implementation skill (not generic messaging-patterns). Adding to APPLY list. Per doc 07 §"During session: write to Tier 1, propose updates" — artifact updated mid-gate.

### SKIP — auto-evolved (Tier 3)

(none active with confidence ≥ 0.6 for this task type)

## Rules enumeration (total: 13)

### APPLY (6)

| Rule | Score | Action |
|---|---|---|
| rules/common/spec-driven.md | 100% | Brainstorm output feeds Spec gate |
| rules/common/lanes.md | 100% | High-stakes requires ≥3 options + ADR |
| rules/common/patterns.md | 90% | Architectural pattern (hexagonal + outbox) |
| rules/common/skill-enforcement.md | 100% | 1% rule reminder |
| rules/java/security.md | 60% | Event payload PII check |
| rules/java/observability.md | 70% | Define metrics + alerts in chosen option |

### SKIP (7)

| Rule | Reason |
|---|---|
| rules/common/coding-style.md | Style applies at Execute, not design |
| rules/common/development-workflow.md | Workflow rule, not solution-space |
| rules/common/git-workflow.md | Commit happens at end |
| rules/common/security.md | Generic — covered by java/security.md in this scope |
| rules/java/api-design.md | No REST surface changes |
| rules/java/coding-style.md | Style at Execute |
| rules/java/reactive.md | Reactive correctness at Execute |
| rules/java/testing.md | Testing at Execute / Verify |

## Active instincts (≥0.6 confidence)

| Instinct | Confidence | Action |
|---|---|---|
| "Outbox dispatcher needs explicit at-least-once + dedup downstream" | 0.78 | Surface in trade-off discussion |
| "Kafka topic naming `{bc}.{aggregate}.{event}.v{n}` cluster convention" | 0.85 | Include in solution sketches |

## Total summary

- Skills: 8 + 1 added = 9 APPLY, 17 SKIP
- Rules: 6 APPLY, 7 SKIP
- All SKIPs reference concrete evidence (filesystem grep, ADR cross-ref, or scope statement)

## Output destination

- Brainstorm artifact → `.claude/memory/brainstorm-artifacts/2026-05-16-outbox-migration.md`
- ADR (mandatory high-stakes) → `docs/adr/0042-outbox-migration.md`
