# Example: Refactor Brainstorm

## User request

"Refactor PaymentProcessor — currently 800-line god class."

## Phase 1 — Frame

**Problem:** Single 800-line class mixes payment validation, fraud check, settlement, notification, audit. Hard to test, change-fearful.

**Dimensions:**
- Blast radius
- Reversibility
- Test coverage impact
- Team familiarity with approach
- Implementation time
- Risk of regression

**Constraints:** no breaking change to `PaymentController` API
**Assumptions:** existing test suite covers behavior

## Phase 2 — Tournament

### A1: Big-bang rewrite

**Approach:** rewrite PaymentProcessor as 6 collaborating classes, swap atomically.

**Implementation sketch:**
- Extract PaymentValidator, FraudChecker, Settler, Notifier, Auditor
- New PaymentProcessor delegates
- Replace old class in single PR

**Weakness:** huge blast radius, hard to review, all-or-nothing risk.

### Challenge 1 — Beat A1 on blast radius

### A2: Strangler Fig — extract one collaborator at a time

**Targets A1 weakness:** blast radius.

**Approach:** extract one method to a new class per PR. Old PaymentProcessor calls new class. After all extracted, delete the dispatcher.

**Implementation sketch:**
- PR1: extract `validate()` → PaymentValidator class
- PR2: extract `checkFraud()` → FraudChecker class
- ... 6 PRs total
- PR7: rename old PaymentProcessor → PaymentProcessorFacade

**A1 vs A2:**
| Dimension | A1 | A2 | Winner |
|---|---|---|---|
| Blast radius | All 800 lines | 100-200 per PR | A2 |
| Reversibility | One revert | Per-PR revert | A2 |
| Test coverage | Net 0 (rewrite) | Net + (each PR adds tests) | A2 |
| Team familiarity | High | High | Tie |
| Implementation | 1 week | 3 weeks | A1 |
| Regression risk | High (atomic) | Low (incremental) | A2 |

**Champion: A2**.

### Challenge 2 — Different paradigm

### A3: Branch-by-abstraction — new impl behind flag

**Paradigm shift:** parallel deployment of old + new (vs sequential extraction).

**Approach:** new `PaymentProcessorV2` implementation behind feature flag. Run both in shadow mode, compare outputs. Gradually shift traffic. Delete V1 after full cutover.

**Implementation sketch:**
- Create PaymentProcessorV2 (full new design)
- `PaymentService` chooses V1/V2 by flag
- Shadow mode: run V2 but use V1 result
- Compare outputs in metrics
- Gradual flag rollout: 1% → 10% → 100%

**A2 vs A3:**
| Dimension | A2 | A3 | Winner |
|---|---|---|---|
| Blast radius | Per-PR | Per-rollout-step | Tie |
| Reversibility | Revert PR | Flip flag | A3 |
| Test coverage | Net + | Net + + shadow validation | A3 |
| Team familiarity | High | Medium (feature flags) | A2 |
| Implementation | 3 weeks | 4 weeks | A2 |
| Regression risk | Low | Lowest (shadow validates) | A3 |
| Rollback speed | Hours | Seconds (flag flip) | A3 |

**Close call:** A2 wins on familiarity + ship time; A3 wins on rollback speed.

### Challenge 3 — Question assumptions

**Assumption questioned:** "existing test suite covers behavior"

If suite has gaps, A1 + A2 + A3 all risk regression. Reject the brainstorm + return to Align: characterize test coverage first.

Suite verified comprehensive → tournament proceeds.

## Phase 3 — Synthesis

### Comparison matrix

| Dimension | A1: Big-bang | A2: Strangler Fig | A3: Branch-by-abstraction |
|---|---|---|---|
| Blast radius | All 800 lines | 100-200 per PR | Per-flag-step (effectively 0-1%) |
| Reversibility | Single revert | Per-PR revert | Flip flag (instant) |
| Test coverage | Net 0 | Net + | Net + + shadow validation |
| Team familiarity | High | High | Medium |
| Implementation | 1 week | 3 weeks | 4 weeks |
| Regression risk | High | Low | Lowest |
| Rollback speed | Minutes (revert + deploy) | Hours | Seconds |

### Recommendation: A2 (Strangler Fig)

**Why:** Best balance of risk, familiarity, ship time. Each PR independently reviewable + revertable. Team already comfortable with pattern.

**What we gain:**
- 6 small, reviewable PRs vs 1 mega-PR
- Per-PR test coverage gain
- Low regression risk
- No new infrastructure (no flag system)

**What we sacrifice:**
- 3 weeks vs A1's 1 week (worth it)
- Slower rollback than A3's flag flip (acceptable for non-emergency refactor)

**Confidence:** Moderate

**Caveats:**
- Close call vs A3 — if rollback speed becomes critical (e.g., recent prod incident), switch to A3
- Requires test suite confirmation upfront

**Close call?** Yes — A2 vs A3 close. Tiebreaker: team familiarity + ship time. If org has mature feature-flag platform already, recommend A3 instead.

## What changes if assumption breaks

If test suite gaps revealed during PR1 of A2:
1. Stop refactor mid-flight
2. Add characterization tests for uncovered paths (1-week sub-project)
3. Resume A2 OR escalate to A3 (shadow mode validates by comparison, lower test-coverage dependency)

This branching captured in plan, not just brainstorm — but brainstorm flagged it.
