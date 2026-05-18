---
name: align
description: Surface ambiguity, missing requirements, hidden assumptions BEFORE planning. Fires after triage for standard (vague request) or high-stakes (always). Updates CONTEXT.md vocabulary. Produces agreed-requirements artifact feeding Plan gate.
triggers:
  natural: ["align", "grill", "clarify requirements", "surface ambiguity"]
  command: ["/align"]
  keyword: ["implement", "build", "add", "improve", "fix", "optimize"]
applicability:
  always: false
  triggers:
    auto_fire:
      - "standard lane with vague request (<3 specific requirements)"
      - "high-stakes lane (always)"
    task_keywords: ["implement", "build", "add", "improve", "make better", "fix"]
relevance_assessment: |
  HIGH 100%: high-stakes lane (mandatory always)
  HIGH 80%+: standard lane, request <3 specific requirements
  MEDIUM 40-79%: standard lane, request specific but edge cases unmentioned
  LOW 1-39%: standard lane, highly specific request with files/line numbers
  ZERO: trivial lane (skipped)
---

# Align — Grill Ambiguity Before Planning

> "No one knows exactly what they want." — Pragmatic Programmer

Plan before align = plan on wrong prompt. Build on wrong plan = waste.

## When to fire

**Always:**
- High-stakes lane
- Standard lane with vague request

**Vague indicators:**
- <3 specific requirements stated
- Generic terms ("better", "improve", "fix", "optimize") without specifics
- No edge cases, error handling, or success criteria

**Skip:**
- Trivial lane
- Highly specific request (files, line numbers, exact behaviors)
- User: "/no-align" or "just do it" (warn for high-stakes)

## Process — 5 steps

### Step 1 — Restate the problem

```
## My understanding

You want to <restated task> because <inferred reason>.

Specifically:
- <requirement 1>
- <requirement 2>
- <requirement 3>

Is this correct?
```

User confirms or corrects.

### Step 2 — List assumptions

```
## Assumptions I'm making

1. <e.g., "Existing OrderService modified, not new service">
2. <e.g., "Postgres remains the database">
3. <e.g., "No breaking change to public API">
4. <e.g., "Existing test suite covers affected paths">

Any wrong?
```

### Step 3 — Surface unstated requirements

Pick 3-5 most relevant per task:

**Behavior gaps:** error types, latency targets, invalid input, rollback, concurrency

**Data gaps:** validation rules, retention, migration, backup/recovery

**Integration gaps:** upstream/downstream consumers, monitoring, auth rules

**Operational gaps:** deployment strategy, observability, feature flags, docs

Detail: `references/grill-questions.md`.

### Step 4 — Extract vocabulary

Capture domain terms during grilling: nouns, process names, acronyms, custom verbs. Add to `CONTEXT.md`. Reuse cross-session.

### Step 5 — Produce alignment artifact

Output template → `.claude/memory/align-artifacts/<YYYY-MM-DD>-<task-name>.md`:

```markdown
# Alignment: <Task name>

**Date:** YYYY-MM-DD
**Lane:** Standard | High-stakes

## Agreed requirements

1. <Specific requirement 1>
2. <Specific requirement 2>

## Assumptions (confirmed by user)

1. <Confirmed assumption 1>

## Out of scope

1. <Explicit non-goal 1>

## New vocabulary added to CONTEXT.md

- <Term 1>: <definition>

## Open questions for Brainstorm / Plan

1. <Question affecting solution choice>
```

## Anti-patterns

**Don't:** all questions at once, philosophical questions, skip restate-and-confirm, forget CONTEXT.md update.

**Do:** 3-5 focused questions per round, concrete examples, acknowledge clear parts, persist to CONTEXT.md, offer to proceed early.

## Output consumption

| Downstream | Reads |
|---|---|
| Brainstorm | Agreed requirements (problem framing) |
| Plan | Same (decomposition input) |
| Spec | Same (scenario coverage) |
| Pre-flight 1 (brainstorm-prep) | Open questions section |

## Acceptance tests

- **Vague:** "Make user lookup faster" → Align fires, asks latency/data size/query patterns → specific requirements (e.g., "p95 < 100ms for 10k users")
- **High-stakes+detail:** "Migrate MySQL→TigerBeetle, 50k tx/sec" → Align fires anyway, confirms assumptions, surfaces edge cases (CDC lag)
- **Trivial:** "Fix typo in line 42" → Align does NOT fire

## Integration

- Auto-fired by `session-init.sh` when `TRIAGE_LANE=high-stakes` or vague request
- Manual: `/align`
- Output → `.claude/memory/align-artifacts/`
- CONTEXT.md update critical — value compounds across sessions

## Related

- `references/grill-questions.md` — full question library, 5 patterns
- `skills/triage/SKILL.md` — runs before Align
- `skills/brainstorm/SKILL.md` — consumes Align output
- `commands/align.md` — entry point
- `templates/CONTEXT_TEMPLATE.md` — vocabulary destination
