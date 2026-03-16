---
name: status
description: >
  Check devco-agent-skills installation status for this project.
  Shows what's installed, what's missing, and how to fix it.
---

# /status — Installation Health Check

Run a health check to see what's installed and what needs setup.

Use the Bash tool to execute:

```bash
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     devco-agent-skills — Installation Status     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

PASS="✅"
FAIL="❌"
WARN="⚠️ "
ALL_OK=true

# CLAUDE.md
if [ -f ".claude/CLAUDE.md" ]; then
  echo "  $PASS  CLAUDE.md              — project rules loaded"
elif grep -q "devco-agent-skills" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  echo "  $WARN  CLAUDE.md              — global only (run /setup for project scope)"
else
  echo "  $FAIL  CLAUDE.md              — MISSING"
  ALL_OK=false
fi

# WORKING_WORKFLOW.md
if [ -f ".claude/WORKING_WORKFLOW.md" ]; then
  echo "  $PASS  WORKING_WORKFLOW.md    — workflow reference available"
else
  echo "  $FAIL  WORKING_WORKFLOW.md    — MISSING"
  ALL_OK=false
fi

# Rules
if [ -d ".claude/rules" ]; then
  RULE_COUNT=$(find .claude/rules -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  echo "  $PASS  Rules                  — $RULE_COUNT rule files"
else
  echo "  $FAIL  Rules                  — MISSING (.claude/rules/)"
  ALL_OK=false
fi

# Hook wiring
if [ -f ".claude/settings.json" ] && grep -q "session-start" ".claude/settings.json" 2>/dev/null; then
  echo "  $PASS  Hook wiring            — configured in settings.json"
else
  echo "  $FAIL  Hook wiring            — MISSING (.claude/settings.json)"
  ALL_OK=false
fi

# Marketplace config
if [ -f ".claude/settings.json" ] && grep -q "extraKnownMarketplaces" ".claude/settings.json" 2>/dev/null; then
  echo "  $PASS  Team auto-install      — marketplace configured for teammates"
else
  echo "  $WARN  Team auto-install      — not configured (teammates must install manually)"
fi

# Memory
if [ -d ".claude/memory" ] && [ -f ".claude/memory/sessions/index.json" ]; then
  SESSION_COUNT=$(python3 -c "import json; print(len(json.load(open('.claude/memory/sessions/index.json')).get('sessions',[])))" 2>/dev/null || echo "0")
  echo "  $PASS  Memory                 — initialized ($SESSION_COUNT sessions)"
else
  echo "  $WARN  Memory                 — not initialized (auto-creates on first session)"
fi

# Knowledge graph
if [ -f ".claude/memory/knowledge-graph.jsonl" ]; then
  GRAPH_LINES=$(wc -l < ".claude/memory/knowledge-graph.jsonl" 2>/dev/null | tr -d ' ')
  echo "  $PASS  Knowledge graph        — $GRAPH_LINES entries"
else
  echo "  $WARN  Knowledge graph        — not yet populated"
fi

# MCP server
if [ -f ".mcp.json" ] && grep -q "server-memory" ".mcp.json" 2>/dev/null; then
  echo "  $PASS  MCP memory server      — registered in .mcp.json"
else
  echo "  $WARN  MCP memory server      — not registered"
fi

echo ""

if [ "$ALL_OK" = false ]; then
  echo "  ────────────────────────────────────────────────"
  echo "  Run /setup to install missing components."
  echo "  Then: git add .claude/ && git commit -m 'chore: add Claude Code context'"
  echo ""
else
  echo "  All components installed. Plugin is fully operational."
  echo ""
fi
```
