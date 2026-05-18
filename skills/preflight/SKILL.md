---
name: preflight
description: Mandatory pre-flight discovery before every workflow gate. Enumerate ALL skills + rules ≥1% relevant. Justify every SKIP with concrete evidence. Produces artifact downstream gates + subagents consume. Meta-skill — fires before all other skills.
triggers:
  natural: ["pre-flight", "preflight", "skill discovery", "1% rule"]
  code: ["PreToolUse before workflow command"]
  command: ["/preflight"]
applicability:
  always: true
  triggers:
    auto_fire: ["before EVERY workflow gate"]
relevance_assessment: |
  Always 100% — meta-skill, fires first before any other skill in the gate.
---

# Pre-flight — Skill + Rule Discovery Protocol

> **"Dù 1% cũng phải enumerate. Dù SKIP cũng phải có evidence."**

Bias toward over-enumeration. False positive (enumerate then SKIP) = few tokens. False negative (miss applicable skill/rule) = technical debt, rework.

## When this skill fires

**Always fire** before:
- Triage (variant 0 — initial discovery)
- Brainstorm (variant 1 — brainstorm prep)
- Plan (variant 2 — plan prep)
- Spec (variant 3 — spec prep)
- Execute (variant 4 — execute prep, also per-slice for subagents)
- Review (variant 5 — review prep, both Stage 1 + Stage 2 use same artifact)

**Light version** for:
- Trivial lane tasks (3–5 line condensed format)

**Align gate** inherits variant 0 artifact (alignment = requirements-gathering, not solution-space exploration). Emit `align-*.md` only if new-skill discovery occurred mid-alignment.

**Never skip.** No bypass flag.

## 6 variants — what to enumerate

| Variant | Scope |
|---|---|
| 0 — Initial | ALL skills (filesystem walk), ALL rules, active instincts. Bias to over-enumerate. |
| 1 — Brainstorm | Brainstorm skill + evaluation-dimension refs + domain skills surfaced by Align |
| 2 — Plan | Planning skills, `rules/common/patterns.md`, agents rule, lanes rule |
| 3 — Spec | API design rule (if API), testing rule, blackbox patterns |
| 4 — Execute | TDD workflow, language patterns, framework patterns (webflux OR mvc), domain patterns (DB / messaging / Redis), coding-style + security + observability rules, `rules/java/reactive.md` |
| 5 — Review | security-review skill, verification skill, testing rule, observability rule |

Detail in `references/gate-mappings.md`.

## Process

### Step 1 — Identify upcoming gate

From context: user invoked `/brainstorm` → variant 1. Plan approved → variant 3. Build complete → variant 5.

### Step 2 — List available skills + rules

Read filesystem, NOT memory:

```bash
find skills -name "SKILL.md" -type f
find rules -name "*.md" -type f
# Active instincts: query memory system for confidence > 0.6
```

Output injected as gate context via `preflight-discovery.sh`.

### Step 3 — Score each item

| Score | Threshold | Meaning |
|---|---|---|
| 90–100% | High | Central to gate, definitely applies |
| 60–89% | Medium-High | Supports gate, likely applies |
| 30–59% | Medium | Possibly applies, depends on specifics |
| 1–29% | Low | Marginal, verify carefully |
| 0% | None | Not relevant, must justify |

### Step 4 — APPLY or SKIP per item

**APPLY format:**
```
- <name>: APPLY (score%) — <reason + action to take>
```

**SKIP format:**
```
- <name>: SKIP — <concrete evidence>
```

**SKIP justification rules:**
- ✅ "verified no gRPC dependencies in build.gradle"
- ✅ "no @KafkaListener annotations in src/"
- ✅ "task only modifies test files, no production code"
- ❌ "not relevant" (vague)
- ❌ "doesn't apply" (vague)
- ❌ "skipped for now" (procrastination)

### Step 5 — Output artifact

Save to `.claude/memory/preflight/<gate>-<timestamp>.md`. Format:

```markdown
# Pre-flight: <Gate name>
**Date:** YYYY-MM-DD HH:MM
**Task:** <task>
**Lane:** <trivial | standard | high-stakes>
**Gate:** <Triage | Align | Brainstorm | Plan | Spec | Execute | Review>

## Skills enumeration (total: N)

### APPLY (count)
| Skill | Score | Action |
|---|---|---|
| ... | ... | ... |

### SKIP (count)
| Skill | Reason |
|---|---|
| ... | ... |

## Rules enumeration (total: N)
... (same structure)

## Active instincts (≥0.6 confidence)
... (same structure)

## Total summary
- Skills: X applying, Y skipped
- Rules: A applying, B skipped
- All skips justified with concrete evidence
```

### Step 6 — Reference during gate

Agent (and subagents) must:
1. Read pre-flight artifact at gate start
2. Reference applied skills/rules during execution
3. Update artifact if new items emerge mid-gate
4. Cite skill/rule names in output

## Light version (trivial lane)

3–5 lines, mandatory:


```markdown
# Pre-flight (trivial): <task>
**Skills applied:** none (trivial fix)
**Rules applied:** rules/common/coding-style.md, rules/java/coding-style.md
**Action:** apply format, ensure consistent style
```

Still required. Still announced. No bypass.

## Anti-patterns

### ❌ Lazy enumeration

Bad:
```
Skills considered: too many to list, picking most relevant.
- brainstorm, jpa-patterns
SKIP: everything else
```

Good: enumerate ALL. 24 skills exist → table has 24 rows.

### ❌ Vague justification

See Step 4.

### ❌ Implicit category skip

Bad:
```
- Database patterns: all SKIP (no DB changes)
```

Good (per-item):
```
- database-patterns: SKIP — no Repository touches (verified grep)
- redis-patterns: SKIP — no caching in this scope
```

### ❌ APPLY without action

Bad:
```
- jpa-patterns: APPLY (70%)
```

Good:
```
- jpa-patterns: APPLY (70%)
  Action: Reference for OrderRepository entity design, N+1 prevention via @EntityGraph, pagination via PageRequest
```

## Subagent context

Subagent during Execute receives variant 4 artifact as context:

```
You are executing slice N.

**Pre-flight artifact (skills + rules to apply):**
<paste preflight/execute-<ts>.md>

**Plan slice:** <description>
**Spec:** <slice spec>

**Process:**
1. Re-verify pre-flight items match this slice's needs
2. New items emerge → update artifact
3. Apply listed skills/rules
4. Cite skill names in commits and PR description
```

## Acceptance tests

- **T1:** 24 skills exist → artifact has 24 rows
- **T2:** Every SKIP has concrete evidence (file path, missing dep, grep result)
- **T3:** Multi-gate task → 1 artifact per gate, different content
- **T4:** Subagent receives artifact in context
- **T5:** Trivial lane → light format (3–5 lines)
- **T6:** New skill added → next pre-flight enumerates it

## Related

- `references/gate-mappings.md` — which skills/rules per gate
- `references/applicability-guide.md` — authoring applicability blocks
- `rules/common/skill-enforcement.md` — 1% rule mandate
- `scripts/hooks/preflight-gate.sh` — enforcement
- `scripts/hooks/preflight-discovery.sh` — enumeration
