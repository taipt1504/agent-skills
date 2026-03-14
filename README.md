# Agent Skills

A curated collection of skills, agents, commands, rules, and hooks for Claude Code CLI — optimized for Java Spring WebFlux backend development.

## Structure

```
agent-skills/
├── agents/         # Sub-agent definitions (12 specialized agents)
├── commands/       # Slash command definitions (15 commands)
├── rules/          # Global behavioral rules (8 rule files)
├── scripts/
│   └── hooks/      # Lifecycle hook scripts (8 shell scripts)
├── skills/         # Skill definitions (15 skills)
└── README.md
```

---

## Skills

| Skill | Description |
|---|---|
| [backend-patterns](./skills/backend-patterns/) | RESTful API design, DB optimization, messaging, and server-side patterns for Spring WebFlux/MVC |
| [blackbox-test](./skills/blackbox-test/) | JSON-driven black box integration tests with JUnit 5, Testcontainers, WireMock, and Flyway |
| [coding-standards](./skills/coding-standards/) | Universal Java Spring coding standards: KISS, DRY, SOLID, readability |
| [continuous-learning](./skills/continuous-learning/) | v1: Stop hook that extracts patterns from sessions and saves learned skills |
| [continuous-learning-v2](./skills/continuous-learning-v2/) | v2: Instinct-based learning with confidence scoring, team export/import, `/evolve` clustering |
| [java-patterns](./skills/java-patterns/) | Java 17+ best practices: immutability, null safety, concurrency, streams, memory |
| [postgres-patterns](./skills/postgres-patterns/) | PostgreSQL query optimization, indexing strategies, RLS, and connection pooling |
| [project-guidelines](./skills/project-guidelines/) | Pointer skill — always read `PROJECT_GUIDELINES.md` at project root |
| [security-review](./skills/security-review/) | Security checklist: OWASP Top 10, secrets management, input validation, auth |
| [solution-design](./skills/solution-design/) | Architecture documents: Solution Design (stakeholders) + Service Design (developers) |
| [strategic-compact](./skills/strategic-compact/) | Suggests `/compact` at strategic workflow boundaries to manage context efficiently |
| [tdd-workflow](./skills/tdd-workflow/) | Enforces write-tests-first TDD with 80%+ coverage for Java Spring projects |
| [verification-loop](./skills/verification-loop/) | Multi-phase verification: Gradle build → compile check → tests → security scan |

---

## Agents

Specialized sub-agents invoked by orchestration commands. All use `model: opus`.

| Agent | Purpose |
|---|---|
| `architect` | Backend architecture — Spring WebFlux, CQRS, DDD, Event Sourcing |
| `blackbox-test-runner` | Generates E2E API tests following the blackbox-test skill standard |
| `build-error-resolver` | Fixes Java/Gradle build and compilation errors with minimal diffs |
| `code-reviewer` | Expert code review for quality, security, and maintainability |
| `database-reviewer` | PostgreSQL query optimization, schema design, RLS, Supabase |
| `e2e-runner` | E2E API testing with Testcontainers and WebTestClient |
| `planner` | Planning specialist for features, architecture, and refactoring |
| `refactor-cleaner` | Identifies and removes dead code and unused dependencies |
| `security-reviewer` | Security vulnerability detection — Spring WebFlux, OWASP Top 10 |
| `spring-boot-reviewer` | Spring Boot review: DI, config, auto-configuration |
| `spring-webflux-reviewer` | Reactive programming review: backpressure, Project Reactor patterns |
| `tdd-guide` | TDD specialist enforcing write-tests-first with 80%+ coverage |

---

## Commands (Slash Commands)

| Command | Purpose |
|---|---|
| `/build-fix` | Incrementally fix Java/Gradle build errors |
| `/checkpoint` | Create or verify a workflow checkpoint |
| `/code-review` | Comprehensive security + quality review of uncommitted changes |
| `/e2e` | Generate and run E2E API tests with Testcontainers |
| `/eval` | Manage eval-driven development workflow |
| `/evolve` | Cluster related instincts into skills/commands/agents |
| `/instinct-export` | Export instincts for sharing with teammates |
| `/instinct-import` | Import instincts from teammates or other sources |
| `/instinct-status` | Show all learned instincts with confidence levels |
| `/learn` | Analyze current session and extract patterns as skills |
| `/orchestrate` | Sequential agent workflow for complex tasks |
| `/plan` | Restate requirements, assess risks, create implementation plan |
| `/refactor-clean` | Safely identify and remove dead code with test verification |
| `/skill-create` | Analyze git history to extract coding patterns and generate SKILL.md |
| `/verify` | Run comprehensive verification on the current codebase state |

---

## Rules

Global behavioral rules applied to all Claude Code sessions in a project.

| Rule | Purpose |
|---|---|
| `agents.md` | Agent orchestration rules and available agent registry |
| `coding-style.md` | Immutability, code style, Java Spring patterns |
| `git-workflow.md` | Commit message format conventions |
| `hooks.md` | Hook system documentation (PreToolUse, PostToolUse, Stop) |
| `patterns.md` | Points to project-specific `PROJECT_GUIDELINES.md` |
| `performance.md` | Model selection strategy (Haiku 4.5 for cost savings, Opus for complex tasks) |
| `security.md` | Mandatory security checks before any commit |
| `testing.md` | Minimum 80% coverage, required test types |

---

## Hooks

Lifecycle scripts in `scripts/hooks/` that run automatically during sessions.

| Script | Hook Type | Purpose |
|---|---|---|
| `check-debug-statements.sh` | Stop | Checks modified Java files for debug statements before session ends |
| `evaluate-session.sh` | Stop | Evaluates session for extractable reusable patterns |
| `java-compile-check.sh` | PostToolUse | Runs compilation check after Java file edits |
| `java-format.sh` | PostToolUse | Runs Spotless/Google Java Format after Java file edits |
| `pre-compact.sh` | PreCompact | Saves state before context compaction |
| `session-end.sh` | SessionEnd | Persists session state when a session ends |
| `session-start.sh` | SessionStart | Loads previous context when a new session starts |
| `suggest-compact.sh` | PreToolUse | Suggests `/compact` at logical workflow boundaries |

---

## Skill Format

Skills are defined as Markdown files with optional YAML frontmatter.

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

### Skill Components

| Component | Description | Required |
|---|---|---|
| `SKILL.md` | Main file containing instructions | Yes |
| `references/` | API docs, examples, reference material | No |
| `scripts/` | Setup scripts, helpers, validators | No |

---

## Adding a New Skill

1. Create a folder under `skills/your-skill-name/`
2. Add a `SKILL.md` with YAML frontmatter and instructions
3. Optionally add `references/` and `scripts/` subdirectories
4. Use the `/skill-create` command or the `skill-creator` skill in Claude Code to generate skills from git history or session patterns
