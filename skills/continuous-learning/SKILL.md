---
name: continuous-learning
description: Observable learning system — automatic via native memory + MCP knowledge graph, observable via /meta learn commands. Replaces the old instinct-based pipeline.
version: 3.0.0
triggers:
  - /meta learn
  - /meta create-skill
  - pattern extraction
---

# Continuous Learning — Automatic & Observable

Learning happens automatically through two systems working together. No manual setup required.

## How Learning Works

```
During Session:
  Claude native auto-memory captures:
    → User corrections → feedback memories (automatic)
    → Project decisions → project memories (automatic)
    → User preferences → user memories (automatic)

  Agents with memory: project capture:
    → Architectural decisions → MCP knowledge graph entities
    → Resolved bugs/patterns → MCP knowledge graph observations
    → Anti-patterns found → MCP knowledge graph entities

Between Sessions:
  → Native Auto Dream consolidates memories (prune, merge, date-convert)
  → Knowledge graph persists across sessions (entities + relations)
  → /meta learn extract distills session into high-value patterns
```

## What Gets Learned (Automatically)

| Source | What | Stored In | How |
|--------|------|-----------|-----|
| User corrections | "Don't mock DB" / "Use constructor injection" | Native `feedback` memory | Claude saves automatically |
| Project decisions | "Chose PostgreSQL over MySQL because..." | Native `project` memory | Claude saves automatically |
| Architecture patterns | Service X uses Y, decided Z | MCP knowledge graph entities | Agents create after work |
| Bug resolutions | Error pattern → fix applied | MCP knowledge graph observations | Agents add after fix |
| User preferences | Code style, response format | Native `user` memory | Claude saves automatically |

## Observable Learning — /meta Commands

### /meta learn status
Shows what has been learned across both systems:
1. Read native memory files from project memory directory
2. Query MCP knowledge graph: `mcp__memory__read_graph`
3. Present dashboard:
   - Memory count by type (user/feedback/project/reference)
   - Knowledge graph entity count by type
   - Recent learnings (last 5 memories + last 5 entities)
   - Knowledge graph health (total entities, relations, observations)

### /meta learn extract
Distill current session into high-value patterns:
1. Review session for extractable insights
2. For corrections/preferences: save as native memory (user asks Claude to `/remember`)
3. For structured patterns: create MCP knowledge graph entities
4. Report what was extracted

### /meta learn report
Periodic summary of learning activity:
1. Count native memories created in last 7 days
2. Count MCP entities/observations added in last 7 days
3. Show most-referenced entities (frequently queried)
4. Identify stale entities (not referenced in 30+ days)

## Design Principles

1. **Automatic** — learning happens without user intervention
2. **Observable** — users can SEE what was learned via /meta learn
3. **Dual-system** — native memory for qualitative, MCP graph for structured
4. **Minimal** — don't store what git log or reading code can tell you
5. **Prunable** — Auto Dream handles native memory; stale graph entities flagged via /meta learn report

## What NOT to Learn

Per Claude Code's design principle:
- Code patterns/conventions → read the code
- Git history → git log/blame
- Debugging solutions → the fix is in the code
- Architecture → read the project structure
- Anything in CLAUDE.md or rules/
