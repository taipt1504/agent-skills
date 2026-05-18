---
name: bootstrap
description: Foundation skill — auto-loads at SessionStart. Teaches 5-layer adaptive workflow, 1% pre-flight discovery rule, triage routing, skill announcement contract, project detection. All other skills depend on this. Do NOT manually load.
triggers:
  natural: ["plugin status", "skill discovery", "workflow engine", "1% rule"]
  code: ["SessionStart"]
applicability:
  always: true
  triggers:
    files_match: ["**"]
relevance_assessment: |
  Always 100% — meta-skill, fires first every session.
---

# Bootstrap — Workflow Foundation

## You Have Skills + Rules. Use Them.

Before EVERY workflow gate: enumerate ALL skills + rules with ≥1% relevance, score each, decide APPLY or SKIP, justify every SKIP with concrete evidence.

**1% rule** — non-negotiable. See `skills/preflight/SKILL.md`.

## Skill announcement contract (replaces skills-loaded.json gate)

When loading skill:
1. Announce: `Using skill: <name> for <reason>`
2. Reference skill name in commits / PR description
3. NO file write. NO gate. Announcement IS the contract.

No match: `No matching skill found, proceeding with general knowledge`.

`skills/preflight/SKILL.md` enforces enumeration. `scripts/hooks/skill-router.sh` emits hints (non-blocking).

## 5-Layer Adaptive Workflow

```
REQ → BOOT → PREFLIGHT0 → TRIAGE
                            ├── trivial → EXECUTE (light) → REVIEW (S2) → COMMIT
                            └── standard/high-stakes →
                                ALIGN → PREFLIGHT1 → BRAINSTORM →
                                PREFLIGHT2 → PLAN → PREFLIGHT3 → SPEC →
                                PREFLIGHT4 → EXECUTE (subagent dispatch) →
                                PREFLIGHT5 → REVIEW (S1+S2) → LEARN → COMMIT
```

Six pre-flights:
- **0** Initial discovery (after Boot, before Triage) — enumerate ALL skills + rules + instincts
- **1** Brainstorm prep — brainstorm + domain skills from Align
- **2** Plan prep — planning skills, pattern rules
- **3** Spec prep — API design, testing, spec patterns
- **4** Execute prep — TDD, language, framework, production rules
- **5** Review prep — security, verification, testing rules

Detail: `skills/preflight/references/gate-mappings.md`.

## Triage Router — Choose Lane First

Three lanes:

| Lane | Criteria | Required gates |
|---|---|---|
| Trivial | ≤5 lines, no behavior change, no new dep | Execute (light TDD), Verify (compile+format), Review S2 |
| Standard | bounded scope, feature/bugfix/refactor | Full flow (Align if vague, Brainstorm if multi-path, Plan, Spec, Execute, Review S1+S2, Learn) |
| High-stakes | architecture / migration / security / public API / breaking change / new dep | All gates mandatory + ADR + worktree + Brainstorm ≥3 options |

User override: "treat as <lane>". See `skills/triage/SKILL.md`.

## Workflow State Machine — Phase Tracking

`scripts/hooks/workflow-tracker.sh` writes `.claude/workflow-state.json` as gates progress:

```
/triage → lane set in .claude/memory/state/current-triage.json
/align  → phase:ALIGN (artifacts in .claude/memory/align-artifacts/)
/brainstorm → phase:BRAINSTORM (artifacts in .claude/memory/brainstorm-artifacts/, ADR if high-stakes)
/plan   → phase:PLAN → user approves → PLAN_APPROVED → /spec
/spec   → phase:SPEC → approves → SPEC_APPROVED → /build
/build  → phase:BUILD → tests pass → VERIFY_PENDING → AUTO /verify
/verify → phase:VERIFY → green → REVIEW_PENDING → AUTO /dc-review
/dc-review → Stage 1 spec compliance → Stage 2 quality → 0 critical → COMPLETE
```

VERIFY_PENDING + REVIEW_PENDING: `workflow-gate.sh` blocks `src/main/` writes. Run required gate.

Trivial lane bypasses ALIGN / BRAINSTORM / PLAN / SPEC / REVIEW_S1.

## Skill announcement at gate start

Every gate announce:
- `Skills loaded: <comma-separated list>`
- `Pre-flight artifact: <path>`

Replaces skills-loaded.json file gate.

## Project Detection (run once per session)

```
1. Scan build.gradle / build.gradle.kts / pom.xml
2. No build file → not Java → skip Java skills
3. Java detected:
   a. spring-boot-starter-webflux → load `spring-webflux-patterns` on demand
   b. spring-boot-starter-web → load `spring-mvc-patterns` on demand
   c. Neither → plain Java
4. io.f8a.summer:summer-platform → load `summer-core` + relevant summer-* skills
```

