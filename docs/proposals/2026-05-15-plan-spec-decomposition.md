# Proposal — Plan/Spec Decomposition for Large Features

**Status:** DRAFT — awaiting user evaluation before refactor
**Date:** 2026-05-15
**Trigger:** large-feature single-file plans/specs become unreviewable, miss info, lose audit granularity.

---

## Problem

Current `templates/PLAN_TEMPLATE.md` + `SPEC_TEMPLATE.md` enforce single-file artifacts. Works for small features (1-2 slices) but breaks down at scale:

| Pain point | Evidence |
|---|---|
| Reviewer fatigue on giant files | `auth-ms/.claude/docs/plans/sub-merchant-user-cascade.md` = 43.9K, `profile-management.md` = 39.5K — humans skim, miss issues |
| All-or-nothing approval | User can't say "approve slice 1+2, revise slice 4" cleanly. Whole file edited → diff polluted |
| Diff pollution | Revising slice 3 changes scrolling context for slice 1 reviewer — false signal |
| Cross-cutting concerns mixed in | Auth, logging, error envelope repeated per-slice OR vaguely "see top" |
| Multi-service plans monolithic | `profile-management.md` 46.6K spec covers multiple integration points |
| Slice-executor sees too much | Subagent loads entire spec just to find its slice's scenarios — context pollution |
| Hard to assign reviewers | Can't split "auth specialist reviews slice 1, DB specialist reviews slice 2" |
| Spec scenarios bloat | 30+ scenarios in one file → table loses readability |
| Frontmatter `status` is binary per file | Can't track per-slice approval state |

---

## Goals (evaluation criteria)

Any new approach must:

1. **Granular approval** — user approves/revises per slice, not per feature
2. **Diff isolation** — changing slice N does NOT pollute slice M's diff
3. **Subagent context isolation** — slice-executor reads ONLY its slice's spec
4. **Reviewer assignment** — Stage 1 can split slice-1 to reviewer A, slice-2 to reviewer B
5. **Cross-cutting concerns explicit** — auth/logging/error envelope defined ONCE, referenced
6. **Backward compatible** — small features keep single-file form (no forced ceremony)
7. **Template-enforced** — validator catches non-conformance
8. **Audit trail preserved** — per-slice revision history

---

## Approach options considered

### Option A — Single-file (current)

Status quo. Works for ≤2 slices. Fails at scale.

**Reject:** doesn't meet goals 1-4.

### Option B — Per-slice files only (no index)

Each slice = `plans/<feature>/<NN>-<title>.md`. No top-level overview.

**Reject:** loses goal 5 (cross-cutting), reviewers can't see scope without scanning all files. Dep graph orphaned.

### Option C — Phased decomposition (heavyweight)

`plans/<feature>/00-overview.md`, `01-design.md`, `02-slices/*.md`, `03-risks.md`...

**Reject:** ceremony tax. 4+ files even for medium features.

### Option D — Hierarchical: index + per-slice (RECOMMENDED)

```
.claude/docs/plans/<feature>/
├── index.md                          # frontmatter + Scope + Dep graph + Risk register + Out-of-scope + slice index + References
└── slices/
    ├── 01-domain-sort-field.md       # one file per slice: full template §3 row
    ├── 02-application-query-service.md
    └── 03-interfaces-controller.md

.claude/docs/specs/<feature>/
├── index.md                          # frontmatter + Common (Auth + Idempotency + Logging + Cross-cutting) + Scenarios index + Out-of-scope + References
└── slices/
    ├── 01-domain-sort-field.md       # per slice: Inputs + Outputs + Contracts + Error Cases + Scenarios + SDD↔TDD
    ├── 02-application-query-service.md
    └── 03-interfaces-controller.md
```

