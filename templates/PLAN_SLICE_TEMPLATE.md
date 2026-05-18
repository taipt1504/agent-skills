---
slice_id: <NN>
slice_title: <Slice title — matches index.md row>
parent_plan: ../index.md
status: DRAFT | APPROVED | REVISED
risk: Low | Medium | High
complexity: S | M | L
depends_on: []           # list of slice IDs that block this slice
blocks: []               # list of slice IDs this slice blocks
service: <name>          # for multi-service: explicit per-slice service
---

# Slice <NN> — <Slice Title>

> **Template version:** v1.0 (templates/PLAN_SLICE_TEMPLATE.md)
> **Parent:** `../index.md`
> **Validation:** required sections below + frontmatter keys.

---

## 1. Description

<1-2 sentences. What this slice does in isolation. Why it is its own unit (vs collapsing with adjacent slice).>

---

## 2. Files touched

### New

| Path | Purpose |
|---|---|
| `src/main/java/...` | <one-line> |
| `src/test/java/...` | <test file> |

### Modified

| Path | Change |
|---|---|
| `src/main/java/...` | <one-line> |

---

## 3. Skills required (from pre-flight 2 APPLY)

- <skill-name> — <one-line why>
- <skill-name> — <one-line why>

---

## 4. Rules required (from pre-flight 2 APPLY)

- `rules/<path>` — <one-line why>
- `rules/<path>` — <one-line why>

---

## 5. Rationale

<2-3 sentences. Why this slice exists as a separate unit. What it would mean to merge with adjacent slice (and why that's worse).>

---

## 6. Estimated effort

<S = <2h | M = 2-8h | L = >8h>

---

## 7. Slice-level risks `[OPTIONAL — only if differs from index aggregate]`

If slice carries risks not captured in index §5 (or with details too long for aggregate table):

- **Risk:** <description>
- **Mitigation:** <action>

---

## 8. Slice-level rollback `[OPTIONAL — only if differs from index §8]`

If rollback of THIS slice differs from feature-wide rollback:

- Trigger: <condition>
- Steps: <sequence>

---

## Revision history

- YYYY-MM-DD: <what changed and why>

---

> **Validation:** sections 1-6 mandatory. 7-8 optional. Validator checks frontmatter (`slice_id`, `slice_title`, `parent_plan`, `status`, `risk`, `complexity`).
