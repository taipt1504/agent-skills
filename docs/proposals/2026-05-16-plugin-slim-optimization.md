# Plugin Slim Optimization Proposal

**Status:** DRAFT — awaiting user evaluation before refactor
**Date:** 2026-05-16
**Trigger:** plugin bloat after v4.0 refactor — 32 skills + 13 agents + 17 commands + 18 rules + 22 hooks = ~180K tokens bundle. Users pay this cost every session.

---

## Goals (per user mandate)

1. **Full agentic workflow:** user request → triage → align → brainstorm → approve → auto-execute → review → done. No manual hand-off in the middle.
2. **Backend Java focus:** Spring MVC + WebFlux baseline. Auto-detect Summer library; load summer-specific assets only when detected.
3. **Native Claude Code memory only:** NO `claude-mem`, NO `mcp__memory__*`, NO third-party stores. Plugin manages memory entirely via Claude Code primitives + filesystem.
4. **Slim inventory:** trim duplication. Goal: 50%+ token reduction beyond v4.0 baseline (180K → ~85K tokens).
5. **Caveman compression:** apply per matrix to agent-facing content while preserving core principles.

---

## Current state — measured

| Category | Count | Bytes | ~Tokens |
|---|---|---|---|
| Skills | 32 | 245 K | ~61 k |
| Agents | 13 | 114 K | ~28 k |
| Commands | 17 | 115 K | ~29 k |
| Rules | 18 | 76 K | ~19 k |
| Hooks | 22 | 125 K | ~31 k |
| Templates | 8 | 45 K | ~11 k |
| **Total** | **110 files** | **720 K** | **~180 k** |

Largest items (compression candidates):
- `agents/spec-writer.md` 21 K
- `agents/planner.md` 20 K
- `skills/summer-security/SKILL.md` 20 K
- `skills/summer-data/SKILL.md` 18 K
- `templates/PROJECT_GUIDELINES_TEMPLATE.md` 18 K
- `scripts/hooks/session-init.sh` 24 K (script, not agent-facing — keep as-is)
- `commands/build.md` 15 K
- `commands/spec.md` 13 K

---

## **REVISION 2026-05-16:** Memory architecture — MCP back in + lifecycle-aware scale

Per user clarification:
- **MCP memory servers (mcp__memory__*) ARE allowed.** They load on-demand from the MCP server, NOT into static context. Acceptable use.
- Third-party PLUGINS (claude-mem, ECC continuous-learning binary, etc.) are NOT allowed. Logic must live in this plugin's files / hooks.
- Current flat `.claude/memory/{preflight,align-artifacts,brainstorm-artifacts}/` accumulates at scale → propose lifecycle-aware reorganization.

See dedicated section "Scale-aware memory architecture" below. The original "Native Claude Code Memory" research stays as primitives reference.

## Native Claude Code Memory — research findings

### Primitives Claude Code provides natively (no plugins needed)

| Primitive | Path | Lifetime | Auto-loaded |
|---|---|---|---|
| User CLAUDE.md | `~/.claude/CLAUDE.md` | global, per-user | Yes — every session |
| Project CLAUDE.md | `<repo>/CLAUDE.md` | per-repo, git-tracked | Yes — every session |
| Subdir CLAUDE.md | `<subdir>/CLAUDE.md` | per-subdir | Yes — when cwd inside |
| `.claude/settings.json` | per-repo | per-repo | Yes — config |
| `.claude/settings.local.json` | per-repo | per-repo (git-ignored) | Yes — user-local config |
| Plugin skills | `plugin-root/skills/*/SKILL.md` | per-install | On-demand via Skill tool |
| Plugin agents | `plugin-root/agents/*.md` | per-install | On-demand via Task tool |
| Plugin hooks | `plugin-root/hooks/hooks.json` | per-install | Yes — at hook events |
| Plugin slash commands | `plugin-root/commands/*.md` | per-install | On invocation |
| Session log | `.claude/sessions/<id>.json` | per-session | Read on resume |
| Workspace state | any path under repo | per-repo | Read on-demand by plugin |
| `/memory` command | built-in | n/a | Manages CLAUDE.md from chat |
| `/compact` / `/clear` | built-in | n/a | Compaction triggers PreCompact/PostCompact hooks |

### What we DON'T need (and should remove dependencies on)

- `mcp__memory__*` knowledge-graph servers — third-party, contradicts mandate
- `claude-mem` — third-party
- `~/.claude/instincts.jsonl` — proprietary format from ECC plugin
- `mcp__memory__create_entities` / `search_nodes` / `add_observations` calls in `_shared-protocol.md`

### Memory architecture (native-only) — proposed