**Pros:**
- ✅ Goal 1: per-slice frontmatter `status: DRAFT|APPROVED|REVISED` → granular approval
- ✅ Goal 2: revising slice-03 touches one file only → clean diff
- ✅ Goal 3: subagent receives `slices/03-interfaces-controller.md` path → loads ONLY its slice
- ✅ Goal 4: PR can split review by file path → assign per-slice
- ✅ Goal 5: `index.md` Common section holds cross-cutting; per-slice spec references it
- ✅ Goal 6: small features keep single-file via threshold rule (see below)
- ✅ Goal 7: validator extended to handle both shapes
- ✅ Goal 8: per-slice `## Revision history` section

**Cons:**
- More files (2 per slice — plan + spec). Mitigation: NN prefix enables sort, slice title in filename enables grep
- Index sync risk (slice in `slices/` but not in `index.md` slice index). Mitigation: validator cross-references
- Cross-cutting in index requires discipline. Mitigation: template requires explicit `## Cross-cutting (see also)` section per-slice spec

### Option E — Collocated plan+spec per slice

```
.claude/docs/features/<feature>/
├── index.md
└── slices/
    └── 01-domain-sort-field.md     # plan + spec in same file
```

**Reject:** loses plan/spec separation. Plan approval and Spec approval are distinct gates per workflow. Merging breaks gate boundaries.

---

## Recommended approach (Option D)

### Threshold rule

Single-file when ALL hold:
- ≤ 2 slices (trivial or simple standard task)
- Plan body < 200 lines after first draft
- Spec body < 300 lines after first draft

Otherwise → MUST split into `index.md` + `slices/*.md`.

Threshold checked by planner during decomposition. Spec-writer inherits planner's decision (file shape mirrors plan shape).

### File structure detail

#### Plan `index.md`

```markdown
---
status: DRAFT | APPROVED | PARTIALLY_APPROVED | REVISED
feature: <slug>
service: <name>
lane: <trivial | standard | high-stakes>
slice_count: <N>
slice_decomposition: split  # or "single" for small features
align: <path>
brainstorm: <path>
adr: <path>  # high-stakes
created: YYYY-MM-DD
phase: PLAN
---

# Plan — <Feature Title>

## 1. Scope
<2-4 sentences. Sources.>

## 2. Affected files (aggregate)
### New
<table — sum across all slices>
### Modified
<table>
### Schema delta (if any)
<SQL block>

## 3. Slice index
| # | Slice file | Title | Risk | Complexity | Status |
|---|---|---|---|---|---|
| 01 | slices/01-domain-sort-field.md | Domain layer — sort field whitelist | Low | S | APPROVED |
| 02 | slices/02-application-query-service.md | Application — UserQueryService | Low | M | DRAFT |
| 03 | slices/03-interfaces-controller.md | Interfaces — controller + DTO | Med | M | DRAFT |

## 4. Dependency graph
<as before>

## 5. Risk register (aggregate)
<as before>

## 6. Out of scope
<as before>

## 7. Execution order
<as before>

## 8. Rollback (high-stakes optional)

## 9. References
```

#### Plan `slices/<NN>-<title>.md`

```markdown
---
slice_id: 03
slice_title: Interfaces — controller + DTO
parent_plan: ../index.md
status: DRAFT | APPROVED | REVISED
risk: Medium
complexity: M
depends_on: [02]
blocks: []
---

# Slice 03 — Interfaces — controller + DTO

## Description
<1-2 sentences>

## Files touched
### New
<table>
### Modified
<table>

## Skills required (from pre-flight 2 APPLY)
- spring-webflux-patterns
- api-design
- coding-standards
- testing-workflow

## Rules required
- rules/java/api-design.md
- rules/java/reactive.md
- rules/java/security.md

## Rationale
<why this slice is its own unit>

## Estimated effort
2h

## Revision history
- 2026-05-15: initial draft
```

#### Spec `index.md`

