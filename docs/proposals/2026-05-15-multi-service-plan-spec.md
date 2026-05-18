# Multi-Service Plan/Spec — Decomposition Pattern

**Status:** ACCEPTED (Option 2c per default recommendation)
**Date:** 2026-05-15
**Parent proposal:** `docs/proposals/2026-05-15-plan-spec-decomposition.md`

---

## Decision

When a feature spans multiple services, plan/spec uses **single feature directory with `service:` per-slice frontmatter** (Option 2c).

```
.claude/docs/plans/<feature>/
├── index.md                              # frontmatter: services_involved: [auth-ms, party-ms, notification-ms]
└── slices/
    ├── 01-auth-emit-event.md             # frontmatter: service: auth-ms
    ├── 02-party-store-record.md          # frontmatter: service: party-ms
    └── 03-notification-send-email.md     # frontmatter: service: notification-ms

.claude/docs/specs/<feature>/
├── index.md                              # frontmatter: services_involved: [...]
└── slices/
    ├── 01-auth-emit-event.md             # frontmatter: service: auth-ms
    └── ...
```

### Why Option 2c (not 2a / 2b)

| Option | Shape | Reject reason |
|---|---|---|
| 2a — Nested by service | `<feature>/<service>/slices/` | Deep nesting; slice files split between dirs; navigation cost |
| 2b — Flat with feature-service combo | `<feature>-<service>/` | Feature identity scattered across multiple dirs; index per service breaks aggregate review |
| **2c — Single feature dir + per-slice service** | `<feature>/slices/<NN>-<service>-<title>.md` | Feature identity preserved; slice ownership explicit; aggregate dep graph in single index |

### Naming convention for multi-service slices

```
slices/<NN>-<service-name>-<slice-title-slug>.md
```

Examples:
- `slices/01-auth-emit-merchant-created-event.md`
- `slices/02-party-store-merchant-record.md`
- `slices/03-notification-send-welcome-email.md`

Service prefix in filename enables quick `grep` per service.

---

## Frontmatter additions (multi-service)

### Index frontmatter

```yaml
---
status: DRAFT
feature: merchant-registration-flow
service: <NOT applicable for multi-service — use services_involved>
services_involved: [auth-ms, party-ms, notification-ms]
lane: high-stakes  # multi-service usually high-stakes
slice_count: 8
slice_decomposition: split
multi_service: true
plan: ../plans/merchant-registration-flow/index.md
created: 2026-05-15
phase: PLAN | SPEC
---
```

### Slice frontmatter

```yaml
---
slice_id: 01
slice_title: Auth — emit MerchantCreatedEvent
parent_plan: ../index.md
service: auth-ms                          # MANDATORY for multi-service
status: DRAFT
risk: Medium
complexity: M
depends_on: []                            # cross-service deps allowed
blocks: [02, 03]                          # blocks slices in other services
---
```

---

## Cross-service dependencies

`depends_on` + `blocks` can span services. Dep graph in index:

```
Slice 01 (auth-ms) → blocks: 02 (party-ms), 03 (notification-ms)
Slice 02 (party-ms) → blocks: 04 (party-ms)
Slice 03 (notification-ms) → blocks: 05 (notification-ms)
```

**Cross-service contract slices first:** order events / API contracts before consumer slices. Example: slice 01 defines event payload; slices 02 + 03 consume it. 01 unblocks both.

---

## Cross-service cross-cutting (spec index §1)

`spec_index §1` defines feature-wide cross-cutting. Per-service overrides go in slice §"Cross-cutting override" with ADR.

Common cross-cutting for multi-service features:
- **Correlation ID propagation** — header `X-Request-Id` forwarded across service hops
- **Idempotency key propagation** — `Idempotency-Key` consistent across services
- **Distributed tracing** — Micrometer Tracing span context propagation
- **Saga / outbox pattern** — if eventual consistency required (link to ADR)
- **Cross-service auth** — mTLS / service-account tokens / JWT propagation
- **Error envelope** — shared RFC 7807 shape across services (or per-service variants documented)

---

## Subagent dispatch (multi-service)

