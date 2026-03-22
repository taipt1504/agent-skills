# Context & Memory Management Review

> **Reviewer**: memory-reviewer | **Grade**: C+ (Design B+, Implementation D)
> **Scope**: Plugin code only (`scripts/memory/`, `scripts/hooks/`). `docs/` excluded (document storage, not plugin structure).

---

## 1. Memory Architecture

### Designed vs Actual

| Tier | Path | Purpose | Actually Works? |
|------|------|---------|----------------|
| L1 Session | `.claude/memory/sessions/` | Last 5 sessions | **Partially** (index corrupted) |
| L2 Knowledge | `.claude/memory/knowledge/` | decisions, patterns, blockers | **NO** (never created) |
| L2 Context | `.claude/memory/context/` | project state, active work | **NO** (never created) |
| L3 Graph | MCP `mcp__memory__*` tools | Knowledge graph | **NO** (not wired to hooks) |
| Debug KB | `.claude/memory/debug-knowledge.md` | Fix patterns | **NO** (never created) |

### Root Cause: init.sh Guard Bug

```bash
# Line 23 of init.sh — THE BUG
if [ ! -d ".claude/memory" ]; then
  # All creation logic is inside this block
  # But .claude/memory/ already exists (created by sessions/)
  # So this NEVER runs after first initialization
fi
```

**Fix**: Check each subdirectory independently:
```bash
[ ! -d ".claude/memory/knowledge" ] && mkdir -p ".claude/memory/knowledge"
[ ! -d ".claude/memory/context" ] && mkdir -p ".claude/memory/context"
# ... create files ...
```

---

## 2. Session Lifecycle

### Flow

```
SESSION START (session-init.sh)
  ├── Auto-init memory (if .claude/memory/ missing — broken guard)
  ├── Detect project type (Gradle/Maven, WebFlux/MVC, Summer)
  ├── Inject bootstrap SKILL.md (~1,320 tokens)
  ├── Inject L2 memory context (DEAD — active-work.json doesn't exist)
  └── Output project detection summary

DURING SESSION (compact-advisor.sh)
  ├── Count Edit|Write|MultiEdit tool calls only
  ├── Stage 1 (50 calls): "Unload meta skills"
  ├── Stage 2 (75 calls): "Unload unused domain skills"
  └── Stage 3 (100 calls): "Full compact recommended"

PRE-COMPACT (pre-compact.sh — strict profile only)
  ├── Capture git diff file list
  ├── Write recovery JSON (but nothing reads it)
  └── ⚠️ SHELL INJECTION vulnerability in Python heredoc

SESSION END (session-save.sh)
  ├── Capture git diff, staged, committed, uncommitted files
  ├── Detect test files modified
  ├── Write session markdown to .claude/sessions/
  ├── Write session JSON to .claude/memory/sessions/ (via write-session.sh)
  ├── Append debug fixes to debug-knowledge.md (file doesn't exist)
  └── Write learning signals to .claude/signals/ (never consumed)
```

### Critical Issues

1. **Dual session directories**: `.claude/sessions/` (markdown) AND `.claude/memory/sessions/` (JSON) — confusing
2. **Session index corrupted**: 21 duplicate entries for same session ID (no file locking)
3. **Transcript counters always 0**: `CLAUDE_TRANSCRIPT_PATH` is unset, so user_messages and tool_calls show 0
4. **compact-advisor undercounts**: Only counts Edit|Write|MultiEdit — misses Read, Bash, Grep, Glob

---

## 3. Context Injection Analysis

### What Actually Gets Injected at Session Start

| Source | Tokens | Status |
|--------|--------|--------|
| Bootstrap SKILL.md | ~1,320 | **Working** |
| "EXTREMELY IMPORTANT" wrapper | ~15 | Working |
| Memory context Tier 0 (recent sessions) | 0 | **Dead code** — index corrupted |
| Memory context Tier 1 (active work) | 0 | **Dead code** — file doesn't exist |
| Memory context Tier 2 (latest session) | 0 | **Dead code** — no valid data |
| Project detection summary | ~30 | Working (if Spring) |
| **Total actual** | **~1,365** | |

### Token Budget Config vs Reality

```json
// config.json says:
"token_budget": { "tier0_index": 50, "tier1_context": 200, "tier2_full": 500, "max_total": 750 }
```

