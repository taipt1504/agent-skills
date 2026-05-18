# Migration Guide — v1 (5-phase rigid) → v2 (5-layer adaptive)

> **Important narrative correction:** the audit confirmed the prior plugin already ran a 5-phase pipeline (`PLAN → SPEC → BUILD → VERIFY → REVIEW`), not the 7-phase narrative used in some legacy docs. This migration describes the move from 5-phase rigid to 5-layer adaptive + triage.

---

## Why v2

Three structural gaps in v1:

1. **No triage router.** Every task ran the same gates regardless of scope. A typo fix and a database migration both passed through PLAN + SPEC.
2. **No reasoning gates before Plan.** Alignment and brainstorming happened inside the planner agent at best, not as discrete gates with auditable artifacts.
3. **No pre-flight discovery.** v1 owned 24 skills and 10 rules, but nothing forced enumeration. Skills accumulated and went underused.
4. **No subagent isolation.** The implementer agent executed monolithically. Context polluted across tasks.

v2 closes these gaps while preserving v1's strengths (spec gate, hook-enforced quality, two-layer rules, Spring focus).

---

## What changed

| Change | Impact | Migration effort |
|---|---|---|
| Triage routing (3 lanes) | Medium — workflow paths differ per lane | None for users, set per task |
| Pre-flight discovery (1% rule) | Medium — every gate now has an artifact | Auto — hook produces |
| Align gate (grill-me) | Low — auto-fires for high-stakes / vague requests | None |
| Brainstorm gate (tournament) | Medium — mandatory for high-stakes | None — auto-fires after Align |
| Subagent dispatch in Build | High — execution model changed | Backward-compat: single-agent path still works |
| Two-stage review | Low — output format changes | Backward-compat: `/dc-review` orchestrates |
| Auto-evolution loop | Low — pure addition | Opt-in via `/meta evolve` |
| `CONTEXT.md` auto-load | Low — addition | Run `/dc-setup` to scaffold |
| Rules split (`common/` + `java/`) | Medium — paths changed | One-time rename in user customizations |
| `spring-patterns` split → webflux + mvc | Low — file rename in agent configs | Automatic via project profile |
| `implementer` → `slice-executor` | Low — rename | Old agent still functional 30 days |
| `reviewer` → split into spec-compliance + code-quality | Low — backward-compat | Old agent deprecated, redirects |
| `skills-loaded.json` gate removed | High — multi-agent dispatch unblocked | None — was the source of dispatch failures |

---

## Side-by-side workflow

### Trivial task — typo fix in error message

**v1 (5-phase rigid):**
```
BOOT → PLAN → SPEC → BUILD → VERIFY → REVIEW
```
Every gate ran. ~5 minutes time-to-first-edit.

**v2 (lane-aware):**
```
Boot → Pre-flight 0 (light) → Triage [trivial]
     → Execute (direct, no subagent) → Verify (compile+format) → Review S2 → Commit
```
Time-to-first-edit: 30 seconds.

### Standard task — add pagination to user list

**v1:**
```
BOOT → PLAN → SPEC → BUILD → VERIFY → REVIEW
```

**v2:**
```
Boot → Pre-flight 0 → Triage [standard]
     → Align (if vague) → Pre-flight 1 → Brainstorm (if multi-path)
     → Pre-flight 2 → Plan → Pre-flight 3 → Spec
     → Pre-flight 4 → Execute (subagent per slice)
     → Pre-flight 5 → Review (Stage 1 spec compliance → Stage 2 quality) → Learn
```
Roughly equivalent gate count, but each gate produces an auditable artifact.

### High-stakes task — migrate MySQL → PostgreSQL

**v1:**
```
BOOT → PLAN → SPEC → BUILD → VERIFY → REVIEW
```
Same gates as a one-line fix. No ADR. No alternative-considered trail.

**v2:**
```
Boot → Pre-flight 0 → Triage [high-stakes]
     → Align (mandatory) → Pre-flight 1
     → Brainstorm (mandatory, ≥3 options) → ADR auto-generated
     → Architect review (optional but auto for high-stakes)
     → Pre-flight 2 → Plan
     → Pre-flight 3 → Spec (extra rigorous)
     → Pre-flight 4 → Execute (subagent + worktree per slice)
     → Verify (full + security CVE scan)
     → Pre-flight 5 → Review (Stage 1 + Stage 2 with security deep-dive)
     → Learn
```
ADR captured. Alternatives logged. Subagent isolation prevents context pollution across slices.

