# Agent Skills

A curated collection of skills, agents, commands, rules, and hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — optimized for **Java 17+ Spring WebFlux** backend development.

Provides a complete development workflow: planning → TDD → verification → multi-agent code review → continuous learning. All enforced automatically through hooks and rules.

## Quick Start

### 1. Install

Clone into your Claude Code configuration directory:

```bash
# Clone the repo
git clone https://github.com/your-org/agent-skills.git

# Copy contents into your project's .claude/ directory
cp -r agent-skills/skills/ .claude/skills/
cp -r agent-skills/agents/ .claude/agents/
cp -r agent-skills/commands/ .claude/commands/
cp -r agent-skills/rules/ .claude/rules/
cp -r agent-skills/scripts/ .claude/scripts/

# Or symlink for easy updates
ln -s /path/to/agent-skills/skills .claude/skills
```

### 2. Configure Hooks

Add hook registrations to `~/.claude/settings.json`:

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
cp agent-skills/templates/PROJECT_GUIDELINES_TEMPLATE.md ./PROJECT_GUIDELINES.md
```

### 4. Start a Session

Claude Code will automatically load the workflow. Start with `/plan` for any non-trivial task.

---

## Structure

```
agent-skills/
├── CLAUDE.md                              # Global context auto-loaded by Claude Code
├── WORKING_WORKFLOW.md                    # 6-phase mandatory workflow reference
├── README.md
├── agents/                                # 12 specialized sub-agents
│   ├── architect.md
│   ├── blackbox-test-runner.md
│   ├── build-error-resolver.md
│   ├── code-reviewer.md
│   ├── database-reviewer.md
│   ├── e2e-runner.md
│   ├── planner.md
│   ├── refactor-cleaner.md
│   ├── security-reviewer.md
│   ├── spring-boot-reviewer.md
│   ├── spring-webflux-reviewer.md
│   └── tdd-guide.md
├── commands/                              # 15 slash commands
│   ├── build-fix.md
│   ├── checkpoint.md
│   ├── code-review.md
│   ├── e2e.md
│   ├── eval.md
│   ├── evolve.md
│   ├── instinct-export.md
│   ├── instinct-import.md
│   ├── instinct-status.md
│   ├── learn.md
│   ├── orchestrate.md
│   ├── plan.md
│   ├── refactor-clean.md
│   ├── skill-create.md
│   └── verify.md
├── rules/                                 # 8 global behavioral rules
│   ├── agents.md
│   ├── coding-style.md
│   ├── git-workflow.md
│   ├── hooks.md
│   ├── patterns.md
│   ├── performance.md
│   ├── security.md
│   └── testing.md
├── scripts/
│   └── hooks/                             # 8 lifecycle hook scripts
│       ├── check-debug-statements.sh
│       ├── evaluate-session.sh
│       ├── java-compile-check.sh
│       ├── java-format.sh
│       ├── pre-compact.sh
│       ├── session-end.sh
│       ├── session-start.sh
│       └── suggest-compact.sh
├── skills/                                # 19 skill definitions
│   ├── api-design/
│   ├── backend-patterns/
│   ├── blackbox-test/
│   ├── coding-standards/
│   ├── continuous-learning/
│   ├── continuous-learning-v2/
│   ├── grpc-patterns/
│   ├── hexagonal-arch/
│   ├── java-patterns/
│   ├── kafka-patterns/
│   ├── postgres-patterns/
│   ├── project-guidelines/
│   ├── redis-patterns/
│   ├── security-review/
│   ├── solution-design/
│   ├── spring-webflux-patterns/
│   ├── strategic-compact/
│   ├── tdd-workflow/
│   └── verification-loop/
└── templates/
    └── PROJECT_GUIDELINES_TEMPLATE.md     # Project-level config template