**Reality**: Bootstrap alone (~1,320 tokens) exceeds the 750 "max_total". Budget numbers are **fictional — never enforced by any code**.

---

## 4. Cross-Agent Context Sharing

### Current State: **Non-Existent** (1/5)

| Agent | Gets Context From | Writes Context To |
|-------|-------------------|-------------------|
| Planner | Bootstrap only | Nothing |
| Spec-writer | Bootstrap only | Nothing |
| Implementer | Bootstrap + manual prompt | Nothing |
| Reviewer | Bootstrap only | Nothing |

No automatic context propagation. Plans, specs, implementation decisions — nothing is persisted for downstream agents.

### What Should Happen

```
PLAN phase:
  planner → writes .claude/plans/feature-x.md

SPEC phase:
  spec-writer → reads .claude/plans/feature-x.md
  spec-writer → writes .claude/specs/feature-x.md

BUILD phase:
  implementer-1 → reads .claude/specs/feature-x.md (task 1 section)
  implementer-2 → reads .claude/specs/feature-x.md (task 2 section)

REVIEW phase:
  reviewer → reads .claude/specs/feature-x.md (all scenarios)
  reviewer → reads git diff (all changes)
```

---

## 5. Security Issue: Shell Injection

**pre-compact.sh** (lines 41-50):
```bash
ACTIVE_FILES=$(python3 -c "
...
for line in '''$STAGED
$MODIFIED'''.strip().splitlines():
```

If a filename contains `'''`, this breaks the Python triple-quote string and could execute arbitrary code.

**Fix**: Use environment variables instead of string interpolation:
```bash
ACTIVE_FILES=$(STAGED="$STAGED" MODIFIED="$MODIFIED" python3 -c "
import os
for line in (os.environ['STAGED'] + '\n' + os.environ['MODIFIED']).strip().splitlines():
...")
```

---

## 6. Memory vs Claude's Native Auto-Memory

| Feature | Plugin Memory | Claude Native |
|---------|--------------|---------------|
| Session tracking | Custom (broken) | None |
| Project knowledge | L2 (never created) | `project` type memories |
| User preferences | Not captured | `user` type memories |
| Feedback | Not captured | `feedback` type memories |
| Implementation | Shell scripts + Python | Built-in, always works |

**Recommendation**: Leverage Claude's native auto-memory for qualitative knowledge (preferences, decisions, patterns). Use plugin memory only for structured session data (git diffs, test counts, phase tracking).

---

## 7. Continuous Learning System

### Status: Isolated & Incomplete

- References `observe.sh` hook that **doesn't exist**
- Uses separate path (`~/.claude/homunculus/`) — completely isolated from plugin memory
- `config.json` defines instinct scoring but no consumer exists
- Observer agent (`agents/observer.md`) is defined but never triggered

The continuous learning system operates on a **completely separate data path** from the core memory system. They don't share data or coordinate.

---

## Priority Summary

| Priority | Issue | Effort |
|----------|-------|--------|
| **Critical** | Cross-agent context sharing doesn't exist | High |
| **High** | init.sh guard bug breaks L2/L3/debug KB | Low (1-line fix) |
| **High** | Session index race condition (no flock) | Medium |
| **High** | pre-compact.sh shell injection | Low |
| **High** | Unify dual session directories | Medium |
| **Medium** | Compact advisor undercounts (Edit-only) | Low |
| **Medium** | Token budget config is unenforced | Low-Medium |
| **Medium** | Evaluate native auto-memory overlap | Design |
| **Low** | Debug KB growth control + read integration | Low |
| **Low** | Learning signal consumer missing | Medium |

---

## Recommended Architecture

```
.claude/
├── memory/
│   └── sessions/        ← Unified (merge .claude/sessions/ here)
│       ├── index.json   ← With flock locking
│       └── *.json       ← Session data
├── workflow-state.json  ← NEW: phase, approvals, task progress
├── plans/               ← NEW: persisted plan artifacts
│   └── feature-x.md
├── specs/               ← NEW: persisted spec artifacts
│   └── feature-x.md
└── handoffs/            ← NEW: structured handoff documents
    └── layer-0-to-1.md
```

This architecture:
- Persists workflow state for compaction resilience
- Provides file-based handoffs between agents
- Unifies session storage
- Enables cross-session workflow continuation
