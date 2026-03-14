# Agent Skills

A curated collection of skills, agents, commands, rules, and hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — optimized for **Java 17+ Spring WebFlux** backend development.

Provides a complete development workflow: planning → spec → TDD → verification → multi-agent code review → continuous learning. All enforced automatically through hooks and rules.

## Quick Start

### 1. Install

#### Method 1: GitHub Marketplace (Recommended)

```bash
# Register the marketplace source (one-time)
/plugin marketplace add taipt1504/agent-skills

# Install the plugin
/plugin install devco-agent-skills
```

#### Method 2: npm

```bash
npm install -g @devco/agent-skills
claude plugin install ./node_modules/@devco/agent-skills
```

#### Method 3: Manual Clone (Fallback)

```bash
git clone https://github.com/taipt1504/agent-skills.git ~/.claude/plugins/agent-skills
claude plugin install ~/.claude/plugins/agent-skills
```

### 2. Configure Hooks

Hooks are registered automatically when installed via marketplace or npm. To configure manually, add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "command": ".claude/scripts/hooks/session-start.sh" }
    ],
    "SessionEnd": [
      { "command": ".claude/scripts/hooks/session-end.sh" }
    ],
    "PreToolUse": [
      { "command": ".claude/scripts/hooks/suggest-compact.sh" }
    ],
    "PostToolUse": [
      { "command": ".claude/scripts/hooks/java-compile-check.sh" },
      { "command": ".claude/scripts/hooks/java-format.sh" }
    ],
    "PreCompact": [
      { "command": ".claude/scripts/hooks/pre-compact.sh" }
    ],
    "Stop": [
      { "command": ".claude/scripts/hooks/check-debug-statements.sh" },
      { "command": ".claude/scripts/hooks/evaluate-session.sh" }
    ]
  }
}
```

### 3. Add Project Guidelines (Optional)

Copy the template to your project root and customize:

```bash
cp templates/PROJECT_GUIDELINES_TEMPLATE.md ./PROJECT_GUIDELINES.md
```

### 4. Start a Session

Claude Code will automatically load the workflow. Start with `/plan` for any non-trivial task.

---

## Team Onboarding

### Per Developer (One-Time)

```bash
# Register the marketplace source
/plugin marketplace add taipt1504/agent-skills

