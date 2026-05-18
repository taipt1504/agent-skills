---
status: DRAFT
feature: <kebab-case-feature-slug>
service: <service-name>
lane: <trivial | standard | high-stakes>
slice_count: <N>
slice_decomposition: split  # "split" — this is the index for a multi-slice feature
align: ../../../.claude/memory/align-artifacts/<date>-<feature>.md
brainstorm: ../../../.claude/memory/brainstorm-artifacts/<date>-<feature>.md
adr: ../../../docs/adr/<NNNN>-<decision>.md  # high-stakes only
design: ../../../<service>-design-docs/designs/<feature>/design.md  # optional
created: YYYY-MM-DD
phase: PLAN
---

# Plan — <Feature Title>

> **Template version:** v1.0 (templates/PLAN_INDEX_TEMPLATE.md)
> **Shape:** SPLIT — slice details in `slices/<NN>-<title>.md` files
> **Threshold rule:** ≥3 slices use this index+slice shape. ≤2 slices use single-file `templates/PLAN_TEMPLATE.md`.
> **Conformance:** ALL required sections below MUST be present. Validator: `scripts/ci/validate-plan-spec-templates.sh`.

---

## 1. Scope

<2-4 sentences. What this feature delivers. What it depends on. Cross-link to per-slice files for detail.>

**Sources:**
- Align artifact: `<path>`
- Brainstorm artifact: `<path>` (chosen option: A<N>)
- ADR: `<path>` (high-stakes only)

---

## 2. Affected files (aggregate)

Sum across all slices. Per-slice detail lives in each slice file.

### New

| Path | Slice | Purpose |
|---|---|---|
| `src/...` | 01 | <one-line> |
| `src/test/...` | 01 | <one-line> |

### Modified

| Path | Slice | Change |
|---|---|---|
| `src/...` | 02 | <one-line> |

### Schema delta `[OPTIONAL — only if DB migration]`

```sql
-- V<N>__<description>.sql
ALTER TABLE ...;
```

Apply `rules/java/migration.md`.

---

## 3. Slice index

Authoritative list of slices. Each row links to its slice file. Validator cross-checks: every file in `slices/` MUST appear here; every row MUST point to existing file.

| # | Slice file | Title | Risk | Complexity | Status |
|---|---|---|---|---|---|
| 01 | [slices/01-<slug>.md](slices/01-<slug>.md) | <Slice title> | Low \| Medium \| High | S \| M \| L | DRAFT \| APPROVED \| REVISED |
| 02 | [slices/02-<slug>.md](slices/02-<slug>.md) | ... | ... | ... | ... |
| 03 | [slices/03-<slug>.md](slices/03-<slug>.md) | ... | ... | ... | ... |

---

## 4. Dependency graph

```
Slice 01 → blocks: 02, 03
Slice 02 → blocks: 04
Slice 03 → blocks: 05
Slice 04 → blocks: (leaf)
Slice 05 → blocks: (leaf)
```

**Parallel-eligible (independent):**
- Slice 02 + 03 (both depend only on 01)

**Sequential chains:**
- 01 → 02 → 04
- 01 → 03 → 05

`commands/build.md` dispatches per this graph. Bounded by `config.team.maxTeammates`.

---

## 5. Risk register (aggregate)

Slice-level risks lifted to top. Mitigation strategies per slice live in slice file.

| Slice | Risk | Severity | Mitigation summary |
|---|---|---|---|
| 03 | <one-line risk> | Low \| Medium \| High | <one-line — full detail in slices/03-<slug>.md> |

---

## 6. Out of scope (aggregate)

Feature-wide non-goals. Slice-level non-goals in slice files.

- <Non-goal 1>
- <Non-goal 2>

---

## 7. Execution order

Final order respecting dependency graph + risk priority.

1. Slice 01 — <why first>
2. Slice 02, 03 (parallel batch — independent)
3. Slice 04 (depends on 02)
4. Slice 05 (depends on 03)

---

## 8. Rollback `[OPTIONAL — required for high-stakes]`

Feature-wide rollback strategy. Per-slice rollback in slice files.

- **Rollback trigger:** <condition>
- **Rollback steps:** <high-level sequence>
- **Cost estimate:** <hours>
- **Data integrity:** <how preserved>

---

## 9. References

- Align artifact: `<path>`
- Brainstorm artifact: `<path>`
- ADR: `<path>` (high-stakes)
- Pre-flight 2 artifact: `.claude/memory/preflight/plan-<ts>.md`
- CONTEXT.md vocabulary added: <list>
- Related ADRs: <list>
- External design doc: `<path>` (optional)

---

## Approval

Status transitions (this index):
- `DRAFT` → user reviews all slices
- `APPROVED` → all slices APPROVED + user confirms aggregate
- `PARTIALLY_APPROVED` → mixed states (some slices APPROVED, others DRAFT/REVISED)
- `REVISED` → revisions in progress

`/build` requires `status: APPROVED` AND all slices APPROVED. PARTIALLY_APPROVED blocks dispatch (gate discipline per decision §6.7.x).

### Revision history `[OPTIONAL — auto-appended]`

- YYYY-MM-DD: <what changed and why>

---

> **Validation:** sections 1-7 mandatory. 8-9 optional. Validator enforces structure + slice-index cross-references.
