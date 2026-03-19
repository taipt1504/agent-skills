---
name: setup
description: Install devco-agent-skills into the current project. Copies rules, hooks, and CLAUDE.md. Includes MCP server configuration as a subcommand.
---

# /setup -- One-Time Project Install

Everything installs under `.claude/` -- one directory for all Claude context:

| File/Dir | Auto-loaded by Claude |
|----------|----------------------|
| `.claude/CLAUDE.md` | Every session for this project |
| `.claude/rules/` | Every session for this project |
| `.claude/memory/` | Restored by session-init hook |

## Run setup now

Use the Bash tool to execute the setup script. First, locate the plugin:

```bash
PLUGIN_DIR="$(find "$HOME/.claude/plugins" -maxdepth 4 -name "setup.sh" \
  -path "*/devco-agent-skills/*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {})"

if [ -z "$PLUGIN_DIR" ]; then
  echo "Plugin not found in ~/.claude/plugins"
  echo "Install it first: claude plugin add devco-agent-skills@devco-agent-skills"
  exit 1
fi

echo "Plugin found at: $PLUGIN_DIR"
```

Then run setup from the **target project's root directory**:

```bash
bash "$PLUGIN_DIR/scripts/setup.sh"
```

## Commit to version control

Share with your team by committing the generated files:

```bash
git add .claude/CLAUDE.md .claude/rules/ .claude/settings.json
git commit -m "chore: add Claude Code project context"
```

Once committed, every teammate who clones the repo gets the full context automatically -- no manual setup required.

## Optional: also install globally

To load plugin rules in **every** project on this machine:

```bash
bash "$PLUGIN_DIR/scripts/setup.sh" --global
```

## Refresh after plugin update

Safe to run multiple times -- idempotent:

```bash
bash "$PLUGIN_DIR/scripts/setup.sh" --update
```

## Verify it worked

```bash
test -f .claude/CLAUDE.md        && echo "CLAUDE.md installed"
ls .claude/rules/ 2>/dev/null    && echo "Rules installed"
ls .claude/memory/ 2>/dev/null   && echo "Memory tier installed"
```

## What gets installed

```
PROJECT_ROOT/
+-- .claude/
    +-- CLAUDE.md              <- project conventions (~400 tokens)
    +-- rules/                 <- 9 flat rule files, loaded every session
    |   +-- coding-style.md
    |   +-- security.md
    |   +-- architecture-patterns.md
    |   +-- testing.md
    |   +-- ...
    +-- memory/                <- 3-tier memory (L1/L2/L3)
    +-- settings.json          <- team auto-install (hooks + permissions)
```

## Subcommand: /setup mcp

Guided setup for MCP (Model Context Protocol) servers.

### Step 1: Audit Current State

```bash
claude mcp list
```

### Step 2: Token Budget Analysis

Recommended: <10 servers, <80 tools total. If over budget, suggest removing unused servers before adding new ones.

### Step 3: Recommended Pre-Installed Servers

| Server | Package |
|--------|---------|
| memory | @modelcontextprotocol/server-memory |
| sequential-thinking | @modelcontextprotocol/server-sequential-thinking |
| context7 | @upstash/context7-mcp |

```bash
claude mcp add memory -s user -- npx -y @modelcontextprotocol/server-memory
claude mcp add sequential-thinking -s user -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp add context7 -s user -- npx -y @upstash/context7-mcp@latest
```

### Step 4: Productivity Servers

| Server | Tools | Description |
|--------|-------|-------------|
| fetch | ~2 | URL fetch + HTML-to-Markdown |
| exa-search | ~3 | Neural web search (needs EXA_API_KEY) |
| filesystem | ~11 | Secure directory access outside CWD |
| notion | ~8 | Workspace/wiki access |

### Step 5: Core Stack Servers

| Server | Tools | Description |
|--------|-------|-------------|
| postgres | ~8 | Schema inspection, read-only queries (needs POSTGRES_CONNECTION_STRING) |
| docker | ~8 | Container lifecycle for Testcontainers |
| github | ~8 | PR/issue management (needs GITHUB_PERSONAL_ACCESS_TOKEN) |
| gradle | ~7 | Build task execution |

### Step 6: Optional Stack Servers

| Server | When to Enable |
|--------|---------------|
| redis | Project uses Spring Data Redis or Lettuce |
| kafka | Project uses Spring Kafka or Confluent |
| playwright | Project has browser-facing UI tests |

### Post-Install

- Run `claude mcp list` to verify
- Restart Claude Code to load new servers
- Never hardcode credentials -- always use environment variables
- Use read-only database users for PostgreSQL MCP
- Dev/local instances only for Redis and Kafka
