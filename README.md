# Agent Skills

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

Interactive setup walks you through mode selection (standard/yolo/strict), workflow options (auto-verify, auto-review, max retries), and team features. Or use `--mode standard` to skip prompts.

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

| Harness Component      | Implementation                                                                        |
| ---------------------- | ------------------------------------------------------------------------------------- |
| **Tool Orchestration** | 13 hooks across 7 lifecycle events, skill-router auto-matching                        |
| **Knowledge Curation** | 21 domain skills, 3-tier lazy loading, progressive disclosure                         |
| **Context Management** | Token budget estimation, progressive unload warnings at 70/85/95%                     |
| **State Persistence**  | workflow-state.json, verify-fix-state.json, build-checkpoint.json — all on disk       |
| **Verification Loops** | Ralph Pattern: detect failure → extract error signature → retry with circuit breakers |
| **Observability**      | execution-trace.jsonl (per-call), session-metrics.json (aggregated)                   |
| **Evaluation**         | 9-criteria benchmark framework, 15 eval tasks, automated session scoring              |

### Hook-Bootstrapped Enforcement

```
SessionStart hook → injects bootstrap/SKILL.md
  → Agent learns: search skills → announce → use → follow workflow
  → Auto-detects: Java/Spring type, Summer Framework, project structure
  → Lazy loads: domain skills on demand, progressive disclosure
```

### Context Budget

| Scope                       | Token Limit |
| --------------------------- | ----------- |
| Bootstrap skill             | ≤ 1,700     |
| CLAUDE.md                   | ≤ 1,000     |
| Each domain skill           | ≤ 800       |
| Each rule                   | ≤ 500       |
| Auto-loaded per session     | ≤ 5,000     |
| Max with lazy-loaded skills | ≤ 15,000    |

### 5-Phase Workflow

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