```markdown
---
status: DRAFT | APPROVED | PARTIALLY_APPROVED
feature: <slug>
service: <name>
lane: <lane>
slice_count: <N>
plan: ../plans/<feature>/index.md
created: YYYY-MM-DD
phase: SPEC
---

# Spec — <Feature Title>

## 1. Cross-cutting (applies to all slices)

### 1.1 Inputs (common)
- Authenticated caller: <source>
- Correlation ID: from `X-Request-Id` header
- Locale: from `Accept-Language`

### 1.2 Auth (if endpoint feature)
- Required roles: <list>
- @AuthRoles annotation: ...

### 1.3 Idempotency (if mutation feature)
- Key source: <header / generated>
- Replay behavior: ...

### 1.4 Logging (MDC mandatory)
- Required fields: ...
- Sensitive masking: ...

### 1.5 Error envelope (RFC 7807)
- Shape: ...

### 1.6 Performance budget
- Throughput target, latency, resource ceiling

## 2. Slice index (links to per-slice specs)
| # | Slice file | Title | Scenarios | Status |
|---|---|---|---|---|
| 01 | slices/01-domain-sort-field.md | Domain — sort field | 4 | APPROVED |
| 02 | slices/02-application-query-service.md | Application service | 6 | DRAFT |
| 03 | slices/03-interfaces-controller.md | Interfaces — controller | 8 | DRAFT |

## 3. Out of scope (aggregate)
<as before>

## 4. References
```

#### Spec `slices/<NN>-<title>.md`

```markdown
---
slice_id: 03
slice_title: Interfaces — controller + DTO
parent_spec: ../index.md
parent_plan_slice: ../../plans/<feature>/slices/03-interfaces-controller.md
status: DRAFT | APPROVED | REVISED
scenario_count: 8
---

# Spec Slice 03 — Interfaces — controller + DTO

## Cross-cutting reference
Auth + logging + idempotency + error envelope: see `../index.md` §1.

## 1. Inputs (slice-specific)
<HTTP request body schema, query params, path vars>

## 2. Outputs / Side Effects (slice-specific)
<response shape, DB writes scoped to this slice, events emitted>

## 3. Contracts / Invariants (slice-specific)
<invariants beyond cross-cutting>

## 4. Error Cases (slice-specific)
<table of errors NOT already in cross-cutting envelope>

## 5. Scenarios (test specifications)
| ID | Name | Setup | Action | Expected |
|---|---|---|---|---|
| S3.1 | shouldReturnFirstPageWhenDefaultParams | ... | GET /api/v1/users | 200 |
| S3.2 | ... | ... | ... | ... |

## 6. SDD ↔ TDD mapping
| Scenario | Test class | Test method |
|---|---|---|
| S3.1 | UserControllerTest | shouldReturnFirstPageWhenDefaultParams |

## 7. Revision history
- 2026-05-15: initial draft
```

### Slice-executor dispatch (changed)

**Before:** orchestrator passes `artifacts.spec` (single file). Subagent greps for its slice.

**After:** orchestrator passes `artifacts.spec_slice` (per-slice file). Subagent reads ONE file = clean context.

```
artifacts: {
  plan_index: ".claude/docs/plans/user-pagination/index.md",
  spec_index: ".claude/docs/specs/user-pagination/index.md",
  plan_slice: ".claude/docs/plans/user-pagination/slices/03-interfaces-controller.md",
  spec_slice: ".claude/docs/specs/user-pagination/slices/03-interfaces-controller.md"
}
```

Workflow state writes both index path + per-dispatch slice path.

### Approval flow (changed)

**Before:** user reads single plan.md, approves all-or-nothing.

**After:**
1. Planner produces `index.md` + N `slices/*.md`
2. User reviews `index.md` (overview, dep graph, slice list)
3. User reviews each slice file independently
4. Approval semantics:
   - Approve all → `index.md` status = APPROVED, all slices APPROVED
   - Approve some → `index.md` status = PARTIALLY_APPROVED, mixed slice states
   - Revise specific slices → individual slice file status = REVISED, version bumped
5. `/spec` cannot proceed unless `index.md` status ∈ {APPROVED, PARTIALLY_APPROVED} AND all referenced slices are APPROVED
6. `/build` dispatches only APPROVED slices; DRAFT/REVISED slices wait

### Cross-cutting concerns rule

