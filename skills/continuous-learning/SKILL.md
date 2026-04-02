---
name: continuous-learning
description: >
  Observable learning system for tracking what Claude has learned during sessions.
  Manages dual learning: native Claude memory (automatic) and MCP knowledge graph
  (structured entities and relations). Use when a user asks what Claude has learned
  about the project, wants to store a preference, requests a learning summary, asks
  about memory or knowledge graph state, wants to extract patterns from a session,
  or invokes /meta learn commands.
triggers:
  natural: ["learn pattern", "extract skill", "evolve", "meta command"]
  code: ["/meta"]
---

# Continuous Learning — Automatic and Observable

Learning happens through two systems. Native Claude memory captures qualitative feedback automatically. The MCP knowledge graph stores structured decisions and patterns that persist across sessions. If MCP memory tools are unavailable, fall back to file-based storage in `.claude/knowledge/`.

## Trigger-to-Action Table

| Trigger | Action |
|---------|--------|
| "What have you learned?" | `mcp__memory__read_graph` → summarize by type |
| "Store this / remember this" | `mcp__memory__create_entities` type `user_preference` |
| "What decisions were made?" | `mcp__memory__search_nodes` with keywords |
| `/meta learn status` | Read graph → dashboard (entity count, recent, relations) |
| `/meta learn extract` | Review session → deduplicate → create entities |
| `/meta learn report` | Flag stale entities, suggest prune/update |

## What to Store

| Entity Type | Example |
|-------------|---------|
| `architecture_decision` | "Chose R2DBC over JPA for reactive stack" |
| `bug_pattern` | "Null pointer in Flux.zip when one source empty" |
| `anti_pattern` | "Team uses @Autowired field injection" |
| `project_convention` | "All handlers extend BaseHandler" |

**Never store:** code patterns readable from codebase, git history, debugging solutions in code, anything in CLAUDE.md or rules/.

## /meta Commands

| Command | Action |
|---------|--------|
| `/meta learn status` | Read graph → entity count by type, recent 5, relation count |
| `/meta learn extract` | Review session → search for dupes → create/update entities |
| `/meta learn report` | Stale entities, most-connected, prune suggestions |
| `/meta evolve` | Cluster instincts → suggest promotions |
| `/meta evolve --generate` | Write evolved skills from clusters |
| `/meta prune` | Remove stale instincts (confidence < 0.2 or 30 days idle) |

## Instinct Pipeline

Instincts are micro-patterns extracted from sessions that compound into skills over time. See **[references/instinct-pipeline.md](references/instinct-pipeline.md)** for the full technical reference including architecture, file format, confidence scoring, auto-promotion rules, and evolution workflow.

**Quick reference:** Instincts live in `.claude/instincts/personal/` (project) or `~/.claude/instincts/promoted/` (global). Confidence starts at 0.5, increases on successful application (+0.05) or user confirmation (+0.1), decreases on rejection (-0.2) or inactivity. Promotion triggers at ≥2 projects with avg confidence ≥0.8.

## Related Skills

- **testing-workflow** — TDD patterns become instincts for test-writing preferences
- **architecture** — Architectural decisions stored as knowledge graph entities
- **coding-standards** — Style preferences captured as instincts
