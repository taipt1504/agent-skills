# Agent Skills

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin for **Java Spring** backend development. **v4.1** ships a fully agentic 5-layer adaptive workflow: triage → align → brainstorm → plan → spec → execute → verify → review → learn.

> **v4.1.0-beta.** Agent = Model + Harness. Plugin provides the harness — 1% pre-flight discovery, lane-aware workflow, native Claude auto-memory, MCP optional layer, hook output caps, lifecycle-organized state, template-enforced plans/specs.

## Workflow

```
REQ → BOOT → PREFLIGHT0 → TRIAGE
                            ├── trivial → EXECUTE (light) → REVIEW (S2) → COMMIT
                            └── standard / high-stakes →
                                ALIGN → BRAINSTORM (if needed) →
                                PLAN → SPEC → EXECUTE (subagent per slice) →
                                REVIEW (S1 + S2) → LEARN → COMMIT
```

Three lanes. Six pre-flight variants (one per gate). **1% rule:** every gate enumerates ALL skills + rules with ≥1% relevance, justifies every SKIP with concrete evidence.

Full operational reference: [WORKING_WORKFLOW.md](WORKING_WORKFLOW.md). End-to-end walkthroughs: [examples/](examples/). Migration from v1 (5-phase rigid): [MIGRATION_v2.md](MIGRATION_v2.md).

## Quick Start

```bash
# 1. Install (one-time per machine)
/plugin marketplace add taipt1504/agent-skills
/plugin install devco-agent-skills

# 2. Setup project (one-time per project)
/dc-setup

# 3. Commit + share
git add .claude/ && git commit -m "chore: add Claude Code project context"

# 4. Start coding
/triage "describe your task"     # auto-routes to trivial / standard / high-stakes lane
```

Teammates clone → `claude` → auto-prompted to install. Zero setup.

## Inventory (v4.1)

| Category | Count | Lazy-loaded? |
|---|---|---|
| Agents | 8 | yes (Task tool) |
| Skills | 28 | yes (Skill tool — only description in catalog) |
| Commands | 16 | yes (invoke time) |
| Rules | 18 (common 8 + java 7 + summer 3) | partial — `summer/` conditional on `io.f8a.summer` detection |
| Hooks | 20 | always — registered via `hooks/hooks.json` |
| Templates | 7 | manual reference |

Plugin bundle: **~628 KB / ~157k tokens** (12% reduction from v3.3 baseline).

## Architecture

### 5-Layer Adaptive Workflow

| Layer | Gate | Output |
|---|---|---|
| 0 — Boot | session-init.sh | Detect project, load CONTEXT.md + ADRs, pre-flight 0 |
| 1 — Triage | `/triage` | Lane: trivial / standard / high-stakes |
| 2 — Align (if vague / high-stakes) | `/align` | Requirements + assumptions + vocabulary → CONTEXT.md |
| 2 — Brainstorm (if multi-path / mandatory high-stakes) | `/brainstorm` | ≥3 options + comparison matrix + recommendation + ADR |
| 2 — Plan | `/plan` | Slices + dependency graph + risk register |
| 2 — Spec | `/spec` | Per-slice behavioral contracts (template-enforced) |
| 3 — Execute | `/build` | Subagent dispatch per slice (worktree for high-stakes) |
| 3 — Verify | `/verify` | Compile + tests + coverage + (high-stakes) security scan |
| 4 — Review S1 | `/dc-review` Stage 1 | Spec compliance binary verdict |
| 4 — Review S2 | `/dc-review` Stage 2 | Severity-tagged quality findings |
| 5 — Learn | `/meta evolve` | Pattern observations → Claude native auto-memory |

### Memory Architecture (v4.1)

5 layers, native-first:

```
LAYER 1 — Auto-loaded by Claude Code
  ~/.claude/CLAUDE.md                              user-level
  ./CLAUDE.md or ./.claude/CLAUDE.md               project-level
  ./CLAUDE.local.md                                per-user project
  ~/.claude/projects/<project>/memory/MEMORY.md   Claude native auto-memory (≤200 lines/25KB)

LAYER 2 — Loaded on-demand by Claude Code
  ./.claude/rules/*.md with paths: frontmatter   path-conditional
  ~/.claude/projects/<project>/memory/<topic>.md  Claude native topic files

LAYER 3 — Plugin / agents / hooks (NOT auto-loaded)
  Plugin SKILL.md bodies                          Skill tool
  Plugin agent .md                                 Task tool dispatch
  Plugin rules/{common,java,summer}/*.md          agent Read in pre-flight
  ./.claude/memory/active/<feature-id>/           per-feature state
  Hook additionalContext                          capped via DEVCO_*_MAX_CHARS

LAYER 4 — MCP memory server (optional)
  mcp__memory__search_nodes / read_graph         cross-feature search
  mcp__memory__create_entities                   persist decisions
  Plugin probes availability; degrades to filesystem-only if absent

LAYER 5 — Git-tracked durable docs
  ./CONTEXT.md, ./docs/adr/*.md
  ./docs/plans/**, ./docs/specs/**
```

