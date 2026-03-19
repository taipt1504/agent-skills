# Agent Skills

A lightweight, context-efficient [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for **Java Spring** backend development.

Hook-bootstrapped skill system with 3-tier organization, lazy loading, and ≤5K auto-loaded tokens per session.

## Quick Start

### Step 1 — Install plugin (one-time per machine)

```bash
/plugin marketplace add taipt1504/agent-skills
/plugin install devco-agent-skills
```

### Step 2 — Setup project (one-time per project, lead dev)

```
/setup
```

### Step 3 — Commit and share

```bash
git add .claude/ && git commit -m "chore: add Claude Code project context"
```

Teammates clone → run `claude` → auto-prompted to install plugin. Zero setup needed.

### Step 4 — Start coding

```
/plan    # for any non-trivial task
```

---

## Architecture

### Hook-Bootstrapped Enforcement (Level 4-5 Compliance)

CLAUDE.md is **passive** (project conventions only, ~400 tokens). The **bootstrap skill** is the enforcement engine:

```
SessionStart hook → injects bootstrap/SKILL.md (EXTREMELY_IMPORTANT)
  → Agent learns: search skills → announce → use → follow workflow
  → Auto-detects: Java/Spring type, Summer Framework, project structure
  → Lazy loads: domain skills on demand, ≤800 tokens each
```

### Context Budget

| Scope | Token Limit |
|-------|-------------|
| Bootstrap skill | ≤ 1,500 |
| CLAUDE.md | ≤ 1,000 |
| Each skill body | ≤ 800 |
| Each rule | ≤ 500 |
| Auto-loaded per session | ≤ 5,000 |
| Max with lazy-loaded skills | ≤ 15,000 |

### 5-Phase Workflow

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

| Phase | Command | Agent |
|-------|---------|-------|
| PLAN | `/plan` | planner (opus) |
| SPEC | `/spec` | spec-writer (opus) |
| BUILD | `/build` | implementer (sonnet) |
| VERIFY | `/verify` | pipeline |
| REVIEW | `/review` | reviewer (opus) |

**Skip condition**: ≤5 lines, 1 file, no new behavior → BUILD directly.

---

## Structure

```
agent-skills/
├── CLAUDE.md                          # Project conventions only (~400 tokens)
├── skills/
│   ├── bootstrap/SKILL.md            # Enforcement engine (loaded by SessionStart hook)
│   ├── generic/                      # 10 Java/Spring skills (lazy loaded)
│   │   ├── spring-patterns/          # MVC + WebFlux + Boot patterns
│   │   ├── spring-security/          # Auth, JWT, CORS, OWASP
│   │   ├── database-patterns/        # PostgreSQL, MySQL, JPA, R2DBC, migrations
│   │   ├── messaging-patterns/       # Kafka + RabbitMQ
│   │   ├── testing-workflow/         # TDD, blackbox, verification pipeline
│   │   ├── coding-standards/         # Java 17+ standards + patterns
│   │   ├── architecture/             # Hexagonal, CQRS, solution design
│   │   ├── api-design/              # REST conventions, pagination, RFC 7807
│   │   ├── redis-patterns/          # Caching, locking, Pub/Sub, Streams
│   │   └── observability-patterns/  # Logging, tracing, metrics, alerting
│   ├── summer/                       # 6 Summer Framework skills (hard gate: io.f8a.summer)
│   │   ├── summer-core/             # Version detection, shared types, router
│   │   ├── summer-rest/             # Handlers, controllers, WebClient
│   │   ├── summer-data/             # Audit, outbox, R2DBC
│   │   ├── summer-security/         # APISIX, Keycloak, role sync
│   │   ├── summer-ratelimit/        # Rate limiting (v0.2.2+)
│   │   └── summer-test/            # Testcontainers, WireMock, blackbox
│   └── meta/
│       └── continuous-learning/     # Pattern extraction (on-demand)
├── agents/                           # 8 specialized agents
│   ├── planner.md                   # Architecture + planning (opus)
│   ├── spec-writer.md               # Behavioral specs (opus)
│   ├── implementer.md               # TDD cycle (sonnet)
│   ├── reviewer.md                  # Unified review with conditional checklists (opus)
│   ├── build-fixer.md               # Build error resolution (sonnet)
│   ├── test-runner.md               # E2E + blackbox tests (sonnet)
│   ├── database-reviewer.md         # DB schema/query review (sonnet)
│   └── refactorer.md               # Dead code cleanup (sonnet)
├── commands/                         # 12 slash commands
│   ├── plan.md                      # Start planning
│   ├── spec.md                      # Define contracts
│   ├── build.md                     # TDD cycle
│   ├── verify.md                    # Verification pipeline
│   ├── review.md                    # Multi-aspect review
│   ├── setup.md                     # Project install
│   ├── status.md                    # Health check
│   ├── build-fix.md                 # Fix build errors
│   ├── refactor.md                  # Dead code cleanup
│   ├── db-migrate.md               # Database migrations
│   ├── e2e.md                       # E2E test generation
│   └── meta.md                      # learn, evolve, instinct, create-skill
├── rules/                            # 9 flat rules (≤500 tokens each)
│   ├── development-workflow.md
│   ├── spec-driven.md
│   ├── coding-style.md
│   ├── architecture-patterns.md
│   ├── security.md
│   ├── git-workflow.md
│   ├── api-design.md
│   ├── testing.md
│   └── observability.md
├── hooks/hooks.json                  # Hook configuration
├── scripts/hooks/                    # 6 lifecycle hooks + run-with-flags
│   ├── session-init.sh              # Bootstrap injection + project detection
│   ├── session-save.sh              # Session persistence + learning signals
│   ├── skill-router.sh             # File→skill matching
│   ├── quality-gate.sh             # Compile + debug check + format
│   ├── compact-advisor.sh          # Progressive unloading guidance
│   └── pre-compact.sh              # State checkpoint before compaction
├── scripts/memory/                   # 3-tier memory management
├── templates/                        # PROJECT_GUIDELINES_TEMPLATE.md
└── mcp-configs/                      # MCP server configurations
```

---

## Skills (18)

### Bootstrap (auto-loaded every session)

| Skill | Description |
|---|---|
| `bootstrap` | Enforcement engine — skill discovery, workflow compliance, project detection, mandatory skill usage |

### Generic (lazy-loaded for Java/Spring projects)

| Skill | Merged From | Triggers |
|---|---|---|
| `spring-patterns` | spring-mvc + spring-webflux + springboot-patterns | Controllers, handlers, WebClient, filters |
| `spring-security` | springboot-security + security-review | JWT, CORS, @PreAuthorize, secrets |
| `database-patterns` | postgres + mysql + jpa + migrations | Repository, Entity, SQL, migrations |
| `messaging-patterns` | kafka + rabbitmq | @KafkaListener, @RabbitListener, DLT/DLQ |
| `testing-workflow` | tdd-workflow + blackbox-test + verification | Test files, coverage, verification |
| `coding-standards` | coding-standards + java-patterns | Any Java file |
| `architecture` | hexagonal-arch + solution-design | Package structure, CQRS, domain events |
| `api-design` | _(kept/trimmed)_ | REST endpoints, pagination, error format |
| `redis-patterns` | _(kept/trimmed)_ | Redis, caching, locking, rate limiting |
| `observability-patterns` | _(kept/trimmed)_ | Logging, metrics, tracing, health checks |

### Summer Framework (hard gate: `io.f8a.summer:summer-platform` required)

| Skill | Triggers |
|---|---|
| `summer-core` | Always loaded when summer detected |
| `summer-rest` | BaseController, RequestHandler, @Handler |
| `summer-data` | AuditService, OutboxService |
| `summer-security` | @AuthRoles, ReactiveKeycloakClient |
| `summer-ratelimit` | RateLimiterService (v0.2.2+ only) |
| `summer-test` | src/test/ + summer-test dependency |

### Meta (on-demand)

| Skill | Triggers |
|---|---|
| `continuous-learning` | `/meta learn`, `/meta evolve` |

---

## Agents (8)

| Agent | Model | Description |
|---|---|---|
| `planner` | opus | Architecture design, task decomposition, risk assessment, investigation |
| `spec-writer` | opus | Behavioral specs, test mapping, observable contracts |
| `implementer` | sonnet | TDD cycle: RED → GREEN → REFACTOR |
| `reviewer` | opus | Unified review with 7 conditional checklists (Spring, Security, Reactor, DB, Messaging, Config, Quality) |
| `build-fixer` | sonnet | Fix build/compilation errors, minimal diffs |
| `test-runner` | sonnet | E2E + blackbox test generation & execution |
| `database-reviewer` | sonnet | DB schema, query optimization, migration review |
| `refactorer` | sonnet | Dead code cleanup, consolidation |

---

## Hooks (6)

3 profiles controlled by `HOOK_PROFILE` env var (default: `standard`):

| Profile | Hooks |
|---------|-------|
| `minimal` | session-init, session-save |
| `standard` | + skill-router, quality-gate, compact-advisor |
| `strict` | + pre-compact |

| Hook | Event | Description |
|---|---|---|
| `session-init.sh` | SessionStart | Injects bootstrap skill, detects project, restores memory |
| `session-save.sh` | Stop | Saves session summary, learning signals |
| `skill-router.sh` | PreToolUse | File→skill matching before edits |
| `quality-gate.sh` | PostToolUse | Compile check + debug audit + format |
| `compact-advisor.sh` | PreToolUse | 3-stage progressive unloading guidance |
| `pre-compact.sh` | PreCompact | State checkpoint before compaction |

---

## Team Onboarding

**Target: productive in 2 minutes.**

### Lead dev (one-time)

```bash
/plugin marketplace add taipt1504/agent-skills
/plugin install devco-agent-skills
/setup
git add .claude/ && git commit -m "chore: add Claude Code project context"
# Optional: cp templates/PROJECT_GUIDELINES_TEMPLATE.md ./PROJECT_GUIDELINES.md
```

### Every teammate after

```bash
git clone <repo>
claude                  # auto-prompted to install plugin
# Start coding — everything works
```

---

## Stack Coverage

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC · R2DBC · JPA/Hibernate · Kafka · RabbitMQ · Redis · PostgreSQL · MySQL · Docker · Testcontainers · Summer Framework (io.f8a.summer)

---

## License

MIT — built by [TaiPT](https://github.com/taipt1504)
