---
name: meta
description: Umbrella for learning, evolution, ADR generation, and architecture review. Subcommands cover the Learn layer of the workflow (Layer 5) plus on-demand maintenance gates.
---

# /meta — Learning, Evolution, ADR, Architecture Review

> **Decision (REFACTOR_PLAN §6.7):** `/meta` is the umbrella. Workflow gates (`/triage`, `/align`, `/brainstorm`, `/plan`, `/spec`, `/build`, `/verify`, `/dc-review`) stay top-level. Learning + maintenance live here as subcommands.

## Usage

```
# Learning + memory
/meta learn status        -> learning dashboard (memories + knowledge graph + instincts)
/meta learn extract       -> distill current session into learnings + instinct files
/meta learn report        -> weekly learning summary + instinct trends

# Evolution (Phase 4 auto-promotion)
/meta evolve              -> review promotion candidates from evolution-check.sh
/meta evolve promote <id> -> force-promote a specific instinct
/meta evolve --generate   -> write evolved skills from candidates
/meta evolve --auto       -> promote all candidates meeting thresholds (confidence ≥ 0.8, ≥3 occ, ≥2 sessions, ≥2 projects)

# Pruning
/meta prune               -> remove stale instincts (confidence < 0.2 or 30 days idle)
/meta prune --dry-run     -> preview what would be pruned
/meta prune --archive     -> archive instead of delete

# Skill scaffolding
/meta create-skill        -> create new skill from repo patterns (skill-creator template)

# ADR (Phase 4 — high-stakes lane assist)
/meta adr                 -> generate ADR from latest brainstorm artifact
/meta adr <decision-name> -> create ADR with given title
/meta adr list            -> list all ADRs

# Architecture review (Phase 4)
/meta improve-architecture        -> run periodic architectural review (commands/meta improve-architecture subcommand)
/meta improve-architecture --quick -> single-package scan (faster, narrower)
```

## Auto-promotion threshold (Phase 4)

`scripts/hooks/evolution-check.sh` runs at every session end. Writes promotion candidates to `.claude/memory/promotion-candidates.md` when instinct meets:

- Confidence ≥ 0.8
- Occurrences ≥ 3
- Distinct sessions ≥ 2
- Distinct projects ≥ 2

`/meta evolve` reads that file and walks user through each candidate. See `commands/meta.md §"/meta evolve" + Claude native /memory` §"Auto-Evolution Policy" for full process.

## ADR subcommand (Phase 4)

`scripts/hooks/auto-adr.sh` (Stop hook) prompts user when high-stakes lane completes without ADR.

`/meta adr` then:
1. Reads latest brainstorm artifact at `.claude/memory/brainstorm-artifacts/`
2. Copies `docs/adr/0000-template.md` to `docs/adr/<NNNN>-<decision-slug>.md`
3. Pre-fills:
   - Status: Proposed
   - Date: today
   - Lane: high-stakes
   - Context: from align artifact
   - Decision: chosen option from brainstorm
   - Considered alternatives: rejected options from brainstorm with rationale
4. Opens for user to fill in Consequences + Reversibility + When to revisit

## Improve-architecture subcommand (Phase 4)

`/meta improve-architecture` invokes `commands/meta.md §"/meta improve-architecture"`. Four phases:

1. **Survey** — read CONTEXT.md, ADRs, package structure, recent commits
2. **Detect smells** — module-level, class-level, naming, coupling
3. **Propose improvements** — severity-tagged, cross-check against existing ADRs
4. **Prioritize** — ranked list, user picks 1-3 to act on

Output to `.claude/memory/improve-architecture-<date>.md`. Picked items trigger fresh `/triage` → likely high-stakes.

Recommended cadence: every 2 weeks per project, or after large feature merge.

---

---

## /meta learn status

Show what has been learned across native memory and MCP knowledge graph.

### Process

1. **Read native memories**: List files in project's memory directory, categorize by type (user/feedback/project/reference)
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

Instincts:
  personal:  12 (8 active, 3 stale, 1 fading)
  promoted:  2 (cross-project patterns)
  learned:   1 skill generated from instincts

Recent Learnings:
  [feedback] Don't mock DB in integration tests (2026-03-24)
  [project]  Auth middleware rewrite for compliance (2026-03-23)
  [entity]   OrderService uses PostgreSQL+R2DBC (2026-03-22)

Stale (>30 days, consider pruning):
  (none)