### Lifecycle (`.claude/memory/`)

```
.claude/memory/
├── pointers.json              # active feature IDs (multi-feature parallelism)
├── index.json                 # fast lookup catalog
├── active/<feature-id>/       # in-flight (per-feature dir)
├── recent/<feature-id>/       # completed last 30 days
├── archive/<YYYY-MM>/         # >30 days, tar.gz compressed
└── shared/                    # cross-feature (pattern observations, promotion candidates)
```

Multi-feature parallelism. Configurable retention. Archival via `devco-config.json memory.{activeRetentionDays, recentRetentionDays}`.

### Hook Output Caps

`additionalContext` from hooks capped per `DEVCO_*_MAX_CHARS` env vars:

| Hook | Default cap | Override |
|---|---|---|
| session-init | 8000 chars | `DEVCO_SESSION_START_MAX_CHARS` |
| subagent-init | 6000 chars | `DEVCO_SUBAGENT_INIT_MAX_CHARS` |
| preflight-* | 4000 chars | `DEVCO_PREFLIGHT_MAX_CHARS` |
| post-compact | 3000 chars | `DEVCO_POST_COMPACT_MAX_CHARS` |

Profile: `DEVCO_HOOK_PROFILE=minimal|standard|strict` (minimal halves caps, strict 1.5x).

### Plan/Spec Templates

Threshold-based:

| Slice count | Shape | Templates |
|---|---|---|
| ≤2 | single-file | `PLAN_TEMPLATE.md`, `SPEC_TEMPLATE.md` |
| 3+ | split | `PLAN_INDEX_TEMPLATE.md` + `PLAN_SLICE_TEMPLATE.md`, `SPEC_INDEX_TEMPLATE.md` + `SPEC_SLICE_TEMPLATE.md` |

Split shape:
- `index.md` §1 Cross-cutting (auth/logging/error envelope/idempotency) is AUTHORITATIVE
- Per-slice `§0 Cross-cutting reference` points to index — slice override forbidden w/o ADR
- Granular approval: per-slice `status: DRAFT|APPROVED|REVISED` frontmatter
- `/build` blocks dispatch when index status = `PARTIALLY_APPROVED`

Enforced by `scripts/ci/validate-plan-spec-templates.sh` (run via `npm test` or directly).

### Conditional Loading

| Asset | Loaded when |
|---|---|
| `rules/summer/*` | `project-profile.json` shows `summer:true` OR `io.f8a.summer` in build.gradle |
| `skills/summer-*` | same |
| `skills/grpc-patterns` | `grpc-spring-boot-starter` in build.gradle |
| `skills/spring-webflux-patterns` | WebFlux on classpath |
| `skills/spring-mvc-patterns` | MVC on classpath |

Pre-flight discovery (`scripts/hooks/preflight-discovery.sh`) enforces. No project = no skill list pollution.

### Agents (8)

| Agent | Model | Use |
|---|---|---|
| `_shared-protocol` | n/a | Included by all agents (1% rule, memory, hard rules) |
| `planner` | opus | Slice decomposition (Plan gate) |
| `spec-writer` | opus | Behavioral contracts (Spec gate) |
| `slice-executor` | sonnet | TDD per slice (Execute, absorbs former implementer + test-runner + refactorer) |
| `spec-compliance-reviewer` | sonnet | Stage 1 binary verdict |
| `code-quality-reviewer` | sonnet | Stage 2 severity-tagged (absorbs former pentest + database-reviewer) |
| `build-fixer` | sonnet | Verify/fix loop (hook-invoked) |
| `architect` | opus | High-stakes pre-Plan ADR + bounded context review |

### Commands (16)

`/triage` `/align` `/brainstorm` `/plan` `/spec` `/build` `/verify` `/dc-review` `/dc-setup` `/dc-status` `/build-fix` `/e2e` `/db-migrate` `/pentest-scan` `/threat-model` `/meta` (+ subcommands: `learn` / `evolve` / `prune` / `create-skill` / `adr` / `improve-architecture`)

### Skills (28)

Core meta: bootstrap, preflight, triage, align, brainstorm
Java + Spring: coding-standards, architecture, api-design, testing-workflow
Spring stacks (mutually exclusive): spring-webflux-patterns, spring-mvc-patterns
Domain: database-patterns, messaging-patterns, redis-patterns, observability-patterns, deployment-patterns, spring-security
Conditional: grpc-patterns
Summer (conditional, requires io.f8a.summer): summer-core, summer-data, summer-rest, summer-security, summer-test, summer-kafka, summer-ratelimit, summer-file, summer-payment-sdk
Misc: pentest (thin OWASP script wrapper)

