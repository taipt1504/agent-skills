# Memory & Context Management — Upgrade Plan

> Detailed plan to evolve devco-agent-skills from bash-hook-only context management
> to a production-grade memory system using open-source MCP servers, structured persistence,
> and cross-session/cross-agent knowledge sharing.

**Date:** 2026-03-17
**Status:** Draft — awaiting approval
**Scope:** 3 phases, incremental — each phase delivers standalone value

---

## Table of Contents

1. [Current State Analysis](#1-current-state-analysis)
2. [Problem Statement](#2-problem-statement)
3. [Phase 1 — Fix Foundation + Structured Memory](#3-phase-1--fix-foundation--structured-memory)
4. [Phase 2 — Integrate Open-Source MCP Memory Servers](#4-phase-2--integrate-open-source-mcp-memory-servers)
5. [Phase 3 — Subagent Memory + Knowledge Graph](#5-phase-3--subagent-memory--knowledge-graph)
6. [Architecture Overview](#6-architecture-overview)
7. [Migration Strategy](#7-migration-strategy)
8. [Risk Assessment](#8-risk-assessment)
9. [Open-Source Evaluation](#9-open-source-evaluation)

---

## 1. Current State Analysis

### What Exists Today

```
Hooks (bash scripts):
├── session-start.sh    ── Detects project, loads last session (flat text), pings claude-mem
├── session-end.sh      ── Writes session .md file, posts to claude-mem (fire-and-forget)
├── pre-compact.sh      ── Saves recovery JSON, reads instincts, posts to claude-mem
├── suggest-compact.sh  ── Advisory counter (50 tool calls → suggest)
├── evaluate-session.sh ── Signal to stderr (NOT wired in settings.json)
├── cost-tracker.sh     ── Token/cost tracking to JSONL
├── java-compile-check  ── PostToolUse compile check
├── java-format.sh      ── PostToolUse spotless format
└── check-debug.sh      ── Stop: scan for debug statements

Learning System (continuous-learning-v2):
├── observe.sh          ── Observation hook (NOT wired in settings.json)
├── observer agent      ── Background daemon (never started)
├── instinct-cli.py     ── CLI for instinct management
├── config.json         ── observer.enabled = false
└── ↳ Result: ZERO instincts, ZERO observations, ZERO learned skills

Session Files (.claude/sessions/):
├── *-session.md        ── Structured markdown (date, branch, files, summary)
├── .written-*          ── Idempotency markers
├── cost-log.jsonl      ── Cost tracking
└── ↳ Problem: All sessions show "0 messages" — CLAUDE_TRANSCRIPT_PATH not set

MCP Infrastructure:
├── .mcp.json           ── DOES NOT EXIST
├── mcp-configs/        ── Template configs only (not active)
└── ↳ No bundled MCP server, no active memory server
```

### What's Broken

| Issue | Root Cause | Impact |
|-------|-----------|--------|
| Session files all "0 messages" | `CLAUDE_TRANSCRIPT_PATH` not available to hooks | No session history, no learning signals |
| `evaluate-session.sh` not wired | Missing from `.claude/settings.json` Stop hooks | Learning evaluation never triggers |
| `observe.sh` not wired | Missing from settings.json, `observer.enabled = false` | Zero observations captured |
| Observer daemon never started | `start-observer.sh` never invoked | No pattern extraction |
| `~/.claude/homunculus/` absent | Never initialized | Instinct system has no storage |
| `claude-mem` assumed running | All hooks degrade gracefully but silently | No cross-session memory when claude-mem is absent |
| `SessionEnd` timeout 1.5s default | Claude Code system limit | AI summarization impossible in hook |
| Session-start loads flat text | No semantic relevance ranking | Irrelevant context wastes tokens |

### What Works

- Session file structure is solid — date, branch, files, summary format
- `additionalContext` via hook stdout — correct pattern for context injection
- `pre-compact.sh` recovery JSON — good data capture
- Cost tracking — functional and useful
- Profile gating (`run-with-flags.sh`) — clean minimal/standard/strict separation
- All hooks degrade gracefully — never block session start

---

## 2. Problem Statement

### Core Problem

The plugin's memory/context system is **designed but not operational**. The continuous-learning-v2
infrastructure exists (observe.sh, observer daemon, instinct-cli.py) but nothing is wired or running.
Bash hooks handle session lifecycle adequately but cannot:

1. **Persist structured knowledge** — only flat markdown files
2. **Search semantically** — session-start loads last session regardless of relevance
3. **Share context between agents** — each subagent starts with zero memory
4. **Compress intelligently** — no AI summarization (timeout too short)
5. **Learn from sessions** — observation pipeline is dormant

### Design Constraints

- **Zero mandatory dependencies** — plugin must work standalone (no Docker, no external DB)
- **Progressive enhancement** — each layer adds value but isn't required
- **Sub-second hooks** — lifecycle hooks cannot block for AI calls
- **Offline-first** — no network required for core functionality
- **Git-friendly** — memory files should be committable for team sharing

---

## 3. Phase 1 — Fix Foundation + Structured Memory

**Goal:** Make existing infrastructure work + add structured memory files
**Effort:** 3-5 days
**Dependencies:** None — pure bash + JSON/YAML files
**Value:** Session continuity actually works, learning pipeline activates

### 1.1 Fix Hook Wiring

Wire missing hooks in `.claude/settings.json`:

```jsonc
{
  "hooks": {
    "Stop": [
      // existing entries ...
      {
        "command": "scripts/hooks/evaluate-session.sh",
        "timeout": 15000,
        "type": "command"
      }
    ]
    // observe.sh wiring deferred to Phase 1.3
  }
}
```

**Files to modify:**
- `.claude/settings.json` — add `evaluate-session.sh` to Stop hooks

### 1.2 Fix Session Data Capture

The session files are empty because `CLAUDE_TRANSCRIPT_PATH` isn't available. Two fixes:

**Fix A — Use git diff as primary data source (not transcript)**

`session-end.sh` already collects git data (modified files, branch, etc.). Enhance it to:

1. Capture `git diff --stat` for a meaningful change summary
2. Parse hook stdin JSON for available metadata (the `Stop` event passes session data)
3. Write richer session files even without transcript access

**Fix B — Capture context from hook stdin**

The `Stop` hook receives JSON on stdin with session metadata. Extract:
- `session_id`
- `transcript_path` (if available)
- Token usage stats (from cost-tracker)

**Files to modify:**
- `scripts/hooks/session-end.sh` — enhance data capture from stdin + git

### 1.3 Structured Memory Directory

Replace flat session files with a structured memory directory:

```
.claude/memory/
├── sessions/
│   ├── index.json              ← Session index (id, date, branch, summary, token count)
│   └── 2026-03-17-abc123.json  ← Full session data (structured JSON)
├── knowledge/
│   ├── decisions.json          ← Architectural decisions made in sessions
│   ├── patterns.json           ← Recurring patterns observed
│   └── blockers.json           ← Known blockers and resolutions
├── context/
│   ├── project-state.json      ← Current project state snapshot
│   └── active-work.json        ← What's being worked on right now
└── config.json                 ← Memory system configuration
```

**Session index format** (`sessions/index.json`):
```json
{
  "sessions": [
    {
      "id": "2026-03-17-abc123",
      "date": "2026-03-17T14:30:00Z",
      "branch": "feat/memory-upgrade",
      "summary": "Rewrote mysql-patterns skill, fixed 4 bugs",
      "files_modified": 6,
      "tokens_used": 45000,
      "cost_usd": 0.23,
      "tags": ["mysql", "skill-rewrite", "bug-fix"]
    }
  ]
}
```

**Tiered retrieval in session-start.sh:**
```
Tier 0 (~50 tokens):  Read sessions/index.json → last 5 sessions, one line each
Tier 1 (~200 tokens): Read context/active-work.json → current focus
Tier 2 (~500 tokens): Read latest session JSON → full context if relevant
```

**Files to create:**
- `scripts/memory/init.sh` — initialize memory directory structure
- `scripts/memory/write-session.sh` — called by session-end, writes structured JSON
- `scripts/memory/read-context.sh` — called by session-start, tiered retrieval

**Files to modify:**
- `scripts/hooks/session-start.sh` — use tiered retrieval from structured memory
- `scripts/hooks/session-end.sh` — write to structured memory directory

### 1.4 Activate Learning Pipeline

The continuous-learning-v2 infrastructure exists but is dormant. Activate it:

1. **Initialize homunculus directory:**
   ```bash
   mkdir -p ~/.claude/homunculus/instincts/{personal,inherited}
   mkdir -p ~/.claude/homunculus/evolved
   touch ~/.claude/homunculus/observations.jsonl
   ```

2. **Wire observe.sh** (selectively — not all tool uses):
   ```jsonc
   // settings.json
   "PostToolUse": [
     // existing entries...
     {
       "command": "skills/continuous-learning-v2/hooks/observe.sh",
       "timeout": 5000,
       "type": "command"
       // No matcher → observes all tool uses (observe.sh has its own blocklist)
     }
   ]
   ```

3. **Enable observer in config:**
   ```json
   // skills/continuous-learning-v2/config.json
   { "observer": { "enabled": true } }
   ```

4. **Auto-start observer in session-start.sh:**
   ```bash
   # Start observer daemon if not running
   if [ -f "skills/continuous-learning-v2/agents/start-observer.sh" ]; then
     bash "skills/continuous-learning-v2/agents/start-observer.sh" &
   fi
   ```

**Files to modify:**
- `.claude/settings.json` — wire observe.sh
- `skills/continuous-learning-v2/config.json` — enable observer
- `scripts/hooks/session-start.sh` — auto-start observer daemon

### 1.5 `additionalContext` for Silent Injection

Currently session-start.sh writes to stdout which is visible in Claude's context.
Use the `additionalContext` hook output field for cleaner injection:

```bash
# Instead of echo to stdout:
# echo "## Session Boot"

# Use additionalContext (injected silently, not shown to user):
# Hook output JSON format:
cat <<EOF
{
  "hookSpecificOutput": {
    "additionalContext": "## Session Boot\n\nStack: Java 17+ ..."
  }
}
EOF
```

**Note:** This requires the hook to output valid JSON to stdout. The current approach
(plain markdown to stdout) works but `additionalContext` is the official pattern.

**Files to modify:**
- `scripts/hooks/session-start.sh` — switch to JSON output with additionalContext

### Phase 1 Deliverables

| Deliverable | Status |
|-------------|--------|
| Hook wiring fixed (evaluate-session, observe) | |
| Session data capture enhanced (git diff, stdin parsing) | |
| Structured memory directory (`.claude/memory/`) | |
| Tiered retrieval (50 → 200 → 500 tokens) | |
| Learning pipeline activated (observer, observations) | |
| `additionalContext` hook output | |

---

## 4. Phase 2 — Integrate Open-Source MCP Memory Servers

**Goal:** Add persistent memory via existing open-source MCP servers — no custom build
**Effort:** 2-3 days
**Dependencies:** Node.js (for `@modelcontextprotocol/server-memory`)
**Value:** Knowledge graph, cross-session knowledge, agent-queryable memory

### 2.1 Why Open-Source Instead of Custom Build

We evaluated 7 open-source memory solutions (see [Section 9](#9-open-source-evaluation)).
Key finding: **the primitives we need already exist** — building from scratch adds maintenance
burden without meaningful capability advantage.

| Need | Open-Source Solution | Custom Build Advantage |
|------|---------------------|----------------------|
| Knowledge graph | `@mcp/server-memory` (Anthropic) | None — identical model |
| Session persistence | Phase 1 structured JSON files | None |
| Semantic search | `memsearch` or future addition | Marginal (FTS5 vs vector) |
| Progressive disclosure | Hook integration layer | None |
| Offline-first | `@mcp/server-memory` (JSONL) | None |

**Decision:** Use `@modelcontextprotocol/server-memory` as the knowledge graph layer.
Hooks handle session lifecycle (Phase 1). Semantic search deferred until needed.

### 2.2 Architecture — Two-Layer Approach

```
┌─────────────────────────────────────────────────────────────────┐
│                        Claude Code Session                       │
│                                                                   │
│  Layer 1: Hooks (Session Lifecycle — Phase 1)                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ session-start│  │  PostToolUse │  │  session-end  │          │
│  │ → read JSON  │  │  → observe   │  │ → write JSON  │          │
│  │ → inject ctx │  │              │  │ → populate    │          │
│  │              │  │              │  │   graph       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                   │
│  Layer 2: MCP Server (Knowledge Graph — Phase 2)                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │     @modelcontextprotocol/server-memory (stdio)          │    │
│  │                                                           │    │
│  │  Tools (already available):                               │    │
│  │    create_entities     ← store decisions, patterns        │    │
│  │    create_relations    ← link entities (uses, implements) │    │
│  │    add_observations    ← append facts to entities         │    │
│  │    search_nodes        ← keyword search across graph      │    │
│  │    open_nodes          ← load specific entities by name   │    │
│  │    read_graph          ← dump entire graph                │    │
│  │    delete_entities/relations/observations                 │    │
│  │                                                           │    │
│  │  Storage: .claude/memory/memory.jsonl  (flat file, git)   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  Layer 3 (Optional — Future): Semantic Search                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  memsearch / vector DB plugin (if keyword search proves  │    │
│  │  insufficient for retrieval quality)                      │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Register `@mcp/server-memory` in Plugin

Create `.mcp.json` at plugin root:

```json
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "env": {
        "MEMORY_FILE_PATH": "${CLAUDE_PROJECT_DIR}/.claude/memory/knowledge-graph.jsonl"
      }
    }
  }
}
```

**Auto-start:** Plugin MCP servers start automatically when the plugin loads.
**Offline:** No network needed after first `npx` cache. JSONL storage is a flat file.
**Fallback:** If MCP server fails, hooks still work with Phase 1 JSON files.

### 2.4 Knowledge Graph Entity Model

Define a consistent entity taxonomy for the plugin:

```
Entity Types:
  service       — microservice or module (OrderService, PaymentGateway)
  technology    — tech choice (R2DBC, PostgreSQL, Redis, Kafka)
  pattern       — architectural pattern (CQRS, Event Sourcing, Hexagonal)
  anti_pattern  — known problem (N+1 Query, .block() in reactive)
  decision      — architectural decision (ADR-001, "Use CQRS for orders")
  blocker       — known issue blocking progress
  preference    — team/user coding preference

Relation Types:
  uses          — service uses technology
  implements    — service implements pattern
  decided_in    — decision decided_in session
  found_in      — anti_pattern found_in service
  blocks        — blocker blocks service
  replaces      — decision replaces decision
  related_to    — generic association
```

### 2.5 Hook → Graph Integration

**`session-end.sh` — auto-populate graph after each session:**

```bash
# After writing session JSON (Phase 1), write a graph population script
# that Claude reads on next session-start and optionally executes

GRAPH_SUGGESTIONS=".claude/memory/pending-graph-updates.json"

cat > "$GRAPH_SUGGESTIONS" <<EOF
{
  "session": "$SESSION_ID",
  "date": "$DATE",
  "suggestions": [
    {
      "action": "create_entity",
      "name": "$PROJECT_NAME",
      "type": "service",
      "observation": "Session $SESSION_ID: modified $FILE_COUNT files on branch $BRANCH"
    }
  ],
  "files_modified": $FILES_JSON,
  "branch": "$BRANCH"
}
EOF
```

**`session-start.sh` — query graph for relevant context:**

```bash
# If graph JSONL exists, extract recent entities for context injection
GRAPH_FILE=".claude/memory/knowledge-graph.jsonl"
if [ -f "$GRAPH_FILE" ]; then
  # Count entities (rough — each line is a JSON object)
  ENTITY_COUNT="$(wc -l < "$GRAPH_FILE" | tr -d ' ')"
  if [ "$ENTITY_COUNT" -gt 0 ]; then
    log "Knowledge graph: $ENTITY_COUNT entries"
    # Inject graph summary into additionalContext
    # (MCP tools are available for deeper queries during session)
  fi
fi
```

**Key insight:** Hooks provide **lightweight automatic capture** (session lifecycle).
The MCP `memory` tools provide **on-demand deep queries** (Claude calls them when needed).
The combination avoids the need for a custom server.

### 2.6 Agent Instructions for Graph Usage

Add instructions to agent system prompts for graph interaction:

```markdown
## Memory (Knowledge Graph)

You have access to a persistent knowledge graph via `mcp__memory__*` tools.

**Before starting work:**
- `search_nodes` for entities related to the files/services you're reviewing
- `open_nodes` to load specific decisions or patterns

**After completing work:**
- `create_entities` for new decisions, patterns, or anti-patterns found
- `add_observations` to append findings to existing entities
- `create_relations` to link entities (e.g., anti_pattern found_in service)

**Entity naming convention:** PascalCase for services, kebab-case for decisions,
UPPER_SNAKE for anti-patterns. Example: `OrderService`, `adr-use-cqrs`, `N_PLUS_ONE_QUERY`.
```

### 2.7 Optional Enhancement: Semantic Search (Future)

If keyword-based `search_nodes` proves insufficient for retrieval quality,
add `memsearch` as a second MCP layer:

```json
// .mcp.json — add alongside memory server
{
  "mcpServers": {
    "memory": { "..." },
    "memsearch": {
      "command": "memsearch",
      "args": ["serve", "--memory-dir", "${CLAUDE_PROJECT_DIR}/.claude/memory/docs"]
    }
  }
}
```

This is **additive** — no changes to existing hooks or graph server.
Defer until Phase 2 is in production and retrieval gaps are identified.

**Files to create:**
- `.mcp.json` — register `@mcp/server-memory`
- `scripts/memory/graph-conventions.md` — entity taxonomy documentation

**Files to modify:**
- `scripts/hooks/session-end.sh` — write pending graph updates JSON
- `scripts/hooks/session-start.sh` — check graph file, inject summary
- `scripts/setup.sh` — initialize `.claude/memory/` including graph JSONL path
- Key agent files — add graph usage instructions to system prompts

### Phase 2 Deliverables

| Deliverable | Status |
|-------------|--------|
| `.mcp.json` with `@mcp/server-memory` registration | |
| Entity taxonomy (types + relations + naming) | |
| Hook → graph integration (session-end populates, session-start queries) | |
| Agent instructions for graph usage | |
| Fallback: works without MCP server running | |
| Optional: memsearch for semantic search (deferred) | |

---

## 5. Phase 3 — Subagent Memory + Cross-Agent Knowledge Sharing

**Goal:** Agents remember across invocations + share knowledge through the graph
**Effort:** 3-5 days
**Dependencies:** Phase 2 (`@mcp/server-memory` running)
**Value:** Agents learn from past reviews, architecture decisions survive across sessions

### 3.1 Subagent Memory (Native Claude Code Feature)

Add `memory: project` to key agents so they persist learnings:

```yaml
# agents/code-reviewer.md frontmatter
---
name: code-reviewer
memory: project
tools: ["Read", "Grep", "Glob", "Bash"]
model: sonnet
---
```

**Agents to upgrade:**

| Agent | Memory Scope | What It Remembers |
|-------|-------------|-------------------|
| `architect` | project | ADRs, design decisions, rejected alternatives |
| `code-reviewer` | project | Recurring code issues, team style preferences |
| `planner` | project | Past plan structures, estimation accuracy |
| `database-reviewer` | project | Schema evolution, index decisions, query patterns |
| `spring-webflux-reviewer` | project | Reactive anti-patterns found, fix patterns that worked |
| `security-reviewer` | project | Security findings, false positives to skip |
| `build-error-resolver` | project | Common build errors and their fixes for this project |

**Memory files stored at:** `.claude/agent-memory/<agent-name>/MEMORY.md`

Each agent's MEMORY.md is auto-loaded (first 200 lines) into its system prompt.
Agents are instructed to update MEMORY.md with learnings after each invocation.

### 3.2 Knowledge Graph Population Strategy

The `@mcp/server-memory` from Phase 2 is already a knowledge graph. Phase 3 focuses
on **systematically populating it** through agent workflows and auto-capture.

```
┌──────────────────────────────────────────────────┐
│      Knowledge Graph (@mcp/server-memory)         │
│                                                    │
│  ┌──────────┐     uses      ┌──────────────┐     │
│  │ OrderSvc │──────────────▶│ R2DBC + PG   │     │
│  └────┬─────┘               └──────────────┘     │
│       │ implements                                 │
│       ▼                                           │
│  ┌──────────┐     decided_in  ┌──────────┐       │
│  │ CQRS     │────────────────▶│ ADR-001  │       │
│  └──────────┘                 └──────────┘       │
│       │                                           │
│       │ pattern_of                                │
│       ▼                                           │
│  ┌──────────────┐  found_in  ┌───────────┐      │
│  │ N+1 Query    │───────────▶│ Session-5 │      │
│  │ (anti-pattern)│           └───────────┘      │
│  └──────────────┘                                │
└──────────────────────────────────────────────────┘

Tools (from @mcp/server-memory — no custom build):
  create_entities(entities)      → batch create nodes
  create_relations(relations)    → batch create edges
  add_observations(observations) → append facts to nodes
  search_nodes(query)            → keyword search
  open_nodes(names)              → load by name
  read_graph()                   → full graph dump
  delete_entities/relations/observations
```

### 3.3 Auto-Population: Backfill Command

Create a `/graph-init` command that populates the graph from existing project data:

```bash
# Extract from CLAUDE.md
→ Entity: "project-stack" (technology) with observations for each tech

# Extract from git log
→ Entity per active service/module with recent commit summaries

# Extract from ADR files (if docs/adr/ exists)
→ Entity per ADR (decision) with observations for status/consequences

# Extract from session files (.claude/memory/sessions/)
→ Entity per session with summary observations
```

This runs once per project, then agents maintain the graph incrementally.

### 3.4 Agent ↔ Knowledge Graph Integration

When agents run, they query and update the knowledge graph:

**code-reviewer example:**
```
1. Agent starts → queries graph: "anti_pattern entities related to modified files"
2. Reviews code → finds N+1 query in OrderService
3. Checks graph: "has this been flagged before?"
   → Yes: escalate severity ("recurring issue, 3rd time in 2 weeks")
   → No: add to graph as new observation
4. Agent finishes → updates MEMORY.md with this session's findings
```

**architect example:**
```
1. Agent starts → queries graph: "decision entities for this service"
2. Designs feature → references past ADRs from graph
3. Makes new decision → creates entity + relation to relevant ADRs
4. Agent finishes → updates MEMORY.md
```

### 3.5 Cross-Agent Context Sharing

Agents share knowledge through the graph, not through direct communication:

```
architect → creates ADR entity → "Use CQRS for OrderService"
    ↓
code-reviewer → queries graph → sees CQRS decision
    → validates code follows CQRS pattern
    ↓
database-reviewer → queries graph → sees CQRS decision
    → validates read/write model separation in DB
    ↓
spring-webflux-reviewer → queries graph → sees reactive requirement
    → validates no .block() in CQRS command handlers
```

### Phase 3 Deliverables

| Deliverable | Status |
|-------------|--------|
| `memory: project` on 7 key agents | |
| `/graph-init` backfill command | |
| Agent system prompt instructions for graph usage | |
| Cross-agent context sharing via `@mcp/server-memory` graph | |

---

## 6. Architecture Overview

### Final State (After All 3 Phases)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Claude Code Session                       │
│                                                                   │
│  Layer 1: Hooks (Session Lifecycle)                              │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐                       │
│  │ session  │  │ PostTool │  │ session  │                       │
│  │ start    │  │ Use hook │  │ end      │                       │
│  │ → inject │  │ → observe│  │ → write  │                       │
│  │   context│  │          │  │   JSON   │                       │
│  └────┬─────┘  └──────────┘  └────┬─────┘                       │
│       │                            │                              │
│       ▼                            ▼                              │
│  .claude/memory/              .claude/memory/                    │
│  sessions/ (read)             sessions/ (write)                  │
│                                                                   │
│  Layer 2: @mcp/server-memory (Knowledge Graph)                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Entities ←→ Relations ←→ Observations                   │    │
│  │  Storage: .claude/memory/knowledge-graph.jsonl (flat)    │    │
│  │  Tools: create_entities, search_nodes, open_nodes, ...   │    │
│  └─────────────────────────────────────────────────────────┘    │
│       ↑                                                          │
│       │ query + update                                           │
│       ▼                                                          │
│  Layer 3: Subagents (with memory: project)                       │
│  ┌────────────┐ ┌────────────┐ ┌──────────────┐                │
│  │ architect  │ │code-reviewer│ │db-reviewer   │  ...           │
│  │ MEMORY.md  │ │ MEMORY.md  │ │ MEMORY.md    │                │
│  └────────────┘ └────────────┘ └──────────────┘                │
│  .claude/agent-memory/<name>/MEMORY.md                          │
└─────────────────────────────────────────────────────────────────┘
```

### Token Budget per Session Start

| Source | Tokens | Phase |
|--------|--------|-------|
| Session index (last 5) | ~50 | 1 |
| Active work context | ~200 | 1 |
| Relevant knowledge (top 3) | ~300 | 2 |
| Graph context (related entities) | ~200 | 3 |
| **Total injection** | **~750** | |

Compare to current: session-start.sh injects ~2000+ tokens of flat text including
the full workflow reminder, previous session dump, and project detection output.
The structured approach is **more relevant with fewer tokens**.

---

## 7. Migration Strategy

### Phase 1 → Phase 2 Migration

Phase 1 writes JSON files to `.claude/memory/`. Phase 2 adds `@mcp/server-memory`
as a separate knowledge graph layer (JSONL file). No migration needed — they coexist:

- Hooks continue reading/writing JSON session files (unchanged)
- `@mcp/server-memory` stores the knowledge graph in its own JSONL file
- Session-end hook optionally writes pending graph updates for Claude to process

### Phase 2 → Phase 3 Migration

Phase 3 adds `memory: project` to agent frontmatter. No data migration —
agent memory files (`.claude/agent-memory/`) are separate from the graph
and managed by Claude Code natively. Agents query the Phase 2 graph via MCP tools.

### Backwards Compatibility

At every phase, the plugin must still work if:
- `@mcp/server-memory` is not running (Phase 1 JSON files as fallback)
- Node.js is not installed (pure bash hooks still function)
- No previous memory exists (cold start with empty memory)
- Plugin is freshly installed (setup.sh initializes memory directory)

---

## 8. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| `@mcp/server-memory` not available | Low | Low | Hooks fall back to JSON files; graph is enhancement only |
| JSONL graph file grows large | Medium | Medium | Periodic cleanup of stale entities; cap at ~500 entities |
| Node.js not installed | Low | Medium | Phase 1 works purely in bash; MCP server is opt-in |
| `npx` first-run downloads package | Low | Low | Cached after first run; add to setup.sh pre-warm |
| Agent memory files conflict in git | Medium | Low | `.claude/agent-memory/` in `.gitignore` by default |
| Token budget exceeded at session start | Medium | Medium | Hard cap at 1000 tokens; tiered retrieval with early exit |
| Claude Code API changes break hooks | Low | High | Pin to documented hook API; test in CI |
| `@mcp/server-memory` API changes | Low | Medium | Pin version in `.mcp.json` args; monitor releases |

---

## Appendix A — File Inventory

### Phase 1 (New Files)

```
scripts/memory/
├── init.sh                  ← Initialize memory directory
├── write-session.sh         ← Write structured session JSON
└── read-context.sh          ← Tiered retrieval for session-start

.claude/memory/
├── sessions/
│   └── index.json
├── knowledge/
│   ├── decisions.json
│   ├── patterns.json
│   └── blockers.json
├── context/
│   ├── project-state.json
│   └── active-work.json
└── config.json
```

### Phase 1 (Modified Files)

```
.claude/settings.json        ← Wire evaluate-session.sh + observe.sh
scripts/hooks/session-start.sh ← Tiered retrieval + additionalContext
scripts/hooks/session-end.sh   ← Write structured JSON + enhanced capture
skills/continuous-learning-v2/config.json ← Enable observer
```

### Phase 2 (New Files)

```
.mcp.json                            ← Register @mcp/server-memory
scripts/memory/graph-conventions.md  ← Entity taxonomy documentation
```

### Phase 2 (Modified Files)

```
scripts/hooks/session-end.sh   ← Write pending graph updates JSON
scripts/hooks/session-start.sh ← Check graph, inject summary
scripts/setup.sh               ← Initialize .claude/memory/ including graph path
```

### Phase 3 (New Files)

```
commands/graph-init.md         ← /graph-init backfill command
```

### Phase 3 (Modified Files)

```
agents/                        ← Add memory: project + graph instructions
├── architect.md
├── code-reviewer.md
├── planner.md
├── database-reviewer.md
├── spring-webflux-reviewer.md
├── security-reviewer.md
└── build-error-resolver.md
```

---

## Appendix B — Reference Implementations

| Project | Architecture | Key Takeaway |
|---------|-------------|-------------|
| [claude-mem](https://github.com/thedotmack/claude-mem) | Hooks + Worker + SQLite + ChromaDB | Fire-and-forget pattern, 3-layer retrieval |
| [memsearch](https://github.com/zilliztech/memsearch) | Hooks + ONNX + Milvus | Zero MCP overhead, subagent isolation |
| [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | SQLite + tree-sitter | 99.2% token reduction with structural queries |
| [git-notes-memory](https://github.com/mourad-ghafiri/git-notes-memory) | git notes | Branch-aware, zero infra, tiered retrieval |
| [@mcp/server-memory](https://github.com/modelcontextprotocol/servers/tree/main/src/memory) | Knowledge graph JSONL | Entity/Relation/Observation model |
| [MemCP](https://dev.to/dalimay28/how-i-built-memcp-giving-claude-a-real-memory-15co) | Dual storage + blocking | 218x token reduction on large docs |

---

## 9. Open-Source Evaluation

Evaluated 7 solutions for persistent agent memory. Full comparison:

| Solution | Plugin-Bundleable | Offline | Semantic Search | Knowledge Graph | Infrastructure |
|----------|------------------|---------|----------------|----------------|---------------|
| **`@mcp/server-memory`** | **Yes** | **Yes** | No (keyword) | **Yes** | **None (Node)** |
| OpenMemory (mem0) | No | Partial | Yes (Qdrant) | No | Docker + Qdrant |
| Graphiti/Zep MCP | No | No | Yes (hybrid) | Yes (temporal) | Docker + Neo4j |
| memsearch | Yes (hooks) | Partial | Yes (Milvus) | No | Python + API key |
| basic-memory | Yes | Yes | No (FTS) | Yes (Markdown) | None (SQLite) |
| Memento MCP | Partial | Yes (SQLite) | Partial | Yes | SQLite or Neo4j |
| memory-mcp (yuvalsuede) | Yes | Partial | No (keyword) | No | None (JSON) |

**Selected:** `@modelcontextprotocol/server-memory`

**Why:**
- Zero infrastructure (Node.js + JSONL flat file)
- Maintained by Anthropic — aligned with Claude Code evolution
- Entity/Relation/Observation model matches our needs exactly
- Already available in current plugin tool list (`mcp__memory__*`)
- Plugin-bundleable via `.mcp.json`
- Offline-first, git-friendly storage

**What we skip (and why):**
- OpenMemory: active Claude Code bug (`mem0ai/mem0#3400`), Docker requirement
- Graphiti/Zep: requires Neo4j + Docker + OpenAI — too heavy for a plugin
- memsearch: good architecture but requires Python + embedding API key
- Semantic search: deferred — `search_nodes` keyword search is sufficient to start;
  add vector layer later if retrieval quality is a bottleneck

---

## Appendix C — Decision Log

| Decision | Choice | Why |
|----------|--------|-----|
| Build vs. use MCP server | **Use open-source** | `@mcp/server-memory` covers knowledge graph; no custom build needed |
| Knowledge graph server | `@mcp/server-memory` (Anthropic) | Zero infra, offline, maintained by Anthropic, plugin-bundleable |
| Session storage | Structured JSON files (Phase 1) | Bash-accessible, git-friendly, no DB dependency |
| Semantic search | Deferred (optional future layer) | Keyword search sufficient initially; add memsearch if needed |
| Memory location | `.claude/memory/` | Consistent across phases; git-friendly (ignore JSONL, keep JSON) |
| Agent memory scope | `project` | Team-shareable; `.claude/agent-memory/` committed to git |
| Graph model | Entity/Relation/Observation | Proven pattern from @mcp/server-memory; simple, extensible |
| Token budget | 750 tokens max at session start | Enough for context, not enough to crowd out the actual task |