```

---

## /meta learn extract

Distill current session into reusable knowledge and instinct files.

### Process

1. Review conversation for high-value patterns:
   - User corrections (agent got wrong → feedback memory)
   - Architectural decisions (why X over Y → project memory + MCP entity)
   - Bug resolutions (error → fix pattern → MCP entity with observation)
   - New conventions discovered (naming, patterns → project memory)

2. For each pattern, determine storage:
   - Qualitative (preferences, corrections): suggest user runs `/remember`
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

4. Identify non-obvious patterns worth preserving as instincts:
   - Corrections made (user said "no, do X instead")
   - Approaches that worked well (user confirmed or accepted)
   - Repeated patterns (same type of change done 3+ times)
5. For each pattern, create instinct file at `.claude/instincts/personal/`:

```yaml
---
trigger: "normalized trigger phrase"
action: "what to do when triggered"
confidence: 0.5
source: "session"
createdAt: "2026-04-01T10:00:00Z"
lastApplied: null
applyCount: 0
project: "my-service"
---

Detailed explanation of the pattern, when to apply it, and why.
Example: When creating a new endpoint in this project, always add @Valid 
on the request body and use ResponseEntity with RFC 7807 error format.
```

6. Log extracted instincts count

---

## /meta learn report

Weekly summary of learning activity.

### Process

1. Read native memory files — count by type, identify recent additions
2. Query MCP graph — count entities, relations, observations
3. Identify trends:
   - Most frequently queried entities (popular knowledge)
   - Stale entities (not referenced in 30+ days)
   - Feedback memories (user corrections — decreasing over time?)

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

Instinct Trends (last 7 days):
  New: 4 instincts extracted
  Applied: 8 times across 3 instincts
  Confidence changes: 2 increased, 1 decreased
  Ready for evolution: 1 cluster ("error-handling", 4 instincts)

Stale (consider pruning):
  - old-auth-middleware-decision (45 days, replaced by compliance rewrite)
```

---

## /meta evolve

Analyze instincts and suggest promotions to skills/agents.

### Process

1. Read all instinct files from `.claude/instincts/personal/`
2. Normalize triggers (lowercase, remove articles, stem verbs)
3. Cluster instincts by normalized trigger similarity
4. Apply promotion rules:

| Cluster Size | Avg Confidence | Action |
|-------------|---------------|--------|
| 2+ instincts | ≥0.8 | Suggest new skill |
| 3+ instincts | ≥0.75 | Suggest new agent |
| 1 instinct | ≥0.9 | Mark as "established" |
| Any | <0.3 | Mark as "fading" |

5. Output evolution report:
```
EVOLUTION REPORT
================
Clusters found: 3
  "error-handling" (4 instincts, avg confidence: 0.85)
    → SUGGEST: Create skill "error-handling-patterns"
  "testing-setup" (2 instincts, avg confidence: 0.72)
    → No action (confidence below threshold)
  "api-conventions" (3 instincts, avg confidence: 0.80)
    → SUGGEST: Create agent "api-enforcer"

Actions available:
  /meta evolve --generate   # Write suggested skills to .claude/skills/learned/
  /meta evolve --promote    # Promote to ~/.claude/instincts/promoted/
```

---

## /meta evolve --generate

Write evolved skills from instinct clusters.

### Process

1. Read cluster suggestions from most recent `/meta evolve` output
2. For each suggested skill: create `.claude/skills/learned/{skill-name}/SKILL.md`
3. SKILL.md generated from cluster's instinct content with:
   - Merged triggers from cluster's normalized triggers
   - Combined pattern descriptions from all instincts in cluster
   - Source attribution to originating instinct files
4. Report created skills

---

## /meta evolve --promote

Promote high-confidence instincts to global scope.

### Process

1. Identify instincts appearing in ≥2 projects with avg confidence ≥0.8
2. Copy qualifying instincts to `~/.claude/instincts/promoted/`
3. Update source field to "promoted"
4. Report promoted instincts

---

## /meta prune

Remove stale instincts.

### Process

1. Read all instinct files from `.claude/instincts/personal/`
2. Apply TTL rules:
   - `lastApplied` > 30 days ago → STALE
   - `confidence` < 0.3 → FADING
   - `applyCount` = 0 and `createdAt` > 14 days ago → UNUSED
3. Output prune report:
```
PRUNE REPORT
============
Total instincts: 15
  Active: 10
  Stale (>30d): 3 → will remove
  Fading (<0.3 confidence): 1 → will remove
  Unused (0 applies, >14d): 1 → will remove

Removing 5 instincts. Run `/meta prune --dry-run` to preview.
```
4. Delete stale files (or move to `.claude/instincts/archived/` if --archive flag)

### Flags

- `--dry-run`: Preview what would be pruned without deleting
- `--archive`: Move to `.claude/instincts/archived/` instead of deleting

---

## /meta create-skill

Analyze repo's git history to extract coding patterns and generate SKILL.md files.

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
