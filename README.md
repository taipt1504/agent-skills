# Agent Skills v3.2

A lightweight, context-efficient [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for **Java Spring** backend development.

Built on **Harness Engineering** principles: Agent = Model + Harness. The plugin provides the harness — hook-bootstrapped skill system with verify/fix loops, observability traces, context budget management, and state persistence on disk.

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

### Design Philosophy: Harness Engineering

The plugin treats the agent as `Model + Harness`. CLAUDE.md is passive (project conventions, ~800 tokens). The **harness** — hooks, skills, agents, and state files — does the heavy lifting:

| Harness Component | Implementation |
|---|---|
| **Tool Orchestration** | 13 hooks across 7 lifecycle events, skill-router auto-matching |
| **Knowledge Curation** | 18 domain skills, 3-tier lazy loading, ≤800 tokens each |
| **Context Management** | Token budget estimation, progressive unload warnings at 70/85/95% |
| **State Persistence** | workflow-state.json, verify-fix-state.json, build-checkpoint.json — all on disk |
| **Verification Loops** | Ralph Pattern: detect failure → extract error signature → retry with circuit breakers |
| **Observability** | execution-trace.jsonl (per-call), session-metrics.json (aggregated) |

### Hook-Bootstrapped Enforcement

```
SessionStart hook → injects bootstrap/SKILL.md
  → Agent learns: search skills → announce → use → follow workflow
  → Auto-detects: Java/Spring type, Summer Framework, project structure
  → Lazy loads: domain skills on demand, ≤800 tokens each
```

### Context Budget

| Scope | Token Limit |
|-------|-------------|
| Bootstrap skill | ≤ 1,700 |
| CLAUDE.md | ≤ 1,000 |
| Each domain skill | ≤ 800 |
| Each rule | ≤ 500 |
| Auto-loaded per session | ≤ 5,000 |
| Max with lazy-loaded skills | ≤ 15,000 |

### 5-Phase Workflow

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

| Phase | Command | Agent | Auto-Transition |
|-------|---------|-------|-----------------|
| PLAN | `/plan` | planner (opus) | → remind `/spec` |
| SPEC | `/spec` | spec-writer (opus) | → remind `/build` |
| BUILD | `/build` | implementer (sonnet) | → AUTO `/verify` |
| VERIFY | `/verify` | pipeline | → AUTO `/dc-review` |
| REVIEW | `/dc-review` | reviewer (opus) | → TASK COMPLETE |

**Skip condition**: ≤5 lines, 1 file, no new behavior → BUILD directly.

### Verify/Fix Loop (Ralph Pattern)

When BUILD or VERIFY fails, the harness handles recovery automatically:

```
1. Hook detects gradle failure → extracts normalized error signature (MD5)
2. Attempt < maxRetryOnFail AND not same error repeated:
   → Agent runs /build-fix → re-runs /verify (automatic)
3. Same error ≥ noProgressThreshold (3) → ESCALATE to user
4. Total attempts ≥ maxRetryOnFail (3) → FORCE_ACCEPT with warning
```

State persists in `.claude/verify-fix-state.json` — survives context resets.

---

## Structure

```
agent-skills/
├── CLAUDE.md                          # Harness entry point (~800 tokens)
├── skills/                            # 19 skills (flat, auto-discovered)
│   ├── bootstrap/                    # Enforcement engine (SessionStart hook)
│   ├── spring-patterns/              # MVC + WebFlux + Boot patterns
│   ├── spring-security/              # Auth, JWT, CORS, OWASP
│   ├── database-patterns/            # PostgreSQL, MySQL, JPA, R2DBC, migrations
│   ├── messaging-patterns/           # Kafka + RabbitMQ
│   ├── testing-workflow/             # TDD, blackbox, verification pipeline
│   ├── coding-standards/             # Java 17+ standards + patterns
│   ├── architecture/                 # Hexagonal, CQRS, solution design
│   ├── api-design/                   # REST conventions, pagination, RFC 7807
│   ├── redis-patterns/               # Caching, locking, Pub/Sub, Streams
│   ├── observability-patterns/       # Logging, tracing, metrics, alerting
│   ├── summer-core/                  # Summer: version detection, shared types
│   ├── summer-rest/                  # Summer: handlers, controllers, WebClient
│   ├── summer-data/                  # Summer: audit, outbox, R2DBC
│   ├── summer-security/              # Summer: APISIX, Keycloak, role sync
│   ├── summer-ratelimit/             # Summer: rate limiting (v0.2.2+)
│   ├── summer-test/                  # Summer: Testcontainers, WireMock
│   └── continuous-learning/          # Meta: pattern extraction (on-demand)
├── agents/                           # 9 specialized agents
│   ├── planner.md                   # Architecture + planning (opus)
│   ├── spec-writer.md               # Behavioral specs (opus)
│   ├── implementer.md               # TDD cycle (sonnet)
│   ├── reviewer.md                  # Unified review (opus)
│   ├── build-fixer.md               # Build error resolution (sonnet)
│   ├── test-runner.md               # E2E + blackbox tests (sonnet)
│   ├── database-reviewer.md         # DB schema/query review (sonnet)
│   ├── refactorer.md               # Dead code cleanup (sonnet)
│   └── pentest.md                  # Security penetration testing (sonnet)
├── commands/                         # 14 slash commands
│   ├── plan.md                      # Start planning
│   ├── spec.md                      # Define contracts
│   ├── build.md                     # TDD cycle
│   ├── verify.md                    # Verification pipeline
│   ├── dc-review.md                 # Multi-aspect review
│   ├── dc-setup.md                  # Project install
│   ├── dc-status.md                 # Health check + metrics
│   ├── build-fix.md                 # Fix build errors
│   ├── refactor.md                  # Dead code cleanup
│   ├── db-migrate.md               # Database migrations
│   ├── e2e.md                       # E2E test generation
│   ├── meta.md                      # learn, evolve, instinct, create-skill
│   ├── pentest-scan.md             # Security penetration testing
│   └── threat-model.md            # Threat modeling
├── rules/                            # 10 flat rules (≤500 tokens each)
│   ├── development-workflow.md
│   ├── spec-driven.md
│   ├── coding-style.md
│   ├── architecture-patterns.md
│   ├── security.md
│   ├── git-workflow.md
│   ├── api-design.md
│   ├── testing.md
│   ├── observability.md
│   └── skill-enforcement.md
├── hooks/hooks.json                  # 13 hooks across 7 lifecycle events
├── scripts/hooks/                    # 12 hook scripts + run-with-flags
│   ├── session-init.sh              # Bootstrap injection + project detection
│   ├── session-save.sh              # Session persistence + auto-extract learning
│   ├── subagent-init.sh             # Teammate context injection
│   ├── skill-router.sh             # File→skill matching
│   ├── quality-gate.sh             # Compile + debug check + format
│   ├── workflow-tracker.sh          # Phase transition tracking
│   ├── git-guard.sh                # Git operation guardrails
│   ├── compact-advisor.sh          # Token budget estimation + progressive warnings
│   ├── pre-compact.sh              # State checkpoint before compaction
│   ├── post-compact.sh             # State restoration after compaction
│   ├── verify-fix-loop.sh          # Ralph Pattern: auto-retry with circuit breakers
│   ├── build-checkpoint.sh         # BUILD file tracking for context-reset recovery
│   ├── observability-trace.sh      # Per-call JSONL traces + session metrics
│   └── run-with-flags.sh           # Hook profile manager + granular disabling
├── scripts/memory/                   # 3-tier memory management
├── config/                           # devco-config schema + defaults
├── templates/                        # PROJECT_GUIDELINES_TEMPLATE.md
└── mcp-configs/                      # MCP server configurations
```

---

## Skills (19)

### Bootstrap (auto-loaded every session)

| Skill | Description |
|---|---|
| `bootstrap` | Enforcement engine — skill discovery, workflow compliance, verify/fix loops, project detection, harness awareness |

### Generic (lazy-loaded for Java/Spring projects)

| Skill | Triggers |
|---|---|
| `spring-patterns` | Controllers, handlers, WebClient, filters, Boot config |
| `spring-security` | JWT, CORS, @PreAuthorize, secrets, OWASP |
| `database-patterns` | Repository, Entity, SQL, migrations, R2DBC |
| `messaging-patterns` | @KafkaListener, @RabbitListener, DLT/DLQ |
| `testing-workflow` | Test files, coverage, verification pipeline |
| `coding-standards` | Any Java file |
| `architecture` | Package structure, CQRS, domain events |
| `api-design` | REST endpoints, pagination, error format (RFC 7807) |
| `redis-patterns` | Redis, caching, locking, rate limiting |
| `observability-patterns` | Logging, metrics, tracing, health checks |

### Summer Framework (hard gate: `io.f8a.summer:summer-platform` required)

| Skill | Triggers |
|---|---|
| `summer-core` | Always load when summer detected |
| `summer-rest` | BaseController, RequestHandler, @Handler |
| `summer-data` | AuditService, OutboxService |
| `summer-security` | @AuthRoles, ReactiveKeycloakClient |
| `summer-ratelimit` | RateLimiterService (v0.2.2+ only) |
| `summer-test` | src/test/ + summer-test dependency |

### Security (on-demand)

| Skill | Triggers |
|---|---|
| `pentest` | `/pentest-scan`, `/threat-model`, security audit |

### Meta (on-demand)

| Skill | Triggers |
|---|---|
| `continuous-learning` | `/meta learn`, `/meta evolve` |

---

## Agents (9)

| Agent | Model | Role |
|---|---|---|
| `planner` | opus | Architecture design, task decomposition, risk assessment |
| `spec-writer` | opus | Behavioral specs, test mapping, observable contracts |
| `implementer` | sonnet | TDD cycle: RED → GREEN → REFACTOR |
| `reviewer` | opus | Unified review with 7 conditional checklists |
| `build-fixer` | sonnet | Fix build/compilation errors, minimal diffs |
| `test-runner` | sonnet | E2E + blackbox test generation & execution |
| `database-reviewer` | sonnet | DB schema, query optimization, migration review |
| `refactorer` | sonnet | Dead code cleanup, consolidation |
| `pentest` | sonnet | Security penetration testing, vulnerability scanning |

---

## Hooks (13)

4 profiles controlled by `HOOK_PROFILE` env var or `devco-config.json`:

| Profile | Active Hooks |
|---------|-------------|
| `minimal` | session-init, session-save |
| `standard` (default) | + skill-router, quality-gate, compact-advisor, workflow-tracker, verify-fix-loop, build-checkpoint, observability-trace |
| `strict` | + pre-compact, post-compact, git-guard, subagent-init |
| `off` | None (not recommended) |

| Hook | Event | Type | Description |
|---|---|---|---|
| `session-init` | SessionStart | sync | Bootstrap injection + project detection + memory restore |
| `subagent-init` | SubagentStart | sync | Teammate context injection |
| `skill-router` | PreToolUse | sync | File→skill matching before edits |
| `compact-advisor` | PreToolUse | sync | Token budget estimation, progressive warnings at 70/85/95% |
| `workflow-tracker` | PreToolUse | async | Phase transition tracking |
| `quality-gate` | PostToolUse | sync | Compile check + debug audit + format enforcement |
| `verify-fix-loop` | PostToolUse | sync | Ralph Pattern: error detection → retry → circuit breaker |
| `build-checkpoint` | PostToolUse | async | Track file edits during BUILD for recovery |
| `observability-trace` | PostToolUse | async | JSONL traces + aggregated session metrics |
| `git-guard` | PostToolUse | sync | Git operation guardrails |
| `pre-compact` | PreCompact | sync | State checkpoint before compaction |
| `post-compact` | PostCompact | sync | State restoration after compaction |
| `session-save` | Stop | sync | Session summary + auto-extract learning signal |

Granular disabling: `DISABLED_HOOKS="hook1,hook2"` env var or `devco-config.json → hooks.disabled[]`.

---

## State Files (on disk, not in context)

| File | Purpose | Written By |
|---|---|---|
| `.claude/project-profile.json` | Detected stack, framework type | session-init |
| `.claude/workflow-state.json` | Current phase, history, decisions | workflow-tracker |
| `.claude/verify-fix-state.json` | Error signatures, retry counts | verify-fix-loop |
| `.claude/sessions/build-checkpoint.json` | Modified files during BUILD | build-checkpoint |
| `.claude/sessions/execution-trace.jsonl` | Per-tool-call JSONL traces | observability-trace |
| `.claude/sessions/session-metrics.json` | Aggregated session telemetry | observability-trace |
| `.claude/devco-config.json` | User/project configuration | user / dc-setup |

---

## Configuration

Settings in `.claude/devco-config.json`. Default mode: `standard`.

Key settings:

| Setting | Default | Effect |
|---------|---------|--------|
| `workflow.autoVerify` | `true` | Auto-invoke `/verify full` after BUILD |
| `workflow.autoReview` | `true` | Auto-invoke `/dc-review` after VERIFY |
| `workflow.maxRetryOnFail` | `3` | Max verify retries before force-accept |
| `workflow.noProgressThreshold` | `3` | Same error N times → escalate |
| `workflow.maxIterationsPerPhase` | `10` | Absolute ceiling per phase |
| `team.enabled` | `false` | Enable multi-agent team |
| `team.maxTeammates` | `3` | Max parallel subagents |
| `hooks.profile` | `standard` | Hook activation profile |
| `hooks.disabled` | `[]` | Granular hook disabling |

See `config/devco-config.schema.json` for full schema and `config/defaults.json` for all defaults.

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

## Changelog

### v3.2.0 (2026-04-02)

**Harness Engineering upgrade** — 3 new hooks, 4 upgraded scripts, bootstrap rewrite.

- **Verify/Fix Loop** (`verify-fix-loop.sh`): Ralph Pattern — auto-detects gradle failures, extracts normalized error signatures, retries with circuit breakers (same-error escalation + max-retry force-accept)
- **Observability Traces** (`observability-trace.sh`): Every tool call traced to JSONL, session metrics aggregated (tool distribution, skill usage, phase timing, quality gate violations)
- **BUILD Checkpoint** (`build-checkpoint.sh`): Tracks file edits during BUILD for context-reset recovery
- **Context Budget** (`compact-advisor.sh` v3.2): Real token estimation replacing proxy metrics, dual-triggered thresholds (call count OR budget %)
- **Auto-Extract Learning** (`session-save.sh` v3.2): Signals productive sessions (>20 calls, >3 file changes) for pattern extraction
- **Hook Profiles** (`run-with-flags.sh` v3.2): Granular `DISABLED_HOOKS` override, all new hooks integrated into profiles
- **Bootstrap SKILL.md**: Added Ralph Loop, Checkpoint-Resume, Operational Awareness sections (1,700 tokens)
- **13 hooks** across 7 lifecycle events (up from 6 hooks in v3.0)

### v3.0.3

- Initial public release with 19 skills, 9 agents, 6 hooks, 14 commands

---

## License

MIT — built by [TaiPT](https://github.com/taipt1504)
