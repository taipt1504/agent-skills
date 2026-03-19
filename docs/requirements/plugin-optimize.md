# Requirements: Optimize DevCo Agent Skills Plugin

> **Final Version** — validated & consolidated

## Vision

Build một **lightweight, high-quality agent skills plugin** cho Claude Code, custom cho Java Spring backend development. Plugin phải đạt được: agent output tốt nhất có thể, context-efficient, dễ onboard cho team member.

## References

| Repo                                                                         | Stars (~3/2026) | Triết lý cốt lõi lấy được                                                                                                                                                                                                         |
| ---------------------------------------------------------------------------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [superpowers](https://github.com/obra/superpowers)                           | ~95k            | Skills trigger tự động, **subagent-per-task bắt buộc** (v5+), plans execute continuously, brainstorm → plan → implement, "1% cũng phải dùng skill"                                                                                |
| [everything-claude-code](https://github.com/affaan-m/everything-claude-code) | ~73-82k         | Instinct-based learning, confidence scoring, AgentShield security scanning, cross-harness parity                                                                                                                                  |
| [get-shit-done](https://github.com/gsd-build/get-shit-done)                  | ~35k            | **Fresh session per unit** (context isolation triệt để), discuss → plan → execute → verify → ship per phase, context pre-loading, persistent debug knowledge base, **gsd-2 evolve thành standalone CLI với real context control** |

## Scope & Constraints

**Phase hiện tại: Backend Plugin only**

- **Language**: Java 17+ (primary), Java 11 (legacy — Spring MVC only, không support WebFlux)
- **Framework**: Spring Boot MVC, Spring WebFlux, Spring Security, Hibernate/JPA, R2DBC
- **Internal Framework**: Summer Framework (`io.f8a.summer`) — reactive Spring Boot library
- **Infra**: Redis, Kafka, RabbitMQ, PostgreSQL, MySQL
- **Testing**: JUnit 5, Testcontainers, StepVerifier, Blackbox/E2E

### Compliance Architecture

> **CLAUDE.md KHÔNG phải mechanism chính.** Dựa vào research thực tế:
>
> | Level | Mechanism                             | Compliance |
> | ----- | ------------------------------------- | ---------- |
> | 1     | CLAUDE.md passive rules               | ~60%       |
> | 2     | CLAUDE.md assertive + stop conditions | ~75%       |
> | 3     | Hooks (PreToolUse/PostToolUse)        | ~85%       |
> | 4     | Skill state machine + announce        | ~92%       |
> | 5     | All combined                          | ~95%       |
>
> **Plugin phải target Level 4-5.** Mechanism chính là **hook-bootstrapped skill** (pattern Superpowers), không phải CLAUDE.md.

#### Bootstrap pattern (học từ Superpowers)

```
SessionStart hook → inject EXTREMELY_IMPORTANT prompt
  → Agent đọc skills/bootstrap/SKILL.md
    → Skill dạy agent:
       1. You have skills. Search before EVERY action.
       2. If a skill exists, you MUST use it. No exceptions.
       3. ANNOUNCE which skill you are using before starting.
       4. Detect project type → load right skill set.
```

**Tại sao không dùng CLAUDE.md làm core:**

- Dự án thực tế có thể có nhiều CLAUDE.md (project root, subdirectories, team conventions) → conflict
- CLAUDE.md là passive — agent đọc 1 lần rồi "quên" dần khi context đầy
- Hook + skill = active enforcement — hook fire mỗi session, skill được agent internalize như mandatory behavior

**CLAUDE.md vẫn tồn tại** nhưng vai trò giảm xuống: chỉ chứa project-specific conventions (tech stack, naming, architecture decisions). KHÔNG chứa workflow engine, skill routing, hay enforcement rules — tất cả nằm trong bootstrap skill.

### Context Budget (hard limits)

| Scope                                                         | Token limit |
| ------------------------------------------------------------- | ----------- |
| Bootstrap skill (getting-started)                             | ≤ 1,500     |
| CLAUDE.md (project conventions only)                          | ≤ 1,000     |
| Mỗi skill SKILL.md body                                       | ≤ 800       |
| Mỗi rule file                                                 | ≤ 500       |
| Auto-loaded per session (bootstrap + rules + detected skills) | ≤ 5,000     |
| Max với tất cả lazy-loaded domain skills                      | ≤ 15,000    |

> **Nguyên tắc bất di bất dịch**: Agent phải auto-detect project dùng Language/Framework gì (từ `build.gradle`/`pom.xml`/imports) để invoke đúng rules, skills, commands. Không detect được = không làm gì cả.

---

## Mục tiêu 1: Tái cấu trúc Agents, Skills, Commands, Rules

### 1.1 Phân tầng — 3 layers

| Layer      | Vai trò                                                  | Load khi nào                        |
| ---------- | -------------------------------------------------------- | ----------------------------------- |
| **Core**   | Workflow engine, project detection, skill router         | Luôn luôn (mỗi session)             |
| **Domain** | Generic Java/Spring patterns + Summer Framework patterns | Lazy — chỉ khi project detect match |
| **Meta**   | Learning, compact, evolve, skill authoring               | On-demand — chỉ khi user gọi        |

### 1.2 Consolidate Generic Skills (24 → 10)

**Merge plan:**

| Skill mới                | Gộp từ                                                                  | Lý do                                                           |
| ------------------------ | ----------------------------------------------------------------------- | --------------------------------------------------------------- |
| `spring-patterns`        | spring-mvc-patterns + spring-webflux-patterns + springboot-patterns     | Cùng Spring ecosystem, conditional sections theo MVC vs WebFlux |
| `spring-security`        | springboot-security + security-review + rules/\*/security.md            | Security tản mạn 4 nơi                                          |
| `database-patterns`      | postgres-patterns + mysql-patterns + jpa-patterns + database-migrations | Cùng data layer, conditional theo DB engine                     |
| `messaging-patterns`     | kafka-patterns + rabbitmq-patterns                                      | Cùng async messaging domain                                     |
| `testing-workflow`       | tdd-workflow + blackbox-test + verification                             | Cùng testing lifecycle                                          |
| `coding-standards`       | coding-standards + java-patterns                                        | Java coding = coding standards cho Java                         |
| `architecture`           | hexagonal-arch + solution-design                                        | Architecture decisions + patterns                               |
| `api-design`             | _(giữ nguyên)_                                                          | Domain riêng, trigger riêng                                     |
| `redis-patterns`         | _(giữ nguyên)_                                                          | Caching là concern riêng biệt                                   |
| `observability-patterns` | _(giữ nguyên)_                                                          | Cross-cutting concern riêng                                     |

**Remove:**

- `grpc-patterns` → remove khỏi default, chuyển thành optional skill cài riêng nếu team cần
- `strategic-compact` → chuyển thành logic trong hooks
- `continuous-learning-v2` → chuyển thành `/meta` command

### 1.3 Tách Summer Framework Skill (1 monolith → 1 router + 5 sub-skills)

Summer Framework (`io.f8a.summer`) là internal reactive Spring Boot library. Skill hiện tại gộp tất cả vào 1 SKILL.md + 5 reference files (~15-20K tokens) — vi phạm context budget nghiêm trọng.

#### Hard gate — bắt buộc

> **Summer skills KHÔNG PHẢI là generic skills.** Chúng CHỈ dành cho projects sử dụng Summer Framework.
>
> Agent PHẢI detect `io.f8a.summer:summer-platform` trong `build.gradle` hoặc `pom.xml` TRƯỚC KHI load bất kỳ summer skill nào. Không tìm thấy dependency → KHÔNG load, KHÔNG suggest, KHÔNG apply bất kỳ summer pattern nào. Không có exception.

#### 6 summer skills

| Skill              | Trigger (sau khi pass hard gate)                                                          | Nội dung                                                                                                                                                            |
| ------------------ | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `summer-core`      | Luôn load khi detect summer-platform                                                      | Version detection, shared types (`Member`, `CallerAware`, `Password`, `PhoneNumber`), module overview, `CommonExceptions` enum                                      |
| `summer-rest`      | `BaseController`, `RequestHandler`, `@Handler`, `WebClientBuilderFactory`, `f8a.common.*` | Handler pattern, controller patterns, `SpringBus`, `ResponseFactory`, exception handling, Jackson config, pooled WebClient, retry patterns                          |
| `summer-data`      | `AuditService`, `OutboxService`, `f8a.audit.*`, `f8a.outbox.*`                            | Audit logging (builder + annotation + convenience), outbox pattern, DDL scripts, R2DBC converters, table validators                                                 |
| `summer-security`  | `@AuthRoles`, `ReactiveKeycloakClient`, `f8a.security.*`, `sync-role.*`                   | APISIX auth, role definitions, `SecurityWebFilterChain`, Keycloak resource API, `KeycloakException` mapping, role synchronizer, version-specific `enable`→`enabled` |
| `summer-ratelimit` | `RateLimiterService`, `f8a.rate-limiter.*`                                                | 3 strategies, `acquire()`/`tryAcquire()`, Redis/memory storage — **v0.2.2+ only**                                                                                   |
| `summer-test`      | `src/test/` context + `summer-test` dependency                                            | `PostgresTestContainer`, `WireMockServiceManager`, blackbox config/test-case JSON                                                                                   |

**Tại sao REST + WebClient gộp**: Cùng HTTP layer. `WebClientBuilderFactory` luôn đi kèm handler/controller context.

**Tại sao Security + Keycloak gộp**: Keycloak là implementation cụ thể của security layer. Role sync, `@AuthRoles`, APISIX auth là 1 flow liền mạch.

**Version handling**: Mỗi sub-skill tự ghi version differences inline. Router `summer-core` detect version từ `gradle.properties` / BOM, set context cho sub-skills. Không tách file v0.2.x.md riêng.

### 1.4 Consolidate Agents (15 → 8)

| Agent               | Vai trò                                                                          | Model  |
| ------------------- | -------------------------------------------------------------------------------- | ------ |
| `planner`           | Decompose task, risk assess, architecture decisions                              | opus   |
| `spec-writer`       | Behavioral spec, test mapping                                                    | opus   |
| `implementer`       | TDD cycle: RED → GREEN → REFACTOR per task                                       | sonnet |
| `reviewer`          | Code + security + performance + spring + reactive review (conditional checklist) | opus   |
| `build-fixer`       | Fix build/compile errors, minimal diff                                           | sonnet |
| `test-runner`       | E2E, blackbox, integration test generation & execution                           | sonnet |
| `database-reviewer` | DB schema, query, migration review (conditional — chỉ khi task liên quan DB)     | sonnet |
| `refactorer`        | Dead code cleanup, refactor (on-demand only)                                     | sonnet |

### 1.5 Consolidate Commands (21 → 12)

**Core (luôn có):**

| Command   | Chức năng                             |
| --------- | ------------------------------------- |
| `/plan`   | Decompose task → approved plan        |
| `/spec`   | Behavioral spec → approved spec       |
| `/build`  | TDD cycle per step                    |
| `/verify` | Build + test + security scan pipeline |
| `/review` | Multi-aspect code review              |
| `/setup`  | One-time project install              |
| `/status` | Health check, plugin state            |

**On-demand:**

| Command       | Chức năng                                  |
| ------------- | ------------------------------------------ |
| `/build-fix`  | Fix build/compile errors                   |
| `/refactor`   | Dead code cleanup                          |
| `/db-migrate` | Database migration workflow                |
| `/e2e`        | E2E test generation & run                  |
| `/meta`       | Subcommands: `learn`, `evolve`, `instinct` |

### 1.6 Consolidate Rules (15 → 9)

| Rule                       | Scope                             |
| -------------------------- | --------------------------------- |
| `development-workflow.md`  | Core 5-phase workflow             |
| `spec-driven.md`           | Spec-driven mandate               |
| `coding-style.md`          | Merged common + java coding style |
| `architecture-patterns.md` | Merged patterns + reactive        |
| `security.md`              | Merged common + java security     |
| `git-workflow.md`          | Commit conventions                |
| `api-design.md`            | REST conventions                  |
| `testing.md`               | Testing standards                 |
| `observability.md`         | Logging, tracing, metrics         |

---

## Mục tiêu 2: Workflow Engine

### 2.1 Spec-Driven Development — 5 phase

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

BOOT (project detection, context restore) và LEARN (pattern extraction) được handle bởi hooks, không phải workflow phases. Agent không cần biết mình đang "ở BOOT phase".

| Phase  | Trigger                             | Agent       | Skills loaded                               |
| ------ | ----------------------------------- | ----------- | ------------------------------------------- |
| PLAN   | User task hoặc `/plan`              | planner     | architecture, api-design                    |
| SPEC   | `/spec` sau plan approved           | spec-writer | testing-workflow                            |
| BUILD  | Sau spec approved                   | implementer | Theo files being touched (xem 2.2)          |
| VERIFY | Auto sau build hoặc `/verify`       | (pipeline)  | testing-workflow, observability             |
| REVIEW | Auto sau verify pass hoặc `/review` | reviewer    | coding-standards, security, spring-patterns |

### 2.2 Skill Routing — "1% cũng phải dùng skill"

Trước mỗi code action, agent PHẢI check skill registry:

```
1. Detect project type → load matching generic skills
2. Detect summer-platform? → load summer-core + relevant summer sub-skills
3. What files am I touching?
   - *Controller.java, *Handler.java → spring-patterns (+ summer-rest nếu summer project)
   - *Repository.java, *.sql         → database-patterns (+ summer-data nếu summer project)
   - *Config.java + security imports  → spring-security (+ summer-security nếu summer project)
   - *Test.java                       → testing-workflow (+ summer-test nếu summer project)
   - application.yml + f8a.*          → summer-core + relevant summer sub-skill
4. Execute with loaded context
```

### 2.3 Skip Conditions

```
IF ALL true: ≤5 lines, 1 file, no new behavior, no arch impact, no schema change
THEN → BUILD directly
ELSE → /plan first
```

### 2.4 Subagent Isolation (học từ Superpowers v5 + GSD)

- Mỗi task trong plan → 1 subagent instance riêng
- Subagent nhận pre-loaded context: task description, relevant spec, loaded skills, summary of prior tasks (không phải full context)
- Execute continuously, chỉ dừng khi blocker hoặc reviewer reject
- 2-stage review per task: spec compliance trước, code quality sau

---

## Mục tiêu 3: Context & Memory Strategy

### 3.1 Context Budget Management

**Lazy loading:**

```
Session start → load ONLY:
  - CLAUDE.md (core workflow + skill router + project detection)
  - Rules matching detected project type
  - summer-core (nếu detect summer-platform)

On-demand → load khi cần:
  - Generic domain skills (khi touching relevant files)
  - Summer sub-skills (khi touching summer-specific code)
  - Agent definitions (khi invoking agent)
```

**Budget accounting ví dụ — summer project:**

```
CLAUDE.md                    ~2,000 tokens
Auto-loaded rules (5 core)   ~2,500 tokens
summer-core                    ~500 tokens
                             ─────────────
Auto-loaded total:            ~5,000 tokens ✓

+ summer-rest (khi cần)        ~800 tokens
+ summer-data (khi cần)        ~800 tokens
+ spring-patterns (khi cần)    ~800 tokens
+ coding-standards (khi cần)   ~800 tokens
                             ─────────────
Worst case with 4 skills:     ~8,200 tokens ✓ (< 15K limit)
```

### 3.2 Memory Tiers (3-layer)

| Tier              | Storage                   | Lifetime                | Content                                                                     |
| ----------------- | ------------------------- | ----------------------- | --------------------------------------------------------------------------- |
| **L1: Session**   | In-context                | Current session         | Current task, plan, spec, progress                                          |
| **L2: Project**   | `.claude/memory/` files   | Persistent, git-tracked | Architecture decisions, patterns, project conventions, debug knowledge base |
| **L3: Knowledge** | claude-mem MCP (optional) | Cross-project           | Instincts, cross-session learnings, team knowledge                          |

**L1 → L2** (session-end hook): Extract decisions, patterns, errors → JSON ≤ 500 tokens → `.claude/memory/sessions/YYYY-MM-DD-HH.json`. Retain last 5, auto-prune.

**Debug Knowledge Base** (học từ GSD): Resolved debug sessions append vào `.claude/memory/debug-knowledge.md`. Khi gặp lỗi tương tự → check trước khi investigate từ đầu.

**L2 → L3** (manual, `/meta evolve`): Cluster learnings, promote confidence ≥ 0.7 into skills/rules. Requires claude-mem MCP — graceful fallback.

### 3.3 Anti-Context-Rot

1. Compact triggers tại workflow boundaries (sau VERIFY, sau REVIEW) — không giữa task
2. Auto-checkpoint before compact
3. Progressive unloading khi context > 70%: meta skills → unused domain skills → compact conversation

---

## Mục tiêu 4: Hooks Strategy

### 4.1 Nguyên tắc

- 1 hook = 1 responsibility
- Structured output (JSON stdout)
- Hook không modify context trực tiếp — chỉ suggest

### 4.2 Hook Registry (10 → 6)

| Hook                 | Type         | Responsibility                                                                                                             |
| -------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `session-init.sh`    | SessionStart | **Inject bootstrap skill** (`EXTREMELY_IMPORTANT: read skills/bootstrap/SKILL.md`), detect project type, restore L2 memory |
| `session-save.sh`    | SessionEnd   | Save session summary to L2, persist files list, extract patterns                                                           |
| `skill-router.sh`    | PreToolUse   | Check skill registry before file operations, inject relevant skill                                                         |
| `quality-gate.sh`    | PostToolUse  | After Java file edit: compile check + debug statement check                                                                |
| `compact-advisor.sh` | PreToolUse   | Monitor context, suggest compact at workflow boundaries                                                                    |
| `pre-compact.sh`     | PreCompact   | Checkpoint state before compaction                                                                                         |

### 4.3 Hook Profiles

| Profile    | Hooks                                         | Use case                          |
| ---------- | --------------------------------------------- | --------------------------------- |
| `minimal`  | session-init, session-save                    | Quick tasks, exploration          |
| `standard` | + skill-router, quality-gate, compact-advisor | Daily dev (default)               |
| `strict`   | + pre-compact                                 | Complex features, production code |

---

## Mục tiêu 5: Organization & Onboarding

### 5.1 Skills Organization

Skills được tổ chức theo 3 tầng, mapping trực tiếp với 3 layers ở mục 1.1:

```
skills/
├── bootstrap/                         # CORE — loaded by session-start hook
│   └── SKILL.md                       # State machine: detect → route → enforce
│
├── generic/                           # Generic Java/Spring skills (mọi project)
│   ├── spring-patterns/SKILL.md
│   ├── spring-security/SKILL.md
│   ├── database-patterns/SKILL.md
│   ├── messaging-patterns/SKILL.md
│   ├── testing-workflow/SKILL.md
│   ├── coding-standards/SKILL.md
│   ├── api-design/SKILL.md
│   ├── redis-patterns/SKILL.md
│   ├── observability-patterns/SKILL.md
│   └── architecture/SKILL.md
│
├── summer/                            # Summer Framework skills (CHỈ summer projects)
│   ├── summer-core/
│   │   └── SKILL.md                   # Router + shared types + version detection
│   ├── summer-rest/
│   │   ├── SKILL.md                   # Handler, controller, WebClient, exception, Jackson
│   │   └── references/
│   │       └── handler-examples.md    # Deep dive examples
│   ├── summer-data/
│   │   ├── SKILL.md                   # Audit, outbox, R2DBC
│   │   └── references/
│   │       └── ddl-scripts.md         # audit_log + outbox_events DDL
│   ├── summer-security/
│   │   ├── SKILL.md                   # APISIX + Keycloak + role sync
│   │   └── references/
│   │       └── keycloak-error-map.md  # 58 error mappings (v0.2.3)
│   ├── summer-ratelimit/
│   │   └── SKILL.md                   # Rate limiting (v0.2.2+ only)
│   └── summer-test/
│       ├── SKILL.md                   # TestContainers, WireMock, blackbox
│       └── references/
│           └── blackbox-config.md     # JSON config format
│
└── meta/                              # Meta skills (on-demand, power users)
    └── continuous-learning/SKILL.md   # Instinct extraction, evolve
```

**Naming convention:**

- Generic: `{domain}-patterns` hoặc `{concern}` (ví dụ: `spring-patterns`, `api-design`)
- Summer: `summer-{module}` (ví dụ: `summer-rest`, `summer-data`)
- Mỗi skill folder PHẢI có `SKILL.md` với YAML frontmatter (name, description, triggers)
- `references/` subfolder cho deep content — chỉ load khi agent cần chi tiết

**Skill discovery flow (hook-driven, not CLAUDE.md-driven):**

```
1. session-init hook fires → inject "EXTREMELY_IMPORTANT: read bootstrap/SKILL.md"
2. Agent reads bootstrap skill → learns: must search skills, must announce, must use
3. Bootstrap skill instructs agent to detect project:
   a. Scan build.gradle/pom.xml
   b. Java + Spring Boot? → register skills/generic/* as available
   c. io.f8a.summer:summer-platform? → THÊM skills/summer/* as available
4. Agent receives available skills list (name + description only, ~50 tokens/skill)
5. Before EVERY action → agent searches skills, announces which skill applies
6. Load full SKILL.md body when skill activates
7. Load references/*.md only when deep detail needed
```

**Compliance enforcement trong bootstrap skill:**

- Agent PHẢI announce skill trước khi bắt đầu: "Using skill: summer-rest for handler pattern"
- Nếu không có skill match → agent ghi rõ: "No matching skill found, proceeding with general knowledge"
- PreToolUse hook (`skill-router.sh`) cross-check: file being edited matches announced skill?

### 5.2 Repo Structure (complete)

```
agent-skills/
├── CLAUDE.md                          # Core: workflow + skill router + detection (≤2K tokens)
├── README.md
├── package.json
│
├── agents/                            # 8 agent definitions
│   ├── planner.md
│   ├── spec-writer.md
│   ├── implementer.md
│   ├── reviewer.md
│   ├── build-fixer.md
│   ├── test-runner.md
│   ├── database-reviewer.md
│   └── refactorer.md
│
├── skills/                            # 3-tier skill organization
│   ├── generic/                       # 10 generic Java/Spring skills
│   │   ├── spring-patterns/SKILL.md
│   │   ├── spring-security/SKILL.md
│   │   ├── database-patterns/SKILL.md
│   │   ├── messaging-patterns/SKILL.md
│   │   ├── testing-workflow/SKILL.md
│   │   ├── coding-standards/SKILL.md
│   │   ├── api-design/SKILL.md
│   │   ├── redis-patterns/SKILL.md
│   │   ├── observability-patterns/SKILL.md
│   │   └── architecture/SKILL.md
│   ├── summer/                        # 6 summer-specific skills
│   │   ├── summer-core/SKILL.md
│   │   ├── summer-rest/SKILL.md (+references/)
│   │   ├── summer-data/SKILL.md (+references/)
│   │   ├── summer-security/SKILL.md (+references/)
│   │   ├── summer-ratelimit/SKILL.md
│   │   └── summer-test/SKILL.md (+references/)
│   └── meta/                          # 1 meta skill
│       └── continuous-learning/SKILL.md
│
├── commands/                          # 12 slash commands
│   ├── plan.md
│   ├── spec.md
│   ├── build.md
│   ├── verify.md
│   ├── review.md
│   ├── build-fix.md
│   ├── refactor.md
│   ├── db-migrate.md
│   ├── e2e.md
│   ├── setup.md
│   ├── status.md
│   └── meta.md
│
├── rules/                             # 9 behavioral rules
│   ├── development-workflow.md
│   ├── spec-driven.md
│   ├── coding-style.md
│   ├── architecture-patterns.md
│   ├── security.md
│   ├── git-workflow.md
│   ├── api-design.md
│   ├── testing.md
│   └── observability.md
│
├── hooks/                             # 6 lifecycle hooks
│   ├── session-init.sh
│   ├── session-save.sh
│   ├── skill-router.sh
│   ├── quality-gate.sh
│   ├── compact-advisor.sh
│   └── pre-compact.sh
│
├── templates/
│   └── PROJECT_GUIDELINES_TEMPLATE.md
│
├── scripts/
│   └── setup.sh
│
└── docs/                              # Extended docs (KHÔNG load vào context)
    ├── workflow-reference.md
    ├── skill-authoring-guide.md
    └── troubleshooting.md
```

### 5.3 Onboarding Flow

**Target: Productive trong 2 phút**

```
Team lead (one-time):
  1. /plugin install devco-agent-skills
  2. /setup                              # auto-detect project, summer detection
  3. git add .claude/ && git commit

Team member (zero-setup):
  1. git clone <repo>
  2. claude                              # auto-prompt install plugin
  3. Start coding                        # everything works
```

### 5.4 Progressive Disclosure

| Level       | Audience   | Visible commands                                            | Skills awareness                   |
| ----------- | ---------- | ----------------------------------------------------------- | ---------------------------------- |
| **Level 1** | Mọi người  | `/plan`, `/spec`, `/verify`                                 | Agent tự load, user không cần biết |
| **Level 2** | Khi cần    | `/review`, `/build-fix`, `/e2e`, `/refactor`, `/db-migrate` | User biết skills tồn tại           |
| **Level 3** | Power user | `/meta learn`, `/meta evolve`, `/status`, hook profiles     | User tạo/edit skills               |

`/status` phải show: detected project type, summer detected (yes/no + version), loaded skills, loaded rules, context usage, hook profile.

---

## Success Metrics

| Metric                 | Target                                          | Cách đo                                                  |
| ---------------------- | ----------------------------------------------- | -------------------------------------------------------- |
| Context efficiency     | ≤ 5K tokens auto-loaded                         | Count tokens CLAUDE.md + auto-loaded rules + summer-core |
| Summer skill precision | Summer skills load = 0 trên non-summer projects | Test 10 non-summer projects                              |
| Workflow compliance    | Agent follows 5-phase ≥ 95%                     | Audit 20 sessions                                        |
| Onboarding time        | ≤ 2 min for team member                         | Time from clone → first `/plan`                          |
| Agent output quality   | Code passes review without rework ≥ 80%         | Track review reject rate                                 |
| Skill usage rate       | Skills invoked ≥ 90% of applicable cases        | Hook logging                                             |
| Context rot resistance | Output quality stable after 50+ tool calls      | Compare early vs late quality                            |

---

## Implementation Phases

### Phase 1: Consolidate Generic Skills & Rules (Week 1-2)

- [ ] Merge generic skills: 24 → 10
- [ ] Merge rules: 15 → 9
- [ ] Merge agents: 15 → 8
- [ ] Merge commands: 21 → 12
- [ ] Enforce token budget cho mỗi file
- [ ] Rewrite CLAUDE.md ≤ 2K tokens

### Phase 2: Split Summer Skill (Week 2-3)

- [ ] Tách summer monolith → summer-core + 5 sub-skills
- [ ] Implement summer-platform hard gate detection
- [ ] Move version-specific content inline vào từng sub-skill
- [ ] Validate: summer skills = 0 load trên non-summer project
- [ ] Validate: đúng sub-skill load cho từng task type

### Phase 3: Workflow Engine (Week 3-4)

- [ ] Implement 5-phase workflow trong CLAUDE.md
- [ ] Implement skill router logic (generic + summer aware)
- [ ] Add subagent isolation pattern
- [ ] Define skip conditions

### Phase 4: Hooks & Memory (Week 4-5)

- [ ] Consolidate hooks: 10 → 6
- [ ] Implement L1/L2/L3 memory tiers
- [ ] Implement debug knowledge base
- [ ] Anti-context-rot strategy
- [ ] Hook profiles

### Phase 5: Onboarding & Polish (Week 5-6)

- [ ] Tổ chức repo structure (generic/ + summer/ + meta/)
- [ ] Simplify setup flow
- [ ] Progressive disclosure
- [ ] Write docs (workflow-reference, skill-authoring, troubleshooting)
- [ ] Test với 2-3 team members, iterate

### Phase 6: Validate (Week 6-7)

- [ ] Measure all success metrics
- [ ] Compare output quality: before vs after
- [ ] Đặc biệt validate summer skill precision metric
- [ ] Collect team feedback
- [ ] Iterate based on data