`index.md` §1 holds:
- Auth shape (referenced by per-slice §"Cross-cutting reference")
- Logging fields (MDC)
- Error envelope (RFC 7807 shape)
- Performance budget
- Idempotency strategy

Per-slice spec MUST contain `## Cross-cutting reference` pointing to `../index.md §1`. Validator checks this.

NEVER duplicate cross-cutting in per-slice files. Slice-level overrides only when slice deviates from cross-cutting (rare, explicit).

### Validator extension

`scripts/ci/validate-plan-spec-templates.sh` extended:

```bash
# Detect shape from feature directory
if [ -d "$path/slices/" ]; then
  # Split shape: validate index.md + each slice file
  validate_index "$path/index.md"
  for slice in "$path"/slices/*.md; do
    validate_slice_plan "$slice"  # or _spec
  done
  validate_cross_references "$path"  # slice IDs in index match files
else
  # Single-file shape (small features)
  validate_single_file "$path.md"
fi
```

Cross-reference checks:
- Every slice listed in `index.md §3 Slice index` must exist as file
- Every file in `slices/` must be referenced in index
- Dependency graph slice IDs must match existing files
- `parent_plan` / `parent_spec` frontmatter values must point to valid index
- Cross-cutting reference present in per-slice specs

### Migration path

| Existing format | New format | Migration |
|---|---|---|
| `plans/<feature>.md` (single file, ≤2 slices) | KEEP as single file | None |
| `plans/<feature>.md` (single file, 3+ slices) | SPLIT into `plans/<feature>/index.md + slices/` | `scripts/migration/split-plan-spec.py` (new) |
| `plans/<feature>/index.md` (already split) | KEEP | None |

Migration script auto-extracts slices from existing single-file plan based on §3 Slices section headings. Manual review required.

### Template updates

- Existing `PLAN_TEMPLATE.md` + `SPEC_TEMPLATE.md` → kept as **single-file template** for small features
- New `PLAN_INDEX_TEMPLATE.md` + `PLAN_SLICE_TEMPLATE.md` + `SPEC_INDEX_TEMPLATE.md` + `SPEC_SLICE_TEMPLATE.md`
- Validator routes per shape detected

### Agent updates

- `planner.md` — decide single-file vs split per threshold; write correct shape
- `spec-writer.md` — inherit planner's shape; write matching shape
- `slice-executor.md` — receive per-slice file path from orchestrator; read only one file
- `spec-compliance-reviewer.md` — Stage 1 reviews per-slice spec independently → per-slice verdict aggregated into overall verdict in `index.md`
- `code-quality-reviewer.md` — Stage 2 reviews diff scoped to slice files

### Subagent dispatch update

`subagent-init.sh` injects `parent_plan_slice` + `parent_spec_slice` paths + cross-cutting reference excerpt from `index.md §1`.

---

## Concrete example — pagination feature comparison

### Before (single-file, 3 slices)

```
plans/user-pagination.md         # 250 lines
specs/user-pagination.md         # 480 lines
```

User must read 730 lines to review. Diff for any slice change touches whole file.

### After (split shape)

```
plans/user-pagination/
├── index.md                     # 80 lines (overview + slice index + dep graph + risks + out-of-scope)
└── slices/
    ├── 01-domain-sort-field.md  # 35 lines
    ├── 02-application.md        # 60 lines
    └── 03-interfaces.md         # 80 lines

specs/user-pagination/
├── index.md                     # 150 lines (cross-cutting auth + logging + error envelope + slice index)
└── slices/
    ├── 01-domain-sort-field.md  # 70 lines
    ├── 02-application.md        # 90 lines
    └── 03-interfaces.md         # 120 lines
```

User can review per-slice in isolation. Approving slice 01 + 02 while revising 03 is clean: 03's diff doesn't pollute 01/02 context.

### Slice-executor dispatch comparison

**Before:** subagent loads 480-line spec, greps for "Slice 3" section. Other slices' content pollutes context.

