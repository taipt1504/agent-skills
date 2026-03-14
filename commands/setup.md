---
name: setup
description: >
  One-time install that writes devco-agent-skills rules and stack guidelines into
  ~/.claude/CLAUDE.md so they auto-load in EVERY Claude Code session across ALL projects.
  Optionally copies rules/ into the current project's .claude/rules/.
  Re-run after plugin updates with --update flag.
---

# /setup — Install Plugin Rules Globally

This command makes the plugin's coding standards, workflow, and Java/Spring rules
**auto-load in every Claude Code session** — not just in this repo.

## What happens

| Action | Result |
|--------|--------|
| Writes to `~/.claude/CLAUDE.md` | Rules load globally in every session |
| Copies to `.claude/rules/` (with `--project`) | Rules load for this specific project |

## Run setup now

Use the Bash tool to execute the setup script. First, locate the plugin:

```bash
# Find the installed plugin directory
PLUGIN_DIR="$(find "$HOME/.claude/plugins" -maxdepth 4 -name "setup.sh" \
  -path "*/devco-agent-skills/*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {})"

if [ -z "$PLUGIN_DIR" ]; then
  echo "❌ Plugin not found in ~/.claude/plugins"
  echo "   Ensure it is installed: claude plugin add devco-agent-skills@devco-agent-skills"
  exit 1
fi

echo "Plugin found at: $PLUGIN_DIR"
```

Then run the appropriate variant:

**Global only** (rules load everywhere):
```bash
bash "$PLUGIN_DIR/scripts/setup.sh"
```

**Global + current project rules** (recommended for new projects):
```bash
bash "$PLUGIN_DIR/scripts/setup.sh" --project
```

**Refresh after plugin update**:
```bash
bash "$PLUGIN_DIR/scripts/setup.sh" --update
```

## Verify it worked

After running setup, confirm rules are installed:
```bash
grep -c "devco-agent-skills" ~/.claude/CLAUDE.md && echo "✅ Global rules installed"
ls .claude/rules/ 2>/dev/null && echo "✅ Project rules installed" || echo "ℹ️  No project rules (run with --project)"
```

## What gets loaded where

```
~/.claude/CLAUDE.md          ← loaded EVERY session, EVERY project (this machine)
  └── Stack: Java 17+ / Spring Boot 3.x / WebFlux
  └── Architecture: Hexagonal, CQRS, DDD
  └── Critical rules: no .block(), constructor injection, 80% coverage...
  └── Workflow: PLAN → BUILD (TDD) → VERIFY → REVIEW

.claude/rules/               ← loaded only for THIS project
  ├── common/coding-style.md
  ├── common/security.md
  ├── java/reactive.md
  └── java/testing.md        (and 12 more...)
```

## Session context (hook stdout)

The `session-start` hook also outputs a **workflow reminder to Claude's context** at every session start, so Claude is reminded of the mandatory workflow even without reading CLAUDE.md explicitly.
