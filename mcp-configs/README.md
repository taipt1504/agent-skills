# MCP Server Configs

Curated MCP server configurations for agent productivity and the Java/Spring WebFlux stack. Security-first, token-budget-aware.

## Token Budget

Claude Code recommends **<10 MCP servers** and **<80 tools active** at a time.

| Source | Servers | ~Tools |
|--------|---------|--------|
| Recommended pre-installed (memory, sequential-thinking, context7, atlassian) | 4 | ~35 |
| + Productivity (fetch, exa-search, filesystem, notion) | +4 | ~24 |
| + Core stack (postgres, docker, github, gradle) | +4 | ~31 |
| **Total with productivity + core** | **12** | **~90** |
| + Optional stack (redis, kafka, playwright) | +3 | ~24 |
| **Max if all enabled** | **15** | **~114** |

**Strategy:** Pre-installed + productivity covers agent research needs. Add core stack servers for active Java/Spring projects. Enable optional servers only when actively needed, disable otherwise. Never enable all at once.

## Directory Structure

```
mcp-configs/
├── productivity/        # Agent productivity — research, memory, file access
│   ├── fetch.json       # URL fetch + HTML-to-Markdown (no API key)
│   ├── exa-search.json  # Neural web search with full page content
│   ├── filesystem.json  # Secure access to directories outside CWD
│   └── notion.json      # Notion workspace/wiki access
├── core/                # Java/Spring stack — always-on for dev
│   ├── postgres.json    # Schema inspection, read-only queries
│   ├── docker.json      # Container lifecycle (Testcontainers)
│   ├── github.json      # PR/issue management
│   └── gradle.json      # Build task execution
└── optional/            # Enable per-project as needed
    ├── redis.json       # Cache inspection
    ├── kafka.json       # Topic management
    └── playwright.json  # Browser E2E tests
```

## Recommended Pre-Installed Servers

These should be configured at user-level before using this plugin. They are foundational for agent quality:

| Server | Package | Why |
|--------|---------|-----|
| `memory` | `@modelcontextprotocol/server-memory` | Knowledge-graph persistent memory — entities, relations, observations across sessions |
| `sequential-thinking` | `@modelcontextprotocol/server-sequential-thinking` | Structured chain-of-thought reasoning for complex problem decomposition |
| `context7` | `@upstash/context7-mcp` | Live, version-pinned library documentation — eliminates hallucinated APIs |
| `mcp-atlassian` | `mcp-atlassian` | Jira + Confluence access for teams using Atlassian |

Install these first if not already configured:

```bash
claude mcp add memory -s user -- npx -y @modelcontextprotocol/server-memory
claude mcp add sequential-thinking -s user -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp add context7 -s user -- npx -y @upstash/context7-mcp@latest
```

## How to Use

### Quick Setup

Run `/mcp-setup` inside Claude Code for guided installation with token budget tracking.

### Manual Install

Each JSON file contains a `_install` field with the exact `claude mcp add` command. Example:

```bash
# 1. Set required env vars (see _env_required in each file)
export POSTGRES_CONNECTION_STRING="postgresql://user:pass@localhost:5432/mydb"

# 2. Run the install command from the JSON file
claude mcp add postgres -s user -- npx -y @modelcontextprotocol/server-postgres $POSTGRES_CONNECTION_STRING
```

### Scope

All configs use `-s user` (user scope) so they're available across all projects. Use `-s project` if you only need a server for a specific project.

### Remove a Server

```bash
claude mcp remove <server-name>
```

### List Active Servers

```bash
claude mcp list
```

## Environment Variables

**Never hardcode credentials in MCP configs.** Each JSON file lists required env vars in `_env_required` and examples in `_env_example`. Set them in your shell profile or `.env` file.

## Security Notes

### Productivity Servers
- **Fetch**: Read-only HTTP GET. No credentials sent. Respects robots.txt.
- **Exa Search**: API key has usage-based billing. Only search queries are sent.
- **Filesystem**: ONLY exposes directories you list in args. Never add `~/` or system paths.
- **Notion**: Use read-only integration tokens. Share only specific pages, not entire workspace.

### Stack Servers
- **PostgreSQL**: Use read-only connection strings for schema inspection
- **Docker**: Only exposes local Docker socket — no remote daemon access
- **GitHub**: Requires `GITHUB_TOKEN` with minimal scopes (repo, read:org)
- **Gradle**: Executes build tasks — review task names before running
- **Redis/Kafka**: Dev/local instances only — never point at production
- **Playwright**: Runs a local browser — no network access beyond localhost by default