| Phase  | Command      | Agent                | Auto-Transition     |
| ------ | ------------ | -------------------- | ------------------- |
| PLAN   | `/plan`      | planner (opus)       | → remind `/spec`    |
| SPEC   | `/spec`      | spec-writer (opus)   | → remind `/build`   |
| BUILD  | `/build`     | implementer (sonnet) | → AUTO `/verify`    |
| VERIFY | `/verify`    | pipeline             | → AUTO `/dc-review` |
| REVIEW | `/dc-review` | reviewer (opus)      | → TASK COMPLETE     |

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
├── skills/                            # 21 skills (flat, auto-discovered)
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
│   ├── deployment-patterns/          # Docker, K8s, CI/CD, health probes
│   ├── grpc-patterns/               # gRPC, protobuf, streaming, interceptors
│   ├── pentest/                     # Security scanner, OWASP, CVE patterns
│   ├── summer-core/                  # Summer: version detection, shared types
│   ├── summer-rest/                  # Summer: handlers, controllers, WebClient
│   ├── summer-data/                  # Summer: audit, outbox, R2DBC
│   ├── summer-security/              # Summer: APISIX, Keycloak, role sync
│   ├── summer-ratelimit/             # Summer: rate limiting (v0.2.2+)
│   ├── summer-test/                  # Summer: Testcontainers, WireMock
│   └── continuous-learning/          # Meta: pattern extraction (on-demand)
├── agents/                           # 9 specialized agents
│   ├── _shared-protocol.md          # Common agent protocol
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
│   ├── plan.md, spec.md, build.md  # Workflow phase commands
│   ├── verify.md, dc-review.md     # Verification + review
│   ├── dc-setup.md, dc-status.md   # Project install + health check
│   ├── build-fix.md, refactor.md   # Fix + cleanup
│   ├── db-migrate.md, e2e.md       # Database + E2E tests
│   ├── meta.md                      # learn, evolve, instinct, create-skill
│   ├── pentest-scan.md             # Security penetration testing
│   └── threat-model.md            # Threat modeling
├── evals/                            # Benchmark & evaluation framework
│   ├── tasks/                       # 15 eval tasks across 6 categories
│   ├── rubrics/                     # 9-criteria scoring + grader prompt
│   └── scripts/                     # Benchmark runner, session scorer, aggregator
├── rules/                            # 10 production-grounded rules
├── hooks/hooks.json                  # 13 hooks across 7 lifecycle events
├── scripts/hooks/                    # 12 hook scripts + run-with-flags
├── scripts/memory/                   # 3-tier memory management
├── tests/                            # Hook + skill trigger tests
├── config/                           # devco-config schema + defaults
├── templates/                        # PROJECT_GUIDELINES_TEMPLATE.md
├── docs/                             # Design documents
└── mcp-configs/                      # MCP server configurations
```

---

## Skills (21)

### Bootstrap (auto-loaded every session)

| Skill       | Description                                                                                                       |
| ----------- | ----------------------------------------------------------------------------------------------------------------- |
| `bootstrap` | Enforcement engine — skill discovery, workflow compliance, verify/fix loops, project detection, harness awareness |

### Domain (lazy-loaded, progressive disclosure)

| Skill                    | Refs | Scripts | Triggers                                               |
| ------------------------ | ---- | ------- | ------------------------------------------------------ |
| `spring-patterns`        | 4    | 0       | Controllers, handlers, WebClient, filters, Boot config |
| `spring-security`        | 5    | 0       | JWT, CORS, @PreAuthorize, secrets, OWASP               |
| `database-patterns`      | 5    | 1       | Repository, Entity, SQL, migrations, R2DBC             |
| `messaging-patterns`     | 4    | 0       | @KafkaListener, @RabbitListener, DLT/DLQ               |
| `testing-workflow`       | 3    | 1       | Test files, coverage, verification pipeline            |
| `coding-standards`       | 1    | 0       | Any Java file                                          |
| `architecture`           | 4    | 0       | Package structure, CQRS, domain events                 |
| `api-design`             | 2    | 0       | REST endpoints, pagination, error format (RFC 7807)    |
| `redis-patterns`         | 4    | 0       | Redis, caching, locking, rate limiting                 |
| `observability-patterns` | 3    | 0       | Logging, metrics, tracing, health checks               |
| `deployment-patterns`    | 4    | 1       | Dockerfile, K8s, CI/CD, health probes                  |
| `grpc-patterns`          | 4    | 0       | Proto files, @GrpcService, streaming                   |

### Security (on-demand)

| Skill     | Refs | Scripts | Triggers                                         |
| --------- | ---- | ------- | ------------------------------------------------ |
| `pentest` | 5    | 6       | `/pentest-scan`, `/threat-model`, security audit |

### Summer Framework (hard gate: `io.f8a.summer:summer-platform` required)

| Skill              | Triggers                                 |
| ------------------ | ---------------------------------------- |
| `summer-core`      | Always load when summer detected         |
| `summer-rest`      | BaseController, RequestHandler, @Handler |
| `summer-data`      | AuditService, OutboxService              |
| `summer-security`  | @AuthRoles, ReactiveKeycloakClient       |
| `summer-ratelimit` | RateLimiterService (v0.2.2+ only)        |
| `summer-test`      | src/test/ + summer-test dependency       |

### Meta (on-demand)

| Skill                 | Scripts | Triggers                      |
| --------------------- | ------- | ----------------------------- |
| `continuous-learning` | 1       | `/meta learn`, `/meta evolve` |

---

## Agents (9)

All agents share a common protocol (`_shared-protocol.md`) enforcing skill usage, memory management, and workflow compliance.

| Agent               | Model  | Role                                                     |
| ------------------- | ------ | -------------------------------------------------------- |
| `planner`           | opus   | Architecture design, task decomposition, risk assessment |
| `spec-writer`       | opus   | Behavioral specs, test mapping, observable contracts     |
| `implementer`       | sonnet | TDD cycle: RED → GREEN → REFACTOR                        |
| `reviewer`          | opus   | Unified review with 7 conditional checklists             |
| `build-fixer`       | sonnet | Fix build/compilation errors, minimal diffs              |
| `test-runner`       | sonnet | E2E + blackbox test generation & execution               |
| `database-reviewer` | sonnet | DB schema, query optimization, migration review          |
| `refactorer`        | sonnet | Dead code cleanup, consolidation                         |
| `pentest`           | sonnet | Security penetration testing, vulnerability scanning     |

---

## Hooks (13)

4 profiles controlled by `HOOK_PROFILE` env var or `devco-config.json`:

| Profile              | Active Hooks                                                                                                            |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `minimal`            | session-init, session-save                                                                                              |
| `standard` (default) | + skill-router, quality-gate, compact-advisor, workflow-tracker, verify-fix-loop, build-checkpoint, observability-trace |
| `strict`             | + pre-compact, post-compact, git-guard, subagent-init                                                                   |
| `off`                | None (not recommended)                                                                                                  |

| Hook                  | Event         | Type  | Description                                                |
| --------------------- | ------------- | ----- | ---------------------------------------------------------- |
| `session-init`        | SessionStart  | sync  | Bootstrap injection + project detection + memory restore   |
| `subagent-init`       | SubagentStart | sync  | Teammate context injection                                 |
| `skill-router`        | PreToolUse    | sync  | File→skill matching before edits                           |
| `compact-advisor`     | PreToolUse    | sync  | Token budget estimation, progressive warnings at 70/85/95% |
| `workflow-tracker`    | PreToolUse    | async | Phase transition tracking                                  |
| `quality-gate`        | PostToolUse   | sync  | Compile check + debug audit + secret scanning              |
| `verify-fix-loop`     | PostToolUse   | sync  | Ralph Pattern: error detection → retry → circuit breaker   |
| `build-checkpoint`    | PostToolUse   | async | Track file edits during BUILD for recovery                 |
| `observability-trace` | PostToolUse   | async | JSONL traces + aggregated session metrics                  |
| `git-guard`           | PostToolUse   | sync  | Git operation guardrails                                   |
| `pre-compact`         | PreCompact    | sync  | State checkpoint before compaction                         |
| `post-compact`        | PostCompact   | sync  | State restoration after compaction                         |
| `session-save`        | Stop          | sync  | Session summary + auto-extract learning signal             |

---

## Evaluation & Benchmarking

The plugin includes a built-in evaluation framework (`evals/`) to measure agent effectiveness across **9 criteria**:

| # | Criterion | Weight | What it measures |
|---|-----------|--------|------------------|
| 1 | Code Quality | 15% | Compile, tests, violations, coverage |
| 2 | Convention Compliance | 10% | CLAUDE.md hard blocks (`.block()`, `@Autowired` field, etc.) |
| 3 | Workflow Compliance | 10% | 5-phase workflow adherence |
| 4 | Skill Utilization | 15% | Are agents using skills/commands effectively? |
| 5 | Skill Trigger Accuracy | 10% | Right skill loaded for right task |
| 6 | Context & Memory | 10% | Progressive disclosure, memory cross-session |
| 7 | Task Completion | 15% | REVIEW pass rate, verify retries |
| 8 | Execution Optimality | 10% | Tool call efficiency, recovery speed |
| 9 | Cross-Session Memory | 5% | Recall, accuracy, knowledge graph updates |

### Running Benchmarks

```bash
# Score a real session (0 extra tokens)
python3 evals/scripts/score-session.py --project-dir /path/to/project

