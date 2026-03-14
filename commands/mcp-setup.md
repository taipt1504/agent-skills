# /mcp-setup — MCP Server Configuration Guide

Guided setup for MCP (Model Context Protocol) servers — agent productivity tools and Java/Spring WebFlux stack integrations.

## Trigger

User runs `/mcp-setup`

## Workflow

### Step 1: Audit Current State

Run `claude mcp list` to discover currently configured MCP servers.

```bash
claude mcp list
```

Parse the output and present a summary table:

```
## Current MCP Servers

| Server | Scope | Status |
|--------|-------|--------|
| (list from output) | user/project | active |

**Currently active:** X servers, ~Y estimated tools
```

### Step 2: Token Budget Analysis

Present the token budget table showing current vs planned usage:

```
## Token Budget (recommended: <10 servers, <80 tools)

| Source | Servers | ~Tools |
|--------|---------|--------|
| Currently configured | X | ~Y |
| + Productivity (fetch, exa-search, filesystem, notion) | +4 | ~24 |
| + Core stack (postgres, docker, github, gradle) | +4 | ~31 |
| **Projected total** | **X+8** | **~Y+55** |

Status: [WITHIN BUDGET / APPROACHING LIMIT / OVER BUDGET]
```

If already over 80 tools, warn and suggest removing unused servers before adding new ones.

### Step 3: Check Recommended Pre-Installed Servers

Verify these foundational servers are already configured. If missing, offer to install:

```
## Recommended Pre-Installed Servers

These are foundational for agent quality across all projects:

| Server | Status | Package |
|--------|--------|---------|
| memory | [installed/MISSING] | @modelcontextprotocol/server-memory |
| sequential-thinking | [installed/MISSING] | @modelcontextprotocol/server-sequential-thinking |
| context7 | [installed/MISSING] | @upstash/context7-mcp |

Install commands for any missing:
claude mcp add memory -s user -- npx -y @modelcontextprotocol/server-memory
claude mcp add sequential-thinking -s user -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp add context7 -s user -- npx -y @upstash/context7-mcp@latest
```

### Step 4: Install Productivity Servers

Present agent productivity servers that improve research, knowledge access, and file management:

```
## Productivity Servers (agent research & knowledge)

### 1. Fetch — URL fetch + HTML-to-Markdown (~2 tools)
Read documentation, Stack Overflow, blog posts — no API key needed.
claude mcp add fetch -s user -- npx -y @modelcontextprotocol/server-fetch

### 2. Exa Search — neural web search with full content (~3 tools)
Superior to basic search: returns full page content, semantically ranked.
Required env: EXA_API_KEY (get from exa.ai)
claude mcp add exa-search -s user -e EXA_API_KEY -- npx -y exa-mcp-server

### 3. Filesystem — secure directory access outside CWD (~11 tools)
Access shared configs, reference projects, multi-repo setups.
Customize paths in the command below:
claude mcp add filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem ~/projects

### 4. Notion — workspace/wiki access (~8 tools)
Read architecture docs, ADRs, runbooks from Notion.
Required env: OPENAPI_MCP_HEADERS (Notion integration token)
claude mcp add notion -s user -e OPENAPI_MCP_HEADERS -- npx -y @notionhq/notion-mcp-server
```

**Ask the user:** "Which productivity servers would you like to install? (all / select by number / skip)"

### Step 5: Install Core Stack Servers

Present the 4 core server install commands for Java/Spring development:

```
## Core Stack Servers (Java/Spring development)

### 5. PostgreSQL — schema inspection, read-only queries (~8 tools)
Required env: POSTGRES_CONNECTION_STRING
claude mcp add postgres -s user -- npx -y @modelcontextprotocol/server-postgres $POSTGRES_CONNECTION_STRING

### 6. Docker — container lifecycle for Testcontainers (~8 tools)
No env vars required.
claude mcp add docker -s user -- docker run -i --rm -v /var/run/docker.sock:/var/run/docker.sock docker/mcp:latest

### 7. GitHub — PR/issue management (~8 tools)
Required env: GITHUB_PERSONAL_ACCESS_TOKEN
claude mcp add github -s user -e GITHUB_PERSONAL_ACCESS_TOKEN -- npx -y @modelcontextprotocol/server-github

### 8. Gradle — build task execution (~7 tools)
No env vars required.
claude mcp add gradle -s user -- npx -y gradle-mcp-server
```

**Ask the user:** "Which core stack servers would you like to install? (all / select by number / skip)"

### Step 6: Optional Stack Servers

Ask which optional servers the user needs based on their project:

```
## Optional Stack Servers (enable per-project as needed)

### 9. Redis — cache inspection (~8 tools)
Enable if: project uses Spring Data Redis or Lettuce
Required env: REDIS_URL
claude mcp add redis -s user -- npx -y mcp-redis --url $REDIS_URL

### 10. Kafka — topic management (~8 tools)
Enable if: project uses Spring Kafka or Confluent
Required env: CONFLUENT_CLOUD_API_KEY, CONFLUENT_CLOUD_API_SECRET
claude mcp add kafka -s user -e CONFLUENT_CLOUD_API_KEY -e CONFLUENT_CLOUD_API_SECRET -- npx -y @confluentinc/mcp-confluent

### 11. Playwright — browser E2E tests (~8 tools)
Enable if: project has browser-facing UI tests
No env vars required.
claude mcp add playwright -s user -- npx -y @playwright/mcp@latest
```

**Ask the user:** "Which optional servers do you need? (none / select by number)"

### Step 7: Post-Install Verification

After installation, provide verification steps:

```
## Verification

1. List all configured servers:
   claude mcp list

2. Restart Claude Code to load new servers:
   Exit and re-launch your Claude Code session.

3. Verify tools are available:
   After restart, check that new tools appear in your tool list.

## Managing Servers

- Remove: claude mcp remove <server-name>
- Disable temporarily: claude mcp remove <server-name> (re-add later)
- Config reference: see mcp-configs/ directory in this plugin

## Recommended Configurations

For solo dev:       pre-installed + fetch + filesystem + core stack (~8 servers, ~66 tools)
For team dev:       + notion or atlassian + github (~10 servers, ~82 tools)
For full stack:     + redis/kafka as needed (disable when not in use)
```

## Important Notes

- **Never hardcode credentials** — always use environment variables
- **Use read-only database users** for PostgreSQL MCP
- **Dev/local instances only** for Redis and Kafka — never production
- **Restart required** after adding/removing MCP servers
- **Token budget** — if over 80 tools, disable servers you're not actively using
- **Filesystem security** — only expose specific directories, never home root
