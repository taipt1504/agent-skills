# Multi-Agent Orchestration Patterns

> Six orchestration patterns from ECC, from simple to sophisticated.

---

## Pattern Spectrum

```
Simple ◄──────────────────────────────────────────────► Complex

Sequential    NanoClaw    Infinite     Continuous    De-Sloppify    Ralphinho
Pipeline      REPL        Loop         PR Loop       Pattern        RFC DAG
```

---

## 1. Sequential Pipeline (`claude -p`)

Non-interactive chained calls, each in isolated context:

```bash
#!/bin/bash
set -e  # Critical: propagate exit codes

# Step 1: Research (Opus for reasoning)
claude -p "Research the authentication patterns in this codebase" \
  --model opus --output-format text > /tmp/research.md

# Step 2: Plan (Opus for planning)
claude -p "Based on research in /tmp/research.md, create implementation plan" \
  --model opus --output-format text > /tmp/plan.md

# Step 3: Implement (Sonnet for coding)
claude -p "Implement the plan in /tmp/plan.md" \
  --model sonnet --output-format text > /tmp/impl.md

# Step 4: Review (Sonnet for review)
claude -p "Review the changes made. Check for security issues." \
  --model sonnet --output-format text > /tmp/review.md
```

**Key insight:** Each step has an isolated context window. They communicate via filesystem (files, git state).

**Model routing:** Use Opus for research/review, Sonnet for implementation, Haiku for formatting.

---

## 2. NanoClaw REPL

Session-aware REPL with full conversation history:

```bash
# Interactive exploration with session persistence
claude --session-id "feature-auth" -p "Explore auth patterns"
claude --session-id "feature-auth" -p "Now implement the chosen pattern"
```

**Use for:** Interactive exploration. Use sequential pipeline for scripted automation.

---

## 3. Infinite Agentic Loop

Two-prompt system: Orchestrator + N Sub-Agents:

```
Orchestrator (Opus)
  ├── Assigns creative direction to each sub-agent
  ├── Assigns iteration number (prevents duplicates)
  └── Batches: 1-5 at once, 6-20 in groups of 5

Sub-Agent 1 (Sonnet) → Direction A, Iteration 1
Sub-Agent 2 (Sonnet) → Direction B, Iteration 2
Sub-Agent 3 (Sonnet) → Direction C, Iteration 3
```

**Key insight:** The orchestrator **assigns** each agent a specific creative direction and iteration number — this prevents duplicate concepts.

**Batching guidance:**
- 1-5 tasks: all at once
- 6-20 tasks: batches of 5
- Infinite: waves of 3-5

---

## 4. Continuous PR Loop

Full PR automation cycle:

```
┌─────────────────────────────────────────────────┐
│  1. Create branch                                │
│  2. claude -p "implement feature"                │
│  3. claude -p "review changes" (reviewer pass)   │
│  4. Commit → Push → Create PR                    │
│  5. Wait for CI                                  │
│  6. If CI fails → claude -p "fix CI failures"    │
│  7. If CI passes → merge                         │
└─────────────────────────────────────────────────┘
```

**Context bridge:** `SHARED_TASK_NOTES.md` persists across independent `claude -p` invocations.

**Completion signal:** Magic phrase stops loop after N consecutive signals.

**Safety flags:** `--max-runs`, `--max-cost`, `--max-duration`, `--review-prompt`

---

## 5. De-Sloppify Pattern

Separate cleanup pass after implementation:

```
Step 1: Implementation agent (thorough, no constraints)
  → Writes complete code with all edge cases

Step 2: Cleanup agent (focused removal)
  → Removes: unnecessary type tests, over-defensive checks,
     console.logs, commented code, excessive comments
```

**Principle:** Never constrain the implementer. Let it be thorough, then clean separately. "Two focused agents outperform one constrained agent."

---

## 6. Ralphinho / RFC-Driven DAG

The most sophisticated pattern — a full dependency DAG:

```
RFC Document
  ├── WorkUnit 1 (no deps)     ─── Layer 0 (parallel)
  ├── WorkUnit 2 (no deps)     ─── Layer 0 (parallel)
  ├── WorkUnit 3 (deps: 1, 2)  ─── Layer 1 (after Layer 0)
  ├── WorkUnit 4 (deps: 3)     ─── Layer 2
  └── WorkUnit 5 (deps: 3, 4)  ─── Layer 3
```

**Pipeline per WorkUnit:**
```
Research (Sonnet) → Plan (Opus) → Implement (Codex/Sonnet) → Review (Opus)
```

**Key features:**
- Each stage in its own context window with its own model
- Layer-based execution (same-layer units run in parallel)
- SQLite-backed state for resumability
- Merge queue with eviction and context-rich recovery
- Uses git worktrees for isolation

**Tier-based depth:**
- Trivial: 2 stages (implement → review)
- Small: 4 stages (plan → implement → review → test)
- Large: 8 stages (research → plan → implement → review → test → security → docs → merge)

---

## ECC's `/orchestrate` Command

Pre-built orchestration workflows:

```markdown
/orchestrate feature    → planner → tdd-guide → code-reviewer → security-reviewer
/orchestrate bugfix     → planner → tdd-guide → code-reviewer
/orchestrate refactor   → architect → code-reviewer → tdd-guide
/orchestrate security   → security-reviewer → code-reviewer → architect
```

### Structured Handoff Document

```markdown
## HANDOFF: planner -> tdd-guide

### Context
Feature: Add order validation with business rules

### Findings
- 3 validation rules identified
- Domain model: Order → OrderItem → Product
- Risk: Complex discount calculation

### Files Modified
- `src/.../OrderValidationService.java`
- `src/.../OrderValidator.java`

### Open Questions
- Max order total limit? (ask product)

### Recommendations
- Start with happy-path tests
- Edge cases: empty order, negative quantities, expired products
```

### Parallel Execution

Independent checks can run in parallel:

```
                    ┌── code-reviewer ──┐
planner → tdd-guide ├── security-reviewer ├── merge results
                    └── architect ──────┘
```

### Worktree-Based Workers

For full isolation, ECC supports tmux-pane workers with separate git worktrees:

```bash
node scripts/orchestrate-worktrees.js plan.json --execute
```

`plan.json` defines the work units, dependencies, and model assignments. `seedPaths` overlays untracked files into worker worktrees.

---

## Orchestration Design Principles

| Principle | Description |
|-----------|-------------|
| Context isolation | Each agent/stage gets a clean context window |
| Filesystem communication | Agents share state via files, not conversation |
| Model routing | Match model to task complexity |
| Parallel when possible | Independent tasks run simultaneously |
| Structured handoffs | Formal handoff documents between stages |
| Exit codes matter | `set -e` in pipelines, check return values |
| Safety limits | Max runs, max cost, max duration |
| Resumability | State persistence for long pipelines |

---

## Applying to Our Plugin

### Current State
Our `/orchestrate` command uses sequential agent execution.

### Improvement Opportunities
1. **Structured handoff documents** between agents
2. **Parallel execution** for independent reviewers
3. **Model routing** (Opus for planning, Sonnet for coding)
4. **Pre-built workflows** (feature, bugfix, refactor, security)
5. **Safety limits** (max iterations, cost tracking)
6. **Worktree isolation** for multi-agent parallel coding
