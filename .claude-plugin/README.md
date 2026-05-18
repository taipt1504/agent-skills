# agent-skills — Claude Code Plugin

A lightweight, context-efficient Claude Code plugin for **Java Spring** backend development.

## What It Provides

- **30+ Skills** — bootstrap + preflight + triage + align + brainstorm + subagent-dispatch + git-worktree + 10 generic (Spring WebFlux/MVC, Java) + 6 Summer Framework + meta-skills
- **9 Agents** — planner, spec-writer, slice-executor (formerly implementer), reviewer (split into spec-compliance + code-quality coming Phase 4), build-fixer, test-runner, database-reviewer, refactorer, pentest
- **17 Commands** — `/triage`, `/align`, `/brainstorm`, `/plan`, `/spec`, `/build`, `/verify`, `/dc-review`, `/dc-setup`, `/dc-status`, `/build-fix`, `/refactor`, `/db-migrate`, `/e2e`, `/meta`, `/pentest-scan`, `/threat-model`
- **13 Rules** — split into `rules/common/` (language-agnostic: coding-style, security, patterns, lanes, spec-driven, skill-enforcement, development-workflow, git-workflow) + `rules/java/` (coding-style, security, api-design, testing, observability, reactive)
- **20 Hooks** — session-init (with smart skill load + triage), preflight-gate + preflight-discovery (1% rule enforcement), workflow-gate (lane-aware), quality-gate, compact-advisor, pre/post-compact, skill-router (announcement-only), subagent-init, verify-fix-loop, build-checkpoint, observability-trace (stubbed), and more

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