# Install the plugin
/plugin install devco-agent-skills
```

### Per Machine

Enable hooks in `~/.claude/settings.json` (see [Configure Hooks](#2-configure-hooks) above). Hook profiles (`minimal`, `standard`, `strict`) are controlled via the `HOOK_PROFILE` env var.

### Per Project Repo

Create `PROJECT_GUIDELINES.md` at the project root:

```bash
cp templates/PROJECT_GUIDELINES_TEMPLATE.md /path/to/your/project/PROJECT_GUIDELINES.md
```

This file overrides generic conventions with project-specific rules (architecture decisions, naming conventions, dependency choices, etc.).

### Shared Settings (Optional)

Commit a `.claude/settings.json` at the project root to share hook configuration and plugin settings across the team. This ensures every developer gets the same hooks without manual setup.

---

## Structure

```
agent-skills/
├── CLAUDE.md                              # Global context auto-loaded by Claude Code
├── WORKING_WORKFLOW.md                    # 7-phase mandatory workflow reference
├── README.md
├── mcp-configs/                           # 11 MCP server configs (4 productivity + 4 core + 3 optional)
│   ├── README.md
│   ├── productivity/
│   │   ├── fetch.json
│   │   ├── exa-search.json
│   │   ├── filesystem.json
│   │   └── notion.json
│   ├── core/
│   │   ├── postgres.json
│   │   ├── docker.json
│   │   ├── github.json
│   │   └── gradle.json
│   └── optional/
│       ├── redis.json
│       ├── kafka.json
│       └── playwright.json
├── agents/                                # 14 specialized sub-agents
│   ├── architect.md
│   ├── blackbox-test-runner.md
│   ├── build-error-resolver.md
│   ├── code-reviewer.md
│   ├── database-reviewer.md
│   ├── e2e-runner.md
│   ├── performance-reviewer.md
│   ├── planner.md
│   ├── rabbitmq-reviewer.md
│   ├── refactor-cleaner.md
│   ├── security-reviewer.md
│   ├── spring-reviewer.md
│   ├── spring-webflux-reviewer.md
│   └── tdd-guide.md
├── commands/                              # 21 slash commands
│   ├── adr.md
│   ├── api-doc.md
│   ├── build-fix.md
│   ├── checkpoint.md
│   ├── code-review.md
│   ├── db-migrate.md
│   ├── e2e.md
│   ├── eval.md
│   ├── evolve.md
│   ├── instinct.md
│   ├── learn.md
│   ├── mcp-setup.md
│   ├── orchestrate.md
│   ├── plan.md
│   ├── refactor-clean.md
│   ├── resume-session.md
│   ├── save-session.md
│   ├── setup.md
│   ├── skill-create.md
│   ├── spec.md
│   └── verify.md
├── rules/                                 # 15 behavioral rules (two-layer)
│   ├── common/                            # Language-agnostic workflow rules
│   │   ├── agents.md
│   │   ├── coding-style.md
│   │   ├── development-workflow.md
│   │   ├── git-workflow.md
│   │   ├── hooks.md
│   │   ├── patterns.md
│   │   ├── performance.md
│   │   ├── security.md
│   │   └── spec-driven.md
│   └── java/                              # Java/Spring-specific rules
│       ├── api-design.md
│       ├── coding-style.md
│       ├── observability.md
│       ├── reactive.md
│       ├── security.md
│       └── testing.md
├── scripts/
│   └── hooks/                             # 10 lifecycle hook scripts
│       ├── check-debug-statements.sh
│       ├── cost-tracker.sh
│       ├── evaluate-session.sh
│       ├── java-compile-check.sh
│       ├── java-format.sh
│       ├── pre-compact.sh
│       ├── run-with-flags.sh
│       ├── session-end.sh
│       ├── session-start.sh
│       └── suggest-compact.sh
├── skills/                                # 24 skill definitions
│   ├── api-design/
│   ├── blackbox-test/
│   ├── coding-standards/
│   ├── continuous-learning-v2/
│   ├── database-migrations/
│   ├── grpc-patterns/
│   ├── hexagonal-arch/
│   ├── java-patterns/
│   ├── jpa-patterns/
│   ├── kafka-patterns/
│   ├── mysql-patterns/
│   ├── observability-patterns/
│   ├── postgres-patterns/
│   ├── rabbitmq-patterns/
│   ├── redis-patterns/
│   ├── security-review/
│   ├── solution-design/
│   ├── spring-mvc-patterns/
│   ├── spring-webflux-patterns/
│   ├── springboot-patterns/
│   ├── springboot-security/
│   ├── strategic-compact/
│   ├── tdd-workflow/
│   └── verification/
└── templates/
    └── PROJECT_GUIDELINES_TEMPLATE.md     # Project-level config template
