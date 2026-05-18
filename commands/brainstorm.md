---
name: brainstorm
description: Tournament-style solution exploration. Generates 2-5 options with adversarial challenges, recommends with trade-offs. Mandatory high-stakes (≥3 options), conditional standard (multi-path).
---

# /brainstorm — Solution Exploration Gate

## Usage

```
/brainstorm                            # Re-brainstorm current task
/brainstorm <problem description>      # Brainstorm new problem
/brainstorm --use A2                   # Skip exploration, lock A2 (manual override)
/no-brainstorm                         # Skip (high-stakes requires explicit ack)
```

## First Action (MANDATORY)

1. Load `skills/brainstorm/SKILL.md`
2. Read lane from `.claude/memory/state/current-triage.json`
3. Read latest align artifact from `.claude/memory/align-artifacts/`
4. Read pre-flight 1 from `.claude/memory/preflight/brainstorm-*.md`
5. If lane=trivial: refuse — Brainstorm skipped
6. If lane=standard AND single obvious solution: state reasoning + offer to skip
7. If lane=high-stakes: proceed (mandatory, ≥3 options)

## Process

Per `skills/brainstorm/SKILL.md`:

**Phase 1 — Frame:** restate problem, pick 3-5 dimensions, separate constraints from assumptions.

**Phase 2 — Tournament:**
- A1 + self-critique
- Challenge 1: beat A1 weakness → A2 + head-to-head
- Challenge 2: different paradigm → A3
- Challenge 3 (high-stakes): question assumption → A4
- Stop at cap 5 OR diminishing returns
- Min: 2 standard, 3 high-stakes

**Phase 3 — Synthesis:** comparison matrix, recommendation with trade-offs.

**Phase 4 (high-stakes only):** ADR → `docs/adr/NNNN-<decision>.md`.

## Output

Save to `.claude/memory/brainstorm-artifacts/<YYYY-MM-DD>-<task-slug>.md`. High-stakes: also write ADR.

State explicitly:
```
## Brainstorm complete
**Lane:** <Standard | High-stakes>
**Options considered:** <count>
**Recommendation:** A<N> — <name>
**Confidence:** <High | Moderate | Low>
**Close call?** <Yes | No>
**Trade-offs:**
- Gain: <bullet>
- Sacrifice: <bullet>
**Next gate:** Plan
**Artifact:** <path>
**ADR (if high-stakes):** <path>
```

## User decision

- "Accept recommendation" → record + proceed to Plan
- "Use A<X>" → record + proceed to Plan with that option
- "Reject all" → return to Align (requirements missed something)

## Lane behavior

| Lane | Behavior |
|---|---|
| Trivial | Refuse (skip) |
| Standard, single obvious | Skip after stating reasoning |
| Standard, multi-path | Run tournament, ≥2 options |
| High-stakes | Run tournament always, ≥3 options + ADR |

## Anti-patterns enforced

- No A1 + A2 in same paradigm (cosmetic difference)
- No vague matrix (✅/❌ without concrete values)
- No skip self-critique
- No hidden weaknesses in recommendation

## Related

- `skills/brainstorm/SKILL.md` — full process
- `skills/brainstorm/references/evaluation-dimensions.md` — dimensions by task type
- `skills/brainstorm/references/adversarial-challenges.md` — challenge question library
- `skills/brainstorm/references/paradigm-shifts.md` — paradigm shift catalog
- `skills/brainstorm/examples/*.md` — 3 worked examples
- `commands/plan.md` — consumes brainstorm output
- `docs/adr/0000-template.md` — ADR template
