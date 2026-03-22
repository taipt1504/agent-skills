# Plugin Review — Executive Summary

> **Date**: 2026-03-23
> **Team**: plugin-review (4 specialists + team lead)
> **Plugin**: devco-agent-skills v3.0.0
> **Overall Grade**: B+ (Strong foundation, significant implementation gaps)
> **Scope**: Plugin code only (agents/, skills/, commands/, rules/, hooks/, scripts/). `docs/` is document storage — excluded from review.

---

## Review Team

| Reviewer | Focus Area | Grade |
|----------|-----------|-------|
| arch-reviewer | Plugin Architecture | B+ |
| components-reviewer | Agents, Skills, Commands, Rules, Hooks | B+ (4.3/5) |
| workflow-reviewer | SDD Workflow Architecture | B (design A, enforcement C) |
| memory-reviewer | Context & Memory Management | C+ (design B+, implementation D) |

---

## Top 10 Findings (Prioritized)

### Critical (Fix Immediately)

| # | Finding | Area | Effort |
|---|---------|------|--------|
| 1 | **init.sh guard bug** — `[ ! -d ".claude/memory" ]` prevents L2/L3/debug KB creation. All memory tiers except L1 sessions are non-functional | Memory | Low (1-line fix) |
| 2 | **No persistent workflow state** — phase tracking (PLAN/SPEC/BUILD) exists only in conversation context, lost on compaction/session boundary | Workflow | Medium |
| 3 | **skill-router.sh lines 82-83** — log message still uses OLD paths `skills/generic/` and `skills/summer/` instead of flat `skills/` (actual routing logic works fine, but log misleads agents) | Hooks | Low |
| 4 | **status.md lines 111-148** — scans `skills/generic/`, `skills/summer/`, `skills/meta/` directories that don't exist in flat structure → reports 0 skills | Commands | Low |
| 5 | **Cross-agent context sharing doesn't exist** — each agent starts from scratch, no plan/spec artifact persistence | Memory | High |

> **Note**: Skills are correctly flat (`skills/{name}/SKILL.md`) since v3.0. The path bugs are remnants in 3 specific files, not a structural issue.

### High (Fix Soon)

| # | Finding | Area | Effort |
|---|---------|------|--------|
| 6 | **Phase gates are advisory-only** — no deterministic enforcement; LLM can bypass plan/spec requirements under user pressure | Workflow | Medium |
| 7 | **quality-gate.sh misses easy wins** — doesn't check `.block()`, `@Autowired`, `SELECT *`, git commit in Bash | Workflow | Low |
| 8 | **Implementer model contradiction** — `build.md` says sonnet, `implementer.md` says opus (cost impact) | Components | Low |
| 9 | **Session index race condition** — no file locking, 21 duplicate entries from concurrent writes | Memory | Medium |
| 10 | **pre-compact.sh shell injection** — filenames break Python heredoc triple-quotes | Memory | Low |

---

## Strengths (What's Done Well)

1. **Bootstrap-as-enforcement-engine** — injecting the skill system via SessionStart hook is brilliant architecture
2. **3-tier lazy loading** — SKILL.md (~800 tokens) → references (deep) → always-on rules (~500 tokens each) is excellent token budget design
3. **Profile-based hook gating** — minimal/standard/strict profiles via `run-with-flags.sh` is great UX
4. **Spec-writer agent** — 7-step process with 5 task type templates, scenario-to-test mapping, and task decomposition is the best-designed component (5/5)
5. **Reviewer conditional checklists** — 7 checklists activated by file content analysis, not blanket checks
6. **Subagent-per-task isolation** in BUILD — prevents context pollution between implementation tasks
7. **SDD workflow design** — PLAN→SPEC→BUILD→VERIFY→REVIEW with explicit handoff sections and feedback loops
8. **Skills quality** — 18 skills averaging 4.5/5, with consistent frontmatter and appropriate sizing
9. **Rules quality** — 9 rules averaging 4.7/5, concise and actionable
10. **Summer Framework hard gate** — prevents loading irrelevant summer skills

---

## Weaknesses (What Needs Work)

### Architecture
- 3 files still have old nested path references (skill-router.sh:82-83 log, status.md:111-148 scan, test-runner.md:157 instruction) — actual skill structure is correctly flat
- Package name inconsistency (`devco-agent-skills` vs `@devco/agent-skills`)
- Dual session directories (`.claude/sessions/` and `.claude/memory/sessions/`)

### Components
- Content duplication across tiers (~2,000-3,000 tokens wasted)
- Continuous-learning feature is incomplete (references non-existent `observe.sh`)
- Several agents missing `maxTurns` limit
- redis-patterns skill has `.subscribe()` anti-pattern in its own code example
- coding-standards method length threshold inconsistency

