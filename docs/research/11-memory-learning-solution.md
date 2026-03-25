# Memory & Continuous Learning — Best Practice Solution

> **Date**: 2026-03-25
> **Team**: memory-research (4 specialists + team lead)
> **Plugin**: devco-agent-skills v3.0.2
> **Verdict**: Replace broken custom memory with Claude Code native + Knowledge Graph MCP + observable learning overlay

---

## 1. Current State (Audit Summary)

The custom `.claude/memory/` system is **95% broken**:

| Component | Status | Evidence |
|-----------|--------|----------|
| sessions/ | Garbage | 37 `.written-*` marker files never cleaned, 5 identical session records with "0 user messages" |
| knowledge/ | Dead | decisions.json, patterns.json, blockers.json all `{"entries":[]}` — NOTHING ever writes to them |
| context/ | Redundant | active-work.json just echoes git branch name, project-state.json never updated |
| debug-knowledge.md | Empty | Template created, never populated |
| Continuous learning | Blind | 3MB of parse errors in observations.jsonl, 7 stale instincts from another project |
| MCP memory | Unused | Available but disconnected from custom system |

**Meanwhile**: Claude Code's native auto-memory (`~/.claude/projects/.../memory/`) has 3 meaningful feedback files that contain MORE useful information than the entire custom system.

**Three memory systems completely disconnected**: Claude native (works), custom filesystem (broken), MCP knowledge graph (unused).

---

## 2. Best Practice Principles (From Research)

### P1: MINIMAL — Don't store what can be derived
The code, git history, and project structure ARE the primary memory. Only store: the "why", user preferences, corrections, external references.

### P2: OBSERVABLE — Users must see what agents learned
Plain markdown files, human-readable, human-editable, human-deletable. No opaque embeddings.

### P3: STRUCTURED — Memories need metadata
Frontmatter with name, description, type. Description used for relevance matching without reading full content.

### P4: PRUNABLE — Stale memories must decay
Auto Dream consolidation, TTL-based expiration, "Why" field for future relevance judgment.

### P5: TIERED — Different lifetimes, different retrieval
Index always loaded (200 lines) + topic files on demand (Claude Code hybrid pattern).

### P6: QUERYABLE — Search, don't just receive
Tool-driven retrieval > auto-injection for large stores.

### P7: VERIFIABLE — Memory claims vs current truth
"The memory says X exists" ≠ "X exists now." Always verify before acting.

### P8: FEEDBACK-DRIVEN — Record corrections AND confirmations
Include "Why" so agents can judge edge cases, not just follow rules blindly.

**Key benchmark**: Letta research found filesystem-based memory (74.0% LoCoMo) beats Mem0 graph-based (68.5%). "Memory is more about how agents manage context than the exact retrieval mechanism."

---

## 3. Recommended Architecture