# Full benchmark (15 tasks × N runs × with/without plugin)
bash evals/scripts/run-benchmark.sh --project-dir /path/to/project --runs 1

# Aggregate results
python3 evals/scripts/aggregate-scores.py --results-dir evals/results/
```

15 eval tasks across 6 categories: feature development, bug fix, security review, database, deployment, TDD, refactoring, multi-skill composition, context stress testing, and cross-session memory.

---

## State Files (on disk, not in context)

| File                                     | Purpose                           | Written By          |
| ---------------------------------------- | --------------------------------- | ------------------- |
| `.claude/project-profile.json`           | Detected stack, framework type    | session-init        |
| `.claude/workflow-state.json`            | Current phase, history, decisions | workflow-tracker    |
| `.claude/verify-fix-state.json`          | Error signatures, retry counts    | verify-fix-loop     |
| `.claude/sessions/build-checkpoint.json` | Modified files during BUILD       | build-checkpoint    |
| `.claude/sessions/execution-trace.jsonl` | Per-tool-call JSONL traces        | observability-trace |
| `.claude/sessions/session-metrics.json`  | Aggregated session telemetry      | observability-trace |
| `.claude/devco-config.json`              | User/project configuration        | user / dc-setup     |

---

## Configuration

Settings in `.claude/devco-config.json`. Default mode: `standard`.

Key settings:

| Setting                          | Default    | Effect                                 |
| -------------------------------- | ---------- | -------------------------------------- |
| `workflow.autoVerify`            | `true`     | Auto-invoke `/verify full` after BUILD |
| `workflow.autoReview`            | `true`     | Auto-invoke `/dc-review` after VERIFY  |
| `workflow.maxRetryOnFail`        | `3`        | Max verify retries before force-accept |
| `workflow.noProgressThreshold`   | `3`        | Same error N times → escalate          |
| `workflow.maxIterationsPerPhase` | `10`       | Absolute ceiling per phase             |
| `team.enabled`                   | `false`    | Enable multi-agent team                |
| `team.maxTeammates`              | `3`        | Max parallel subagents                 |
| `hooks.profile`                  | `standard` | Hook activation profile                |
| `hooks.disabled`                 | `[]`       | Granular hook disabling                |

See `config/devco-config.schema.json` for full schema and `config/defaults.json` for all defaults.

---

## Team Onboarding

**Target: productive in 2 minutes.**

### Lead dev (one-time)

```bash
/plugin marketplace add taipt1504/agent-skills
/plugin install devco-agent-skills
/setup                  # interactive: choose mode, workflow options, team features
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

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC · R2DBC · JPA/Hibernate · Kafka · RabbitMQ · Redis · PostgreSQL · MySQL · Docker · Kubernetes · gRPC · Testcontainers · Summer Framework (io.f8a.summer)

