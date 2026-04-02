---
name: dc-setup
description: Install devco-agent-skills into the current project. Copies rules, hooks, and CLAUDE.md. Includes MCP server configuration as a subcommand.
---

# /dc-setup -- One-Time Project Install

Everything installs under `.claude/` -- one directory for all Claude context:

| File/Dir | Auto-loaded by Claude |
|----------|----------------------|
| `.claude/CLAUDE.md` | Every session for this project |
| `.claude/rules/` | Every session for this project |
| `.claude/memory/` | Restored by session-init hook |

## Run setup now

Use the Bash tool to execute the **Team Kit installer**. First, locate the plugin:

```bash
PLUGIN_DIR="$(find "$HOME/.claude/plugins" -maxdepth 4 -name "setup-kit.sh" \
  -path "*/devco-agent-skills/*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {})"

if [ -z "$PLUGIN_DIR" ]; then
  echo "Plugin not found in ~/.claude/plugins"
  echo "Install it first: claude plugin add devco-agent-skills@devco-agent-skills"
  exit 1
fi

echo "Plugin found at: $PLUGIN_DIR"
```

Then run the full setup from the **target project's root directory**:

```bash
# Interactive (recommended for first install)
bash "$PLUGIN_DIR/scripts/setup-kit.sh"

# Or non-interactive with mode preset
bash "$PLUGIN_DIR/scripts/setup-kit.sh" --mode standard

# With team features enabled
bash "$PLUGIN_DIR/scripts/setup-kit.sh" --mode standard --team
```

This runs all 6 setup phases: core install, plugin config, project detection, hook registration, MCP suggestions, and validation.

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
bash "$PLUGIN_DIR/scripts/setup-kit.sh" --mode standard
```

## Validate installation

```bash
bash "$PLUGIN_DIR/scripts/setup-kit.sh" --validate
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

## Phase 3: MCP Server Setup

After project-profile.json is written, suggest relevant MCP servers based on detected stack:

| Stack Detected | Suggested MCP | Config Source |
|----------------|---------------|---------------|
| Any Java project | context7, sequential-thinking | `mcp-configs/core/context7.json`, `mcp-configs/core/sequential-thinking.json` |
| PostgreSQL in deps | PostgreSQL MCP | `mcp-configs/core/postgres.json` |
| Redis in deps | Redis MCP | `mcp-configs/optional/redis.json` |
| Kafka in deps | Kafka MCP | `mcp-configs/optional/kafka.json` |
| Docker/Testcontainers | Docker MCP | `mcp-configs/core/docker.json` |
| GitHub remote | GitHub MCP | `mcp-configs/core/github.json` |
| Memory desired | SimpleMem MCP | `mcp-configs/optional/memory.json` |

**Flow:**

1. Read `project-profile.json` for stack detection
2. Match detected dependencies against MCP suggestion table
3. Present suggestions to user (only relevant ones, not all)
4. User selects which to install
5. Merge selected MCP configs into `.claude/settings.json` `mcpServers` section
6. Run health check on each installed MCP server

### Audit Current State

Before suggesting new servers, check what's already installed:

```bash
claude mcp list
```

Recommended: <10 servers, <80 tools total. If over budget, suggest removing unused servers before adding new ones.

### Core Servers (recommended for all Java projects)

| Server | Package | Description |
|--------|---------|-------------|
| context7 | @upstash/context7-mcp@latest | Library documentation lookup |
| sequential-thinking | @modelcontextprotocol/server-sequential-thinking | Step-by-step reasoning |
| docker | @modelcontextprotocol/server-docker | Container lifecycle for Testcontainers |
| github | @modelcontextprotocol/server-github | PR/issue management (needs GITHUB_TOKEN) |
| postgres | @modelcontextprotocol/server-postgres | Schema inspection, queries (needs DATABASE_URL) |

### Optional Servers (stack-dependent)

| Server | Package | When to Enable |
|--------|---------|---------------|
| redis | @modelcontextprotocol/server-redis | Project uses Spring Data Redis or Lettuce |
| kafka | @modelcontextprotocol/server-kafka | Project uses Spring Kafka |
| memory | @modelcontextprotocol/server-memory | Cross-session knowledge graph desired |

### Productivity Servers

| Server | Tools | Description |
|--------|-------|-------------|
| fetch | ~2 | URL fetch + HTML-to-Markdown |
| exa-search | ~3 | Neural web search (needs EXA_API_KEY) |
| filesystem | ~11 | Secure directory access outside CWD |
| notion | ~8 | Workspace/wiki access |

### Post-Install

- Run `claude mcp list` to verify
- Restart Claude Code to load new servers
- Never hardcode credentials -- always use environment variables
- Use read-only database users for PostgreSQL MCP
- Dev/local instances only for Redis and Kafka
