# Token Optimization Patterns

> Strategies for managing context window budget effectively.

---

## The Token Economics Problem

Claude Code's context window is finite. Every instruction, skill, rule, and tool result consumes tokens. Unmanaged, context bloat leads to:
- Compaction too early (losing important context)
- Degraded response quality (too much noise)
- Higher costs (wasted tokens on irrelevant content)

---

## 1. CLAUDE.md Optimization

CLAUDE.md is loaded **every session**. Every line counts.

### Techniques

| Technique | Example |
|-----------|---------|
| Tables over prose | `\| Command \| Purpose \|` vs paragraph descriptions |
| Reference, don't duplicate | "See skill: `kafka-patterns`" vs embedding Kafka docs |
| Short imperative rules | "No `.block()` in reactive code" vs explaining why |
| Remove obvious rules | Don't state things Claude already knows |
| Critical rules only | Focus on project-specific constraints |

### Size Target
Keep CLAUDE.md under 200 substantive lines. Our current CLAUDE.md is well-structured with tables — this is the right approach.

---

## 2. Trigger-Table Lazy Loading

Instead of loading all skills upfront:

```
┌──────────────────────────────────────┐
│ CLAUDE.md loads trigger table (small) │
│                                       │
│ "kafka" → kafka-patterns skill        │
│ "redis" → redis-patterns skill        │
│ "test"  → tdd-workflow skill          │
│ "security" → security-review skill    │
└──────────────┬───────────────────────┘
               │
               │ User mentions "kafka"
               ▼
┌──────────────────────────────────────┐
│ kafka-patterns SKILL.md loaded       │
│ (200-500 lines, on demand)           │
└──────────────────────────────────────┘
```

**Result:** Baseline context reduced by 50%+. Skills only load when relevant.

---

## 3. Model Routing

Use the cheapest model that can handle the task:

| Task | Model | Token Cost |
|------|-------|-----------|
| Formatting, simple checks | Haiku | Lowest |
| Code writing, review | Sonnet | Medium |
| Architecture, planning | Opus | Highest |

### Configuration

```json
{
  "model": "sonnet",
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "haiku"
  }
}
```

This uses Sonnet for the main agent and Haiku for subagents — significant cost reduction for background tasks.

---

## 4. Thinking Token Budget

```json
{
  "env": {
    "MAX_THINKING_TOKENS": "10000"
  }
}
```

Default thinking token cap is 31,999. Reducing to 10,000 cuts hidden cost by ~70% with minimal quality impact for routine coding tasks. Reserve higher budgets for complex reasoning.

---

## 5. Autocompact Threshold

```json
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50"
  }
}
```

Default: compaction at 95% context usage.
Recommended: **50%** — quality degrades significantly before reaching 95%.

**Why:** By the time you hit 95%, the model is already struggling with the context load. Compacting at 50% keeps sessions healthier.

---

## 6. Strategic Compaction (PreCompact Hook)

Before compaction, save critical state:

```javascript
// pre-compact.js
// 1. Log compaction timestamp
// 2. Annotate active session file with compaction marker
// 3. Save current task list / progress state
```

### What Survives Compaction

| Survives | Lost |
|----------|------|
| CLAUDE.md instructions | Intermediate reasoning |
| TodoWrite task list | Previously-read file contents |
| Memory files | Tool call history |
| Git state | Verbally-stated preferences |
| Files on disk | Prior conversation context |

### Suggest Compact Hook

Every ~50 tool calls, suggest compaction with guidance on what to preserve:

```javascript
// suggest-compact.js (PreToolUse, async)
const toolCallCount = getToolCallCount();
if (toolCallCount % 50 === 0) {
  console.error('[ECC] Consider running /compact. Preserve: current task, open files, test results.');
}
```

---

## 7. MCP-as-CLI Strategy

**Problem:** MCP servers add tools to the context, even when not in use.
**Solution:** Replace MCPs with CLI wrappers in skills/commands.

```yaml
# Instead of MCP server with 15 tools always loaded:
# Use CLI in a skill that loads on demand:

## When to Activate
- When user needs to interact with GitHub PRs or issues

## Commands
- `gh pr list` — list PRs
- `gh pr view 123` — view PR details
- `gh issue create` — create issue
```

**Rule of thumb:** "Have 20-30 MCPs in config, but keep under 10 enabled / under 80 tools active."

---

## 8. mgrep for Reduced Output

Standard grep output is verbose and consumes tokens. `mgrep` provides ~50% token reduction:
- Deduplicates results
- Summarizes matches
- Returns structured output

---

## 9. Content-Hash Cache Pattern

For expensive file processing, cache results using SHA-256:

```
file.java → SHA-256 → {hash}.json

Benefits:
- Path-independent (rename = cache hit)
- Auto-invalidating (content change = cache miss)
- O(1) lookup (no index file)
```

---

## 10. Applying to Our Plugin

### Quick Wins
1. Set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` in our hook config
2. Add a `suggest-compact` hook at ~50 tool calls
3. Keep CLAUDE.md tables-focused (already doing this)
4. Ensure skills have explicit "When to Activate" triggers

### Medium Effort
1. Add `pre-compact.js` hook to save session state
2. Route subagents to Haiku where possible
3. Reduce MCP server count

### Longer Term
1. Implement session persistence (SessionStart/Stop hooks)
2. Add cost tracking hook
3. Implement trigger-table lazy loading
