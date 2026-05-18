# Memory Architecture Research — Addendum

**Status:** Research findings for evaluation. Updates supersede 2026-05-16 proposal "Scale-aware memory architecture" section.
**Date:** 2026-05-18
**Parent proposal:** `docs/proposals/2026-05-16-plugin-slim-optimization.md`

---

## Critical correction — user's premise was incorrect

**User stated:** ".claude/memory/ will auto-load into context, at scale this blows the context window."

**Reality per official Claude Code docs (https://code.claude.com/docs/en/memory):**

`.claude/memory/` is **NOT** auto-loaded by Claude Code. Only the following load automatically at session start:

| Path | Auto-load? | Limit |
|---|---|---|
| Managed CLAUDE.md (`/Library/Application Support/ClaudeCode/CLAUDE.md` etc.) | YES | none, but target <200 lines |
| User CLAUDE.md (`~/.claude/CLAUDE.md`) | YES | target <200 lines |
| Project CLAUDE.md (`./CLAUDE.md` or `./.claude/CLAUDE.md`) | YES | target <200 lines |
| `CLAUDE.local.md` (project root) | YES | per-user, gitignored |
| `.claude/rules/*.md` (no `paths:` frontmatter) | YES | concatenated into context at launch |
| `.claude/rules/*.md` (with `paths:` frontmatter) | NO at launch — loaded when matching file opened | per-rule |
| `~/.claude/projects/<project>/memory/MEMORY.md` (Claude's auto-memory) | YES | **first 200 lines OR 25KB whichever first** |
| `~/.claude/projects/<project>/memory/<topic>.md` (Claude's auto-memory topic files) | NO — loaded on-demand via Read tool | n/a |
| Plugin SKILL.md frontmatter (description) | YES (catalog only) | n/a |
| Plugin SKILL.md body | NO — loaded via Skill tool invocation | n/a |
| Plugin agent .md | NO — loaded when Task tool dispatches agent | n/a |
| Plugin slash commands | NO — loaded on invocation | n/a |
| `.claude/memory/` (plugin-managed) | **NO — filesystem only, NOT auto-loaded** | n/a |
| `.claude/sessions/<id>.json` | NO — Claude Code reads on resume only | n/a |
| Hook script output (`additionalContext` field) | **YES — injected when hook fires** | controlled by hook |

### What CAN bloat context

The plugin's `.claude/memory/` files only enter the context window when:

1. **A hook reads them and emits `additionalContext`** in its JSON output (e.g., `session-init.sh`, `subagent-init.sh`, `post-compact.sh`, `preflight-gate.sh` all currently do this)
2. **An agent reads them via Read tool** during execution
3. **An MCP server returns content** in response to a tool call

This means the scale risk lives in **hook output discipline**, not in filesystem size.

### Implications

The 2026-05-16 proposal's "lifecycle reorganization" is still valuable for **filesystem manageability + search speed + disk space**, but the framing was wrong. Correct framing: organize memory for **per-feature isolation, fast lookup, and archival**, not because Claude Code auto-loads it.

The real risk is **unbounded hook output**. That has a different fix: hook output caps + selective injection.

---

## Native primitives discovered (not previously leveraged)

### 1. `.claude/rules/` — native rules system

Claude Code natively supports `.claude/rules/*.md` with `paths:` frontmatter for path-scoped rule loading. This is **separate** from CLAUDE.md.

**Behavior:**
- Files without `paths:` frontmatter → loaded at every session start
- Files with `paths: ["src/**/*.ts"]` → loaded only when Claude reads a matching file
- Discovered recursively under `.claude/rules/`
- User-level: `~/.claude/rules/` applies to every project
- Loaded in user-level → project-level order (project rules win)

**Implication for plugin:** plugin already has `rules/common/*.md` + `rules/java/*.md` + `rules/summer/*.md`. These are NOT in `.claude/rules/` — they live in plugin dir. They are read by plugin agents on-demand. **Decision needed:** should we move some rules to `.claude/rules/` so Claude Code itself auto-loads them, OR keep them in plugin dir for explicit per-gate enumeration?

**Trade-off:**

| Option | Pro | Con |
|---|---|---|
| Keep rules in plugin dir | Pre-flight 1% rule + explicit enumeration. Lane-aware loading. | Not auto-loaded; agent must explicitly Read. |
| Move to `.claude/rules/` | Auto-loaded by Claude Code per `paths:` scope. Zero hook cost. | Bypasses pre-flight; rule applies to ALL Claude work, not just plugin agents. Pollutes context for unrelated work. |
| Hybrid | Plugin rules stay in plugin dir for pre-flight discipline. User CAN OPTIONALLY symlink a curated subset into their own `.claude/rules/` via `/dc-setup --link-rules`. | Two locations to manage. |

**Recommend:** Hybrid — keep authoritative copies in plugin's `rules/`, provide `/dc-setup --link-rules` option for users who want Claude Code to auto-apply selected rules at the OS level. Default: NO symlink (preserves 1% rule discipline).

### 2. Claude's own auto-memory at `~/.claude/projects/<project>/memory/MEMORY.md`

Claude Code itself manages per-project auto-memory. Claude writes to `MEMORY.md` based on user corrections + discovered preferences. **First 200 lines or 25KB auto-loaded** at every session.

**Topic files** like `~/.claude/projects/<project>/memory/debugging.md` are NOT auto-loaded — Claude reads them via Read tool when needed.

**Implication for plugin:** **delegate cross-session learning to Claude's auto-memory**. Stop building parallel learning systems (`instincts.jsonl`, `continuous-learning` skill, etc.). When the plugin discovers a pattern worth remembering, tell Claude "remember that ..." — Claude writes it to MEMORY.md automatically. Native, bounded, audit-able via `/memory`.

This **eliminates** the proposed `~/.claude/memory/auto-evolved-skills/` directory in favor of Claude's native mechanism. Less code to maintain, no migration concerns, native compaction handling.

**`/memory` slash command** is built-in — users can view + edit auto-memory anytime.

### 3. Compaction-survives-CLAUDE.md

Project-root `CLAUDE.md` survives compaction — Claude re-reads from disk and re-injects after compact. Subdirectory CLAUDE.md does NOT auto-reload (only reloads when Claude reads files in that subdir).

**Implication for plugin:** put all critical state references in project-root `CLAUDE.md`. Avoid relying on conversation-only state.

### 4. `claudeMdExcludes` for monorepo

Settings option to skip specific CLAUDE.md files. Useful for users in monorepos where other teams' CLAUDE.md isn't relevant. Plugin's `dc-setup` could surface this to users.

### 5. `--add-dir` + `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`

Users can load memory from additional directories (e.g., shared-config repo). Plugin shouldn't fight this — should work alongside.

### 6. `InstructionsLoaded` hook

Native hook event — fires when Claude loads instructions. Plugin could use this to log which CLAUDE.md / rules actually loaded for debugging.

---

## What other plugins do

### ECC (everything-claude-code) — relevant findings

| Pattern | Detail | Adopt? |
|---|---|---|
| **Hook context cap env vars** | `ECC_SESSION_START_MAX_CHARS=8000`, `ECC_SESSION_START_CONTEXT=off` | YES — adopt `DEVCO_SESSION_START_MAX_CHARS` and similar |
| **Hook runtime profiles** | `ECC_HOOK_PROFILE=minimal|standard|strict`, `ECC_DISABLED_HOOKS` | YES — already partially in plugin via `run-with-flags.sh`, extend |
| **Instinct YAML with confidence** | `~/.claude/instincts/<id>.yaml` with Action/Evidence/Examples sections | NO — replace with Claude's native auto-memory (MEMORY.md). Reason: native mechanism already exists, bounded, audit-able. |
| **Stop-phase extraction** | `evaluate-session.js` extracts patterns at session end | YES — plugin already has `evolution-check.sh`. Update to use Claude's auto-memory instead of custom instincts. |
| **6+ MCPs bundled** | github, context7, exa, playwright, memory, sequential-thinking | Optional — plugin should NOT bundle. Let users add. Plugin probes availability + uses if present. |
| **Strategic compaction skill** | `/learn` suggests pruning | YES — keep similar in `/meta compact-advisor` or extend existing `compact-advisor.sh` |

### Superpowers (obra) — relevant findings

| Pattern | Detail | Adopt? |
|---|---|---|
| **Subagent dispatch with fresh context** | Each task spawns fresh subagent | YES — already in plugin (slice-executor + Task tool isolation) |
| **Skill-based (no persistent memory)** | Skills carry knowledge; no `.claude/memory/` accumulation | Adopt PRINCIPLE — minimize plugin-managed memory, prefer skills + Claude's auto-memory |
| **Brainstorming as skill** | Multi-option exploration before commit | YES — already in plugin |
| **Activation phases** | Six lifecycle phases | Different from plugin's 5-layer, no conflict |

### mattpocock — relevant findings

| Pattern | Detail | Adopt? |
|---|---|---|
| **CONTEXT.md in project root** | Domain vocabulary, ADR-aligned | YES — already in plugin |
| **Lightweight, on-demand loading** | Skills load only when invoked | YES — already in plugin |
| **Per-repo configuration via `/setup`** | One-shot setup per project | YES — already in plugin (`/dc-setup`) |
| **git-guardrails pre-execution hook** | Block dangerous git commands | YES — already in plugin (`git-guard.sh`) |
| **No persistent memory beyond CONTEXT.md** | Heavy reliance on CLAUDE.md + CONTEXT.md | YES — minimize plugin memory, lean on native |

---

## Revised memory architecture proposal

### Principle 1 — Filesystem only for ephemeral session state

`.claude/memory/` exists for **session-scoped artifacts that hooks need to read across the same session**. Pre-flight artifacts, plan/spec paths in workflow-state.json, build checkpoints. Not designed for cross-session continuity.

| What goes in `.claude/memory/` | Lifetime |
|---|---|
| Pre-flight artifacts | Until session compacted or next gate of same type |
| Workflow state | Active session |
| Build checkpoint | Until BUILD complete |
| Review verdicts | Until session ends |
| Compaction snapshots | Until next compaction |
| Promotion candidates | Until user runs `/meta evolve` |

After session ends, most of `.claude/memory/` content is **disposable**. Archival is optional, not critical (per `.gitignore`, content is local-only).

### Principle 2 — Cross-session learning goes to Claude's native auto-memory

Replace plugin's custom learning system (`~/.claude/instincts.jsonl`, `~/.claude/memory/auto-evolved-skills/`) with Claude Code's native `~/.claude/projects/<project>/memory/MEMORY.md` mechanism.

**How:**
- `evolution-check.sh` detects promotion candidates → instead of writing to plugin's own location, instruct Claude: "Remember: <pattern>" via additionalContext
- Claude writes to MEMORY.md automatically
- First 200 lines / 25KB auto-load every session — bounded automatically
- Topic files (`debugging.md`, `patterns.md`) load on-demand via Read tool

**Benefits:**
- No parallel storage system
- Native compaction handling
- User audit via `/memory` slash command
- Survives plugin uninstall
- Native bounded auto-load — no manual budget management

**`/meta evolve` becomes:** "review pattern candidates → instruct Claude to remember selected ones." Logic simpler. No file synthesis. No SKILL.md auto-generation. Skills evolve manually via `skill-creator` skill when user actually wants a formal skill from a pattern.

### Principle 3 — Project decisions (durable) go to git-tracked docs

- `CONTEXT.md` (project root) — domain vocabulary, manually maintained
- `docs/adr/*.md` — architectural decisions, manually written from `/meta adr` template
- `docs/plans/`, `docs/specs/` — feature artifacts

These survive plugin uninstall, transfer between machines via git, version-tracked.

### Principle 4 — MCP for cross-feature search (load-on-demand)

When MCP memory server is registered:
- Plugin populates entities on Align/Brainstorm/Review key events
- `/meta search <query>` calls `mcp__memory__search_nodes` on user request
- NO automatic injection in hooks — entity content enters context only on explicit tool call

When MCP memory server is NOT registered:
- Plugin degrades to filesystem grep over `docs/adr/`, `CONTEXT.md`, recent feature dirs
- Same UX, slower

### Principle 5 — Hook output caps (the real scale defense)

Add explicit char/line budgets to every hook that emits `additionalContext`. Configurable via env vars (ECC pattern).

| Hook | Default cap | Env override |
|---|---|---|
| `session-init.sh` | 8000 chars | `DEVCO_SESSION_START_MAX_CHARS` |
| `subagent-init.sh` | 6000 chars | `DEVCO_SUBAGENT_INIT_MAX_CHARS` |
| `preflight-gate.sh` / `preflight-discovery.sh` | 4000 chars | `DEVCO_PREFLIGHT_MAX_CHARS` |
| `post-compact.sh` | 3000 chars | `DEVCO_POST_COMPACT_MAX_CHARS` |
| `compact-advisor.sh` (stderr only) | n/a | n/a |

Inside cap, prioritize: pre-flight artifact summary → workflow state → lane → cross-cutting excerpt (split shape) → likely-skills hint. Drop lower-priority items when cap hit.

Hook profile env: `DEVCO_HOOK_PROFILE=minimal|standard|strict` controls which hooks fire and how much they inject:
- `minimal` — only critical hooks (session-init basic, workflow-gate, quality-gate), small caps
- `standard` — full hook set, default caps (current behavior)
- `strict` — full hook set + extra validation, slightly larger caps for richer context

### Principle 6 — Lifecycle organization for filesystem manageability

Keep the per-feature directory shape from 2026-05-16 proposal, BUT justify by:
- ✅ Per-feature isolation enables multi-feature parallelism
- ✅ Per-feature dir = clean review (`tree .claude/memory/active/<id>/`)
- ✅ Archival reduces disk usage at scale
- ✅ Index file enables fast cross-feature lookup
- ❌ NOT because Claude Code auto-loads `.claude/memory/` (it doesn't)

The per-feature structure is for **human + plugin manageability**, not context budget.

---

## Final memory layer summary

```
LAYER 1 — Auto-loaded by Claude Code at every session
├── /Library/Application Support/ClaudeCode/CLAUDE.md  (managed policy, rare)
├── ~/.claude/CLAUDE.md                                (user-level)
├── ~/.claude/rules/*.md                                (user-level rules, unscoped only)
├── ~/.claude/projects/<project>/memory/MEMORY.md      (Claude's auto-memory, ≤ 200 lines / 25KB)
├── ./CLAUDE.md or ./.claude/CLAUDE.md                  (project-level — INCLUDES plugin guidance)
├── ./.claude/rules/*.md                                (project rules, unscoped only)
└── ./CLAUDE.local.md                                   (per-user project)

LAYER 2 — Loaded conditionally / on-demand
├── ./.claude/rules/*.md with paths: frontmatter        (loaded when matching file opened)
├── ./*/CLAUDE.md in subdirs                            (loaded when files in subdir read)
└── ~/.claude/projects/<project>/memory/<topic>.md     (Claude reads via Read tool)

LAYER 3 — Read by plugin / agents / hooks on-demand (NOT auto-loaded)
├── Plugin SKILL.md bodies                              (via Skill tool)
├── Plugin agent .md                                    (via Task tool dispatch)
├── Plugin slash command .md                            (on invocation)
├── Plugin rules/{common,java,summer}/*.md              (via agent Read in pre-flight)
├── ./.claude/memory/**                                 (via hook + agent Read; NOT auto)
└── Hook output additionalContext                       (capped per Principle 5)

LAYER 4 — Cross-session via MCP server (load-on-demand)
└── mcp__memory__{search_nodes, read_graph, create_entities}  (when explicitly invoked)

LAYER 5 — Git-tracked durable docs (per-session read-on-demand)
├── ./CONTEXT.md
├── ./docs/adr/*.md
├── ./docs/plans/**
└── ./docs/specs/**
```

**Auto-load context budget estimate (Layer 1):**
- Plugin's project CLAUDE.md: ~1-2K tokens (current 4.5K → caveman-compress to ~1.5K)
- User's CLAUDE.md: depends on user, typical 500-2000 tokens
- `.claude/rules/`: 0 by default (plugin's rules stay in plugin dir)
- Claude's auto-memory: bounded to 25KB ≈ 6-8K tokens
- **Total fixed cost per session:** ~10-12K tokens regardless of project scale

**This is bounded.** Hook injection (Layer 3 / Principle 5) is the variable cost. With caps, total session-init context budget ≤ 20K tokens.

---

## Revised decisions for user

Supersedes Open Decisions 11-15 from 2026-05-16 proposal.

11. **MCP memory adoption:** OPTIONAL with graceful degrade.
    - **Recommend:** confirm OPTIONAL.

12. **Plugin's continuous-learning + instincts.jsonl:** REPLACE with Claude's native auto-memory.
    - **Recommend:** YES — delegate cross-session learning to native. Delete plugin's parallel system.

13. **Plugin rules location:** stay in plugin dir vs move to `.claude/rules/`?
    - **Recommend:** Hybrid. Keep authoritative in plugin dir. `/dc-setup --link-rules` opt-in for symlinking subset to `.claude/rules/` for users who want Claude-native auto-load.

14. **Hook output caps:** introduce + configurable?
    - **Recommend:** YES. Add `DEVCO_*_MAX_CHARS` env vars. Default caps per table above. Profile env `DEVCO_HOOK_PROFILE=minimal|standard|strict`.

15. **`.claude/memory/` lifecycle reorganization:** still proceed despite no auto-load issue?
    - **Recommend:** YES for filesystem manageability + per-feature isolation + multi-feature parallelism. Justification refined (not about context budget anymore).

16. **`auto-evolved-skills` directory in `~/.claude/`:** keep OR delete?
    - **Recommend:** DELETE. Use Claude's auto-memory + `skill-creator` skill manually when user wants formal SKILL.md from a pattern.

17. **InstructionsLoaded hook integration:** add debug helper?
    - **Recommend:** add as opt-in `DEVCO_DEBUG_INSTRUCTIONS=1` flag. Default off.

18. **`/memory` integration:** plugin should reference Claude's native `/memory` command in `/meta evolve` workflow?
    - **Recommend:** YES — `/meta evolve` documents how to ask Claude to remember, and points users to `/memory` for audit.

---

## Revised migration sequence

Updated C-phase per findings:

### Phase C (REVISED) — Memory architecture cutover

**C0. Hook output caps (NEW — most impactful)**
- Add char-limit logic + env vars to all `additionalContext`-emitting hooks
- Add `DEVCO_HOOK_PROFILE` env var support
- Document budget per hook
- **Effort:** 2-3h. **Token impact at runtime:** significant (capped injections vs unbounded current state)

**C1. Lifecycle reorganization (filesystem)** — as previously proposed
- Per-feature `.claude/memory/active/<feature-id>/` structure
- `index.json` + `pointers.json` for multi-feature support
- Archival policy + `scripts/migration/reorganize-memory.py`
- **Justification refined:** filesystem manageability + multi-feature parallelism, NOT context budget

**C2. MCP optional layer** — as previously proposed (no change)

**C3. Native auto-memory adoption (NEW — replaces previous C3)**
- Remove plugin's `~/.claude/instincts/` references
- Remove `~/.claude/memory/auto-evolved-skills/` proposal (not built)
- Update `evolution-check.sh` to instruct Claude via additionalContext: "Consider remembering: <pattern>" rather than writing custom files
- Update `continuous-learning` skill body (or delete per slim plan) to reference Claude's native `/memory`
- Update `/meta evolve` subcommand: walks user through saying "remember X" to Claude, OR running `/memory` directly

**C4. Native `.claude/rules/` opt-in support**
- Add `/dc-setup --link-rules <profile>` option (e.g., `--link-rules java-spring-webflux` symlinks plugin's webflux + common rules into `.claude/rules/`)
- Document trade-off in WORKING_WORKFLOW.md
- Default: NO symlink, preserve pre-flight discipline

**C5. Hook profile (NEW)**
- Implement `DEVCO_HOOK_PROFILE=minimal|standard|strict`
- Document per-profile behavior

**C6. Bootstrap + docs**
- Update bootstrap skill memory section
- Update WORKING_WORKFLOW.md with new memory layer table
- Update CLAUDE.md hard blocks

---

## Decision request

Reply with one of:

- **Approve all revisions** — implement C0 (hook caps) + C1 (lifecycle) + C2 (MCP optional) + C3 (native auto-memory) + C4 (rules opt-in) + C5 (profiles) + C6 (docs). Plus phases A + B + D + E from parent proposal.

- **Approve C0 + C3 only** — solve the real problem (hook caps + native auto-memory). Defer lifecycle reorg + MCP + rules symlinks.

- **Approve C0 + C1 + C3 + C6** — hook caps + filesystem reorg + native memory + docs. No MCP/rules/profile for v4.1.

- **Approve revisions but reject `.claude/rules/` symlink option (C4)** — keep pre-flight discipline absolute.

- **Approve with changes** — specify which sub-phases / open decisions (11-18) differ.

- **Counter-proposal** — alternative memory model (describe).

After decision I execute per scope.