Orchestrator dispatches per slice. Subagent context includes:
- `service: <name>` from slice frontmatter
- Working directory: subagent operates in correct service repo
- `slice-executor` reads `service:` and routes to `<service-repo>/.claude/docs/...` if multi-repo

**Multi-repo handling:**
- If plan lives in a coordination repo (e.g., `payment-gateway-design-docs/.claude/docs/plans/<feature>/`)
- Per-service code lives in service repo (`auth-ms/`, `party-ms/`, etc.)
- Slice file references both: `code_repo: <path-to-service-repo>` in frontmatter

```yaml
---
slice_id: 01
slice_title: Auth — emit MerchantCreatedEvent
parent_plan: ../index.md
service: auth-ms
code_repo: ../../../../auth-ms          # relative path from coordination repo
status: DRAFT
...
---
```

`slice-executor` reads `code_repo` → executes Edit/Bash within that path. R5 hard block (per `agents/planner.md`): NEVER modify files outside assigned slice's `code_repo`.

---

## Validator extension

`scripts/ci/validate-plan-spec-templates.sh` checks (when `multi_service: true` in index frontmatter):
- Every slice has `service:` frontmatter key
- `services_involved` list in index matches union of slice `service:` values
- `code_repo` paths (if present) exist relative to plan location
- Cross-service dep graph: slice IDs in `depends_on` + `blocks` exist in index

Validator addition handled by Phase 6.

---

## Stage 1 review (multi-service)

Per-slice `spec-compliance-reviewer` runs in correct service context:
- Service A reviewer: checks scenarios against Service A test suite
- Service B reviewer: checks scenarios against Service B test suite
- Cross-service contract verified: event payload schema matches across publisher + consumer slices

Per-slice verdicts aggregate into feature-level. Aggregate PASS requires:
- ALL per-slice Stage 1 PASS
- Cross-service contract match verified

---

## Stage 2 review (multi-service)

Per-slice `code-quality-reviewer` scoped to slice's `code_repo` diff. Security review (high-stakes) MUST cross-check:
- Event payload PII (publisher slice) ↔ consumer slice handling (no leak)
- Auth propagation across services (mTLS / token forwarding)
- Idempotency consistency across consumer services

---

## Example walkthrough

**Feature:** `merchant-registration-flow` — onboard merchant across 3 services.

**Index slices (excerpt):**

| # | File | Title | Service | Risk | Status |
|---|---|---|---|---|---|
| 01 | `01-auth-emit-merchant-created.md` | Auth — emit MerchantCreatedEvent | auth-ms | Medium | DRAFT |
| 02 | `02-party-store-merchant-record.md` | Party — store record from event | party-ms | Low | DRAFT |
| 03 | `03-notification-send-welcome-email.md` | Notification — send welcome email | notification-ms | Low | DRAFT |

**Dependency graph:**
```
01 (auth-ms) → blocks: 02, 03 (cross-service: event consumers)
02 (party-ms) → blocks: (leaf)
03 (notification-ms) → blocks: (leaf)
```

**Execution:**
1. Slice 01 dispatched first (defines event contract)
2. Slices 02 + 03 dispatched in parallel (independent consumers, both depend only on 01)
3. Per-slice subagent operates in correct service repo via `code_repo`
4. Reviewer S1 aggregates verdicts cross-service

---

## Migration / adoption

Multi-service features rare for greenfield projects; common for established cluster (ewallet). Adoption opt-in:

1. Plan agent detects multi-service from Align artifact (cross-team coordination flagged)
2. Index frontmatter sets `multi_service: true` + `services_involved: [...]`
3. Slice frontmatter requires `service:` + optionally `code_repo:`
4. Validator enforces consistency

Single-service features unaffected (validator does not require `multi_service` flag).

---

## Open items (deferred to Phase 6)

- Validator code update (add multi-service consistency checks)
- Planner agent: detect multi-service trigger from Align (Cross-Service Context Protocol already exists in planner.md — extend to set frontmatter)
- Subagent dispatch: handle `code_repo` path injection in `subagent-init.sh`
- Cross-service contract verification rule (event schema match)

Recommendation: implement when first real multi-service plan needed. Foundation in place; details on-demand.