---

## Backward compatibility

### Legacy mode

Users can preserve v1 behavior with environment variable:

```bash
export AGENT_SKILLS_PROFILE=legacy
```

Behavior:
- All tasks routed to standard lane (no triage)
- Brainstorm + Align do NOT auto-fire (manual only)
- Single-agent execution (no subagent dispatch)
- Single-stage review

Deprecated 30 days after v2.0 release (date in CHANGELOG).

**Pre-flight stays mandatory regardless of `AGENT_SKILLS_PROFILE`.** It is foundational; intermittent enforcement does not build habit. Trivial-lane light format covers cost concerns.

### Gradual adoption

Opt-in feature flags:

```bash
export AGENT_SKILLS_FEATURES="triage"             # just triage
export AGENT_SKILLS_FEATURES="triage,align"       # triage + align
export AGENT_SKILLS_FEATURES="full"               # all v2 features (default in v2.0)
```

### Per-task overrides

```bash
/plan --no-align        # skip Align this task (warns for high-stakes)
/plan --no-brainstorm   # skip Brainstorm this task (warns for high-stakes)
/build --no-subagent    # single-agent execution
/dc-review --no-stage1  # skip spec-compliance check
```

Use sparingly. Each skip = potential miss.

### Slash-command aliases

Old slash commands continue to work:

| v1 command | v2 command | Status |
|---|---|---|
| `/plan` | `/plan` | unchanged (semantics extended — reads brainstorm artifact for high-stakes) |
| `/spec` | `/spec` | unchanged |
| `/build` | `/build` | extended — dispatches subagent per slice |
| `/verify` | `/verify` | extended — security scan in high-stakes |
| `/review` | `/dc-review` | renamed (alias `/review` works 30 days) |

---

## Step-by-step migration

### Step 1 — Update plugin (Week 0)

```bash
/plugin marketplace update taipt1504/agent-skills
/plugin install devco-agent-skills@v4.0
```

Or manually pull latest main + re-install hooks.

### Step 2 — Run `/dc-setup` (Week 0)

```bash
cd <your-project>
/dc-setup
```

This:
- Backs up old `.claude/` to `.claude/v1-backup/` (recoverable)
- Creates `.claude/memory/` tier structure
- Scaffolds `CONTEXT.md` from template if not present
- Creates `docs/adr/` with `0000-template.md`
- Migrates state JSONs to `.claude/memory/state/`
- Updates `.gitignore`

### Step 3 — Initialize CONTEXT.md (Week 1)

```bash
/align
> "Help me build vocabulary for this project"
```

The Align skill grills you for domain terms, architecture decisions, naming conventions, tech stack specifics. Output saved to `CONTEXT.md`. Commit to git — vocabulary compounds across sessions.

### Step 4 — Migrate existing ADRs (Week 1)

If you have ADRs in non-standard location:

```bash
mkdir -p docs/adr
mv <old-adr-dir>/*.md docs/adr/
```

Renumber if needed. v2 auto-discovers ADRs in `docs/adr/`.

### Step 5 — Test with 3 sample tasks (Week 1)

```bash
# Trivial
/triage "fix typo in error message"
# Expected: trivial lane, skip Align/Brainstorm/Plan/Spec

# Standard
/triage "add pagination to user list endpoint"
# Expected: standard lane, full reasoning gates

# High-stakes
/triage "migrate from MySQL to PostgreSQL"
# Expected: high-stakes lane, mandatory brainstorm, ADR auto-trigger
```

Verify each produces expected pre-flight artifacts in `.claude/memory/preflight/`.

### Step 6 — Train team (Week 2)

- 10-minute video walkthrough (link in CHANGELOG)
- Lane reference card (`examples/lane-reference.md`)
- Migration FAQ (below)

Talking points:
- Trivial tasks are faster now
- High-stakes tasks have more rigor (this is good)
- ADRs tracked automatically
- Subagent dispatch invisible most of time