**After:** subagent loads `specs/user-pagination/slices/03-interfaces.md` (120 lines) + `index.md §1 Cross-cutting` (60-line excerpt). Total context = 180 lines, scoped to slice 03.

---

## Trade-offs honest

**What we gain:**
- Per-slice approval + revision granularity
- Diff isolation per slice
- Cleaner subagent context
- Per-slice reviewer assignment
- Cross-cutting concerns DRY

**What we sacrifice:**
- File count grows (3 slices → 6 files: 1 plan index + 3 plan slices + 1 spec index + 3 spec slices is wrong — actually 8: plan index + 3 plan slices + spec index + 3 spec slices). Actually let me recount:
  - Plan: 1 index + N slices = N+1 files
  - Spec: 1 index + N slices = N+1 files
  - Total: 2(N+1) files vs current 2 files
  - 3-slice feature: 8 files vs 2 files
- Navigation overhead (must open multiple files). Mitigation: index has slice index table with links
- Index sync discipline required. Mitigation: validator enforces
- Migration cost for existing artifacts. Mitigation: opt-in (existing single-file OK for small features)

**Mitigations summarized:**
- File count: NN prefix sorts, slice title in filename eases grep
- Navigation: `index.md` is the single entry point; slice list table links to all
- Sync: validator runs in CI + before user approval
- Migration: only required if user decides to split existing large file

---

## Open questions for user

1. **Threshold rule values:** ≤ 2 slices stays single-file; 3+ splits. Acceptable? Or different cutoff (e.g., 4+)?
2. **Multi-service plans:** when a feature spans services, should structure be:
   - **2a:** `plans/<feature>/index.md` + `plans/<feature>/<service>/slices/...` (nested by service)
   - **2b:** `plans/<feature>-<service>/...` (flat — one feature dir per service)
   - **2c:** `plans/<feature>/index.md` lists slices per-service, `slices/` flat with `service:` frontmatter
3. **Cross-cutting authority:** should `index.md §1 Cross-cutting` be authoritative (per-slice MUST reference, NEVER override), or advisory (per-slice MAY override with justification)?
4. **Existing artifacts:** migrate big ewallet plans/specs retroactively, or only enforce on new features?
5. **Stage 1 review granularity:** per-slice verdict (independent PASS/FAIL per slice) or whole-feature verdict (single binary)? Doc 02 says binary per feature; per-slice is finer.
6. **`status: PARTIALLY_APPROVED` semantics:** allow `/build` to dispatch only approved slices, OR require full feature approval before any slice dispatch?

---

## Recommendation

**Proceed with Option D (hierarchical index + per-slice).** Implement:

1. Create 4 new templates: `PLAN_INDEX_TEMPLATE.md`, `PLAN_SLICE_TEMPLATE.md`, `SPEC_INDEX_TEMPLATE.md`, `SPEC_SLICE_TEMPLATE.md`
2. Keep existing `PLAN_TEMPLATE.md` + `SPEC_TEMPLATE.md` as single-file templates (small-feature path)
3. Update planner + spec-writer to decide shape + write per shape
4. Update slice-executor + subagent-init.sh to consume per-slice paths
5. Update reviewers + dc-review.md for per-slice verdict aggregation
6. Extend validator to handle both shapes + cross-reference checks
7. Write `scripts/migration/split-plan-spec.py` for migrating existing single-files
8. Update CLAUDE.md hard blocks + WORKING_WORKFLOW.md + examples

**Estimated effort:** 8-12 hours.

**Risk:** template proliferation if not careful — propose 4 new templates max, no further fragmentation. Validator is the discipline anchor.

---

## Decision needed

Reply with one of:

- **Approve** — proceed with Option D, threshold ≤ 2 slices stays single-file
- **Approve with changes** — Option D but adjust <specific items, e.g., threshold, cross-cutting authority, migration strategy>
- **Reject** — keep current single-file approach (state reasons)
- **Counter-proposal** — alternative shape (describe)

After your decision, I'll execute the refactor per agreed shape.