Profile written to `.claude/project-profile.json` by `session-init.sh`.

## Skill Registry

Skills loaded on-demand by file pattern + content + pre-flight enumeration. Authoritative list: `find skills -name SKILL.md`.

### Skills (24 + meta)

| Skill | Trigger summary |
|---|---|
| `bootstrap` | SessionStart (this skill) |
| `preflight` | Before EVERY workflow gate |
| `triage` | Session start with task description |
| `align` | Standard with vague request OR high-stakes always |
| `brainstorm` | Standard with multi-path OR high-stakes (≥3 options) |
| `api-design` | REST endpoint design, OpenAPI, RFC 7807 |
| `architecture` | Hexagonal, CQRS, DDD |
| `coding-standards` | Immutability, naming, Lombok |
| `database-patterns` | @Entity, @Repository, R2DBC, JPA |
| `deployment-patterns` | Profiles, env config, observability |
| `grpc-patterns` | @GrpcService, protobuf |
| `messaging-patterns` | Kafka, RabbitMQ, outbox |
| `observability-patterns` | Micrometer, MDC, tracing |
| `pentest` | OWASP scanning, security review |
| `redis-patterns` | RedisTemplate, distributed lock, cache-aside |
| `spring-webflux-patterns` | Mono/Flux, WebClient, reactive |
| `spring-mvc-patterns` | @RestController servlet, RestTemplate |
| `spring-security` | SecurityFilterChain, @PreAuthorize |
| `summer-core` | io.f8a.summer detected |
| `summer-data` | f8a.audit, f8a.outbox |
| `summer-file` | f8a.file |
| `summer-kafka` | f8a.kafka |
| `summer-payment-sdk` | f8a.payment |
| `summer-ratelimit` | f8a.rate-limiter |
| `summer-rest` | BaseController, RequestHandler |
| `summer-security` | @AuthRoles, ReactiveKeycloakClient |
| `summer-test` | f8a.test |
| `testing-workflow` | TDD, StepVerifier, Testcontainers |
| `continuous-learning` | `/meta learn`, instinct evolution |

Pre-flight enumerates ALL every gate. Skills missing from list still enumerated (filesystem walk).

## Subagent Dispatch (merged from former skills/subagent-dispatch)

Main agent orchestrates. Subagent executes ONE slice per dispatch. Fresh context per slice.

**When to dispatch:**
- ≥2 slices → dispatch per slice
- Single non-trivial slice → dispatch (isolates orchestrator context)
- Single trivial slice → orchestrator executes directly

**Subagent receives (minimal):**
- Slice description (plan)
- Slice spec scenarios (spec, slice-scoped)
- Pre-flight 4 artifact path
- CONTEXT.md vocabulary
- Files likely touched

**Never:** other slices' specs, full conversation history, unrelated decisions.

**Parallel dispatch:** independent slices → up to `config.team.maxTeammates` concurrent via `Agent(... run_in_background: true)`.

**Reporting:** subagent reports files changed + tests added + skills applied + deviations. Orchestrator aggregates → triggers `/verify`.

## Worktree per Slice (merged from former skills/git-worktree)

High-stakes: auto-creates git worktree per slice. Standard: optional.

**Pattern:**
```bash
WORKTREE_DIR="../$(basename $PWD)-<feature>-slice-<N>"
BRANCH="feature/<feature>-slice-<N>"
git worktree add "$WORKTREE_DIR" -b "$BRANCH"
```

Establish baseline tests pass before edits. Subagent operates inside worktree (`Agent(..., isolation: "worktree")`).

**Benefits:** baseline pre-change, clean discard, parallel features.

**Cleanup:** `git worktree remove --force <dir>` after merge or discard.

State tracked in `.claude/memory/state/active-worktrees.json`. `session-init` warns if >5 active.

## Rule Directory Structure

```
rules/
├── common/   # Language-agnostic; ALWAYS apply
├── java/     # Java + generic Spring; ALWAYS apply for Java projects
└── summer/   # Summer library specific; CONDITIONAL (only when io.f8a.summer detected)
```

`scripts/hooks/preflight-discovery.sh` enumerates `rules/summer/` only when project profile shows `summer:true`. Same as `summer-*` skills — load only when project uses Summer.

## Hard Rules (CLAUDE.md hard blocks — never violate)

1. `.block()` in reactive code → CRITICAL
2. `@Autowired` field injection → `@RequiredArgsConstructor`
3. Expose entities in API → record DTOs
4. Log PII / credentials / tokens → FORBIDDEN
5. Commit secrets to git → FORBIDDEN
6. Skip input validation on API boundaries → FORBIDDEN
7. `SELECT *` → explicit columns
8. Code without `/plan` + `/spec` (except trivial ≤5 lines) → FORBIDDEN
9. Agent commits to git → FORBIDDEN
10. Stop after BUILD without VERIFY + REVIEW → FORBIDDEN