### Step 7 — Deprecate legacy mode (Day 30)

After 30 days:
- Remove `AGENT_SKILLS_PROFILE=legacy` support
- Force v2 behavior
- Notice in CHANGELOG

---

## FAQ

### Q: I'm mid-feature in v1 workflow. Will it break?

**A:** No. v2 detects ongoing work and doesn't re-trigger gates. Complete the in-flight feature with v1 flow. Next feature uses v2.

### Q: Does subagent dispatch increase token cost?

**A:** Yes but managed:
- Subagents use Sonnet (cheap), orchestrator uses Opus (smart)
- Context isolation actually reduces total tokens (no pollution across slices)
- Net: ~10-20% cost increase, ~30% quality increase per internal benchmarks

### Q: Can I disable Brainstorm?

**A:**
- Standard lane: yes, agent skips if solution obvious
- High-stakes lane: no, mandatory (protection against first-solution bias)
- User can force standard lane: `/triage standard` (warns if high-stakes criteria met)

### Q: Does CONTEXT.md conflict with existing project docs?

**A:** CONTEXT.md is project vocabulary, distinct from:
- README — project overview
- ARCHITECTURE.md — system design
- CONVENTIONS.md — style guide

Coexist fine. CONTEXT.md focus: ubiquitous language.

### Q: Two-stage review slower?

**A:** Stage 1 (spec compliance) is binary check, ~30s. Stage 2 (quality) only runs if Stage 1 passes. Net: comparable speed, better signal-to-noise.

### Q: Auto-evolution will spam skills?

**A:** Hard thresholds prevent spam:
- Confidence ≥ 0.8
- ≥ 3 occurrences
- ≥ 2 sessions
- ≥ 2 projects
- User confirmation required

Expected: 1-2 new skills per month per active user.

### Q: Worktree complicates git workflow?

**A:** Auto-managed by `git-worktree` skill. User sees no difference except cleaner main branch. Trivial cleanup on done.

### Q: I use Cursor / OpenCode / Codex. Supported?

**A:** v4.0 focuses on Claude Code. Cross-harness roadmapped v4.1+ (Cursor first).

### Q: My team uses CLAUDE.md customizations. Migrate?

**A:** Your CLAUDE.md is preserved. v4.0 adds a "MANDATORY Pre-flight Discovery Protocol" section to the plugin's CLAUDE.md. If you have project-level CLAUDE.md, it overrides. No automatic merge — review the new section and incorporate manually.

### Q: My agent customizations reference `implementer` / `reviewer`. Migrate?

**A:** Both renamed/split:
- `implementer` → `slice-executor`
- `reviewer` → `spec-compliance-reviewer` + `code-quality-reviewer`

Old agent files retained with `deprecated: true` frontmatter for 30 days. Update your references to new names before the deprecation window expires.

---

## Rollback plan

If v2 causes critical issue:

```bash
# Rollback to v1
/plugin install devco-agent-skills@v3.3.1

# Restore .claude/v1-backup/ to .claude/
rm -rf .claude/skills .claude/agents .claude/commands
cp -r .claude/v1-backup/* .claude/
```

Report issues: https://github.com/taipt1504/agent-skills/issues

---

## Release schedule

| Version | Date | Content |
|---|---|---|
| v4.0.0-beta | Week 5 (target) | Beta, internal testing |
| v4.0.0-rc1 | Week 6 | Release candidate, early adopters |
| v4.0.0 | Week 7 | Stable release |
| v4.0.1 | Week 8 | Bug fixes from real-world usage |
| v4.1.0 | Month 3 | Cross-harness (Cursor first) |
| v4.2.0 | Month 6 | AgentShield integration, multi-language |

---

## Acknowledgments

v2 design inspired by:
- **obra/superpowers** — subagent dispatch, two-stage review, brainstorming
- **mattpocock/skills** — CONTEXT.md, grill-me, ADR integration
- **affaan-m/everything-claude-code** — continuous learning, memory, security
- Original **taipt1504/agent-skills** — spec gate, hook enforcement, two-layer rules

Full design references in `.claude/docs/devco-improve-docs/` (vendored at refactor time).