**Tier 1 — Session (ephemeral, git-ignored):**
```
.claude/memory/
├── preflight/<gate>-<ts>.md              # pre-flight 1% rule artifacts
├── state/
│   ├── current-triage.json               # active lane
│   ├── workflow-state.json               # phase + artifacts paths
│   ├── build-checkpoint.json             # resume state
│   ├── verify-fix-state.json             # retry counter
│   ├── review-stage1.json + stage1-<id>.json
│   ├── review-stage2.json + stage2-<id>.json
│   └── active-worktrees.json
├── align-artifacts/<date>-<task>.md      # align grill outputs
├── brainstorm-artifacts/<date>-<task>.md # brainstorm tournaments + recommendation
├── sessions/<session-id>.md              # optional session notes
└── promotion-candidates.md               # /meta evolve input
```

**Tier 2 — Project (git-tracked, durable across team):**
```
<repo>/
├── CLAUDE.md                             # project rules (auto-loaded by Claude Code)
├── CONTEXT.md                            # domain vocabulary (Align gate updates)
└── docs/
    ├── adr/<NNNN>-<decision>.md          # ADRs (auto-loaded summary by session-init.sh)
    ├── plans/<feature>{.md, /index.md + slices/} # Plan artifacts
    └── specs/<feature>{.md, /index.md + slices/} # Spec artifacts
```

**Tier 3 — Global (cross-repo, per-user):**
```
~/.claude/
├── CLAUDE.md                             # user-level rules (auto-loaded)
└── memory/
    └── auto-evolved-skills/<name>/SKILL.md  # evolution-check.sh promotes here
```

NO `~/.claude/instincts.jsonl`. NO knowledge graph. NO MCP memory.

**Evolution flow (native):**
1. `evolution-check.sh` Stop hook scans `.claude/memory/preflight/` + session log for pattern candidates
2. Writes to `.claude/memory/promotion-candidates.md`
3. User runs `/meta evolve` — reviews candidates, accepts promotion
4. New SKILL.md written to `~/.claude/memory/auto-evolved-skills/<name>/`
5. Next session, `session-init.sh` scans this directory and loads matching auto-evolved skills

**Compaction handling (native):**
- `pre-compact.sh` writes `.claude/memory/state/pre-compact.json` (current phase, plan/spec paths, recent decisions)
- `post-compact.sh` reads it back, injects as additionalContext after compaction
- No external memory server needed

**Cross-session continuity (native):**
- `.claude/sessions/<id>.json` written by Claude Code natively — plugin reads on `/dc-status` only
- `workflow-state.json` is the durable workflow snapshot — pre-compact captures, post-compact restores
- Plan + Spec live in `docs/` → git-tracked → survive any session loss

This replaces `mcp__memory__*` semantics with files. All operations: read, write, grep — no network, no DB.

---

## Scale-aware memory architecture (REVISED)

### Problem at scale

Current flat shape works for ≤20 features. Pain points after that:

| Scale | Problem |
|---|---|
| 50+ features over a year | `docs/plans/` + `docs/specs/` directories balloon. Plan/spec slugs collide. |
| Each feature × 6 gates × N revisions | `.claude/memory/preflight/` has 300-1000+ files in one flat dir. `find` slow. `ls` shows wall of timestamps. |
| Multi-feature parallelism | `current-triage.json` is single-state. Cannot work on Feature A morning + Feature B afternoon without overwriting. |
| Cross-feature pattern reuse | Grepping 1000 markdown files for "outbox pattern usage" → painful. |
| Compaction loss | `pre-compact.json` is single-state. Multi-feature session loses non-active feature state on compaction. |
| Stale artifacts | Completed feature's pre-flight + align + brainstorm artifacts linger. No archival policy. |
| Session log explosion | `.claude/sessions/` Claude-native logs grow without bound (Claude Code manages, but plugin should not pile on top). |
| Disk space | Hundreds of multi-KB markdown files = MB-scale workspace, eats git LFS budget if anyone commits accidentally. |

### Proposed shape — lifecycle + hierarchy + index

```
.claude/memory/
├── pointers.json                                  # active feature IDs (multi-feature support)
├── index.json                                     # fast lookup: feature-id → metadata
│
├── active/                                        # current in-flight features
│   └── <feature-id>/                              # ONE dir per feature
│       ├── meta.json                              # status, lane, created, last_touched
│       ├── triage.json                            # per-feature lane (replaces global current-triage.json)
│       ├── preflight/<gate>-<ts>.md               # 6 gate variants
│       ├── align.md                               # single-shot align artifact
│       ├── brainstorm.md                          # single-shot brainstorm artifact (+ ADR cross-ref)
│       ├── workflow-state.json                    # phase + artifacts paths
│       ├── build-checkpoint.json                  # resume state
│       ├── verify-fix-state.json                  # retry counter
│       ├── review-stage1.json + stage1-<id>.json
│       ├── review-stage2.json + stage2-<id>.json
│       └── worktrees.json                         # per-feature worktree tracking
│
├── recent/                                        # completed within last 30 days
│   └── <feature-id>/                              # same structure as active
│
├── archive/                                       # >30 days completed
│   └── <YYYY-MM>/<feature-id>.tar.gz              # compressed bundle per feature, organized by month
│
└── shared/                                        # cross-feature
    ├── promotion-candidates.md                    # /meta evolve input
    ├── compaction-snapshots/                      # pre-compact dumps (multi-feature aware)
    └── pre-compact.json                           # most-recent global snapshot
```

