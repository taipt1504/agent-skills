---
status: DRAFT
feature: <kebab-case-feature-slug>
service: <service-name>
lane: <trivial | standard | high-stakes>
align: ../../../.claude/memory/align-artifacts/<date>-<feature>.md
brainstorm: ../../../.claude/memory/brainstorm-artifacts/<date>-<feature>.md
adr: ../../../docs/adr/<NNNN>-<decision>.md  # high-stakes only
design: ../../../<service>-design-docs/designs/<feature>/design.md  # optional cross-repo design doc
created: YYYY-MM-DD
phase: PLAN
---

# Plan — <Feature Title>

> **Template version:** v1.0 (templates/PLAN_TEMPLATE.md)
> **Conformance:** ALL required sections below MUST be present. Optional sections marked `[OPTIONAL]`.
> Validation: `scripts/ci/validate-plan-spec-templates.sh`

---

## 1. Scope

<2-4 sentences. What this feature delivers. What it depends on (Align artifact for requirements, Brainstorm for chosen approach, ADR for high-stakes). What it explicitly does NOT do (link to §6 Out of Scope).>

**Sources:**
- Align artifact: `<path>`
- Brainstorm artifact: `<path>` (chosen option: A<N>)
- ADR: `<path>` (high-stakes only)

---

## 2. Affected files

### New

| Path | Purpose |
|---|---|
| `src/...` | <one-line purpose> |
| `src/test/...` | <test file> |

### Modified

| Path | Change |
|---|---|
| `src/...` | <one-line change description> |

### Schema delta `[OPTIONAL — only if DB migration]`

```sql
-- V<N>__<description>.sql
ALTER TABLE ...;
```

Apply `rules/java/migration.md` (Flyway immutability + expand-contract).

---

## 3. Slices

Decompose chosen solution into vertical slices. Each slice = independently testable.

### Slice 1: <verb-led title>

- **Description:** <1-2 sentences>
- **Files touched (estimated):** <count> in `<module>/<layer>/`
- **Skills required:** <from pre-flight 2 APPLY list>
- **Rules required:** <from pre-flight 2 APPLY list>
- **Dependencies:** <slice IDs blocking this, or "none">
- **Risk:** Low | Medium | High
- **Complexity:** S (<2h) | M (2-8h) | L (>8h)
- **Rationale:** <why this slice is its own unit>

### Slice 2: ...

(Repeat per slice. Minimum 1 slice for trivial; typically 2-5 for standard; 3-7 for high-stakes.)

---

## 4. Dependency graph

```
Slice 1 → blocks: 2, 3
Slice 2 → blocks: 4
Slice 3 → blocks: 5
Slice 4 → blocks: (leaf)
Slice 5 → blocks: (leaf)
```

**Parallel-eligible (independent, no shared blocker):**
- Slice 2 + 3 (both depend only on 1)

**Sequential chain:**
- 1 → 2 → 4
- 1 → 3 → 5

`commands/build.md` dispatches per this graph. Max concurrent = `config.team.maxTeammates`.

---

## 5. Risk register

| Slice | Risk | Severity | Mitigation |
|---|---|---|---|
| <id> | <one-line risk> | Low \| Medium \| High | <one-line mitigation> |

---

## 6. Out of scope

Explicit non-goals. Anything ambiguous in Align that the user confirmed is NOT in this feature.

- <Non-goal 1>
- <Non-goal 2>

---

## 7. Execution order

Final ordering, accounting for dependency graph + risk priority (high-risk slices early):

1. Slice <id> — <why first> (typically: highest risk OR most blockers)
2. Slice <id, id> (parallel batch)
3. Slice <id>
4. ...

---

## 8. Rollback `[OPTIONAL — required for high-stakes]`

If feature flag exists or partial rollout planned, describe rollback strategy here.

For high-stakes:
- Rollback trigger: <condition that warrants rollback>
- Rollback steps: <1-step or short sequence>
- Cost estimate: <hours>
- Data integrity: <how data preserved during rollback>

---

## 9. References

- Brainstorm: `<path>`
- Align: `<path>`
- ADR: `<path>` (high-stakes)
- Pre-flight 2 artifact: `.claude/memory/preflight/plan-<ts>.md`
- CONTEXT.md vocabulary used: <list new terms added>
- Related ADRs: <list>
- External design doc: `<path>` (optional)

---

## Approval

Status transitions:
- `DRAFT` → user reviews
- `APPROVED` → user confirms via "yes" / "approve" / "proceed"
- `REVISED` → updated per user feedback (revision history below)

### Revision history `[OPTIONAL — auto-appended]`

- YYYY-MM-DD: <what changed and why>

---

> **Template validation:** This plan MUST contain sections 1-7 (mandatory). Sections 8-9 + revision history are optional but recommended. `scripts/ci/validate-plan-spec-templates.sh` enforces.
