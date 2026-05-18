---
name: brainstorm
description: Tournament-style iterative solution exploration. Generates 2-5 candidates via adversarial challenges, compares multi-dimensionally, recommends with explicit trade-offs. Mandatory high-stakes (≥3), conditional standard. Output feeds Plan + ADR for high-stakes.
triggers:
  natural: ["brainstorm", "explore solutions", "design options", "best approach"]
  command: ["/brainstorm"]
  keyword: ["design", "approach", "architecture", "should I use X or Y", "what's the best way"]
applicability:
  always: false
  triggers:
    auto_fire:
      - "high-stakes lane after Align gate (mandatory)"
      - "standard lane when multiple viable paths detected"
    task_keywords: ["design", "approach", "architecture", "vs", "or", "which", "pattern"]
relevance_assessment: |
  HIGH 100%: high-stakes lane (mandatory always, ≥3 options)
  HIGH 80%+: standard lane with explicit "X or Y" trade-off mentioned
  MEDIUM 40-79%: standard lane, multiple viable paths possible
  LOW 1-39%: standard lane, single obvious solution
  ZERO: trivial lane (skipped)
---

# Brainstorm — Tournament Solution Exploration

## Why this gate exists

Three biases to defeat:

- **First-solution lock-in:** commits to first reasonable solution → local optimum
- **Convergence bias:** asked "any better way?", says "no" to stop sooner
- **Dimensional collapse:** compares on 1 dimension (usually "simple"), ignores others

Brainstorm enforces:
- Multiple candidates (min 2 standard, min 3 high-stakes)
- Multi-dimensional comparison
- Adversarial challenges
- Honest recommendation with trade-offs

## When to fire

**Mandatory:**
- High-stakes lane (always, ≥3 options)
- User invokes `/brainstorm`

**Conditional (standard):**
- Multiple viable paths exist
- User mentions "X or Y" trade-off
- CONTEXT.md suggests recurring decision space

**Skip:**
- Trivial lane
- Solution genuinely obvious (state reasoning before skipping)
- User: "no brainstorm, just do A"

## Process — 3 phases

### Phase 1 — Frame

**1.1 Restate problem.** Use Align artifact if exists; else restate.

**1.2 Identify 3-5 evaluation dimensions.** See `references/evaluation-dimensions.md` for catalog by task type.

**1.3 Separate constraints vs assumptions:**
- Constraints (MUST hold): regulation, hard requirements
- Assumptions (may not hold): challengeable in Round 3

### Phase 2 — Tournament loop

**2.1 Generate A1** — first reasonable solution.

```markdown
## Solution A1: <Name>

**Approach:** <1-2 sentence description>

**Implementation sketch:**
- <Step 1>
- <Step 2>

**Self-assessment:**
| Dimension | Score | Notes |
|---|---|---|
| ... | ... | ... |

**Weaknesses (be honest):**
- <Weakness 1 — most important>
```

**2.2 Adversarial Challenge 1 — beat the weakness.**

"What solution beats A1 on its WEAKEST dimension?"

No meaningful alternative → state so, may stop with note.

**2.3 Generate A2 + head-to-head.**

```markdown
## Solution A2: <Name>

**Targets A1's weakness:** <which weakness, explicit>

**Head-to-head A1 vs A2:**
| Dimension | A1 | A2 | Winner |
|---|---|---|---|
| ... | ... | ... | ... |

**Champion:** A<N>
**Reasoning:** <why champion wins overall>
```

**2.4 Adversarial Challenge 2 — different paradigm.**

After 2 solutions: "DIFFERENT PARADIGM entirely?"

Paradigm shifts: sync↔async, pull↔push, imperative↔declarative, server↔client, in-house↔managed, additive↔subtractive, reactive↔proactive, centralized↔distributed, stateful↔stateless.

Paradigm shift available → generate A3.

**2.5 Generate A3 + compare.** Same template. Update champion.

**2.6 Adversarial Challenge 3 — question assumptions.**

After 3 solutions: "What CONSTRAINT did I ASSUME that doesn't actually hold?"

