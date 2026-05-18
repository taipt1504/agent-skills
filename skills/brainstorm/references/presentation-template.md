# Recommendation Presentation Template

How to present brainstorm output to user. Format matters — vague matrix = useless.

## Full output structure

```markdown
# Brainstorm: <Task name>

**Date:** YYYY-MM-DD
**Lane:** Standard | High-stakes
**Align artifact:** <path to align-artifacts/...>

## Problem framing

<2-3 sentences from Align, restating problem>

## Evaluation dimensions

1. <Dimension 1> — <why this matters for this task>
2. <Dimension 2> — <why>
3. <Dimension 3> — <why>
4. <Dimension 4> — <why>
5. <Dimension 5> — <why>

**Constraints (MUST hold):**
- <Constraint 1>

**Assumptions (questioned in Round 3):**
- <Assumption 1>

## Options considered

### A1: <Name>

**Approach:** <1-2 sentences>

**Implementation sketch:**
- <Step 1>
- <Step 2>

**Self-assessment:** see matrix below

**Weaknesses:**
- <Weakness 1>

### A2: <Name>

**Targets A1's weakness:** <which dimension>

**Approach:** <1-2 sentences>

**Implementation sketch:**
- <Step 1>

### A3: <Name>

**Paradigm shift:** <e.g., "synchronous → event-driven">

**Approach:** <1-2 sentences>

### A4: <Name> (if applicable)

**Assumption questioned:** <which one>

**Approach:** <1-2 sentences>

## Comparison matrix

| Dimension | A1: <Name> | A2: <Name> | A3: <Name> | A4: <Name> |
|---|---|---|---|---|
| <Dim 1> | <concrete> | <concrete> | <concrete> | <concrete> |
| <Dim 2> | <concrete> | <concrete> | <concrete> | <concrete> |
| <Dim 3> | <concrete> | <concrete> | <concrete> | <concrete> |
| <Dim 4> | <concrete> | <concrete> | <concrete> | <concrete> |
| <Dim 5> | <concrete> | <concrete> | <concrete> | <concrete> |

**Rules for matrix cells:**
- Concrete numbers where possible ("5k/sec", "200ms p95", "1 week")
- Comparable units across the row
- ✅/❌ only when truly binary (license OK / not OK)
- Avoid vague labels ("good", "okay", "bad")

## Recommendation: A<N> — <Name>

**Why this option:**
<2-3 sentences justifying choice across the dimensions>

**What we gain:**
- <Concrete benefit 1>
- <Concrete benefit 2>

**What we sacrifice (be honest):**
- <Concrete trade-off 1>
- <Concrete trade-off 2>

**Confidence:** High | Moderate | Low

**Caveats:**
- <Uncertainty 1>
- <When to revisit: e.g., "if QPS exceeds 20k, revisit A4 (TigerBeetle)">

**Close call?** Yes | No
<If yes: which two options are tied, what tiebreaker do you suggest>

## Rejected alternatives (preserved for ADR)

### A1: <Name> — Rejected
**Why rejected:** <specific reason, not "didn't win">

### A2: <Name> — Rejected
**Why rejected:** <specific reason>

### A3: <Name> — Chosen
(see above)

### A4: <Name> — Rejected
**Why rejected:** <specific reason>

## Decision for user

Reply with:
- "Accept recommendation" — proceed to Plan with A<N>
- "Use A<X>" — proceed to Plan with A<X>
- "Reject all" — return to Align (requirements missed something)
```

## Tone notes

- **Be honest about close calls.** "A2 wins on latency by 30%, but A1 wins on ops complexity. Recommendation: A1 because we're ops-constrained this quarter, but if scale grows revisit."
- **Don't hide weaknesses of recommendation.** "Recommended A3 despite higher implementation time because lock-in cost of A1 outweighs the 2-week delta."
- **Don't fake decisiveness.** If genuinely tied, say so. Let user pick. "A2 and A3 tied across all 5 dimensions. Pick based on which team owns the work — A2 fits frontend team's skills, A3 fits platform team's."
- **Reference concrete evidence.** "A1 throughput estimated 5k/sec based on existing OrderRepository benchmark in `bench/order-throughput.md`."

## Anti-patterns

- ❌ "A2 is better than A1" — useless, no concrete why
- ❌ Recommendation paragraph longer than matrix — over-justification
- ❌ All-✅ row for recommended option — unrealistic, hides weaknesses
- ❌ "Future-proof" or "flexible" as a benefit (unfalsifiable)
- ❌ "Industry standard" as a benefit (industry has bad standards too)