---

## Changelog

### v3.2.1 (2026-04-07)

**Version centralization + Summer skill updates** — eliminated hardcoded version strings, standardized API path routing.

- **Version management**: centralized in `package.json` + `.claude-plugin/plugin.json` only. Removed hardcoded versions from `session-init.sh`, `subagent-init.sh`, `setup-kit.sh` (now reads from `package.json` dynamically)
- **summer-rest**: API path format corrected to `/{prefix}/api/{resource}/{version}/...` — all prefixes now include `/api/` segment (`/bo/api/**`, `/internal/api/**`, `/partner/api/**`, `/public/api/**`, `/api/**`)
- **summer-security**: enforced 7 mandatory actions (view, create, update, delete, approve, import, export) per resource; Vietnamese names for `@FeatureDef`/`@ResourceDef`
- **api-design**: decoupled resource mapping (`/api/{resource}`) from versioning (`/v1/...`) for per-resource version bumps

### v3.2.0 (2026-04-05)

**Skill optimization + Evaluation framework** — progressive disclosure enforcement, 4 new automation scripts, benchmark system with 9-criteria scoring.

#### Skill Optimization

- **deployment-patterns** refactored: 305→116 lines SKILL.md + 4 reference files (dockerfile.md, kubernetes.md, cicd.md, health-probes.md) — was the worst anti-pattern, now follows gold standard
- **3 thin references expanded**: observability/logging.md (70→208 lines with ELK/Loki), summer-data/ddl-scripts.md (92→232 lines with AuditService/OutboxService impl), summer-ratelimit/policy-examples.md (99→255 lines with distributed Redis, multi-tenant)
- **4 automation scripts created**: `generate-test-scaffold.sh` (testing-workflow), `validate-migration.sh` (database-patterns), `generate-dockerfile.sh` (deployment-patterns), `extract-instincts.sh` (continuous-learning)
- **13 frontmatter descriptions optimized**: all now include "Use when..." trigger scenarios for better skill routing accuracy
- **QUICKSTART.md deleted**: not auto-loaded by Claude Code, wasted context

#### Evaluation Framework (`evals/`)

- **9-criteria scoring rubric**: code quality, convention compliance, workflow compliance, skill utilization effectiveness, trigger accuracy, context efficiency & memory, task completion, execution optimality, cross-session memory
- **15 eval tasks** across 6 categories: CRUD API, bug fix, Kafka consumer, security review, DB migration, Redis caching, gRPC service, deployment, Summer rate limiting, hexagonal refactor, observability, TDD, cross-session memory, multi-skill composition, context stress
- **3 benchmark scripts**: `score-session.py` (score real sessions from traces — 0 token cost), `run-benchmark.sh` (orchestrate with/without-plugin comparison), `aggregate-scores.py` (statistics + trend analysis)
- **Grader agent prompt**: LLM-as-judge for qualitative criteria

#### Infrastructure Improvements (from improvement plan items 2.4–5.4)

- **Shared agent protocol** (`_shared-protocol.md`): extracted ~270 lines of duplicate boilerplate from 9 agents
- **Agent frontmatter**: all agents now declare `protocol:` and `phase:` fields
- **Quality gate**: strict mode blocking for HIGH violations + secret pattern scanning (AWS keys, API tokens, passwords, Bearer tokens)
- **Observability traces v2**: schema versioning, configurable retention policy, automatic cleanup
- **Skill dependencies**: all Summer skills declare `requires:` field for proper load ordering
- **Architecture skill expanded**: 94→303 lines with full code examples (Aggregate Root, Value Objects, CQRS, Ports wiring)
- **grpc-patterns promoted**: from docs/optional-skills/ to full skill with 4 reference files
- **Hook tests**: 28 tests across 3 test files + stress test + CI pipeline
- **Skill trigger tests**: 10 validation tests for skill structure compliance
- **`.gitignore`**: runtime state files excluded

### v3.1.0 (2026-04-02)

**Harness Engineering upgrade** — 3 new hooks, 4 upgraded scripts, bootstrap rewrite, rules deep upgrade, skill cross-references, interactive setup.

### v3.0.3 (initial release)

- 19 skills, 9 agents, 6 hooks, 14 commands, 10 rules

---

## License

MIT — built by [TaiPT](https://github.com/taipt1504)
