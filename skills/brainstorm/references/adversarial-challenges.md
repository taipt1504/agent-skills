# Adversarial Challenge Question Library

Three rounds. Each surfaces a different blind spot.

## Round 1 — Beat the weakness

**Trigger:** after A1 generated + self-critique done.

**Question pattern:** "What kind of solution beats A1 on its WEAKEST dimension?"

**Critical:** targeted, NOT generic. "Better than A1" too vague. "Better than A1 on <dimension X>" precise.

**Example prompts:**
- "A1's weakest dimension is latency. What architecture optimizes for latency at A1's cost dimension?"
- "A1 is complex. What achieves the same behavior with less code, even at performance cost?"
- "A1 has high ops burden. What runs with zero ops, even at vendor lock-in cost?"

**Honest stop:** if agent genuinely cannot find meaningful alternative → state so, may halt tournament with note.

## Round 2 — Different paradigm

**Trigger:** after 2 solutions generated, both in same conceptual family.

**Question pattern:** "Is there a DIFFERENT PARADIGM entirely?"

**Paradigm shift catalog:**

| If A1, A2 are... | A3 should be... |
|---|---|
| Synchronous | Async / event-driven |
| Pull-based | Push-based |
| Imperative | Declarative |
| Server-side | Client-side |
| In-house | Third-party service / managed |
| Additive (add code) | Subtractive (remove code) |
| Reactive (wait for trigger) | Proactive (pre-compute, cache) |
| Centralized | Distributed |
| Stateful | Stateless |
| Eager | Lazy |
| Compile-time | Runtime |
| Schema-on-write | Schema-on-read |
| Build | Buy (SaaS) |
| Monolith | Decomposed |
| Decomposed | Monolith (intentional) |

**Example prompts:**
- "A1, A2 both pull from DB on demand. What if we pre-compute and push to clients?"
- "A1, A2 both implement in-house. What managed service provides 80% with 10% effort?"
- "A1, A2 both add a service. What if we DELETE a service instead?"

**Honest stop:** if no paradigm shift makes sense for the constraint set, state so.

## Round 3 — Question assumptions

**Trigger:** after 3 solutions generated, looking for breakthrough.

**Question pattern:** "What CONSTRAINT did I ASSUME that doesn't actually hold?"

**Meta-challenge.** Most powerful when assumptions encoded as constraints by accident.

**Example prompts:**
- "We assumed must use Postgres. Why? What changes if we use TigerBeetle for hot path?"
- "We assumed must support legacy clients. Are there really any left? Check call logs."
- "We assumed transaction must be ACID. What if eventual consistency works for this read?"
- "We assumed event must be at-most-once. What if duplicates are deduped downstream?"
- "We assumed must run on JVM. What if a sidecar in another language fits better?"

**Common assumption traps:**

| Assumption | Real question |
|---|---|
| "Must use existing DB" | Existing DB optimal for this access pattern? |
| "Must be backward compatible" | Active clients still depend on it? |
| "Must support all locales" | Which locales generate revenue? |
| "Must be real-time" | What latency does business actually require? |
| "Must be in same service" | Why? What's the coupling cost? |
| "Must scale to 10x" | What's the actual projected growth? |
| "Must be self-hosted" | What's the data-residency rule actually say? |

**Honest stop:** if all assumptions genuinely hold, state so. Champion of A1-A3 stands.

## Question quality checklist

For each challenge question:
- [ ] Targets a specific weakness or assumption, not generic
- [ ] Constraint vs goal distinction explicit
- [ ] Allows honest "no" answer (won't fish for fake alternatives)
- [ ] Surfaces a property the matrix doesn't yet measure

## Anti-patterns

- ❌ "Is there a better way?" (too vague — will get "no")
- ❌ "Have you considered <agent's pet pattern>?" (anchors on biased option)
- ❌ Challenge that nobody could answer ("what's the unknown unknown?")
- ❌ Stopping at 2 because round 2 felt hard
- ❌ Inventing fake A3 just to meet the minimum

## When to stop generating alternatives

**Stop when ALL:**
- Minimum count hit (2 standard, 3 high-stakes)
- AND ANY:
  - 5 reached (hard cap, prevent paralysis)
  - Next option duplicates an existing paradigm
  - Next option fails an existing constraint
  - Genuine "no meaningful alternative remaining"

**Don't stop because tired.** Don't continue to seem thorough.
