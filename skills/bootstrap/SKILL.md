---
name: bootstrap
description: >
  Core enforcement engine for devco-agent-skills plugin. Loaded automatically at session start
  via SessionStart hook. Teaches the agent: skill discovery, workflow compliance, project detection,
  and mandatory skill usage. This skill is the foundation — all other skills depend on it.
---

# EXTREMELY IMPORTANT: You Have Skills. Use Them.

You are enhanced with a skill system. Before EVERY action, you MUST:

1. **Search** available skills for a match
2. **Announce** which skill you are using: "Using skill: {name} for {reason}"
3. **Load** the skill's SKILL.md if not already loaded
4. If no skill matches: state "No matching skill found, proceeding with general knowledge"

**There are NO exceptions.** Even if you are "1% unsure", search skills first.

## Project Detection (run once per session)

```
1. Scan build.gradle / build.gradle.kts / pom.xml
2. No build file found? → NOT a Java project → skip all skills
3. Java project detected:
   a. spring-boot-starter-webflux? → Spring WebFlux (Reactive)
   b. spring-boot-starter-web?     → Spring MVC (Servlet)
   c. Neither?                     → Plain Java
4. io.f8a.summer:summer-platform?  → Summer Framework → ALSO load summer skills
   NOT found? → NEVER load/suggest/apply summer patterns
```

## Skill Registry

### Generic Skills (Java/Spring projects)

| Skill | Trigger (file patterns / imports) |
|-------|----------------------------------|
| `spring-patterns` | *Controller.java, *Handler.java, WebClient, filters, interceptors, pagination |
| `spring-security` | *SecurityConfig*, JWT, CORS, @PreAuthorize, @AuthRoles, secrets |
| `database-patterns` | *Repository.java, *.sql, Entity, migration, pool config, R2DBC |
| `messaging-patterns` | Kafka*, Rabbit*, @KafkaListener, @RabbitListener, DLT, DLQ |
| `testing-workflow` | *Test.java, test commands, coverage, verification |
| `coding-standards` | Any Java file (general coding patterns) |
| `api-design` | REST endpoints, DTO design, pagination, error format |
| `redis-patterns` | Redis*, cache config, Redisson, rate limiting with Redis |
| `observability-patterns` | Logging config, metrics, tracing, health checks, alerting |
| `architecture` | Package structure, hexagonal layers, CQRS, domain events |

### Summer Skills (ONLY when summer-platform detected)

| Skill | Trigger |
|-------|---------|
| `summer-core` | Always load when summer detected (shared types, version) |
| `summer-rest` | BaseController, RequestHandler, @Handler, WebClientBuilderFactory |
| `summer-data` | AuditService, OutboxService, f8a.audit.*, f8a.outbox.* |
| `summer-security` | @AuthRoles, ReactiveKeycloakClient, f8a.security.* |
| `summer-ratelimit` | RateLimiterService, f8a.rate-limiter.* (v0.2.2+ only) |
| `summer-test` | src/test/ + summer-test dependency |

### Meta Skills (on-demand only)

| Skill | Trigger |
|-------|---------|
| `continuous-learning` | `/meta learn`, `/meta evolve`, `/meta instinct` |

## Workflow Engine — 5 Phases

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

### Phase Rules

| Phase | Entry | Agent | Exit |
|-------|-------|-------|------|
| **PLAN** | User task or `/plan` | planner | User approves plan |
| **SPEC** | `/spec` after plan approved | spec-writer | User approves spec |
| **BUILD** | After spec approved | implementer (1 subagent per task) | All tests pass |
| **VERIFY** | Auto after build or `/verify` | (pipeline) | All checks pass |
| **REVIEW** | Auto after verify or `/review` | reviewer | No blocking issues |

### Skip Condition

IF ALL true: ≤5 lines, 1 file, no new behavior, no arch impact, no schema change
THEN → BUILD directly (skip PLAN + SPEC)

### Hard Blocks (STOP immediately if violated)

- Writing code without approved plan → STOP → `/plan` first
- Writing code without approved spec → STOP → `/spec` first
- No tests → BLOCK — code does not ship without tests
- `.block()` in src/main/ → CRITICAL — fix immediately
- Agent attempts git commit → FORBIDDEN — only user commits

## Subagent Isolation (BUILD phase)

Each task from the approved spec → **spawn 1 separate Agent** (implementer) with:
- Task description + relevant spec scenario
- Loaded skills matching files being touched
- Summary of prior completed tasks (NOT full context)

Execute continuously per task. If blocked → ask user. After each task → 2-stage review: spec compliance first, then code quality.

## Skill Loading Protocol

```
Session start → load ONLY: bootstrap (this file)
               + summer-core (if io.f8a.summer detected)
On-demand    → load when touching relevant files:
  1. Detect which files are being modified
  2. Match file patterns → skill from registry above
  3. Load that skill's SKILL.md (≤800 tokens each)
  4. Load references/*.md ONLY when deep detail needed
```

## Commands Quick Reference

| Command | Phase |
|---------|-------|
| `/plan` | Start planning |
| `/spec` | Define contracts |
| `/build` | TDD cycle |
| `/verify` | Run verification pipeline |
| `/review` | Multi-aspect code review |
| `/build-fix` | Fix compilation errors |
| `/e2e` | E2E test generation |
| `/db-migrate` | Database migration |
| `/refactor` | Dead code cleanup |
| `/setup` | Project install |
| `/status` | Plugin health check |
| `/meta` | Learning & evolution |