Meta-challenge. Often reveals breakthrough (e.g., "must use Postgres" → actually have TigerBeetle).

**2.7 Stop conditions.**

Stop when ALL:
- ≥ minimum (2 standard, 3 high-stakes)
- AND any of:
  - 5 solutions reached (hard cap)
  - New option adds no new dimension/paradigm
  - Honest "no meaningful alternative"

Don't stop to save effort. Don't continue to seem thorough.

### Phase 3 — Synthesis

**3.1 Comparison matrix** — concrete values, not ✅/❌.

```markdown
| Dimension | A1: Batch | A2: Parallel | A3: CDC | A4: TigerBeetle |
|---|---|---|---|---|
| Throughput | 5k/sec | 15k/sec | 10k/sec | 50k+/sec |
| Latency p95 | 200ms | 50ms | 100ms | 5ms |
| Ops complexity | Low | Medium | High | High (new tech) |
| Consistency | Strong | Eventual | Eventual | Strong (ledger) |
| Time to ship | 1 week | 2 weeks | 3 days | 3 weeks |
```

**3.2 Agent recommendation.**

```markdown
## Recommendation: A<N> — <Name>

**Why:** <2-3 sentences>

**What we gain:**
- <Concrete benefit 1>

**What we sacrifice (honest):**
- <Concrete trade-off 1>

**Confidence:** High | Moderate | Low

**Caveats:**
- <Uncertainty 1>
- <When to revisit this decision>
```

**3.3 Present to user.** Options:
1. Accept recommendation → Plan
2. Pick different option → Plan with that choice
3. Reject all → Align gate missed requirement, loop back

### Phase 4 (high-stakes only) — ADR

Auto-generate ADR at `docs/adr/NNNN-<decision>.md`. See doc 05 brainstorm.md §"Phase 4" for full template.

## Anti-patterns

**Don't:**
- Generate A1, A2 in same paradigm (cosmetic difference)
- Skip self-critique to commit faster
- Hide weaknesses of recommended option
- Stop at 2 when 3rd paradigm exists
- Vague matrix (✅/❌ only, no concrete values)
- Fake decisive recommendation when tie

**Do:**
- Force paradigm shift at A3
- Question assumptions at A4
- Concrete numbers in matrix
- Acknowledge close calls
- Save rejected alternatives in ADR (institutional memory)

## Output artifacts

| Output | Path | Lane |
|---|---|---|
| Comparison matrix + recommendation | `.claude/memory/brainstorm-artifacts/<date>-<task>.md` | All (when fires) |
| ADR with all considered alternatives | `docs/adr/NNNN-<decision>.md` | High-stakes mandatory |
| Updated CONTEXT.md | project root | If new terminology surfaced |

## Acceptance tests

- **T1 (high-stakes ≥3):** "Migrate monolith to microservices?" → ≥3 options, ≥5 dimensions, recommendation has trade-offs
- **T2 (standard skip):** "Add @Valid annotation" → not fired (obvious)
- **T3 (standard fire):** "Refactor PaymentService to be more testable" → fires, ≥2 options
- **T4 (close call):** "Redis vs Memcached for session?" → "close call" if genuinely close
- **T5 (ADR):** After T1 → `docs/adr/NNNN-microservices-decision.md` exists with 4 options + rationale + consequences

## Integration

- Auto-fire from triage when `TRIAGE_LANE=high-stakes` (after Align)
- Auto-fire from Align when multiple paths detected (standard lane)
- Manual: `/brainstorm`
- Output → Plan gate (chosen solution) + ADR (high-stakes only)

## Related

- `references/evaluation-dimensions.md` — dimension catalog by task type
- `references/adversarial-challenges.md` — challenge question library
- `references/presentation-template.md` — recommendation format
- `references/paradigm-shifts.md` — paradigm-shift examples
- `examples/architecture-decision.md` — full worked example
- `examples/refactor-approach.md` — refactor brainstorm example
- `examples/library-selection.md` — library choice example
- `skills/align/SKILL.md` — runs before Brainstorm
- `commands/brainstorm.md` — entry point
- `commands/plan.md` — consumes Brainstorm output