### Hooks (20)

PreToolUse: preflight-discovery, preflight-gate, workflow-gate, skill-router, compact-advisor, git-guard
PostToolUse: quality-gate, build-checkpoint, workflow-phase-lock, workflow-tracker, verify-fix-loop, docs-index
SessionStart: session-init
PreCompact / PostCompact: pre-compact, post-compact
Stop: session-save, auto-adr, evolution-check
Utility: run-with-flags (sourced by others)

## Rules (18)

```
rules/
├── common/      # 8 — lanes, spec-driven, skill-enforcement, coding-style, security, patterns, git-workflow, development-workflow
├── java/        # 7 — coding-style, reactive, api-design, security, testing, observability, migration
└── summer/      # 3 — audit, messaging, handler-api-standards (CONDITIONAL)
```

Optional symlink to native `.claude/rules/`: `/dc-setup --link-rules <profile>` where profile ∈ `common | java-webflux | java-mvc | summer`. Default OFF — preserves pre-flight discipline.

## Validators

```bash
bash scripts/ci/run-all.sh
```

7 validators:
- Agent Definitions
- Skill Directories
- Command Files
- Hook Configuration
- Skill Trigger Coverage (≥18/20 PASS threshold)
- Plan/Spec Template Conformance (single-file + split shape)
- Non-Interactive Mode (opt-in: `SKIP_NONINTERACTIVE=0`)

## Hard Blocks

See [CLAUDE.md](CLAUDE.md) for the full list. Key rules:

1. `.block()` in reactive code → CRITICAL
2. `@Autowired` field injection → use `@RequiredArgsConstructor`
3. Expose entities in API → use record DTOs
4. Sensitive data (PII, credentials, tokens) in logs or commits
5. Skip input validation at API boundaries
6. `SELECT *` in queries → explicit column selection
7. Write code without `/plan` + `/spec` (except trivial ≤5 lines)
8. Agent commits to git → only user commits
9. Stop after BUILD without VERIFY + REVIEW
10. Plan/spec missing required template sections
11. Cross-cutting override in spec slice without ADR
12. `/build` dispatching on `PARTIALLY_APPROVED` plan/spec

## Developing the Plugin

Load from working tree without re-installing:

```bash
claude --plugin-dir /path/to/agent-skills

# Non-interactive mode:
claude -p \
  --plugin-dir /path/to/agent-skills \
  --model sonnet \
  --output-format json \
  --dangerously-skip-permissions \
  --no-session-persistence \
  "Add pagination to GET /api/users"
```

`--plugin-dir <path>` (Claude Code 2.x) loads any directory with `.claude-plugin/plugin.json` for the current session only. Skills, agents, commands, hooks resolve via `${CLAUDE_PLUGIN_ROOT}`.

## Structure

```
agent-skills/
├── CLAUDE.md                 # harness entry, hard blocks
├── README.md                 # this file
├── WORKING_WORKFLOW.md       # operational reference
├── MIGRATION_v2.md           # v1 → v2 migration
├── REFACTOR_PLAN.md          # original v4.0 refactor plan
├── .claude-plugin/           # plugin manifest
├── agents/                   # 8 agents + _shared-protocol
├── skills/                   # 28 SKILL.md (lazy-loaded)
├── commands/                 # 16 slash commands
├── rules/{common,java,summer}/  # 24 rules (8 common + 13 java incl. 6 code-review + 3 summer conditional)
├── templates/                # 7 plan/spec/CONTEXT templates
├── hooks/hooks.json          # hook registry
├── scripts/
│   ├── hooks/                # 20 hook scripts
│   ├── ci/                   # 7 validators + run-all.sh
│   └── migration/            # reorganize-memory.py, split-plan-spec.py, add-applicability.py
├── examples/                 # 3 lane walkthroughs (trivial / standard / high-stakes)
└── docs/
    ├── proposals/            # design proposals (memory architecture, decomposition)
    └── adr/                  # architecture decisions
```

## Versions

| Version | Status | Notes |
|---|---|---|
| v3.3 | stable | 5-phase rigid, no triage, no pre-flight |
| v4.0 | beta | 5-layer adaptive, 1% pre-flight, triage, two-stage review |
| **v4.1** | **current** | Slim refactor: 12% bundle reduction, native auto-memory, MCP optional, hook caps, lifecycle org, multi-feature parallelism |
| v4.2 (planned) | roadmap | Multi-service plan/spec full implementation, `/meta search` MCP wrapper |

## License

MIT
