# Project Memory — agent-skills

## Project Overview

Personal Claude Code configuration repo for Java Spring Boot development.
Tech stack: Java 17+, Spring Boot/MVC/WebFlux, MySQL, PostgreSQL, Redis, Kafka, RabbitMQ, Lombok, Jackson.

## Completed Work (2026-03-15)

### Full repository optimization — all 5 phases complete

**Phase 1: Foundation**
- `CLAUDE.md` — updated tech stack, skills, agents, commands sections
- `.claude/settings.json` — hooks wired (SessionStart, PreToolUse, PostToolUse, PreCompact, Stop)
- `contexts/dev.md`, `contexts/review.md`, `contexts/research.md` — behavior injection contexts

**Phase 2: New Skills**
- `skills/mysql-patterns/` — MySQL 8.x, JPA/Hibernate, HikariCP, Flyway, Testcontainers
- `skills/rabbitmq-patterns/` — Spring AMQP, DLQ, manual ACK, reactor-rabbitmq
- `skills/spring-mvc-patterns/` — REST controllers, MockMvc, security, pagination
- `skills/observability-patterns/` — Micrometer, OTel, Prometheus, health indicators

**Phase 3: New Agents**
- `agents/mysql-reviewer.md` — MySQL schema, JPA, HikariCP, Flyway review
- `agents/rabbitmq-reviewer.md` — RabbitMQ DLQ, ack mode, publisher confirms review
- `agents/performance-reviewer.md` — N+1, blocking in reactive, caching, parallel ops
- `agents/spring-mvc-reviewer.md` — MVC controllers, validation, exception handlers, MockMvc

**Phase 4: New Commands**
- `commands/adr.md` — Architecture Decision Records
- `commands/db-migrate.md` — Flyway migration generation (MySQL + PostgreSQL)
- `commands/api-doc.md` — OpenAPI/Swagger documentation with springdoc
- `commands/quality-gate.md` — Comprehensive pre-merge quality checks

**Phase 5: Optimizations**
- `rules/agents.md` — Updated with 4 new agents and expanded trigger table
- `agents/planner.md` — Added `maxTurns: 15` frontmatter
- `skills/tdd-workflow/SKILL.md` — Reduced from 734 to 129 lines
- `skills/tdd-workflow/references/test-patterns.md` — Detailed test patterns reference

### Phase 6: Reorganization (2026-03-15)

**Functional fixes:**
- `agents/architect.md` — fixed `name: backend-architect` → `name: architect` (Task dispatch was silently failing)
- `.claude/settings.local.json` — added Write, Edit, MultiEdit, Glob, Grep, Task to allow list (was blocking most tools)
- `scripts/hooks/evaluate-session.sh` — fixed config path to `skills/continuous-learning-v2/config.json`

**Wrong content rewritten:**
- `rules/hooks.md` — replaced JS/tmux/Prettier content with actual 8 Java hook scripts documentation
- `rules/patterns.md` — replaced broken link stub with Java hexagonal/CQRS/DDD architecture guidance
- `rules/testing.md` — replaced Playwright with WebTestClient + Testcontainers
- `rules/performance.md` — updated model IDs to `claude-haiku-4-5`, `claude-sonnet-4-6`, `claude-opus-4-6`
- `agents/code-reviewer.md` — removed JS-specific checks (console.log, React re-renders, bundle sizes, ARIA), made Java-only
- `templates/PROJECT_GUIDELINES_TEMPLATE.md` — replaced Liquibase with Flyway throughout

**Missing documentation added:**
- `CLAUDE.md` — added Contexts section; added api-design, grpc-patterns, spring-webflux-patterns to skills table; removed continuous-learning v1
- `README.md` — synced to 22 skills, 16 agents, 19 commands; updated directory tree

**Cleanup:**
- Deleted `skills/continuous-learning/` (v1 — superseded by v2)
- Deleted `skills/continuous-learning-v2/commands/` (duplicates of top-level commands/)

## Key Conventions

- Agents: YAML frontmatter with `model: opus` for reviewers, `model: sonnet` for executors
- Skills: SKILL.md < 500 lines; detailed content in `references/`
- Rules: flat `rules/` directory (8 files)
- Commands: markdown prompt files in `commands/`
- Hooks: scripts in `scripts/hooks/`, wired in `.claude/settings.json`
- `rules/agents.md` — auto-delegation triggers and file-pattern routing table

## File Pattern → Agent Routing

| Pattern | Agent |
|---------|-------|
| `*Controller.java` (WebFlux) | spring-webflux-reviewer |
| `*Controller.java` (MVC) | spring-mvc-reviewer |
| `*Repository.java` (JPA) | mysql-reviewer |
| `*Repository.java` (R2DBC) | database-reviewer |
| `V*.sql` (Flyway) | mysql-reviewer |
| `*Consumer.java` | rabbitmq-reviewer |
| Performance issues | performance-reviewer |