## Memory architecture (v4.1 — 5 layers)

```
LAYER 1 — Auto-loaded by Claude Code at every session
  ~/.claude/CLAUDE.md                                  user-level
  ./CLAUDE.md or ./.claude/CLAUDE.md                   project-level
  ./CLAUDE.local.md                                    per-user project
  ~/.claude/projects/<project>/memory/MEMORY.md        Claude native auto-memory (≤200 lines / 25KB)
  ./.claude/rules/*.md (unscoped)                      optional native rules

LAYER 2 — Loaded on-demand by Claude Code
  ./.claude/rules/*.md (paths: scoped)                 path-conditional
  ./*/CLAUDE.md in subdirs                             when subdir files read
  ~/.claude/projects/<project>/memory/<topic>.md       Claude native topic files

LAYER 3 — Read by plugin / agents / hooks on-demand (NOT auto-loaded)
  Plugin SKILL.md bodies                                via Skill tool
  Plugin agent .md                                       via Task tool dispatch
  Plugin rules/{common,java,summer}/*.md                via agent Read in pre-flight
  ./.claude/memory/active/<feature-id>/                 per-feature state (lifecycle)
  ./.claude/memory/{recent,archive}/                    completed features
  Hook additionalContext                                capped via DEVCO_*_MAX_CHARS

LAYER 4 — MCP memory server (optional, load-on-demand)
  mcp__memory__search_nodes / read_graph              cross-feature search
  mcp__memory__create_entities / add_observations     persist decisions
  Plugin probes availability; degrades to filesystem-only if absent

LAYER 5 — Git-tracked durable docs (read-on-demand)
  ./CONTEXT.md                                          domain vocabulary
  ./docs/adr/*.md                                       ADRs
  ./docs/plans/**, ./docs/specs/**                      feature artifacts
```

### Lifecycle (`.claude/memory/`)

Per-feature directory — multi-feature parallelism supported:

```
.claude/memory/
├── pointers.json                        active feature IDs (multi-feature)
├── index.json                           fast lookup catalog
├── active/<feature-id>/                 in-flight (per-feature)
│   ├── meta.json, triage.json, workflow-state.json
│   ├── preflight/<gate>-<ts>.md
│   ├── align.md, brainstorm.md
│   └── review-stage1/stage2*.json
├── recent/<feature-id>/                 completed last 30 days
├── archive/<YYYY-MM>/<feature-id>.tar.gz  >30 days compressed
└── shared/                              cross-feature
    ├── pattern-observations.jsonl
    └── promotion-candidates.md
```

### Native auto-memory (primary cross-session)

Claude Code manages `~/.claude/projects/<project>/memory/MEMORY.md`. `remember: <pattern>` → Claude writes. First 200 lines / 25KB auto-loaded. Built-in `/memory` for audit.

Plugin does NOT manage `instincts.jsonl`. Promotion candidates via `evolution-check.sh` → `/meta evolve` or `remember: <pattern>`.

### MCP memory entity types (when available)

| Entity | Use |
|---|---|
| `ArchitecturalDecision` | ADR mirrored as graph node |
| `RecurringPattern` | Cross-feature pattern (instinct) |
| `ProjectVocabulary` | Domain term + definition |
| `CommonBug` | Bug type with fix pattern |
| `ServiceContract` | Cross-service event / API contract |

### Hook output caps

`additionalContext` capped via `DEVCO_*_MAX_CHARS`:
- `DEVCO_SESSION_START_MAX_CHARS=8000`
- `DEVCO_SUBAGENT_INIT_MAX_CHARS=6000`
- `DEVCO_PREFLIGHT_MAX_CHARS=4000`
- `DEVCO_POST_COMPACT_MAX_CHARS=3000`

`DEVCO_HOOK_PROFILE=minimal|standard|strict` (minimal halves caps, strict 1.5×).

## Harness awareness

- Hooks enforce rules — pre-flight, workflow gate, quality gate, verify/fix, observability, evolution
- State on disk: `.claude/memory/state/*.json`
- Verification external: tests, compile, lint. Never self-assess.
- Caveman ecosystem: `~/.claude/skills/caveman*` for token compression

## Related

- `skills/preflight/SKILL.md` — 1% rule + 6 variants
- `skills/triage/SKILL.md` — lane decision
- `rules/common/lanes.md` — lane definitions
- `rules/common/skill-enforcement.md` — 1% rule mandate
- `rules/common/spec-driven.md` — lane-based spec requirement
- `CLAUDE.md` — project-level rules + hard blocks
