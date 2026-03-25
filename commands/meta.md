---
name: meta
description: Observable learning commands — view what agents have learned, extract session patterns, generate learning reports.
---

# /meta -- Observable Learning & Skill Creation

## Usage

```
/meta learn status       -> show learning dashboard (memories + knowledge graph)
/meta learn extract      -> distill current session into learnings
/meta learn report       -> weekly learning summary
/meta create-skill       -> create new skill from repo patterns
```

---

## /meta learn status

Show what has been learned across native memory and MCP knowledge graph.

### Process

1. **Read native memories**: List files in the project's memory directory, categorize by type (user/feedback/project/reference)
2. **Query knowledge graph**: Use `mcp__memory__read_graph` to get all entities and relations
3. **Present dashboard**:

```
LEARNING DASHBOARD
==================
Native Memory:
  user:      2 memories (preferences, expertise)
  feedback:  5 memories (corrections, confirmed approaches)
  project:   3 memories (decisions, context)
  reference: 1 memory (external systems)

Knowledge Graph:
  Entities:     12 (5 services, 3 decisions, 2 patterns, 2 blockers)
  Relations:    8
  Observations: 24

Recent Learnings:
  [feedback] Don't mock DB in integration tests (2026-03-24)
  [project]  Auth middleware rewrite for compliance (2026-03-23)
  [entity]   OrderService uses PostgreSQL+R2DBC (2026-03-22)

Stale (>30 days, consider pruning):
  (none)
```

---

## /meta learn extract

Distill the current session into reusable knowledge.

### Process

1. Review the conversation for high-value patterns:
   - User corrections (things the agent got wrong → feedback memory)
   - Architectural decisions (why X over Y → project memory + MCP entity)
   - Bug resolutions (error → fix pattern → MCP entity with observation)
   - New conventions discovered (naming, patterns → project memory)

2. For each pattern found, determine storage:
   - Qualitative (preferences, corrections): suggest user runs `/remember` to save as native memory
   - Structured (entities, decisions, relations): create MCP knowledge graph entries directly

3. Report extraction results:

```
SESSION DISTILLATION
====================
Extracted 4 learnings:

1. [feedback] User prefers single bundled PR for refactors
   → Suggest: /remember "Prefer single bundled PR for refactors"

2. [entity] PaymentService → created with: R2DBC, Saga pattern
   → Created: MCP entity "PaymentService" with observations

3. [decision] chose-saga-over-2pc → for distributed transactions
   → Created: MCP entity with rationale

4. [pattern] retry-with-backoff → standard error handling pattern
   → Created: MCP entity with code reference
```

---

## /meta learn report

Weekly summary of learning activity.

### Process

1. Read native memory files — count by type, identify recent additions
2. Query MCP graph — count entities, relations, observations
3. Identify trends:
   - Most frequently queried entities (popular knowledge)
   - Stale entities (not referenced in 30+ days)
   - Feedback memories (user corrections — are they decreasing over time?)

```
WEEKLY LEARNING REPORT (2026-03-18 to 2026-03-25)
==================================================
New memories:    +3 (1 feedback, 1 project, 1 reference)
New entities:    +5 (2 services, 2 decisions, 1 pattern)
New observations: +8

Top entities (most referenced):
  1. OrderService (queried 12 times)
  2. chose-cqrs-pattern (queried 8 times)
  3. PostgreSQL (queried 6 times)

Correction trend: 2 feedback memories this week (down from 4 last week)
  → Agent is learning from corrections ✓

Stale (consider pruning):
  - old-auth-middleware-decision (45 days, replaced by compliance rewrite)
```

---

## /meta create-skill

Analyze the repository's git history to extract coding patterns and generate SKILL.md files.

### Usage

```
/meta create-skill                    # Analyze current repo
/meta create-skill --commits 100      # Analyze last 100 commits
```

### Process

1. Gather git data: `git log --oneline -n 200 --name-only`
2. Detect patterns: commit conventions, file co-changes, architecture, testing
3. Generate SKILL.md with extracted patterns
4. Ask user to confirm before saving