```

---

## Skills (19)

| Skill | Description |
|---|---|
| [api-design](./skills/api-design/) | RESTful and reactive API design standards — URL conventions, request/response patterns, error handling, pagination, versioning |
| [backend-patterns](./skills/backend-patterns/) | Backend architecture patterns, API design, DB optimization, messaging, and server-side best practices for Spring WebFlux/MVC |
| [blackbox-test](./skills/blackbox-test/) | JSON-driven black box integration tests with JUnit 5, Testcontainers, WireMock, and Flyway using the F8A Summer Test framework |
| [coding-standards](./skills/coding-standards/) | Universal Java Spring coding standards: KISS, DRY, SOLID, readability, and consistent formatting |
| [continuous-learning](./skills/continuous-learning/) | v1: Stop hook that evaluates sessions and extracts reusable patterns as learned skills |
| [continuous-learning-v2](./skills/continuous-learning-v2/) | v2: Instinct-based learning with confidence scoring, PreToolUse/PostToolUse observation, and `/evolve` clustering |
| [grpc-patterns](./skills/grpc-patterns/) | gRPC service patterns for Java Spring — protobuf definitions, server/client setup, streaming, error handling, and testing |
| [hexagonal-arch](./skills/hexagonal-arch/) | Hexagonal Architecture (Ports & Adapters) for Spring WebFlux — package structure, dependency rules, domain modeling, CQRS integration |
| [java-patterns](./skills/java-patterns/) | Java 17+ best practices: immutability, null safety, concurrency, streams, memory optimization, and modern language features |
| [kafka-patterns](./skills/kafka-patterns/) | Apache Kafka patterns for Spring WebFlux — producer/consumer, exactly-once semantics, reactive Kafka, DLT, Schema Registry, testing |
| [postgres-patterns](./skills/postgres-patterns/) | PostgreSQL query optimization, indexing strategies, schema design, Row Level Security, and connection pooling |
| [project-guidelines](./skills/project-guidelines/) | Pointer skill — reads `PROJECT_GUIDELINES.md` at project root for project-specific conventions |
| [redis-patterns](./skills/redis-patterns/) | Redis patterns for Spring WebFlux — reactive Lettuce, caching strategies, distributed locking, rate limiting, Pub/Sub, Streams |
| [security-review](./skills/security-review/) | Security checklist: OWASP Top 10, secrets management, input validation, auth/authz, dependency CVEs |
| [solution-design](./skills/solution-design/) | Architecture documentation: Solution Design (stakeholders) + Service Design (developers) with templates |
| [spring-webflux-patterns](./skills/spring-webflux-patterns/) | Spring WebFlux reactive patterns — Mono/Flux chains, error handling, backpressure, WebClient, SSE, WebSocket |
| [strategic-compact](./skills/strategic-compact/) | Suggests `/compact` at strategic workflow boundaries to manage context efficiently instead of arbitrary auto-compaction |
| [tdd-workflow](./skills/tdd-workflow/) | Enforces write-tests-first TDD with 80%+ coverage for Java Spring — unit, integration, and E2E tests |
| [verification-loop](./skills/verification-loop/) | Multi-phase verification: Gradle build → compile check → tests → reactive safety scan → security scan → diff review |

---

## Agents (12)

Specialized sub-agents invoked by orchestration commands. All use `model: opus`.

| Agent | Description |
|---|---|
| `architect` | Backend architecture specialist — Spring WebFlux, CQRS, DDD, Event Sourcing, scalable system design |
| `blackbox-test-runner` | Generates E2E API tests following the blackbox-test skill standard with JSON-driven test cases |
| `build-error-resolver` | Fixes Java/Gradle build and compilation errors with minimal diffs — focuses on getting builds green fast |
| `code-reviewer` | Expert code review for quality, security, readability, DRY, SOLID, and test quality |
| `database-reviewer` | PostgreSQL specialist — query optimization, schema design, RLS, N+1 detection, Supabase best practices |
| `e2e-runner` | E2E API testing with Testcontainers and WebTestClient — manages containers, handles async scenarios |
| `planner` | Planning specialist for features, architecture decisions, and complex refactoring with risk assessment |
| `refactor-cleaner` | Dead code cleanup and consolidation — safely removes unused dependencies, classes, and methods |
| `security-reviewer` | Security vulnerability detection — OWASP Top 10, secrets, injection, insecure crypto, reactive-specific issues |
| `spring-boot-reviewer` | Spring Boot review — dependency injection, configuration, auto-configuration, Boot best practices |
| `spring-webflux-reviewer` | Reactive programming review — backpressure handling, non-blocking patterns, Project Reactor best practices |
| `tdd-guide` | TDD enforcement specialist — write-tests-first methodology with JUnit 5, Mockito, Testcontainers, 80%+ coverage |

---

## Commands (15)

| Command | Description |
|---|---|
| `/build-fix` | Incrementally fix Java/Gradle build and compilation errors |
| `/checkpoint` | Create or verify a workflow checkpoint for progress tracking |
| `/code-review` | Comprehensive security + quality review of uncommitted changes |
| `/e2e` | Generate and run E2E API tests with Testcontainers |
| `/eval` | Manage eval-driven development workflow |
| `/evolve` | Cluster related instincts into skills, commands, or agents |
| `/instinct-export` | Export instincts for sharing with teammates or other projects |
| `/instinct-import` | Import instincts from teammates or other sources |
| `/instinct-status` | Show all learned instincts with confidence levels |
| `/learn` | Analyze current session and extract patterns worth saving as skills |
| `/orchestrate` | Sequential multi-agent workflow for complex tasks |
| `/plan` | Restate requirements, assess risks, create step-by-step implementation plan — WAIT for user confirm |
| `/refactor-clean` | Safely identify and remove dead code with test verification |
| `/skill-create` | Analyze local git history to extract coding patterns and generate SKILL.md |
| `/verify` | Run comprehensive verification: build → compile → tests → security → diff review |

---

## Rules (8)

Global behavioral rules applied to all Claude Code sessions.

| Rule | Description |
|---|---|
| `agents.md` | Agent orchestration rules and available agent registry |
| `coding-style.md` | Immutability-first code style, Java Spring patterns, no mutation |
| `git-workflow.md` | Commit message format conventions |
| `hooks.md` | Hook system documentation — PreToolUse, PostToolUse, Stop, SessionStart/End |
| `patterns.md` | Points to project-specific `PROJECT_GUIDELINES.md` |
| `performance.md` | Model selection strategy — Haiku for cost savings, Opus for complex tasks |
| `security.md` | Mandatory security checks before any commit |
| `testing.md` | Minimum 80% coverage, required test types (unit, integration, E2E) |

---

## Hooks (8)

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

---

## Workflow

Every session follows a **6-phase mandatory workflow**:

```
① BOOT → ② PLAN → ③ BUILD (TDD) → ④ VERIFY → ⑤ REVIEW → ⑥ LEARN
```

| Phase | What Happens |
|---|---|
| **① BOOT** | Auto-detect project type, load guidelines, restore context from claude-mem |
| **② PLAN** | `/plan` — decompose task, assess risk, wait for user confirmation |
| **③ BUILD** | TDD cycle per step: RED (write test) → GREEN (implement) → REFACTOR |
| **④ VERIFY** | `/verify` — build, compile, tests (≥80% coverage), reactive safety, security scan |
| **⑤ REVIEW** | Multi-agent code review: code + security + conditional reviewers |
| **⑥ LEARN** | Auto-extract patterns, save instincts to claude-mem with confidence scoring |

📖 **Full details:** [WORKING_WORKFLOW.md](./WORKING_WORKFLOW.md)

### Enforcement Rules

| Violation | Action |
|---|---|
| Writing code without `/plan` | **STOP** — run `/plan` first (exception: ≤5 line fixes) |
| Skipping tests | **BLOCK** — no code ships without tests |
| `.block()` in reactive code | **CRITICAL** — must fix immediately |
| Agent attempts git commit | **FORBIDDEN** — only user commits after final review |

---

## claude-mem Integration

Cross-session memory via `claude-mem` provides continuity between sessions:

- **Session summaries** persist between sessions (last 5 loaded at boot)
- **Instincts** accumulate with confidence scores (0.3–0.9)
- **Unresolved issues** surface as blockers in new sessions
- Use `/instinct-status` to see learned behaviors
- Use `/evolve` to promote high-confidence instincts into skills/commands/agents
- Use `/instinct-export` and `/instinct-import` for team sharing

---

## Configuration

### Hook Registration

Register hooks in `~/.claude/settings.json` (see [Quick Start](#2-configure-hooks) above).

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
| `WORKING_WORKFLOW.md` | Complete 6-phase workflow reference with examples and decision flowcharts |
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
