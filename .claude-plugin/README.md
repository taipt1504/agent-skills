# agent-skills — Claude Code Plugin

A lightweight, context-efficient Claude Code plugin for **Java Spring** backend development.

## What It Provides

- **18 Skills** — 3-tier organization: 1 bootstrap + 10 generic (Spring/Java) + 6 Summer Framework + 1 meta
- **8 Agents** — Planner, spec-writer, implementer, reviewer, build-fixer, test-runner, database-reviewer, refactorer
- **12 Commands** — `/plan`, `/spec`, `/build`, `/verify`, `/review`, `/setup`, `/status`, `/build-fix`, `/refactor`, `/db-migrate`, `/e2e`, `/meta`
- **9 Rules** — Flat, ≤500 tokens each: workflow, coding style, architecture, security, testing, observability, git, API design, spec-driven
- **6 Hooks** — Session init (bootstrap injection), session save, skill router, quality gate, compact advisor, pre-compact

## Architecture

**Hook-bootstrapped enforcement** — not CLAUDE.md-driven. The SessionStart hook injects the bootstrap skill which teaches the agent to search skills, announce usage, and follow the 5-phase workflow.

```
SessionStart hook → injects bootstrap/SKILL.md → agent learns skills → lazy loads on demand
```

**Context budget**: ≤5K tokens auto-loaded per session. ≤15K max with lazy-loaded domain skills.

## Installation

```bash
# Marketplace (recommended)
/plugin marketplace add taipt1504/agent-skills
/plugin install devco-agent-skills

# Then run once per project:
/setup
```

## Stack Coverage

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC · R2DBC · JPA/Hibernate · Kafka · RabbitMQ · Redis · PostgreSQL · MySQL · Docker · Testcontainers

## License

MIT — built by [TaiPT](https://github.com/taipt1504)