### The Big Decision: Don't Build Custom — Leverage Native

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Claude Code Native Auto Memory (FOUNDATION)        │
│  ─────────────────────────────────────────────────────────── │
│  • 4 types: user, feedback, project, reference               │
│  • MEMORY.md index (200 lines auto-loaded per session)       │
│  • Auto Dream consolidation (prune, merge, date-convert)     │
│  • Zero infrastructure, human-readable markdown              │
│  • Already works — 3 feedback files beat entire custom system │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────┴─────────────────────────────────────┐
│  Layer 2: Knowledge Graph MCP (STRUCTURED FACTS)             │
│  ─────────────────────────────────────────────────────────── │
│  • @modelcontextprotocol/server-memory (Tier 1)              │
│  • OR @pepk/mcp-memory-sqlite (Tier 2 — concurrent safe)    │
│  • Entities: services, technologies, decisions, patterns     │
│  • Relations: uses, implements, decided_in, blocks           │
│  • Observations: confidence, usage count, last applied       │
│  • Queryable via search_nodes, open_nodes                    │
│  • Used by agents with `memory: project` for structured data │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────┴─────────────────────────────────────┐
│  Layer 3: Observable Learning Overlay (OUR PLUGIN VALUE-ADD) │
│  ─────────────────────────────────────────────────────────── │
│  • /meta learn status — learning dashboard                   │
│  • /meta learn extract — session distillation                │
│  • /meta learn report — periodic summary                     │
│  • Metrics: memory count, override rate, pattern frequency   │
│  • Reads from Layer 1 + Layer 2, presents unified view       │
└─────────────────────────────────────────────────────────────┘
```

### What Each Layer Does

| Layer | Stores | Who Writes | Who Reads | Persistence |
|-------|--------|-----------|-----------|-------------|
| L1: Native Memory | User preferences, feedback corrections, project decisions, external references | Claude auto-save + user `/remember` | Every session (MEMORY.md auto-loaded) | `~/.claude/projects/{project}/memory/*.md` |
| L2: Knowledge Graph | Structured entities (services, patterns, decisions), relations, confidence scores | Agents with `memory: project` via MCP tools | Agents via `search_nodes` before work | JSONL/SQLite file via MCP server |
| L3: Learning Overlay | Dashboard data, metrics, trend analysis | `/meta learn` commands | User on-demand | Reads L1+L2, no separate storage |

### What NOT to Store (Critical)

Per Claude Code's own design principle and Letta's benchmark:
- Code patterns/conventions — derivable from reading code
- Git history — `git log`/`git blame` are authoritative
- Debugging solutions — the fix is in the code
- Architecture snapshots — read the code
- Session transcripts — ephemeral, no long-term value
- Anything already in CLAUDE.md or rules/

---

## 4. What to REMOVE (Clean Up)

### Kill the Custom Memory System

| Component | Action | Reason |
|-----------|--------|--------|
| `scripts/memory/init.sh` | **REMOVE** | Creates dead L2 knowledge files that nothing writes to |
| `scripts/memory/write-session.sh` | **REMOVE** | Writes low-quality session data (0 user messages, 0 tool calls) |
| `scripts/memory/read-context.sh` | **REMOVE** | Injects garbage context (5 identical session summaries) |
| `scripts/memory/graph-conventions.md` | **KEEP** (move to docs) | Useful reference for MCP knowledge graph entity taxonomy |
| `scripts/hooks/session-save.sh` | **SIMPLIFY** | Remove session writing, keep only active-work.json update |
| `scripts/hooks/session-init.sh` | **SIMPLIFY** | Remove memory init call, remove read-context call, keep bootstrap + project detection |
| `.claude/memory/sessions/` | **DELETE all** | 37 marker files + 5 garbage sessions |
| `.claude/memory/knowledge/` | **DELETE** | Empty files that nothing writes to |
| `.claude/memory/context/` | **KEEP active-work.json** | Useful for cross-session task tracking |
| `.claude/memory/config.json` | **DELETE** | Token budgets never enforced |
| `.claude/memory/debug-knowledge.md` | **DELETE** | Empty template |
| `skills/continuous-learning/` | **OVERHAUL** | Replace instinct pipeline with observable learning overlay |
| `~/.claude/homunculus/` | **DELETE** | 3MB of parse errors + 7 stale instincts from another project |

### Kill the Observation Pipeline

| Component | Action | Reason |
|-----------|--------|--------|
| `observe.sh` hook (if exists) | REMOVE | Captures parse errors, never processed |
| `observations.jsonl` | DELETE | 3MB of garbage |
| `instinct-cli.py` | REMOVE | Complex tool for non-functional system |
| Observer agent (`agents/observer.md`) | REMOVE | Never triggered automatically |
| `start-observer.sh` | REMOVE | Requires manual startup, shells out to expensive claude calls |

---

## 5. What to ADD

### 5.1 MCP Knowledge Graph Configuration

Add to `.mcp.json`:

```json
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "env": {
        "MEMORY_FILE_PATH": ".claude/memory/knowledge-graph.jsonl"
      }
    }
  }
}
```

Tier 2 upgrade path (when concurrent access is needed):
```json
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@pepk/mcp-memory-sqlite"]
    }
  }
}
```

### 5.2 Simplified Session-Init

Remove memory init and read-context calls. Bootstrap + project detection is sufficient:

```bash
# session-init.sh simplified
# 1. Bootstrap skill injection (keep)
# 2. Project type detection (keep)
# 3. Summer detection + injection (keep)
# 4. REMOVE: memory init call
# 5. REMOVE: read-context call
# Context comes from: MEMORY.md (native, auto-loaded) + MCP knowledge graph (agent queries on-demand)
```

### 5.3 Observable Learning Commands

Redesign `/meta learn` to read from native memory + MCP graph:

```markdown
/meta learn status    — Dashboard: memories by type, recent patterns, metrics
/meta learn extract   — Distill current session into key learnings
/meta learn report    — Weekly summary of learning activity
```

### 5.4 Agent Memory Integration

Agents with `memory: project` should use MCP knowledge graph for structured data:

```markdown
## Memory (in agent definitions)

Before work: `search_nodes` for entities related to files/services you'll touch.
After work: `create_entities` for new findings, `add_observations` for updates.

For preferences/corrections: Claude's native auto-memory handles this automatically.
```

---

## 6. Continuous Learning Design

### Replace Blind Instincts with Observable Learning

**Before (broken)**:
```
observe.sh → observations.jsonl (3MB errors) → observer agent (never runs) → instincts (stale)
```

**After (observable)**:
```
Claude native auto-memory captures:
  - User corrections → feedback memories (automatic)
  - Project decisions → project memories (automatic)
  - User preferences → user memories (automatic)

MCP knowledge graph captures:
  - Structured patterns → entities with confidence + usage count
  - Decisions → entities with rationale + evidence

/meta learn reads both → presents unified dashboard
```

### Learning Metrics

| Metric | How to Measure | What It Shows |
|--------|---------------|---------------|
| Memory count by type | Count native memory files by frontmatter type | Knowledge accumulation |
| Feedback ratio | feedback / total memories | How correction-driven |
| Entity count | MCP `read_graph` entity count | Structured knowledge growth |
| User override rate | Trend of user corrections | Lower = better learning |
| Memory freshness | Average age of memories | Knowledge currency |

### Session Distillation (`/meta learn extract`)

After each significant session, the user can run `/meta learn extract`:
1. Review conversation for high-value patterns
2. Extract as `feedback` or `project` type native memories
3. Store structured entities in MCP knowledge graph
4. Report: "Extracted 3 patterns, 1 decision, 2 corrections"

This replaces the automated observation pipeline with a **user-triggered, observable** process.

---

## 7. Implementation Roadmap

### Phase 1: Clean Up (Immediate)
1. Delete all `.written-*` marker files
2. Delete empty knowledge/ directory
3. Delete config.json, debug-knowledge.md
4. Clean `~/.claude/homunculus/` (observations.jsonl, stale instincts)
5. Simplify session-save.sh (remove session writing, keep active-work update)
6. Simplify session-init.sh (remove memory init/read-context calls)

### Phase 2: Wire MCP (Short-term)
1. Add `@modelcontextprotocol/server-memory` to `.mcp.json`
2. Update agent memory sections to use MCP tools properly
3. Update graph-conventions.md as the entity taxonomy reference
4. Test: agents create entities and query them across sessions

### Phase 3: Observable Learning (Medium-term)
1. Redesign `/meta learn` commands (status, extract, report)
2. Implement session distillation in `/meta learn extract`
3. Add learning metrics dashboard
4. Remove old continuous-learning observation pipeline

### Phase 4: Tier 2 Upgrade (Future)
1. Evaluate `@pepk/mcp-memory-sqlite` for concurrent access safety
2. Consider semantic search MCP (ChromaDB or sqlite-vec) if needed
3. Cross-project memory sharing patterns

---

## 8. MCP Evaluation Summary

| Server | Tier | Setup | When to Use |
|--------|------|-------|-------------|
| **@modelcontextprotocol/server-memory** | 1 (Now) | `npx` instant | Structured facts, simple graphs |
| **@pepk/mcp-memory-sqlite** | 2 (Next) | `npx` instant | When concurrent access needed |
| **MemorizedMCP** | 3 (Future) | Binary | When hybrid search needed |
| **Cognee MCP** | 3 (Future) | `uv run` | Enterprise-grade RAG |

**Recommendation: Start Tier 1, plan Tier 2.** Don't let perfect be the enemy of good.

---

## 9. Key Insight

> "Memory is more about how agents manage context than the exact retrieval mechanism used."
> — Letta benchmark (filesystem 74.0% beats Mem0 graph 68.5%)

The plugin's value is in **workflows and skills**, not in reinventing memory storage. Leverage Claude Code's native memory (it works), add MCP knowledge graph for structured data (it's standard), and provide observable learning overlay (our unique value-add). Delete everything else.

---

## Sources

- Letta Benchmark: "Is a Filesystem All You Need?" — letta.com/blog/benchmarking-ai-agent-memory
- Mem0 Research Paper — arXiv:2504.19413
- Zep/Graphiti Temporal KG — arXiv:2501.13956
- Claude Code Memory Documentation — code.claude.com/docs/en/memory
- BREW (Microsoft Research, NeurIPS 2025) — Bootstrapping experiential knowledge
- OpenClaw Memory Strategy — prioritize retrievability over automatic injection
- MCP Memory Server — @modelcontextprotocol/server-memory
- 15+ MCP memory servers evaluated (see full MCP research)