**Plan/spec doc tree (git-tracked, unchanged structure but indexed):**

```
docs/
├── adr/
│   ├── 0001-...md  ... 0050-...md
│   └── INDEX.md                                   # auto-generated TOC by /meta adr index
├── plans/
│   ├── INDEX.md                                   # auto-generated: feature-id, status, lane, date
│   ├── <feature-id>.md                            # single-file (small)
│   └── <feature-id>/                              # split (large)
│       ├── index.md
│       └── slices/*.md
└── specs/
    ├── INDEX.md                                   # auto-generated
    ├── <feature-id>.md
    └── <feature-id>/
        ├── index.md
        └── slices/*.md
```

INDEX.md files are auto-maintained by a new hook (`docs-index.sh` PostToolUse on doc writes) — fast lookup without opening every plan/spec.

### Feature ID convention

`<YYYY-MM>-<service>-<kebab-task-slug>` — e.g. `2026-05-merchant-roles-config-sync`

Benefits:
- Sortable chronologically by `ls`
- Service prefix groups multi-feature work per service
- Slug stays readable

### Pointers.json (multi-feature parallelism)

```json
{
  "active_features": ["2026-05-pagination", "2026-05-outbox-migration"],
  "primary": "2026-05-pagination",
  "last_switched": "2026-05-16T10:00:00Z"
}
```

Each agent reads `pointers.json.primary` for default work; user can switch via `/triage --switch <feature-id>`. Multi-feature work supported without state-overwrite.

### Index.json (fast cross-feature lookup)

```json
{
  "features": {
    "2026-05-pagination": {
      "title": "Add pagination to user list",
      "lane": "standard",
      "status": "active",
      "created": "2026-05-15T09:00:00Z",
      "last_touched": "2026-05-16T10:00:00Z",
      "path": ".claude/memory/active/2026-05-pagination",
      "docs": {
        "plan": "docs/plans/2026-05-pagination.md",
        "spec": "docs/specs/2026-05-pagination.md"
      }
    },
    "2026-05-outbox-migration": { ... }
  },
  "version": 1
}
```

Maintained by `session-init.sh` + `session-save.sh`. `index.json` is the project's "feature catalog" — single file read for `/dc-status`, `/meta search`, cross-feature lookup.

### Lifecycle transitions

| Trigger | Action |
|---|---|
| `/triage <new-task>` → new feature | `mkdir .claude/memory/active/<feature-id>` + add to pointers + index |
| `/dc-review` Stage 2 verdict = Approve + user commits | Mark `meta.json` status: completed |
| Session end OR daily cron via session-init.sh | Move completed features older than X days from `active/` → `recent/` |
| 30 days in `recent/` | Compress to `archive/<YYYY-MM>/<feature-id>.tar.gz`, drop dir |
| `/meta archive <feature-id>` | Force-archive (user-triggered) |
| `/meta restore <feature-id>` | Unarchive (rare, e.g., resuming abandoned feature) |

### Hook responsibilities

| Hook | New responsibility (scale-aware) |
|---|---|
| `session-init.sh` | Read `pointers.json` → load primary feature's state. Periodic archival sweep (idempotent, runs once per day). |
| `session-save.sh` | Update `index.json` entry for active feature. Update `meta.json.last_touched`. |
| `pre-compact.sh` | Snapshot ALL active features to `shared/compaction-snapshots/<ts>.json` (not just one). |
| `post-compact.sh` | Read latest snapshot, restore all active features. |
| `evolution-check.sh` | Scan `recent/` + `active/` artifacts for promotion candidates. Skip `archive/` unless explicit `/meta evolve --include-archive`. |
| New `docs-index.sh` (PostToolUse on docs/plans + docs/specs writes) | Regenerate `docs/{plans,specs}/INDEX.md` |

### MCP memory (load-on-demand, NOT in static context)

MCP servers are server-resident — loaded at runtime via tool calls. Plugin uses them WITHOUT bundling their content into context. Per user clarification, MCP usage is allowed.

**Use MCP memory for:**

| Entity type | Example | Stored in |
|---|---|---|
| `ArchitecturalDecision` | "Chose Summer Outbox over Debezium" | MCP graph (entity per ADR) |
| `RecurringPattern` | "WebFlux + JPA = blocking deadlock" | MCP graph (relations between patterns) |
| `ProjectVocabulary` | "SIMO = State Bank reporting" | MCP graph (entity per term) |
| `CommonBug` | "N+1 in JPA when @OneToMany lazy + Stream" | MCP graph (entity per bug type) |
| `ServiceContract` | "auth-ms publishes MerchantCreated.v1 to merchant.event.created.v1" | MCP graph (cross-service relations) |

**MCP integration points:**