```

---

## Skills (24)

| Skill | Description |
|---|---|
| [api-design](./skills/api-design/) | RESTful and reactive API design standards — URL conventions, request/response patterns, error handling, pagination, versioning |
| [blackbox-test](./skills/blackbox-test/) | JSON-driven black box integration tests with JUnit 5, Testcontainers, WireMock, and Flyway |
| [coding-standards](./skills/coding-standards/) | Universal Java Spring coding standards: KISS, DRY, SOLID, readability, and consistent formatting |
| [continuous-learning-v2](./skills/continuous-learning-v2/) | Instinct-based learning with confidence scoring, PreToolUse/PostToolUse observation, and `/evolve` clustering |
| [database-migrations](./skills/database-migrations/) | Zero-downtime database migration patterns — Flyway conventions, expand-contract, safety checklists, Testcontainers validation |
| [grpc-patterns](./skills/grpc-patterns/) | gRPC service patterns for Java Spring — protobuf definitions, server/client setup, streaming, error handling, and testing |
| [hexagonal-arch](./skills/hexagonal-arch/) | Hexagonal Architecture (Ports & Adapters) for Spring WebFlux — package structure, dependency rules, domain modeling, CQRS integration |
| [java-patterns](./skills/java-patterns/) | Java 17+ best practices: immutability, null safety, concurrency, streams, memory optimization, and modern language features |
| [jpa-patterns](./skills/jpa-patterns/) | JPA/Hibernate patterns for Spring Data — entity design, N+1 prevention, HikariCP configuration, and pagination |
| [kafka-patterns](./skills/kafka-patterns/) | Apache Kafka patterns for Spring WebFlux — producer/consumer, exactly-once semantics, reactive Kafka, DLT, Schema Registry, testing |
| [mysql-patterns](./skills/mysql-patterns/) | MySQL optimization, indexing strategies, JPA best practices, and connection pooling |
| [observability-patterns](./skills/observability-patterns/) | Micrometer metrics, distributed tracing, structured logging, health checks, and alerting rules |
| [postgres-patterns](./skills/postgres-patterns/) | PostgreSQL query optimization, indexing strategies, schema design, Row Level Security, and connection pooling |
| [rabbitmq-patterns](./skills/rabbitmq-patterns/) | RabbitMQ exchanges, queues, DLQ, Spring AMQP patterns, and message reliability |
| [redis-patterns](./skills/redis-patterns/) | Redis patterns for Spring WebFlux — reactive Lettuce, caching strategies, distributed locking, rate limiting, Pub/Sub, Streams |
| [security-review](./skills/security-review/) | Security checklist: OWASP Top 10, secrets management, input validation, auth/authz, dependency CVEs |
| [solution-design](./skills/solution-design/) | Architecture documentation: Solution Design (stakeholders) + Service Design (developers) with templates |
| [spring-mvc-patterns](./skills/spring-mvc-patterns/) | Spring MVC patterns — controllers, servlet filters, exception handlers, validation, and interceptors |
| [spring-webflux-patterns](./skills/spring-webflux-patterns/) | Spring WebFlux reactive patterns — Mono/Flux chains, error handling, backpressure, WebClient, SSE, WebSocket |
| [springboot-patterns](./skills/springboot-patterns/) | Spring Boot patterns — REST controllers, pagination, caching, async processing, rate limiting, production defaults |
| [springboot-security](./skills/springboot-security/) | Spring Security patterns — JWT filter, SecurityFilterChain, method security, CORS, secrets management, OWASP scanning |
| [strategic-compact](./skills/strategic-compact/) | Suggests `/compact` at strategic workflow boundaries to manage context efficiently instead of arbitrary auto-compaction |
| [tdd-workflow](./skills/tdd-workflow/) | Enforces write-tests-first TDD with 80%+ coverage for Java Spring — unit, integration, and E2E tests |
| [verification](./skills/verification/) | Comprehensive verification pipeline — compile, test, coverage, security, static analysis, and diff review |

---

## Agents (14)

Specialized sub-agents invoked by orchestration commands. All use `model: opus`.

| Agent | Description |
|---|---|
| `architect` | Backend architecture specialist — Spring WebFlux, CQRS, DDD, Event Sourcing, scalable system design |
| `blackbox-test-runner` | Generates E2E API tests following the blackbox-test skill standard with JSON-driven test cases |
| `build-error-resolver` | Fixes Java/Gradle build and compilation errors with minimal diffs — focuses on getting builds green fast |
| `code-reviewer` | Expert code review for quality, security, readability, DRY, SOLID, and test quality |
| `database-reviewer` | PostgreSQL/MySQL specialist — query optimization, schema design, N+1 detection, JPA best practices |
| `e2e-runner` | E2E API testing with Testcontainers and WebTestClient — manages containers, handles async scenarios |
| `performance-reviewer` | Performance bottlenecks, memory leaks, slow queries, and reactive pipeline analysis |
| `planner` | Planning specialist for features, architecture decisions, and complex refactoring with risk assessment |
| `rabbitmq-reviewer` | RabbitMQ config, message handling, DLQ setup, and Spring AMQP review |
| `refactor-cleaner` | Dead code cleanup and consolidation — safely removes unused dependencies, classes, and methods |
| `security-reviewer` | Security vulnerability detection — OWASP Top 10, secrets, injection, insecure crypto, reactive-specific issues |
| `spring-reviewer` | Spring Boot + MVC review — dependency injection, controllers, validation, security, configuration, testing |
| `spring-webflux-reviewer` | Reactive programming review — backpressure handling, non-blocking patterns, Project Reactor best practices |
| `tdd-guide` | TDD enforcement specialist — write-tests-first methodology with JUnit 5, Mockito, Testcontainers, 80%+ coverage |

---

## Commands (21)

| Command | Description |
|---|---|
| `/adr` | Create Architecture Decision Record for significant technical decisions |
| `/api-doc` | Generate or update OpenAPI spec from Spring controllers |
| `/build-fix` | Incrementally fix Java/Gradle build and compilation errors |
| `/checkpoint` | Create or verify a workflow checkpoint for progress tracking |
| `/code-review` | Comprehensive security + quality review of uncommitted changes |
| `/db-migrate` | Generate and validate Flyway migration files workflow |
| `/e2e` | Generate and run E2E API tests with Testcontainers |
| `/eval` | Manage eval-driven development workflow |
| `/evolve` | Cluster related instincts into skills, commands, or agents |
| `/instinct` | Manage instincts — status, export, import (subcommands) |
| `/learn` | Analyze current session and extract patterns worth saving as skills |
| `/mcp-setup` | Guided MCP server configuration — audit, token budget, install core/optional servers |
| `/orchestrate` | Sequential multi-agent workflow for complex tasks |
| `/plan` | Restate requirements, assess risks, create step-by-step implementation plan — WAIT for user confirm |
| `/refactor-clean` | Safely identify and remove dead code with test verification |
| `/resume-session` | Load context from a previous session file |
| `/save-session` | Manually persist current session context |
| `/setup` | One-time install — writes plugin rules into `~/.claude/CLAUDE.md` for global auto-loading |
| `/skill-create` | Analyze local git history to extract coding patterns and generate SKILL.md |
| `/spec` | Define behavioral contracts (inputs, outputs, error cases, scenarios) from approved plan — gate between PLAN and BUILD |
| `/verify` | Run comprehensive verification: build → compile → tests → security → diff review |

---

## Rules (15)

Behavioral rules organized in two layers: `common/` (language-agnostic) and `java/` (Java/Spring-specific).

### Common Rules (`rules/common/`)

| Rule | Description |
|---|---|
| `agents.md` | Agent orchestration rules and available agent registry |
| `coding-style.md` | Language-agnostic coding style — clarity, simplicity, consistency |
| `development-workflow.md` | Research-before-coding phases |
| `git-workflow.md` | Commit message format conventions |
| `hooks.md` | Hook system documentation — PreToolUse, PostToolUse, Stop, SessionStart/End |
| `patterns.md` | Hexagonal, CQRS, DDD, Outbox, Saga patterns |
| `performance.md` | Model selection strategy — Haiku for cost savings, Opus for complex tasks |
| `security.md` | Security rules — secrets, access control, dependency scanning |
| `spec-driven.md` | Spec-Driven Design mandate — behavioral contracts before implementation |

### Java Rules (`rules/java/`)

| Rule | Description |
|---|---|
| `api-design.md` | REST conventions, HTTP codes, pagination |
| `coding-style.md` | Immutability-first code style, Java Spring patterns, no mutation |
| `observability.md` | SLF4J, MDC, Micrometer, actuator |
| `reactive.md` | WebFlux, Mono/Flux, backpressure, WebClient |
| `security.md` | Spring Security, Bean Validation, OWASP |
| `testing.md` | JUnit 5, StepVerifier, Testcontainers, 80%+ coverage |

---

## Hooks (10)

Lifecycle scripts in `scripts/hooks/` that run automatically during Claude Code sessions.

| Script | Hook Type | Description |
|---|---|---|
| `session-start.sh` | SessionStart | Loads previous context, detects project type, queries claude-mem |
| `session-end.sh` | SessionEnd | Persists session state and files modified list |
| `pre-compact.sh` | PreCompact | Saves current state before context compaction |
| `suggest-compact.sh` | PreToolUse | Suggests `/compact` at logical workflow boundaries (threshold: 50 tool calls) |
| `java-compile-check.sh` | PostToolUse | Runs compilation check after Java file edits |
| `java-format.sh` | PostToolUse | Runs Spotless/Google Java Format after Java file edits |
| `check-debug-statements.sh` | Stop | Checks modified Java files for debug statements (System.out, printStackTrace) |
| `evaluate-session.sh` | Stop | Evaluates session for extractable reusable patterns |
| `cost-tracker.sh` | Various | Tracks token usage and cost across the session |
| `run-with-flags.sh` | Various | Runs commands with configurable feature flags |

---

## MCP Server Configs

Curated MCP server configurations in `mcp-configs/` for agent productivity and the Java/Spring stack. Run `/mcp-setup` for guided installation.

### Productivity (agent research & knowledge)

| Server | Description |
|---|---|
| `fetch` | URL fetch + HTML-to-Markdown — read docs, blogs, Stack Overflow (no API key) |
| `exa-search` | Neural web search with full page content via `exa-mcp-server` |
| `filesystem` | Secure read/write to directories outside CWD via `@modelcontextprotocol/server-filesystem` |
| `notion` | Notion workspace/wiki access via `@notionhq/notion-mcp-server` |

### Core Stack (Java/Spring dev)

| Server | Description |
|---|---|
| `postgres` | Schema inspection, read-only queries via `@modelcontextprotocol/server-postgres` |
| `docker` | Container lifecycle for Testcontainers via `docker/mcp` |
| `github` | PR/issue management via `@modelcontextprotocol/server-github` |
| `gradle` | Build task execution via `gradle-mcp-server` |

### Optional Stack (per-project)

| Server | Description |
|---|---|
| `redis` | Cache inspection via `mcp-redis` |
| `kafka` | Topic management via `@confluentinc/mcp-confluent` |
| `playwright` | Browser E2E tests via `@playwright/mcp` |

**Token budget:** Keep total under 80 tools active. See [mcp-configs/README.md](./mcp-configs/README.md) for budget breakdown.

---

## Workflow

Every session follows a **7-phase mandatory workflow**:

```
① BOOT → ② PLAN → ③ SPEC → ④ BUILD (TDD) → ⑤ VERIFY → ⑥ REVIEW → ⑦ LEARN
```

| Phase | What Happens |
|---|---|
| **① BOOT** | Auto-detect project type, load guidelines, restore context from claude-mem |
| **② PLAN** | `/plan` — decompose task, assess risk, wait for user confirmation |
| **③ SPEC** | `/spec` — define behavioral contracts (inputs, outputs, error cases, scenarios) |
| **④ BUILD** | TDD cycle per step: RED (write test from spec) → GREEN (implement) → REFACTOR |
| **⑤ VERIFY** | `/verify` — build, compile, tests (≥80% coverage), reactive safety, security scan |
| **⑥ REVIEW** | Multi-agent code review: code + security + conditional reviewers |
| **⑦ LEARN** | Auto-extract patterns, save instincts to claude-mem with confidence scoring |

Full details: [WORKING_WORKFLOW.md](./WORKING_WORKFLOW.md)

### Enforcement Rules

| Violation | Action |
|---|---|
| Writing code without `/plan` | **STOP** — run `/plan` first (exception: ≤5 line fixes) |
| Writing code without approved spec | **STOP** — run `/spec` first (exception: ≤5 line fixes, no new behavior) |
| Skipping tests | **BLOCK** — no code ships without tests |
| `.block()` in reactive code | **CRITICAL** — must fix immediately |
| Agent attempts git commit | **FORBIDDEN** — only user commits after final review |

---

## claude-mem Integration

Cross-session memory via `claude-mem` provides continuity between sessions:

- **Session summaries** persist between sessions (last 5 loaded at boot)
- **Instincts** accumulate with confidence scores (0.3–0.9)
- **Unresolved issues** surface as blockers in new sessions
- Use `/instinct status` to see learned behaviors
- Use `/evolve` to promote high-confidence instincts into skills/commands/agents

---

## Configuration

### Hook Registration

Register hooks in `~/.claude/settings.json` (see [Configure Hooks](#2-configure-hooks) above).

Hook profiles: `minimal` | `standard` (default) | `strict` — set via `HOOK_PROFILE` env var.

### Project-Level Guidelines

Create `PROJECT_GUIDELINES.md` at your project root using the provided template:

```bash
cp templates/PROJECT_GUIDELINES_TEMPLATE.md /path/to/your/project/PROJECT_GUIDELINES.md
```

This file overrides generic conventions with project-specific rules (architecture decisions, naming conventions, dependency choices, etc.).

### Key Files

| File | Purpose |
|---|---|
| `CLAUDE.md` | Global context auto-loaded by Claude Code — tech stack, conventions, critical rules |
| `WORKING_WORKFLOW.md` | Complete 7-phase workflow reference with examples and decision flowcharts |
| `PROJECT_GUIDELINES.md` | Per-project rules (created at each project root from template) |

---

## Templates

| Template | Description |
|---|---|
| [PROJECT_GUIDELINES_TEMPLATE.md](./templates/PROJECT_GUIDELINES_TEMPLATE.md) | Project-level configuration template — customize for each project with specific tech stack, conventions, and architecture decisions |

---

## Skill Format

Skills are defined as Markdown files with optional YAML frontmatter:

```yaml
---
name: skill-name
description: Short description
triggers:
  - keyword
  - /command
tools:
  - Read
  - Write
  - Bash
references:        # Optional
  - references/api-docs.md
scripts:           # Optional
  - scripts/helper.py
---

# Skill instructions go here...
```

### Skill Directory Structure

| Component | Description | Required |
|---|---|---|
| `SKILL.md` | Main file containing instructions and patterns | Yes |
| `references/` | API docs, examples, reference material | No |
| `scripts/` | Setup scripts, helpers, validators | No |

### Adding a New Skill

1. Create a folder under `skills/your-skill-name/`
2. Add a `SKILL.md` with YAML frontmatter and instructions
3. Optionally add `references/` and `scripts/` subdirectories
4. Or use `/skill-create` to generate skills from git history automatically

---

## License

MIT