### Workflow
- All compliance enforcement is prompt-based (probabilistic, ~80% reliable)
- No persistent plan/spec artifacts — vulnerable to compaction
- `/db-migrate` bypasses SDD despite schema changes requiring specs
- No mid-workflow revision/restart mechanism
- `/verify` and `/review` have no prerequisite checks

### Memory
- L2 knowledge and L3 graph tiers are non-functional (init.sh bug)
- Session index corrupted with duplicates (no file locking)
- Compact advisor undercounts (only Edit|Write|MultiEdit, not Read|Bash|Grep)
- Token budget config.json is fictional (never enforced, numbers wrong)
- Debug knowledge base never created

---

## Best Practices for Plugin Development

Based on this review, here are best practices for improving the plugin:

### 1. Deterministic > Advisory
Enforce rules through hooks (deterministic) whenever possible, not just prompt instructions (advisory). Use `quality-gate.sh` and PreToolUse hooks for real-time enforcement.

### 2. Persist Critical State
Write workflow phase, plan/spec content, and task progress to files. Conversation context is ephemeral — compaction, session boundaries, and token limits can destroy it.

### 3. Token Budget Discipline
- Monitor Tier 1 (always-on) budget with CI checks
- Keep SKILL.md files ≤4KB (~800 tokens)
- Keep reference files ≤15KB
- Don't duplicate content across tiers — rules remind, skills detail

### 4. Test What You Ship
- Validate path references in CI (the v3.0 restructure broke 3+ files)
- Test hook scripts with actual plugin installation
- Verify init.sh creates ALL expected directories/files

### 5. One Source of Truth
- Spec templates: keep in spec-writer agent only, not duplicated in command
- Memory section: extract to shared reference, not duplicated in 4 agents
- Workflow phases: bootstrap is the authority, rules are reminders

### 6. Fail Loud, Not Silent
- Scripts use `2>/dev/null || true` everywhere — great for robustness, bad for debugging
- Add logging to a debug log file so failures are discoverable
- Session save transcript counters always show 0 — a silent failure

### 7. Lock Shared Resources
- Session index.json needs file locking (flock) for concurrent access
- Memory files need locking if multiple agents write
- Consider atomic writes (write to temp, rename)

### 8. Separate Design from Implementation
- graph-conventions.md documents a knowledge graph that doesn't exist
- config.json token budgets are never enforced
- continuous-learning references hooks that don't exist
- Mark aspirational features as "planned" or implement them

---

## Improvement Roadmap

### Phase 1: Bug Fixes (1-2 days)
1. Fix init.sh guard logic (1-line fix)
2. Fix skill-router.sh paths for v3.0 flat structure
3. Fix /status command paths
4. Fix test-runner.md old path reference
5. Fix pre-compact.sh shell injection
6. Fix redis-patterns `.subscribe()` anti-pattern
7. Resolve implementer model contradiction
8. Add `maxTurns` to all agents

### Phase 2: Workflow Hardening (3-5 days)
1. Add `.claude/workflow-state.json` — persist phase, approvals, task progress
2. Extend quality-gate.sh with `.block()`, `@Autowired`, `SELECT *`, git commit checks
3. Add prerequisite checks to `/db-migrate`, `/verify`, `/review`
4. Persist plan/spec artifacts to `.claude/plans/`, `.claude/specs/`
5. Add Bash PreToolUse hook for git commit/push detection

### Phase 3: Memory & Context (3-5 days)
1. Fix session index deduplication + add file locking
2. Unify dual session directories
3. Wire L2 knowledge writes (decisions.json, active-work.json)
4. Create cross-agent context handoff mechanism
5. Fix compact-advisor tool counting
6. Evaluate native auto-memory integration

### Phase 4: Optimization (ongoing)
1. Deduplicate content (spec templates, memory preamble, workflow descriptions)
2. Compress large reference files (spring-webflux 32KB, kafka 20KB)
3. Add CI checks for token budgets
4. Complete or remove continuous-learning feature
5. Add debug knowledge base read integration

---

## Files Referenced

Full detailed reviews are in this directory:

| File | Content |
|------|---------|
| `01-architecture-review.md` | Directory structure, plugin config, 3-tier loading, token costs |
| `02-components-review.md` | All 8 agents, 18 skills, 12 commands, 9 rules, 7 hooks scored |
| `03-workflow-review.md` | SDD phases, gating, handoffs, compliance, error handling |
| `04-memory-review.md` | 3-tier memory, session lifecycle, context injection, cross-agent sharing |