| Event | MCP call | Purpose |
|---|---|---|
| Align gate extracts vocabulary | `mcp__memory__create_entities` | Persist term → cross-session lookup |
| Brainstorm produces ADR | `mcp__memory__create_entities` + `create_relations` | ADR node + related decisions |
| Review identifies bug pattern | `mcp__memory__create_entities` | Future preflight surfaces |
| Pre-flight 0 (initial discovery) | `mcp__memory__search_nodes` | "Past features touching auth?" returns related work |
| `/meta search <query>` | `mcp__memory__search_nodes` | Fuzzy semantic search across all features |
| `evolution-check.sh` | `mcp__memory__read_graph` | Aggregate pattern counts for promotion threshold |

**MCP fallback (no MCP available):**

If `mcp__memory__*` tools not registered (no MCP server in user's config), plugin degrades gracefully to filesystem-only mode:
- Vocabulary stored in `CONTEXT.md` (already happens)
- ADRs in `docs/adr/`
- Pattern detection via grep of `recent/` + `active/` directories
- Slower cross-feature search, but functional

Plugin detects MCP availability via tool registry probe at session-init. Sets `mcp_memory_available: bool` in `project-profile.json`.

### Context budget impact

| Operation | Without MCP | With MCP |
|---|---|---|
| Cross-feature vocabulary lookup | grep all `CONTEXT.md` history (slow) | `search_nodes` (fast, on-demand) |
| "What ADRs touch auth?" | grep `docs/adr/*.md` | `search_nodes("auth")` returns related entities + relations |
| Pre-flight context injection | static enumeration | on-demand entity fetch when relevance high |
| Static plugin bundle | ~91k tokens (target) | ~91k tokens (unchanged — MCP loads at runtime) |

MCP usage does NOT inflate static bundle. It expands runtime capability without context cost when unused.

### Archival policy details

Configurable in `devco-config.json`:

```json
{
  "memory": {
    "activeRetentionDays": 7,
    "recentRetentionDays": 30,
    "archiveCompression": "tar.gz",
    "autoArchive": true,
    "indexAutoUpdate": true
  }
}
```

Defaults safe — 7 days active, 30 days recent, then compress. User can disable auto-archive if preferred.

### Migration of existing flat artifacts

Plugin v4.0 → v4.1 migration script: `scripts/migration/reorganize-memory.py`

1. Scan `.claude/memory/{preflight,align-artifacts,brainstorm-artifacts}/` flat dirs
2. Group by inferred feature ID (parse task description from artifact frontmatter; fallback: prompt user)
3. Move into `.claude/memory/active/<feature-id>/` structure
4. Generate `meta.json` per feature
5. Build initial `index.json` + `pointers.json`
6. Backup original flat structure to `.claude/memory/v4.0-backup/` (compressed)

Idempotent. Re-runnable. User can dry-run with `--check`.

### Scale benchmarks (estimated)

| Feature count | Flat shape size | Hierarchical + archive size | Lookup time (cold) |
|---|---|---|---|
| 10 | ~600 KB flat | Same (~600 KB) | <50 ms |
| 100 (1 year @ ~2/wk) | ~6 MB, 1000+ files | ~500 KB active + recent, rest in 12 tarballs (~5 MB compressed) | <100 ms with index.json |
| 500 (3-4 years) | ~30 MB unmanageable | ~500 KB working set + ~25 MB archives (rarely touched) | <100 ms with index.json |
| 1000+ | not viable | <1 MB working set + cold archives | constant via index.json |

Hierarchical + index = constant-time lookup regardless of total feature count.

### Decision: filesystem owns "now", MCP owns "history"

Clear separation of concerns:

| Owns | Filesystem | MCP memory |
|---|---|---|
| Active feature state | Yes | No |
| Recent feature artifacts | Yes | No |
| Historical archives | Yes (tarballs) | No |
| Cross-feature search | Index file (fast) | Graph (semantic, fuzzy) |
| Decision history (ADRs) | `docs/adr/*.md` (canonical) | Entities mirroring ADRs (relations) |
| Vocabulary | `CONTEXT.md` (canonical) | Entities (cross-project) |
| Pattern instincts | `shared/promotion-candidates.md` (transient) | Entities (durable) |
| Git-trackable artifacts | Yes — plans, specs, ADRs, CONTEXT | No |
| Session-ephemeral state | Yes — preflight, workflow-state | No |

Both layers coexist. Filesystem = source of truth for code/decisions. MCP = search index + semantic layer.

---

## Slim target inventory

### Agents: 13 → 7 (-46%)

| Current | Action | Target |
|---|---|---|
| _shared-protocol | KEEP + compress | _shared-protocol (slimmed) |
| planner | KEEP + heavy compress (20K → 8K) | planner |
| spec-writer | KEEP + heavy compress (21K → 8K) | spec-writer |
| slice-executor | KEEP + light compress | slice-executor |
| spec-compliance-reviewer | KEEP | spec-compliance-reviewer |
| code-quality-reviewer | KEEP + absorb pentest + database-reviewer dimensions | code-quality-reviewer (extended) |
| build-fixer | KEEP + compress | build-fixer |
| architect | KEEP (high-stakes only, model: opus) | architect |
| **reviewer** | **REMOVE** (already deprecated, 30 days elapsed → safe to delete) | — |
| **test-runner** | **MERGE into slice-executor** (TDD already covers; E2E becomes spec scenario type) | — |
| **refactorer** | **REMOVE** (invoke `/meta refactor` → slice-executor with refactor flag) | — |
| **pentest** | **REMOVE** (security review absorbed into code-quality-reviewer) | — |
| **database-reviewer** | **REMOVE** (DB review absorbed into code-quality-reviewer dimension) | — |

Result: planner, spec-writer, slice-executor, spec-compliance-reviewer, code-quality-reviewer, build-fixer, architect + _shared-protocol = 7 active + 1 include.

### Skills: 32 → 18 (-44%)

| Current | Action |
|---|---|
| bootstrap | KEEP + compress |
| preflight | KEEP + compress |
| triage | KEEP |
| align | KEEP + light compress |
| brainstorm | KEEP + light compress |
| **subagent-dispatch** | **MERGE into bootstrap §"Subagent dispatch"** (it is a pattern, not a skill — 6K saved) |
| **git-worktree** | **MERGE into bootstrap §"Worktree per slice"** (5K saved) |
| **improve-architecture** | **MERGE into /meta improve-architecture subcommand** (skill content too thin to justify) |
| **continuous-learning** | **MERGE into /meta evolve subcommand** (skill is a meta-doc; logic lives in evolution-check.sh + /meta) |
| coding-standards | KEEP + heavy compress (4.8K → 2K) |
| architecture | KEEP + compress (11K → 5K) |
| api-design | KEEP + compress |
| testing-workflow | KEEP + compress |
| spring-webflux-patterns | KEEP (mutually exclusive with mvc) |
| spring-mvc-patterns | KEEP |
| spring-security | KEEP + compress |
| database-patterns | KEEP + compress |
| messaging-patterns | KEEP + compress |
| redis-patterns | KEEP + compress |
| observability-patterns | KEEP + compress |
| deployment-patterns | KEEP + compress |
| **grpc-patterns** | **REMOVE** (rarely used in this codebase — readd if project actually needs gRPC) OR keep but mark `auto_load: false` |
| **pentest** (skill) | **REMOVE** (review checklist lives in code-quality-reviewer; pentest-scan command still works for explicit audits) |
| summer-core | KEEP (gate skill) |
| summer-data | KEEP + heavy compress (18K → 7K) |
| summer-rest | KEEP + compress |
| summer-security | KEEP + heavy compress (20K → 8K) |
| summer-kafka | KEEP + compress |
| summer-test | KEEP + compress |
| summer-ratelimit | KEEP + compress |
| **summer-file** | **CONDITIONAL** — keep file but only load if project uses summer-file lib |
| **summer-payment-sdk** | **CONDITIONAL** — only load if io.f8a.summer.payment in build.gradle |

Net: 18 active core + 2 conditional rare-load.

### Commands: 17 → 10 (-41%)

| Current | Action |
|---|---|
| triage | KEEP |
| align | KEEP |
| brainstorm | KEEP |
| plan | KEEP + light compress |
| spec | KEEP + light compress |
| build | KEEP + light compress |
| verify | KEEP |
| dc-review | KEEP + compress |
| dc-setup | KEEP + compress |
| dc-status | KEEP + compress |
| meta | KEEP — absorbs subcommands |
| **build-fix** | **REMOVE** (verify-fix-loop.sh hook auto-invokes; no slash command needed) |
| **refactor** | **REMOVE → `/meta refactor`** |
| **pentest-scan** | **REMOVE → `/meta pentest`** OR keep as security-focused entry point (decide below) |
| **threat-model** | **MERGE → `/meta threat-model`** |
| **e2e** | **REMOVE → `/meta e2e`** OR auto-invoked by slice-executor for endpoint slices |
| **db-migrate** | **REMOVE → `/meta db-migrate`** OR call via slice-executor for migration slices |

Result: 10 top-level slashes + `/meta` umbrella for maintenance / security / E2E / refactor / DB-migrate.

### Rules: 18 → 18 (stays — all essential)

No removal. Apply caveman-compress to all. Estimated 76K → 38K.

### Hooks: 22 → 17 (-23%)

| Current | Action |
|---|---|
| session-init | KEEP + light compress (24K — keep most logic) |
| session-save | KEEP + compress |
| preflight-gate | KEEP |
| preflight-discovery | KEEP |
| workflow-gate | KEEP |
| workflow-tracker | KEEP |
| workflow-phase-lock | KEEP |
| quality-gate | KEEP + light compress |
| skill-router | KEEP (announcement-only post-v4.0) |
| subagent-init | KEEP + compress |
| pre-compact | KEEP |
| post-compact | KEEP |
| compact-advisor | KEEP |
| build-checkpoint | KEEP |
| verify-fix-loop | KEEP |
| auto-adr | KEEP |
| evolution-check | KEEP (rewrite to use filesystem only, no mcp__memory__) |
| run-with-flags | KEEP (utility) |
| git-guard | KEEP |
| **observability-trace** | **REMOVE** (already stubbed + unregistered in hooks.json; delete file) |
| **memory-gate** | **REMOVE** (overlap with session hooks + skill-router; merge useful bits into skill-router or delete) |
| **team-spawn-evaluator** | **REMOVE** (logic moved into commands/build.md per v4.0; redundant) |

Result: 19 hooks (was 22).

### Templates: 8 → 7 (-12%)

| Current | Action |
|---|---|
| CONTEXT_TEMPLATE | KEEP |
| PLAN_TEMPLATE | KEEP (single-file) |
| PLAN_INDEX_TEMPLATE | KEEP (split) |
| PLAN_SLICE_TEMPLATE | KEEP |
| SPEC_TEMPLATE | KEEP |
| SPEC_INDEX_TEMPLATE | KEEP |
| SPEC_SLICE_TEMPLATE | KEEP |
| **PROJECT_GUIDELINES_TEMPLATE** | **REMOVE** (17K, never referenced in active code — pre-v4.0 artifact) |

Result: 7 templates.

---

## Token reduction projection

| Category | Now (tokens) | After slim + caveman | Reduction |
|---|---|---|---|
| Skills | 61 k | ~26 k | 57 % |
| Agents | 28 k | ~12 k | 57 % |
| Commands | 29 k | ~14 k | 52 % |
| Rules | 19 k | ~10 k | 47 % |
| Hooks | 31 k | ~22 k | 29 % (scripts stay near-natural) |
| Templates | 11 k | ~7 k | 36 % |
| **Total** | **180 k** | **~91 k** | **49 %** |

Per-session loaded context (bootstrap + auto-loaded fragments only, not entire bundle) drops correspondingly. Plugin install footprint also drops.

---

## Caveman compression matrix (refined)

| Asset type | Audience | Compression | Why |
|---|---|---|---|
| Agent system prompts | Agent | FULL | Agent reads at every invocation — biggest leverage |
| Skill `description` frontmatter | Agent | FULL | Loaded in pre-flight enumeration |
| Skill body | Agent (mostly) | LITE | Code examples + tables need readability |
| Skill `references/*.md` | Agent on-demand | LITE | Loaded sparingly |
| Rules `common/*` + `java/*` + `summer/*` | Agent | FULL | Loaded per pre-flight |
| Commands frontmatter + First Action blocks | Agent | FULL | Read on invocation |
| Commands body (long-form guidance) | Mixed | LITE | Human sometimes reads to debug |
| Hook scripts (bash bodies) | Maintainer | OFF | Code stays normal |
| Hook stderr / additionalContext output | Agent | FULL | Injected into agent context |
| Templates (PLAN/SPEC) | Agent + Human | LITE | Both audiences |
| Frontmatter keys | n/a | n/a | Mechanical |
| Examples in skills | Human-first | OFF | Demonstrate full pattern |
| README, MIGRATION, WORKING_WORKFLOW | Human | OFF | Onboarding |
| ADR | Human | OFF | Institutional memory |
| CONTEXT.md (populated) | Mixed | OFF | Living doc |
| Proposals | Human | OFF | Decision artifacts |

Apply via `~/.claude/plugins/marketplaces/caveman/skills/caveman-compress` skill — already vendored.

---

## Migration sequence (proposed phases)

### Phase A — Removal (safe, mechanical)

1. Delete deprecated agent files: `reviewer.md` (30 days elapsed assumed)
2. Delete unused hook files: `observability-trace.sh`, `memory-gate.sh`, `team-spawn-evaluator.sh`
3. Delete `templates/PROJECT_GUIDELINES_TEMPLATE.md`
4. Delete skills: `grpc-patterns/`, `pentest/` (the skill, not the agent), `improve-architecture/`, `continuous-learning/`, `subagent-dispatch/`, `git-worktree/`
5. Delete agents: `test-runner.md`, `refactorer.md`, `pentest.md`, `database-reviewer.md`
6. Delete commands: `build-fix.md`, `refactor.md` (+ optional pentest-scan/threat-model/e2e/db-migrate per decision)

Cross-references updated:
- `validate-agents.sh` agent list shrinks
- `validate-commands.sh` agent grep list shrinks
- `hooks/hooks.json` already clean
- `skills/bootstrap/SKILL.md` registry table shrinks
- `agents/_shared-protocol.md` `requiredSkills` references updated in agents (no longer reference removed skills)

### Phase B — Merge (logic moves)

1. `subagent-dispatch` content → `skills/bootstrap/SKILL.md §"Subagent dispatch"`
2. `git-worktree` content → `skills/bootstrap/SKILL.md §"Worktree per slice"`
3. `improve-architecture` skill content → `commands/meta.md` documentation (subcommand stays)
4. `continuous-learning` skill content → `commands/meta.md` §"Auto-evolution policy" + `scripts/hooks/evolution-check.sh` updated comments
5. `test-runner` E2E logic → `agents/slice-executor.md §"E2E for endpoint slices"` (slice-executor handles both unit + E2E per spec scenarios)
6. `pentest` checklist → `agents/code-quality-reviewer.md §"Security dimension"` (already has security section, extend)
7. `database-reviewer` DB checklist → `agents/code-quality-reviewer.md §"Database dimension"` (new section)

### Phase C — Memory architecture cutover (REVISED)

**C1. Lifecycle reorganization (filesystem)**

1. Implement `.claude/memory/{active,recent,archive,shared}/` hierarchy
2. Per-feature dirs with `meta.json`, `triage.json`, `workflow-state.json` (move from `.claude/` root + flat `state/`)
3. Build `index.json` + `pointers.json` (multi-feature support)
4. Build `docs-index.sh` hook (regenerate `docs/{plans,specs}/INDEX.md`)
5. Implement archival sweep in `session-init.sh` (idempotent, daily)
6. Write `scripts/migration/reorganize-memory.py` (one-shot v4.0 → v4.1 layout)
7. Update all hooks + agents reading `.claude/memory/state/<file>.json` → read `.claude/memory/active/<feature-id>/<file>.json` via pointer
8. Update `pre-compact.sh` / `post-compact.sh` for multi-feature snapshot
9. Update `evolution-check.sh` to scan active + recent (skip archive unless flag)

**C2. MCP memory integration (on-demand, optional)**

1. Re-enable `mcp__memory__*` calls in `_shared-protocol.md` (restore from earlier removal)
2. Add MCP probe at session-init: set `mcp_memory_available: bool` in `project-profile.json`
3. Define entity types: `ArchitecturalDecision`, `RecurringPattern`, `ProjectVocabulary`, `CommonBug`, `ServiceContract`
4. Align skill → `create_entities` on vocabulary extraction
5. Brainstorm skill → `create_entities` + `create_relations` for ADR + rejected alternatives
6. `/meta search <query>` → `search_nodes` wrapper
7. Pre-flight 0 → optional `search_nodes` for context-relevant past entities (only if `mcp_memory_available`)
8. Graceful fallback: all features work WITHOUT MCP (filesystem grep), MCP only enhances search

**C3. Remove third-party plugin dependencies (NOT MCP)**

1. Remove `claude-mem` references (none currently; verify)
2. Remove ECC `instincts.jsonl` references in continuous-learning skill (if present)
3. Replace `~/.claude/instincts/` paths in `evolution-check.sh` with `~/.claude/memory/auto-evolved-skills/`

**C4. Bootstrap + workflow doc updates**

1. `skills/bootstrap/SKILL.md` — add §"Memory architecture (lifecycle + MCP)"
2. `WORKING_WORKFLOW.md` — replace Tier 1/2/3 section with new lifecycle + MCP detail
3. `CLAUDE.md` — note MCP optional, filesystem authoritative

### Phase D — Caveman compression pass

Run `compress` skill on:
- Every remaining agent .md
- Every remaining skill SKILL.md (skip examples/ + references/)
- Every rule .md
- Every command .md (First Action blocks especially)
- Templates (lite — keep human-readable structure)

Save `.original.md` backups via the compress skill convention.

### Phase E — Final validation

1. `bash scripts/ci/run-all.sh` → 7/7 PASS
2. Smoke test: `bash scripts/ci/validate-plan-spec-templates.sh --all`
3. Token measurement: capture new bundle size, compare to baseline

---

## Open decisions for user

**REVISED 2026-05-16 — memory-related decisions appended (11-15):**

1. **Pentest / threat-model / e2e / db-migrate commands:** REMOVE (move under `/meta`) or KEEP as top-level slashes for discoverability?
   - **Recommend:** KEEP as top-level (security + db-migrate users invoke frequently)
2. **`grpc-patterns` skill:** DELETE outright, OR mark conditional (load only if `grpc-spring-boot` in build.gradle)?
   - **Recommend:** mark conditional. Detect at session-init.sh, set `grpc:true` in project-profile.json. Same pattern as Summer.
3. **`pentest` (the skill) deletion:** absorb 100% into `code-quality-reviewer` §security dimension, OR keep a thin skill file referenced by `pentest-scan` command for OWASP scripts?
   - **Recommend:** keep thin skill file (~2K) wrapping the OWASP scripts; delete the verbose checklist body (lives in reviewer agent now)
4. **`subagent-dispatch` + `git-worktree` skills:** merge into bootstrap (proposed) OR keep as standalone but slim (1-2K each)?
   - **Recommend:** merge into bootstrap. These are patterns, not domain skills.
5. **`continuous-learning` skill:** delete entirely (logic in /meta + evolution-check.sh) OR keep as 1-page meta-doc?
   - **Recommend:** keep as 1-page meta-doc (~2K) so pre-flight discovery can still surface it for `/meta learn` invocations. Strip the heavy instinct-pipeline details (already in `references/`).
6. **`reviewer.md` deprecation:** 30 days elapsed? Delete now or keep stub?
   - **Recommend:** delete. v4.0 published. Anyone still using `/dc-review` gets the new orchestrator.
7. **`PROJECT_GUIDELINES_TEMPLATE.md` (17K):** delete, OR caveman-compress + repurpose as the canonical "what to put in CLAUDE.md" template?
   - **Recommend:** delete. Users have CLAUDE.md hierarchy + plugin's own CLAUDE.md as guidance.
8. **`memory-gate.sh`:** delete outright OR scan for useful bits before deleting?
   - **Recommend:** read file first (200 LOC). If pure no-op / overlap, delete. If has useful logic, merge into `session-save.sh`.
9. **Compression backups:** `caveman-compress` writes `.original.md` backups. Commit backups OR git-ignore?
   - **Recommend:** git-ignore (`*.original.md` in `.gitignore`). Backups are for one-shot rollback during refactor; should not bloat repo long-term.
10. **Schedule:** execute all phases (A-E) in one sweep, OR phase-by-phase with user review between each?
    - **Recommend:** Phase A (Removal) + B (Merge) in one PR — mechanical, low-risk. Phase C1 (lifecycle reorg) separate PR — schema migration touches all hooks. C2 (MCP) separate PR — optional layer. Phase D (Caveman) separate PR. Phase E in each.

11. **MCP memory adoption:** required dependency OR optional enhancement?
    - **Recommend:** OPTIONAL. Probe at session-init, degrade gracefully if MCP absent. Documented as "recommended for projects with 50+ historical features; not needed for greenfield."
12. **Active retention window:** 7 days default, OR shorter (3) / longer (14)?
    - **Recommend:** 7 days. Adjust via `devco-config.json` `memory.activeRetentionDays`.
13. **Archive compression format:** `.tar.gz` OR `.zip` OR uncompressed?
    - **Recommend:** `.tar.gz` (standard, restore via `tar -xzf`, ~5-10x compression on markdown).
14. **Multi-feature support level:** Strict (one active at a time, switch via `/triage --switch`) OR loose (multiple parallel actives)?
    - **Recommend:** LOOSE — `pointers.json.active_features` is array. `primary` for default work. User explicitly handles parallel work via `--switch` or distinct sessions.
15. **Index.json maintenance:** real-time per-write (hook) OR batched (session-end)?
    - **Recommend:** real-time via `session-save.sh` + `docs-index.sh` hook. Cost negligible (<100ms per write). Stale index = bad UX.

---

## What does NOT change

- 5-layer workflow design
- Pre-flight 1% rule
- Triage / Align / Brainstorm / Plan / Spec / Execute / Review / Learn gate sequence
- Two-stage review pattern
- Slice decomposition + template enforcement
- CLAUDE.md hard blocks
- Multi-service decomposition (Option 2c)
- Rules `common/` + `java/` + `summer/` split
- Lane-aware behavior (trivial/standard/high-stakes)
- Caveman compression policy (already documented in REFACTOR_PLAN §7.2)

This proposal only TRIMS implementation, not architecture. Workflow stays whole.

---

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| Deleting agent (test-runner, refactorer, etc.) breaks user macros | Keep deprecation stubs 30 days; document in MIGRATION_v4.1.md |
| Merging logic into bootstrap bloats it | Compress bootstrap aggressively; keep merged sections short |
| Caveman compression loses meaning | Per-section pass-through review before commit |
| Removing mcp__memory__* breaks existing knowledge graphs | Document migration: export to filesystem before upgrade |
| Conditional skills (summer-payment-sdk, summer-file, grpc) cause cold-start misses | session-init.sh detects + sets profile correctly; pre-flight enumerates from filesystem regardless |
| Removing observability-trace.sh hides bugs | Already stubbed; metric collection happens at quality-gate level |
| Bundle still feels large after slim | Acceptable target: ~91 K tokens vs current 180 K = 49% reduction |

---

## Decision request (REVISED)

Phases now:
- **A:** Removal (agents, skills, commands, hooks, templates)
- **B:** Merge (subagent-dispatch + git-worktree → bootstrap; pentest/database-reviewer dimensions → code-quality-reviewer; test-runner → slice-executor)
- **C1:** Memory lifecycle reorganization (filesystem)
- **C2:** MCP memory integration (optional layer)
- **C3:** Remove ECC/claude-mem residue
- **C4:** Bootstrap + workflow doc updates
- **D:** Caveman compression pass
- **E:** Final CI + token measurement

Reply with one of:

- **Approve all phases** — A → B → C (all sub) → D → E
- **Approve A + B + C1 + C4 + E** — filesystem reorg + slim, no MCP yet
- **Approve A + B + D + E** — slim + caveman, defer memory reorg to v4.2
- **Approve A + B only** — slim, defer everything else
- **Approve with changes** — specify Open Decision answers (1-15) that differ from recommendations
- **Counter-proposal** — describe alternative shape
- **Reject** — keep current inventory + memory model

After decision I execute the refactor per agreed scope.
