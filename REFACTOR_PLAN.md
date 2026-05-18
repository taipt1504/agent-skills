# REFACTOR_PLAN.md — agent-skills → v2 (5-layer adaptive + Pre-flight Discovery)

> **Audience:** the junior engineer who will execute this refactor.
> **Source of truth:** `.claude/docs/devco-improve-docs/` (docs 00-07 + `agent-skills-improvement/05-skill-specifications/`).
> **Working assumption:** doc 02 workflow design is fixed, doc 07 "1% rule" is foundational, doc 04 phase ordering must be respected.
> **Style:** plan prose is natural English. Caveman-compressed examples appear only inside code blocks that demonstrate post-refactor agent-facing artifacts.

---

## 0. Prerequisites

Run these before touching code. They are cheap, and several later steps assume the result.

### 0.1 Verify the design docs are readable

```bash
ls .claude/docs/devco-improve-docs/agent-skills-improvement/
# expect: 00-README.md … 07-skill-rule-discovery-protocol.md
ls .claude/docs/devco-improve-docs/agent-skills-improvement/05-skill-specifications/
# expect: triage.md align.md brainstorm.md preflight.md remaining-skills.md
```

If anything is missing, stop and surface the gap — every section below depends on these.

### 0.2 Install the caveman ecosystem

The marketplace `caveman` is mounted at `~/.claude/plugins/marketplaces/caveman/`, but the skills are NOT installed at `~/.claude/skills/`. Install (or symlink) the family before Phase 1 starts:

```bash
# Option A — plugin install (recommended)
/plugin install caveman@caveman

# Option B — manual symlink (fallback if the marketplace plugin install does not expose skills correctly)
for s in caveman caveman-commit caveman-help caveman-review caveman-stats cavecrew compress; do
  ln -sf ~/.claude/plugins/marketplaces/caveman/skills/$s ~/.claude/skills/$s
done
```

After install, verify:

```bash
ls ~/.claude/skills/ | grep -E '^(caveman|cavecrew|compress)'
# expect: caveman, caveman-commit, caveman-help, caveman-review, caveman-stats, cavecrew, compress
```

**Naming note for the brief's table:** the marketplace publishes `compress/`, not `caveman-compress/`. Every reference below uses `compress` (or "the compress skill") to match the actual filesystem entry. The brief's reference to `agent-development` does not exist anywhere in the marketplace or `~/.claude/skills/` — it is dropped from the toolchain. See section 7.2.

### 0.3 Baseline the current token usage

Capture the "before" measurement so section 7.1 can report real reduction percentages, not guesses:

```bash
# Bytes per category — proxy for tokens at ~4 chars/token
wc -c skills/*/SKILL.md agents/*.md rules/*.md commands/*.md CLAUDE.md \
  | tee .claude/baseline-bytes.txt

# If the compress skill exposes a stats helper, snapshot it too:
caveman-stats snapshot --tag pre-refactor 2>/dev/null || true
```

### 0.4 Confirm git state is clean

The refactor will touch ~80 files. Start from a clean tree on a feature branch so reverts stay simple:

```bash
git status              # expect: clean
git checkout -b refactor/v2-workflow
```

---

## 1. Executive Summary

The `devco-agent-skills` plugin today is a 5-phase rigid pipeline (`PLAN → SPEC → BUILD → VERIFY → REVIEW`) with hook-enforced quality, a flat ten-file rule set, ten agents, and 24 skills. The audit confirms strengths the design docs already credit it for — the `/spec` gate, hook quality enforcement, two-layer rule intent — but also four structural gaps the v2 design must close:

1. **No triage router.** Every task takes the same lane regardless of scope.
2. **No reasoning gates before Plan.** Alignment and brainstorming happen inside the planner agent at best, not as discrete gates with auditable artifacts.
3. **No pre-flight discovery.** The plugin owns 24 skills and ten rules, but nothing forces the agent to enumerate them per gate — the "1% rule" from doc 07 is absent.
4. **No subagent isolation in Build.** The implementer agent executes monolithically; context pollutes across slices.

The plan below is faithful to doc 02 (workflow), doc 04 (5-phase, 5-week roadmap), and doc 07 (1% discovery rule). It touches roughly 80 artifacts.

### Items audited

| Category | Count | Source |
|---|---|---|
| Agents | 10 | `agents/*.md` |
| Skills | 24 SKILL.md present, 1 partial scaffold (`skills/triage/`) | `skills/*/SKILL.md` |
| Rules | 10 (flat) | `rules/*.md` |
| Commands | 14 | `commands/*.md` |
| Hooks | 18 shell scripts + 1 `hooks/hooks.json` | `scripts/hooks/*.sh` |
| Templates | 1 (`PROJECT_GUIDELINES_TEMPLATE.md`) | `templates/` |
| Memory | No `memory/` dir; state lives in `.claude/*.json` | runtime |

### Decisions at a glance

| Decision | Agents | Skills | Rules | Commands | Hooks |
|---|---|---|---|---|---|
| KEEP | 0 | 0 | 0 | 0 | 0 |
| KEEP + caveman-compress | 5 | 15 | 6 | 5 | 12 |
| REFACTOR (incl. rename) | 4 | 8 | 3 | 8 | 3 |
| SPLIT | 1 | 1 (spring-patterns per §6.4) | 1 | 1 | 0 |
| MERGE | 0 | 1 | 0 | 0 | 0 |
| REMOVE | 0 | 0 | 0 | 0 | 0 |
| ADD_NEW | 1 (optional architect) | 6 | 1 | 5 | 3 |
| COMPLETE_SCAFFOLD | 0 | 1 | 0 | 0 | 0 |

(Detail in sections 2 and 3.)

### Token reduction projection

Measured baseline (bytes ÷ 4 ≈ tokens) and per-category targets:

| Bucket | Bytes today | Tokens today (≈) | Tokens target | Reduction |
|---|---|---|---|---|
| Skills (`SKILL.md` only) | 165 KB | 41 k | 16 k | 60 % |
| Agents | 78 KB | 19 k | 8 k | 60 % |
| Rules | 48 KB | 12 k | 5 k | 60 % |
| Commands | 98 KB | 25 k | 10 k | 60 % |
| CLAUDE.md (hybrid) | 4.5 KB | 1.1 k | 0.6 k | 45 % |
| **Bundle total** | **393 KB** | **~98 k** | **~40 k** | **~59 %** |

The brief's "~50 k current → ~22 k target" estimate was low; the measured baseline is ~98 k. Percentage targets stay; absolute totals updated honestly.

### Top 5 critical changes

> **Runtime contract.** The plan implements the two reference diagrams supplied 2026-05-15 (linear 6-pre-flight flow + branching trivial bypass + learning feedback edge). §3.0 maps every diagram node to a deliverable; no node is unmapped.

1. **Pre-flight Discovery Protocol (doc 07) is foundation.** Build it in Phase 1 — every later gate consumes its artifact. Six variants per §3.0.1.
2. **Triage router fully replaces the binary "≤5 lines vs full workflow" check.** A skill scaffold already exists at `skills/triage/references/` but has no `SKILL.md` — complete it, do not start from scratch.
3. **Reasoning gates (`align`, `brainstorm`) are NEW.** Both are mandatory for high-stakes lane, conditional otherwise.
4. **`reviewer.md` splits into two agents** (`spec-compliance-reviewer`, `code-quality-reviewer`) per doc 02 Layer 4.
5. **Rules split into `rules/common/` + `rules/java/`** to match docs 04 and 07. This is mechanical (`git mv` + path updates in hooks, agents, CLAUDE.md). Alternative: keep flat (see Open Question 6.1).

### Effort estimate

Doc 04 calls for 5 weeks part-time (≈2-3 weeks full-time). Audit confirms that fits if Phase 1 starts with pre-flight and triage — skipping pre-flight would invalidate Phases 2–5.

### Risks identified

- **Compression that loses technical accuracy.** Caveman tooling is selective; do not blanket-apply.
- **Rule path break.** Splitting `rules/` will break hook references and `requiredSkills` lookups in agents. Mitigation: single PR per category.
- **Pre-flight overhead.** Every gate gains 30–60 s and 500–1000 tokens. Trivial lane uses the light version (doc 07 §"Light version").
- **Caveman install path drift.** Marketplace plugin install may not expose skills as user expects (see §0.2 Option B).
- **24 SKILL.md `applicability` blocks are net-new YAML per file** (doc 07 §"Integration với existing skills"). Likely ~16 hours hand-written; auto-generation is risky because each skill needs domain judgment.

---

## 2. Audit Findings

Each row lists the artifact, current size (bytes → ~tokens), decision, the caveman tool that applies, and effort in hours. Effort is for the per-item refactor only; cross-cutting work (rule-path migration, hook rewiring) is in section 3.

> **Note on ordering.** The tables below do not include a per-row `Dependencies` column. Ordering between items is captured holistically in §5 (Phase-by-phase Schedule) and at the priority level in §4. When two rows touch the same file or the same hook, the lower-numbered priority runs first; within a priority, the §5 task list defines order.

### 2.1 Agents inventory

| # | Name | Path | Bytes | ~Tok | Target | Red. | Decision | Rationale | Caveman tool | Pri | Hrs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 | `_shared-protocol` | `agents/_shared-protocol.md` | 2.8 K | 0.7 k | 0.4 k | 45 % | KEEP + compress | Reused by all agents via `protocol:` frontmatter; small, high leverage | compress | P1 | 0.5 |
| A2 | `build-fixer` | `agents/build-fixer.md` | 8.1 K | 2.0 k | 0.8 k | 60 % | KEEP + compress | No overlap with new gates; system prompt is verbose | compress, prompt-master | P2 | 2 |
| A3 | `database-reviewer` | `agents/database-reviewer.md` | 3.2 K | 0.8 k | 0.3 k | 60 % | KEEP + compress | DB-specific reviewer, complements Stage 2 quality review | compress | P2 | 1 |
| A4 | `implementer` → renamed to `slice-executor` | `agents/implementer.md` → `agents/slice-executor.md` | 4.4 K | 1.1 k | 0.6 k | 45 % | REFACTOR + RENAME | doc 04 Phase 3 calls for `agents/slice-executor.md`; implementer is the closest fit. `git mv` + adapt system prompt to receive plan slice + spec + pre-flight artifact. Keep a 30-day deprecation stub at the old path that redirects (then delete). | compress, prompt-master, skill-creator | P1 | 3 |
| A5 | `pentest` | `agents/pentest.md` | 5.4 K | 1.4 k | 0.6 k | 55 % | KEEP + compress | Security review specialist; orthogonal to two-stage code review | compress | P2 | 1.5 |
| A6 | `planner` | `agents/planner.md` | 15.5 K | 3.9 k | 1.6 k | 60 % | REFACTOR | Add dependency-graph output, consume Brainstorm artifact, emit slices not phases. Largest agent — biggest compression win. | compress, prompt-master | P1 | 4 |
| A7 | `refactorer` | `agents/refactorer.md` | 4.7 K | 1.2 k | 0.5 k | 55 % | KEEP + compress | Orthogonal to workflow; on-demand maintenance | compress | P2 | 1 |
| A8 | `reviewer` | `agents/reviewer.md` | 8.5 K | 2.1 k | — | — | **SPLIT** → A8a `spec-compliance-reviewer.md` + A8b `code-quality-reviewer.md` | doc 02 §"Layer 4 — Two-Stage Review" + doc 05 `remaining-skills.md` spec | compress, prompt-master, skill-creator | P1 | 5 |
| A9 | `spec-writer` | `agents/spec-writer.md` | 18.4 K | 4.6 k | 1.8 k | 60 % | REFACTOR | Largest agent overall; consumes Align + Brainstorm artifacts; remove the parts that re-do alignment | compress, prompt-master | P1 | 4 |
| A10 | `test-runner` | `agents/test-runner.md` | 5.4 K | 1.4 k | 0.6 k | 55 % | KEEP + compress | E2E specialist; complements TDD inside `slice-executor` | compress | P2 | 1 |
| **NEW** | `architect` (optional) | `agents/architect.md` | — | 0 | 0.6 k | new | **ADD_NEW** — high-stakes lane review per doc 02 §"Layer 1 — Triage Router" → high-stakes path | skill-creator, prompt-master | P3 | 3 |

> `slice-executor` is not listed as a separate ADD_NEW row — see row A4, which renames `implementer.md` to `slice-executor.md`. Same file, new name, refactored prompt.

Total agents: 10 today → 11 after refactor (10 + reviewer split + optional architect − implementer renamed = 11, or 12 if architect added).

### 2.2 Skills inventory

All 24 existing skills lack the `applicability` block required by doc 07. None are SKIP-justifiable without it. The migration script in doc 07 only flags missing blocks; content must be hand-authored.

| # | Name | Path | Bytes | ~Tok | Target | Red. | Decision | Rationale | Caveman tool | Pri | Hrs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| S1 | `api-design` | `skills/api-design/SKILL.md` | 4.6 K | 1.1 k | 0.5 k | 55 % | REFACTOR (add applicability) + compress | Doc 07 §"Integration với existing skills" — applicability block mandatory | compress, skill-creator | P1 | 1 |
| S2 | `architecture` | `skills/architecture/SKILL.md` | 10.4 K | 2.6 k | 1.0 k | 60 % | REFACTOR + compress | Big body; surface hexagonal-arch guidance | compress, skill-creator | P1 | 2 |
| S3 | `bootstrap` | `skills/bootstrap/SKILL.md` | 11.9 K | 3.0 k | 1.2 k | 60 % | REFACTOR + compress | Auto-loaded every session — biggest per-session win. Reflect 5-layer workflow + pre-flight mandate. | compress, prompt-master | P0 | 3 |
| S4 | `coding-standards` | `skills/coding-standards/SKILL.md` | 4.4 K | 1.1 k | 0.4 k | 60 % | REFACTOR + compress | Mark `always: true` in applicability | compress, skill-creator | P1 | 1 |
| S5 | `continuous-learning` | `skills/continuous-learning/SKILL.md` | <1 K | 0.1 k | 0.5 k | grow | REFACTOR (extend) | Add auto-evolution rules from doc 02 Layer 5 / doc 05 `remaining-skills.md` §"evolve". Net growth, not reduction — that is acceptable per brief's "no fluff drift" rule | skill-creator, prompt-master | P3 | 3 |
| S6 | `database-patterns` | `skills/database-patterns/SKILL.md` | 4.7 K | 1.2 k | 0.5 k | 58 % | REFACTOR + compress | Add applicability targeting `@Entity`, `@Repository`, JPA keywords | compress, skill-creator | P1 | 1 |
| S7 | `deployment-patterns` | `skills/deployment-patterns/SKILL.md` | 4.5 K | 1.1 k | 0.5 k | 55 % | KEEP + compress + applicability | Add applicability, no body changes | compress, skill-creator | P2 | 1 |
| S8 | `grpc-patterns` | `skills/grpc-patterns/SKILL.md` | 8.8 K | 2.2 k | 0.9 k | 60 % | KEEP + compress + applicability | Applicability `triggers.code_patterns: ["@GrpcService"]`. Doc 07 example uses this skill specifically for SKIP justification | compress, skill-creator | P2 | 1.5 |
| S9 | `messaging-patterns` | `skills/messaging-patterns/SKILL.md` | 4.2 K | 1.0 k | 0.4 k | 60 % | REFACTOR (split conceptually) + compress + applicability | Currently mixes Kafka + RabbitMQ guidance. Decide: leave mixed, or extract a `kafka-patterns` skill to match doc 07's gate-mapping examples. Open Question 6.3. | compress, skill-creator | P2 | 2 |
| S10 | `observability-patterns` | `skills/observability-patterns/SKILL.md` | 5.4 K | 1.4 k | 0.5 k | 60 % | KEEP + compress + applicability | Production code default `APPLY` | compress, skill-creator | P1 | 1 |
| S11 | `pentest` | `skills/pentest/SKILL.md` | 3.7 K | 0.9 k | 0.4 k | 55 % | KEEP + compress + applicability | Used by pentest agent only | compress, skill-creator | P2 | 1 |
| S12 | `redis-patterns` | `skills/redis-patterns/SKILL.md` | 4.7 K | 1.2 k | 0.5 k | 58 % | KEEP + compress + applicability | Triggers on `RedisTemplate`, `Lettuce` | compress, skill-creator | P2 | 1 |
| S13 | `spring-patterns` → SPLIT | `skills/spring-patterns/SKILL.md` → `skills/spring-webflux-patterns/SKILL.md` + `skills/spring-mvc-patterns/SKILL.md` | 4.9 K | 1.2 k | 0.5 k + 0.5 k | n/a (split) | **SPLIT** + compress + applicability | Decided 6.4. Split into reactive vs servlet stack per doc 07 §"Execute gate". Each gets its own applicability block keyed on `Mono`/`Flux` vs `HttpServletRequest`. Agents that depend on `spring-patterns` via `requiredSkills.conditional.spring` must be updated to pick the matching skill per project profile. | compress, skill-creator | P1 | 3 |
| S14 | `spring-security` | `skills/spring-security/SKILL.md` | 4.5 K | 1.1 k | 0.4 k | 60 % | KEEP + compress + applicability | Triggers on `SecurityFilterChain`, `@PreAuthorize` | compress, skill-creator | P2 | 1 |
| S15 | `summer-core` | `skills/summer-core/SKILL.md` | 10.7 K | 2.7 k | 1.1 k | 60 % | KEEP + compress + applicability | Summer framework domain | compress, skill-creator | P2 | 1.5 |
| S16 | `summer-data` | `skills/summer-data/SKILL.md` | 17.0 K | 4.2 k | 1.7 k | 60 % | KEEP + compress + applicability | Largest skill; high compression value | compress, skill-creator | P2 | 2.5 |
| S17 | `summer-file` | `skills/summer-file/SKILL.md` | 7.1 K | 1.8 k | 0.7 k | 60 % | KEEP + compress + applicability | — | compress, skill-creator | P2 | 1 |
| S18 | `summer-kafka` | `skills/summer-kafka/SKILL.md` | 9.8 K | 2.5 k | 1.0 k | 60 % | KEEP + compress + applicability | — | compress, skill-creator | P2 | 1.5 |
| S19 | `summer-payment-sdk` | `skills/summer-payment-sdk/SKILL.md` | 10.9 K | 2.7 k | 1.1 k | 60 % | KEEP + compress + applicability | — | compress, skill-creator | P2 | 2 |
| S20 | `summer-ratelimit` | `skills/summer-ratelimit/SKILL.md` | 5.6 K | 1.4 k | 0.6 k | 55 % | KEEP + compress + applicability | — | compress, skill-creator | P2 | 1 |
| S21 | `summer-rest` | `skills/summer-rest/SKILL.md` | 7.8 K | 1.9 k | 0.8 k | 60 % | KEEP + compress + applicability | — | compress, skill-creator | P2 | 1.5 |
| S22 | `summer-security` | `skills/summer-security/SKILL.md` | 18.8 K | 4.7 k | 1.9 k | 60 % | KEEP + compress + applicability | Largest skill overall — high ROI on compression | compress, skill-creator | P2 | 2.5 |
| S23 | `summer-test` | `skills/summer-test/SKILL.md` | 5.7 K | 1.4 k | 0.6 k | 55 % | KEEP + compress + applicability | — | compress, skill-creator | P2 | 1 |
| S24 | `testing-workflow` | `skills/testing-workflow/SKILL.md` | 4.5 K | 1.1 k | 0.4 k | 60 % | REFACTOR + compress + applicability | Rename conceptually to `tdd-workflow` per doc 07 §"Execute gate"; or keep name, only update content | compress, skill-creator | P1 | 1.5 |
| S25 | `triage` (partial) | `skills/triage/references/` | 0 (no SKILL.md) | 0 | 0.6 k | new | **COMPLETE_SCAFFOLD** | Existing scaffold has only `references/`. Use doc 05 §`triage.md` verbatim as starting point for SKILL.md, then caveman-compress description | skill-creator, compress | P0 | 2 |
| **NEW** | `preflight` | `skills/preflight/SKILL.md` | — | 0 | 0.6 k | new | **ADD_NEW** (foundational) | doc 07 + doc 05 §`preflight.md` | skill-creator, compress | P0 | 3 |
| **NEW** | `align` | `skills/align/SKILL.md` | — | 0 | 0.6 k | new | **ADD_NEW** | doc 05 §`align.md` | skill-creator, compress | P1 | 3 |
| **NEW** | `brainstorm` | `skills/brainstorm/SKILL.md` | — | 0 | 0.7 k | new | **ADD_NEW** | doc 03 + doc 05 §`brainstorm.md` | skill-creator, compress | P1 | 4 |
| **NEW** | `subagent-dispatch` | `skills/subagent-dispatch/SKILL.md` | — | 0 | 0.5 k | new | **ADD_NEW** | doc 04 Phase 3 + doc 05 `remaining-skills.md` | skill-creator, compress | P2 | 2 |
| **NEW** | `git-worktree` | `skills/git-worktree/SKILL.md` | — | 0 | 0.4 k | new | **ADD_NEW** | doc 04 Phase 3 + doc 05 `remaining-skills.md` | skill-creator, compress | P2 | 2 |
| **NEW** | `improve-architecture` | `skills/improve-architecture/SKILL.md` | — | 0 | 0.6 k | new | **ADD_NEW** | doc 04 Phase 4 + doc 05 `remaining-skills.md` | skill-creator, compress | P3 | 3 |
| **NEW (from split)** | `spring-webflux-patterns` | `skills/spring-webflux-patterns/SKILL.md` | — | 0 | 0.5 k | new | **ADD_NEW** (output of S13 SPLIT) | Doc 07 §"Execute gate" lists separately from MVC. Triggers on `Mono`, `Flux`, `WebClient`, `RouterFunction`, WebFlux configs | compress, skill-creator | P1 | (covered by S13) |
| **NEW (from split)** | `spring-mvc-patterns` | `skills/spring-mvc-patterns/SKILL.md` | — | 0 | 0.5 k | new | **ADD_NEW** (output of S13 SPLIT) | Triggers on `@RestController` (servlet stack), `HttpServletRequest`, `RestTemplate`, blocking patterns | compress, skill-creator | P1 | (covered by S13) |

**Conceptual MERGE candidate (optional):** `messaging-patterns` → split into `kafka-patterns` + `rabbitmq-patterns` (Open Question 6.3). Default decision: leave merged, add applicability with both keyword sets, re-evaluate after first 5 pre-flight artifacts to see if SKIP confusion arises.

### 2.3 Rules inventory (currently flat)

| # | Name | Path today | Target path (if split) | Bytes | ~Tok | Target | Red. | Decision | Caveman tool | Pri | Hrs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | `api-design` | `rules/api-design.md` | `rules/java/api-design.md` | 4.8 K | 1.2 k | 0.5 k | 60 % | REFACTOR + compress + move | compress | P1 | 1 |
| R2 | `architecture-patterns` | `rules/architecture-patterns.md` | `rules/common/patterns.md` (rename per doc 07 §"Brainstorm gate → rules/common/patterns.md") | 7.1 K | 1.8 k | 0.7 k | 60 % | REFACTOR + compress + rename | compress | P1 | 1.5 |
| R3 | `coding-style` | `rules/coding-style.md` | split: `rules/common/coding-style.md` + `rules/java/coding-style.md` | 5.2 K | 1.3 k | 0.5 k + 0.4 k | 65 % | **SPLIT** + compress | doc 07 references both files separately. Split the language-agnostic from Java-specific guidance | compress, skill-creator | P1 | 2 |
| R4 | `development-workflow` | `rules/development-workflow.md` | `rules/common/development-workflow.md` | 2.0 K | 0.5 k | 0.2 k | 60 % | REFACTOR + compress + move | compress | P1 | 0.5 |
| R5 | `git-workflow` | `rules/git-workflow.md` | `rules/common/git-workflow.md` | 3.0 K | 0.8 k | 0.3 k | 60 % | KEEP + compress + move | compress | P2 | 0.5 |
| R6 | `observability` | `rules/observability.md` | `rules/java/observability.md` | 5.0 K | 1.3 k | 0.5 k | 60 % | KEEP + compress + move | compress | P2 | 1 |
| R7 | `security` | `rules/security.md` | split: `rules/common/security.md` + `rules/java/security.md` | 6.0 K | 1.5 k | 0.6 k + 0.4 k | 65 % | **SPLIT** + compress | doc 07 references both files | compress | P1 | 2 |
| R8 | `skill-enforcement` | `rules/skill-enforcement.md` | `rules/common/skill-enforcement.md` | 3.2 K | 0.8 k | 0.3 k | 60 % | REFACTOR + compress + move | Update to reference 1% rule + applicability blocks | compress | P0 | 1 |
| R9 | `spec-driven` | `rules/spec-driven.md` | `rules/common/spec-driven.md` | 1.6 K | 0.4 k | 0.2 k | 50 % | REFACTOR + compress + move | Add lane-based mandate (trivial optional, standard if behavior change, high-stakes always) per doc 05 `remaining-skills.md` §"Rules updates summary" | compress | P0 | 0.5 |
| R10 | `testing` | `rules/testing.md` | `rules/java/testing.md` | 5.4 K | 1.4 k | 0.5 k | 60 % | KEEP + compress + move | compress | P2 | 1 |
| **NEW** | `lanes` | — | `rules/common/lanes.md` | — | 0 | 0.3 k | new | **ADD_NEW** | doc 05 `remaining-skills.md` §"Rules updates summary" defines exact content | skill-creator, compress | P0 | 0.5 |
| **NEW** | `reactive` | — | `rules/java/reactive.md` | — | 0 | 0.3 k | new | **ADD_NEW** | doc 07 §"Execute gate" — referenced repeatedly as `no .block()` rule. Currently this guidance is implicit in CLAUDE.md "Hard Blocks #1"; extract into a discoverable rule file | skill-creator, compress | P0 | 1 |

> If the alternative "keep flat" decision wins (Open Question 6.1), the move column collapses but compression and content updates still apply. Renames (`architecture-patterns` → `patterns`, splits for `coding-style` and `security`) still happen.

### 2.4 Commands inventory

| # | Name | Path | Bytes | ~Tok | Target | Red. | Decision | Rationale | Caveman tool | Pri | Hrs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| C1 | `build-fix` | `commands/build-fix.md` | 5.4 K | 1.3 k | 0.5 k | 60 % | KEEP + compress | Triggered by verify/fix loop hook | compress | P2 | 1 |
| C2 | `build` | `commands/build.md` | 11.7 K | 2.9 k | 1.2 k | 60 % | REFACTOR + compress | Wire to subagent-dispatch skill; honor triage lane | compress, prompt-master | P2 | 3 |
| C3 | `db-migrate` | `commands/db-migrate.md` | 4.4 K | 1.1 k | 0.4 k | 60 % | KEEP + compress | Domain command; tag as high-stakes auto-trigger | compress | P3 | 1 |
| C4 | `dc-review` | `commands/dc-review.md` | 7.0 K | 1.7 k | 0.7 k | 60 % | **SPLIT** → `dc-review.md` orchestrates two stages, plus invokes Stage 1 then Stage 2 agents | doc 02 Layer 4 | compress, prompt-master | P1 | 3 |
| C5 | `dc-setup` | `commands/dc-setup.md` | 4.8 K | 1.2 k | 0.5 k | 60 % | REFACTOR + compress | Add CONTEXT.md scaffolding step (doc 06 §Step 3) | compress | P1 | 1.5 |
| C6 | `dc-status` | `commands/dc-status.md` | 9.7 K | 2.4 k | 1.0 k | 60 % | REFACTOR + compress | Output lane, pre-flight artifact paths, CONTEXT.md state | compress | P2 | 2 |
| C7 | `e2e` | `commands/e2e.md` | 7.5 K | 1.9 k | 0.7 k | 60 % | KEEP + compress | Wired to test-runner agent | compress | P2 | 1.5 |
| C8 | `meta` | `commands/meta.md` | 8.6 K | 2.1 k | 0.9 k | 60 % | REFACTOR + compress | Already implements `/meta learn`, `/meta evolve`, `/meta prune`, `/meta create-skill`. Re-scope to consume doc 04 Phase 4 auto-promotion thresholds, align subcommand vocabulary with `skills/continuous-learning`. Do not delete — salvageable content. | compress, prompt-master | P3 | 2.5 |
| C9 | `pentest-scan` | `commands/pentest-scan.md` | 3.0 K | 0.7 k | 0.3 k | 60 % | KEEP + compress | Used by pentest agent | compress | P3 | 0.5 |
| C10 | `plan` | `commands/plan.md` | 8.1 K | 2.0 k | 0.8 k | 60 % | REFACTOR + compress | Read align + brainstorm artifacts, refuse for high-stakes without brainstorm | compress, prompt-master | P1 | 2.5 |
| C11 | `refactor` | `commands/refactor.md` | 3.2 K | 0.8 k | 0.3 k | 60 % | KEEP + compress | Used by refactorer agent | compress | P2 | 0.5 |
| C12 | `spec` | `commands/spec.md` | 11.0 K | 2.7 k | 1.1 k | 60 % | REFACTOR + compress | Consume Brainstorm output; enforce 1:1 scenario→test mapping per doc 02 §2d | compress, prompt-master | P1 | 3 |
| C13 | `threat-model` | `commands/threat-model.md` | 1.0 K | 0.2 k | 0.1 k | 50 % | KEEP + compress | Small; complementary to pentest | compress | P3 | 0.3 |
| C14 | `verify` | `commands/verify.md` | 7.6 K | 1.9 k | 0.8 k | 60 % | REFACTOR + compress | Add security scan stage per doc 04 Phase 3 | compress | P2 | 2 |
| **NEW** | `triage` | `commands/triage.md` | — | 0 | 0.3 k | new | **ADD_NEW** | doc 04 Phase 1 deliverable; manual lane override | skill-creator, compress | P0 | 0.5 |
| **NEW** | `align` | `commands/align.md` | — | 0 | 0.3 k | new | **ADD_NEW** | doc 04 Phase 2 | skill-creator, compress | P1 | 0.5 |
| **NEW** | `brainstorm` | `commands/brainstorm.md` | — | 0 | 0.3 k | new | **ADD_NEW** | doc 04 Phase 2 | skill-creator, compress | P1 | 0.5 |
| ~~NEW~~ | ~~`improve-architecture`~~ | (collapsed into `/meta improve-architecture` per §3.6.3) | — | — | — | — | **DEFERRED to /meta umbrella** | Avoid slash-command sprawl | (covered by C8) | P3 | 0 |
| ~~NEW~~ | ~~`adr`~~ | (collapsed into `/meta adr` per §3.6.3) | — | — | — | — | **DEFERRED to /meta umbrella** | Auto-generation lives inside `/meta evolve` workflow already | (covered by C8) | P2 | 0 |

### 2.5 Hooks inventory

| # | Name | Path | Bytes | Decision | Rationale | Pri | Hrs |
|---|---|---|---|---|---|---|---|
| H1 | `build-checkpoint.sh` | `scripts/hooks/build-checkpoint.sh` | 2.6 K | KEEP + compress comments | Already small; compress only the inline echoes that are agent-facing | P3 | 0.5 |
| H2 | `compact-advisor.sh` | `scripts/hooks/compact-advisor.sh` | 5.7 K | KEEP + compress | Useful as-is; tighten stderr messages | P3 | 0.5 |
| H3 | `git-guard.sh` | `scripts/hooks/git-guard.sh` | 1.3 K | KEEP | Small | P3 | 0 |
| H4 | `memory-gate.sh` | `scripts/hooks/memory-gate.sh` | 1.3 K | REFACTOR | Extend to write Tier 1 session memory under `.claude/memory/preflight/` (mirrors doc 07) | P1 | 1.5 |
| H5 | `observability-trace.sh` | `scripts/hooks/observability-trace.sh` | 4.6 K | KEEP + compress | Compress agent-facing messages | P3 | 0.5 |
| H6 | `post-compact.sh` | `scripts/hooks/post-compact.sh` | 2.3 K | KEEP | — | P3 | 0 |
| H7 | `pre-compact.sh` | `scripts/hooks/pre-compact.sh` | 3.8 K | KEEP + compress | — | P3 | 0.5 |
| H8 | `quality-gate.sh` | `scripts/hooks/quality-gate.sh` | 7.3 K | KEEP + compress | Largest hook; agent-facing stderr is verbose | P2 | 1 |
| H9 | `run-with-flags.sh` | `scripts/hooks/run-with-flags.sh` | 5.5 K | KEEP | Mechanical | P3 | 0 |
| H10 | `session-init.sh` | `scripts/hooks/session-init.sh` | 24.9 K | REFACTOR | Load `CONTEXT.md`, recent ADRs, smart skill loading by keyword (doc 02 §Layer 0), invoke triage. Biggest single-file change. | P0 | 6 |
| H11 | `session-save.sh` | `scripts/hooks/session-save.sh` | 8.5 K | REFACTOR | Tier 3 instinct extraction + evolution-check hook coupling (doc 02 Layer 5) | P3 | 2 |
| H12 | `skill-router.sh` | `scripts/hooks/skill-router.sh` | 8.8 K | REFACTOR | Consume applicability blocks (doc 07); load by trigger match instead of static list | P1 | 4 |
| H13 | `subagent-init.sh` | `scripts/hooks/subagent-init.sh` | 9.2 K | REFACTOR | Inject pre-flight artifact + plan slice + spec into subagent context (doc 07 §"Subagent context") | P1 | 3 |
| H14 | `team-spawn-evaluator.sh` | `scripts/hooks/team-spawn-evaluator.sh` | 6.7 K | KEEP + compress | — | P3 | 0.5 |
| H15 | `verify-fix-loop.sh` | `scripts/hooks/verify-fix-loop.sh` | 5.9 K | KEEP + compress | — | P3 | 0.5 |
| H16 | `workflow-gate.sh` | `scripts/hooks/workflow-gate.sh` | 4.0 K | REFACTOR | Detect lane, allow trivial bypass of plan/spec gates, block high-stakes without brainstorm artifact | P0 | 2 |
| H17 | `workflow-phase-lock.sh` | `scripts/hooks/workflow-phase-lock.sh` | 5.7 K | REFACTOR | Update phase list (replace `PLAN→SPEC→BUILD→VERIFY→REVIEW` with 5-layer flow) | P0 | 2 |
| H18 | `workflow-tracker.sh` | `scripts/hooks/workflow-tracker.sh` | 5.1 K | REFACTOR | Track lane + gate artifacts | P0 | 2 |
| **NEW** | `preflight-gate.sh` | `scripts/hooks/preflight-gate.sh` | — | **ADD_NEW** | doc 07 §"Hook implementation" — PreToolUse on workflow commands, forces artifact creation | P0 | 3 |
| **NEW** | `preflight-discovery.sh` | `scripts/hooks/preflight-discovery.sh` | — | **ADD_NEW** | doc 07 §"Discovery Protocol — Step 1" — enumerate filesystem skills + rules with descriptions | P0 | 2 |
| **NEW** | `auto-adr.sh` | `scripts/hooks/auto-adr.sh` | — | **ADD_NEW** | doc 04 Phase 4 + doc 05 `remaining-skills.md` §"auto-adr" | P3 | 1.5 |
| **NEW** | `evolution-check.sh` | `scripts/hooks/evolution-check.sh` | — | **ADD_NEW** | doc 04 Phase 4 (auto-promotion of instincts) | P3 | 2 |
| **UPDATE** | `hooks/hooks.json` | `hooks/hooks.json` | 4.3 K | REFACTOR | Wire new hooks; reorder PreToolUse to insert preflight-gate before workflow-gate | P0 | 1 |

### 2.5.5 Session-artifact audit (field evidence from ewallet workspace)

Real-world evidence from `/Users/taiphan/Documents/Projects/ewallet-workspace/payment-gateway-design-docs/.claude/sessions/`:

| Artifact | Size | Populated? | Source hook (suspected) | Decision |
|---|---|---|---|---|
| `.last-retention-check` | 0 B | marker only | unknown | REMOVE write — generate at runtime if needed, never commit |
| `compaction-log.txt` | 13 KB | only timestamps | `pre-compact.sh` | REMOVE — no signal beyond `compaction_count` already in JSON |
| `execution-trace.jsonl` | 0 B | never written | `observability-trace.sh` | INSPECT hook — if it never emits, REMOVE the hook entirely (H5 in §2.5 changes from KEEP+compress to REMOVE) |
| `pre-compact-unknown.json` | 201 B | trivial; `session: "unknown"` | `pre-compact.sh` | REMOVE write — naming is wrong (`unknown` means hook failed to detect session) |
| `session-metrics.json` | 0 B | never written | `session-save.sh` or `observability-trace.sh` | REMOVE — feature never wired up |
| `session-summary.json` | 219 B | all fields empty (`decisions:[]`, `skillsUsed:{}`, `filesModified:[]`, `errorsFixed:[]`, `toolCallCount:0`) | `session-save.sh` | KEEP file but **fix the writer** — data is not flowing in. Either populate during BUILD/REVIEW or remove the empty-shell write |
| `skills-loaded.json` | 461 B | populated correctly | `skill-router.sh` / `subagent-init.sh` | **REMOVE blocking semantics** — file currently used as a gate (subagent dispatch blocks if mismatch). Switch to superpowers-style "announce only" — agent announces loaded skills in chat, no file persistence required. File becomes optional debug artifact. |

The pattern is consistent: hooks write skeleton files that are never populated because the data plumbing doesn't reach them, or write log noise that nothing consumes. Aligns with doc 02 §"Memory Architecture" Tier 1 design — Tier 1 should be *ephemeral and meaningful*, not "empty JSON shells".

Action plan for Phase 1 (P0 add-ons):

1. Audit `scripts/hooks/observability-trace.sh` line by line. If it never emits to `execution-trace.jsonl`, demote from KEEP+compress to REMOVE.
2. Strip the compaction-log writer from `scripts/hooks/pre-compact.sh`. Keep only the JSON state (`pre-compact.json`) if used by `post-compact.sh`; rename it away from `*-unknown` once session detection is fixed.
3. Refactor `scripts/hooks/session-save.sh` to populate the summary properly, or remove the write. Empty-shell writes mislead users into thinking learning is happening when it is not.
4. **Critical for multi-agent unblock:** modify `scripts/hooks/subagent-init.sh` and `scripts/hooks/skill-router.sh` to STOP using `skills-loaded.json` as a hard gate. Replace with announcement-only contract (subagent emits one line: `Skills loaded: {list}`). This unblocks the multi-agent dispatch pattern Phase 3 requires.

### 2.5.6 Ewallet rule imports (merge plan)

Inventory of `payment-gateway-design-docs/.claude/rules/`. Plugin already owns 10 rule files; ewallet has 19. Mapping:

| Ewallet rule | Bytes | Plugin counterpart | Decision | Target path post-split |
|---|---|---|---|---|
| `api-design.md` | 13.4 K | `rules/api-design.md` (4.8 K) | **MERGE** — port richer ewallet content, retain plugin's framing | `rules/java/api-design.md` |
| `api-docs-datatype-sync.md` | 3.7 K | (none) | **IMPORT as sub-section** | append to `rules/java/api-design.md` §"OpenAPI sync" |
| `architecture-patterns.md` | 3.9 K | `rules/architecture-patterns.md` (7.1 K) | **MERGE** — plugin richer, pull ewallet specifics into examples | `rules/common/patterns.md` (renamed) |
| `caller-aware-audit-pattern.md` | 5.6 K | (none) | **IMPORT** — Summer `CallerAware` is Summer-specific | **`rules/summer/audit.md`** (final) — moved from rules/java/ during v4.0 polish; conditional load when project profile = summer:true |
| `cluster-event-standards.md` | 21.9 K | (none) | **IMPORT (split)** — Summer outbox+Kafka rules into Summer rule; generic Kafka patterns already in `skills/messaging-patterns` | **`rules/summer/messaging.md`** (final) — moved during v4.0 polish; conditional load |
| `coding-style.md` | 4.7 K | `rules/coding-style.md` (5.2 K) | **MERGE** | split per §2.3 |
| `design-primary-rules.md` | 5.2 K | (none) | **SKIP — project-specific** (payment-gateway SRS hierarchy). Optionally template-ize into `templates/PROJECT_PRIMARY_RULES_TEMPLATE.md` if other projects need similar | (template only) |
| `development-workflow.md` | 1.1 K | `rules/development-workflow.md` (2.0 K) | **MERGE** | `rules/common/development-workflow.md` |
| `git-workflow.md` | 1.7 K | `rules/git-workflow.md` (3.0 K) | **MERGE** | `rules/common/git-workflow.md` |
| `handler-api-standards.md` | 14.6 K | (none) | **IMPORT (split)** — generic REST handler patterns into api-design; Summer SpringBus / `BaseController.execute` into `skills/summer-rest` | extend `rules/java/api-design.md` + `skills/summer-rest` |
| `import-not-fqn.md` | 1.4 K | (none, but in CLAUDE.md "Always #5") | **IMPORT** — promote from CLAUDE.md hard-block hint to dedicated rule section | merge into `rules/java/coding-style.md` §"Imports" |
| `migration-immutability.md` | 1.9 K | (none) | **IMPORT** — Flyway-specific, very actionable | `rules/java/migration.md` (new) |
| `no-jsonnode-response.md` | 2.3 K | (none) | **IMPORT** | merge into `rules/java/api-design.md` §"DTO typing" |
| `observability.md` | 3.0 K | `rules/observability.md` (5.0 K) | **MERGE** | `rules/java/observability.md` |
| `runtime-verification.md` | 1.7 K | (none) | **IMPORT** — defines "implementation complete" gate; complements VERIFY phase | merge into `rules/common/development-workflow.md` §"Definition of done" |
| `security.md` | 2.6 K | `rules/security.md` (6.0 K) | **MERGE** | split per §2.3 |
| `skill-enforcement.md` | 2.9 K | `rules/skill-enforcement.md` (3.2 K) | **MERGE** — likely near-identical; verify, then dedupe. After Phase 1, pre-flight protocol supersedes most of this rule's intent — consider deprecating in Phase 2 once the preflight skill is live | `rules/common/skill-enforcement.md` (then deprecate by Phase 2) |
| `spec-driven.md` | 1.3 K | `rules/spec-driven.md` (1.6 K) | **MERGE** | `rules/common/spec-driven.md` |
| `testing.md` | 2.1 K | `rules/testing.md` (5.4 K) | **MERGE** | `rules/java/testing.md` |

Effort: ~10 h for all merges + imports + 2 new rule files (`audit.md`, `migration.md`, `messaging.md`).

Caveman pass after each merge (rules are agent-facing, ON per §7.2). Apply to merged body, not to the diff-discussion in commit messages.

### 2.6 Memory system state

There is no `memory/` directory. State files exist at the workspace root under `.claude/`:

- `.claude/workflow-state.json`
- `.claude/build-checkpoint.json`
- `.claude/verify-fix-state.json`
- `.claude/session-metrics.json`

Target three-tier alignment per doc 02 §"Memory Architecture":

| Tier | Target location | Today | Gap |
|---|---|---|---|
| Tier 1 — Session (ephemeral) | `.claude/memory/session-*.md`, `.claude/memory/preflight/`, `.claude/memory/align-artifacts/`, `.claude/memory/brainstorm-artifacts/` | scattered `.claude/*.json` | Create `.claude/memory/` subtree; migrate `session-save.sh` to write here. Git-ignore the whole tree. |
| Tier 2 — Project (git-tracked) | `CONTEXT.md` at project root, `docs/adr/*.md` | absent | Create `templates/CONTEXT_TEMPLATE.md` (doc 04 Phase 1), seed `docs/adr/.gitkeep`, instruct `dc-setup` to scaffold both. |
| Tier 3 — Global (cross-repo) | `~/.claude/instincts.jsonl`, `~/.claude/skills/auto-evolved/` | claude-mem integration exists but no auto-evolved skill path | Update `continuous-learning` SKILL and `evolution-check.sh` to write to these paths. |

Apply caveman-compress to all Tier 1 artifact templates and to `CONTEXT_TEMPLATE.md`'s prompt section (agent reads CONTEXT.md vocabulary). Examples and human guidance inside templates stay natural.

### 2.7 Caveman ecosystem availability check

| Skill (in brief) | Marketplace name | Path | Available? |
|---|---|---|---|
| `caveman` | `caveman/` | `~/.claude/plugins/marketplaces/caveman/skills/caveman` | ✅ via marketplace |
| `caveman-compress` | `compress/` ⚠️ | `~/.claude/plugins/marketplaces/caveman/skills/compress` | ✅ — name mismatch with brief |
| `caveman-commit` | `caveman-commit/` | ✅ | ✅ |
| `caveman-review` | `caveman-review/` | ✅ | ✅ |
| `caveman-stats` | `caveman-stats/` | ✅ | ✅ |
| `cavecrew` | `cavecrew/` | ✅ | ✅ |
| `skill-creator` | n/a | `~/.claude/skills/skill-creator` | ✅ (installed globally) |
| `prompt-master` | n/a | `~/.claude/skills/prompt-master` | ✅ (installed globally) |
| `agent-development` | — | not found | ⚠️ does not exist; dropped |

Action: §0.2 installs / symlinks the marketplace family; section 7.2 records the `compress` vs `caveman-compress` naming so later docs do not chase a phantom name.

---

## 3. Refactor Plan by Category

For brevity each subsection shows 1–2 worked examples of before / after / diff. The same pattern applies to every row in section 2.

### 3.0 Workflow Diagram Compliance Map

The two reference diagrams (user-supplied 2026-05-15) define the runtime contract. Every deliverable below must implement one or more nodes. Diagram 1 is the linear happy path with six pre-flights (0 = initial + triage prep, 1–5 = per-gate prep). Diagram 2 is the branching form with trivial-lane bypass, per-gate pre-flight blocks, and the learning → Skills_DB feedback edge.

#### 3.0.1 Six pre-flight variants

Doc 07 mandates one pre-flight per gate. Diagram 1 numbers them 0–5; the plan implements each as a separate gate-flavored artifact written to `.claude/memory/preflight/<variant>-<ts>.md`.

| Pre-flight | Diagram node | Scope (what to enumerate) | Triggered by | Deliverable in plan |
|---|---|---|---|---|
| **0 — Initial / triage prep** | PREFLIGHT0 + ENUM0 + JUSTIFY0 | ALL skills (filesystem walk), ALL rules, active instincts. Bias to over-enumerate. | `session-init.sh` after Boot completes, before Triage runs | `skills/preflight/SKILL.md` + `scripts/hooks/preflight-discovery.sh` (§2.5) + `scripts/hooks/session-init.sh` refactor (§2.5 H10) |
| **1 — Brainstorm prep** | PREFLIGHT1 + ENUM1 | Brainstorm skill itself + evaluation-dimension references + domain skills surfaced by Align output | `preflight-gate.sh` matched on `/brainstorm` invocation | `scripts/hooks/preflight-gate.sh` (§2.5 NEW) + `commands/brainstorm.md` (§2.4 NEW) |
| **2 — Plan prep** | PREFLIGHT2 + ENUM2 | Planning skills, architecture rule (`rules/common/patterns.md`), agents rule, lanes rule | `preflight-gate.sh` matched on `/plan` invocation | `commands/plan.md` REFACTOR §3.4 + the new hook |
| **3 — Spec prep** | PREFLIGHT3 + ENUM3 | API design rule (if API), testing rule, blackbox patterns | `preflight-gate.sh` matched on `/spec` invocation | `commands/spec.md` REFACTOR §2.4 |
| **4 — Execute prep** | PREFLIGHT4 + ENUM4 | TDD workflow, language patterns (java-patterns), framework patterns (`spring-webflux-patterns` OR `spring-mvc-patterns` per §6.4), domain patterns (database-patterns / kafka via messaging-patterns / redis-patterns), coding-style + security + observability rules, `rules/java/reactive.md` | `preflight-gate.sh` matched on `/build` or subagent dispatch | `commands/build.md` REFACTOR (§2.4 C2) + `scripts/hooks/subagent-init.sh` refactor (§2.5 H13) |
| **5 — Review prep** | PREFLIGHT5 + ENUM5 | security-review skill, verification skill, testing rule, observability rule | `preflight-gate.sh` matched on `/dc-review` invocation | `commands/dc-review.md` SPLIT (§2.4 C4) — both Stage 1 and Stage 2 consume the same pre-flight 5 artifact |

#### 3.0.2 Align gate pre-flight clarification

Diagram 1 shows `TRIAGE → ALIGN → PREFLIGHT1 → BRAINSTORM` — Align has no dedicated pre-flight box. Diagram 2 shows Align "with skill/rule check for align phase". Reconciliation: Align inherits pre-flight 0's output (initial enumeration is sufficient; alignment is requirements-gathering, not solution-space exploration). A lightweight `preflight-align.md` is written only if Align surfaces a new domain term that introduces a skill not yet enumerated in pre-flight 0 — otherwise Align references pre-flight 0 directly.

Deliverable: `skills/align/SKILL.md` §"Process" must include "consume `.claude/memory/preflight/initial-*.md` as enumeration source; emit `preflight-align.md` only on new-skill discovery".

#### 3.0.3 Trivial-lane bypass (diagram 2)

`TRIAGE → Trivial → Trivial path → Execute (trivial) → Commit`. Bypasses Align, Brainstorm, Plan, Spec, Two-stage review (Stage 2 only per doc 02 §"Khi nào skip gates?").

Pre-flight still mandatory — uses the light format from doc 07 §"Light version for trivial lane" (3–5 lines, not full artifact).

Deliverable: `scripts/hooks/workflow-gate.sh` REFACTOR (§2.5 H16) must short-circuit gate enforcement when lane=trivial. `skills/preflight/SKILL.md` must document the light format. `rules/common/lanes.md` (§2.3 NEW) must list skipped gates per lane.

#### 3.0.4 Learning loop → Skills_DB feedback (diagram 2 dotted edge)

LEARN node proposes new skills/rules based on gaps surfaced during the session. The dotted edge to Skills_DB indicates write-back; the dotted edge from PREFLIGHT reads from the same DB so newly proposed skills surface in the next session's pre-flight 0.

Deliverable:

- `skills/continuous-learning/SKILL.md` REFACTOR (§2.2 S5) adds an `auto-evolution` section per doc 02 §Layer 5: instinct → skill auto-promotion when confidence ≥ 0.8, ≥ 3 occurrences, ≥ 2 sessions.
- `scripts/hooks/evolution-check.sh` (§2.5 NEW) writes promotion candidates to `.claude/memory/promotion-candidates.md` at session end.
- `commands/meta.md` (subcommand `/meta evolve`) provides the human gate for accepting promotion → writes new `SKILL.md` to `~/.claude/skills/auto-evolved/` (Tier 3 per §2.6).
- `scripts/hooks/preflight-discovery.sh` enumerates `~/.claude/skills/auto-evolved/` alongside the plugin's own `skills/` directory, closing the feedback loop.

#### 3.0.5 Subagent receives skill/rule list (diagram 2)

`EXECUTE: subagent receives skill/rule list`. This is the dispatch contract from main agent (`slice-executor` orchestrator) to per-slice subagent.

Deliverable: `scripts/hooks/subagent-init.sh` REFACTOR (§2.5 H13) injects three artifacts into subagent context:

1. Plan slice description (from `commands/plan.md` output)
2. Spec for the slice (from `commands/spec.md` output)
3. Pre-flight 4 artifact (`.claude/memory/preflight/execute-*.md`)

Doc 07 §"Subagent context" defines the exact template. `agents/slice-executor.md` (renamed from `implementer.md` per §3.1 Example 3) must begin its system prompt with "Read pre-flight artifact; verify applicable items match this slice's needs; if new items emerge, append to artifact."

#### 3.0.6 Node → deliverable matrix (full diagram coverage)

| Diagram node | Plan deliverable | Status |
|---|---|---|
| REQ | n/a — system input | n/a |
| BOOT | `scripts/hooks/session-init.sh` REFACTOR (§2.5 H10) | covered |
| PREFLIGHT0 + ENUM0 + JUSTIFY0 | §3.0.1 row 0 | covered |
| TRIAGE | `skills/triage/SKILL.md` COMPLETE_SCAFFOLD (§2.2 S25) + `commands/triage.md` NEW + `scripts/hooks/workflow-gate.sh` lane detect (§2.5 H16) | covered |
| Trivial lane branch | `rules/common/lanes.md` NEW (§2.3) + workflow-gate.sh short-circuit | covered |
| ALIGN | `skills/align/SKILL.md` NEW (§2.2) + `commands/align.md` NEW (§2.4) | covered |
| PREFLIGHT1 (brainstorm-prep) | §3.0.1 row 1 | covered |
| BRAINSTORM | `skills/brainstorm/SKILL.md` NEW (§2.2) + `commands/brainstorm.md` NEW (§2.4) | covered |
| PREFLIGHT2 (plan-prep) | §3.0.1 row 2 | covered |
| PLAN | `commands/plan.md` REFACTOR (§3.4) + `agents/planner.md` REFACTOR (§2.1 A6) | covered |
| PREFLIGHT3 (spec-prep) | §3.0.1 row 3 | covered |
| SPEC | `commands/spec.md` REFACTOR (§2.4 C12) + `agents/spec-writer.md` REFACTOR (§2.1 A9) | covered |
| PREFLIGHT4 (execute-prep) | §3.0.1 row 4 | covered |
| EXECUTE (loop, subagent dispatch) | `commands/build.md` REFACTOR (§2.4 C2) + `agents/slice-executor.md` (§2.1 A4 rename) + `skills/subagent-dispatch/SKILL.md` NEW (§2.2) + `skills/git-worktree/SKILL.md` NEW + `scripts/hooks/subagent-init.sh` REFACTOR (§2.5 H13) | covered |
| PREFLIGHT5 (review-prep) | §3.0.1 row 5 | covered |
| REVIEW (two-stage) | `agents/spec-compliance-reviewer.md` + `agents/code-quality-reviewer.md` (§2.1 A8 SPLIT) + `commands/dc-review.md` REFACTOR (§2.4 C4) | covered |
| LEARN | §3.0.4 | covered |
| LEARN → Skills_DB dotted edge | §3.0.4 — `evolution-check.sh` write, `preflight-discovery.sh` read | covered |
| COMMIT | `rules/common/git-workflow.md` (§2.3 R5 after move) — user-only commit per CLAUDE.md hard block #9 | covered |

**No diagram node is unmapped.** If a Phase 1–5 deliverable changes scope, re-check this matrix.

### 3.1 Agents

#### Example 1 — `agents/_shared-protocol.md` (KEEP + compress)

This file is injected into every agent via `subagent-init.sh`. Compression is high leverage.

**Before (excerpt, natural prose, ~120 tokens shown):**

```markdown
## First Action (MANDATORY — before any work)

1. **Announce loaded skills** to user: "**Skills loaded**: {list your requiredSkills.always}"
2. If conditional skills activated based on project profile: "**Conditional**: {list}"
3. Read `.claude/devco-config.json` for runtime config (mode, autoVerify, autoReview, team settings)
4. Read `.claude/project-profile.json` for project context (springType, dependencies, Java version)
```

**After (caveman-compressed agent-facing, ~55 tokens):**

```markdown
## First Action (MANDATORY)

1. Announce skills: `Skills loaded: {requiredSkills.always}`
2. Conditional skills active? Announce: `Conditional: {list}`
3. Read `.claude/devco-config.json` (runtime config)
4. Read `.claude/project-profile.json` (project context)
```

**Diff explanation:** dropped pleasantries ("before any work"), articles, redundant inline definitions. Technical substance — JSON paths, list of file names, order of operations — preserved exactly. Total file goes from ~700 tokens to ~400 tokens.

**Tools:** `compress` (description + body), `prompt-master` is unnecessary for this file.

**Effort:** 0.5 h.

#### Example 2 — `agents/reviewer.md` SPLIT into two agents (P1)

The current `reviewer.md` does both spec compliance and code-quality review. Doc 02 §Layer 4 mandates two distinct stages with a "stage 1 fail → stage 2 not run" gate.

**Action:**

1. Copy doc 05 `remaining-skills.md` §"spec-compliance-reviewer agent" and §"code-quality-reviewer agent" into `agents/spec-compliance-reviewer.md` and `agents/code-quality-reviewer.md`.
2. Apply caveman-compress to the system prompts before committing — both files should sit at ~600 tokens each.
3. Update `commands/dc-review.md` to orchestrate: run Stage 1 → if pass, run Stage 2 → emit verdict.
4. Mark the old `agents/reviewer.md` deprecated (do not delete during 30-day deprecation window per doc 04 §"Backward compat"). Add a one-line frontmatter note: `deprecated: true; replacement: spec-compliance-reviewer + code-quality-reviewer`.

**Tools:** `skill-creator` for scaffold, `prompt-master` for system-prompt optimization, `compress` for description fields.

**Effort:** 5 h (3 h for the two new files, 1 h for command rewire, 1 h for deprecation wrapper).

#### Example 3 — `agents/implementer.md` → repurpose as `slice-executor` (P1)

Doc 04 Phase 3 calls for `agents/slice-executor.md`. The current `implementer.md` is the closest behavioral fit (TDD + Spring + coverage focus). Recommendation: copy, rename, adapt the system prompt to receive `{plan-slice, spec, pre-flight-artifact, CONTEXT.md vocabulary}` instead of the full task, then deprecate `implementer.md` for 30 days.

**Tools:** `skill-creator` (frontmatter scaffold), `compress` (description), `prompt-master` (system prompt rewrite — this is a substantive prompt change, not just compression).

**Effort:** 3 h.

### 3.2 Skills

#### Example 1 — `skills/jpa-patterns` ⇒ used as canonical model for the `applicability` block

`jpa-patterns` does not currently exist as a separate skill; database-patterns covers it. Doc 07 §"Integration với existing skills" uses jpa-patterns as the template. Replicate that block for every existing skill.

**Generic applicability template (caveman-compressed, agent-facing):**

```yaml
applicability:
  always: false
  triggers:
    files_match: ["**/*Repository.java", "**/*Entity.java"]
    code_patterns: ["@Entity", "@Repository", "JpaRepository"]
    task_keywords: ["entity", "JPA", "Hibernate", "repository", "persistence"]
  related_rules:
    - rules/java/observability.md
    - rules/java/security.md
relevance_assessment: |
  HIGH 80%+: new @Entity/@Repository/JPA query
  MEDIUM 40-79%: touches repo layer, no new query
  LOW 1-39%: tangential
  ZERO: project has no JPA
```

**Diff explanation:** each existing SKILL.md gains 10–15 lines of YAML. Body content is then run through `compress` to recoup the added tokens. Net per-skill change: roughly neutral on token count; net workflow change: pre-flight can now produce the doc 07 artifact.

#### Example 2 — `skills/bootstrap/SKILL.md` REFACTOR (P0, highest leverage)

This file auto-loads every session. The frontmatter description is what every agent reads first.

**Before (excerpt, ~70 tokens):**

```yaml
description: >
  Core enforcement engine for devco-agent-skills plugin. Auto-loaded at session start via
  SessionStart hook. Teaches skill discovery, 5-phase workflow (PLAN→SPEC→BUILD→VERIFY→REVIEW),
  project detection, and mandatory skill usage. Foundation skill — all others depend on it.
  Do NOT manually load; injected by the harness.
```

**After (caveman-compressed, ~35 tokens):**

```yaml
description: Foundation skill, auto-load via SessionStart. Teaches 5-layer workflow + 1% pre-flight rule + skill discovery. Do NOT manually load.
applicability:
  always: true
  triggers:
    files_match: ["**"]
relevance_assessment: |
  Always 100% — meta-skill, fires first.
```

Body content must be rewritten in caveman style and the phase list must change from `PLAN → SPEC → BUILD → VERIFY → REVIEW` to the 5-layer doc 02 flow with pre-flight references. Roughly 600 lines today → target 300 lines.

**Tools:** `compress`, `prompt-master` (frontmatter description quality), `skill-creator` for the applicability block.

**Effort:** 3 h.

#### Example 3 — `skills/triage/SKILL.md` COMPLETE_SCAFFOLD (P0)

The `references/` directory exists; the SKILL.md is missing. Source: doc 05 §`triage.md` provides the full body verbatim. Steps:

1. Copy `triage.md` content (inside its outer code fence) into `skills/triage/SKILL.md`.
2. Replace its description with a caveman-compressed one (~40 tokens).
3. Verify the existing `references/` subfiles are consistent with the new SKILL.md and update if not.

**Effort:** 2 h.

### 3.3 Rules

The flat→split move is mechanical but breaks paths in agents (`requiredSkills` references), hooks (`skill-router.sh` lookup), and `CLAUDE.md`. Sequence:

1. Create `rules/common/` and `rules/java/` (empty).
2. `git mv` each file per the target paths in table 2.3.
3. For splits (`coding-style`, `security`), copy the original into both directories, then delete the language-specific section from `common/` and the language-agnostic section from `java/`.
4. Update path references everywhere via `grep -rl` (audit list: every agent `requiredSkills`, `scripts/hooks/skill-router.sh`, `CLAUDE.md`, every command that mentions rule paths).
5. Apply caveman-compress to every rule file after the move (separate commit per rule keeps the diff reviewable).

#### Example — `rules/spec-driven.md` REFACTOR + move (P0)

**Before (excerpt, ~40 tokens):**

```markdown
## Mandate

A **spec** MUST be produced and approved before implementation. The spec defines observable behavior — what the system does, not how. No spec, no code.

**Skip conditions**: ≤5 lines, single file, no new behavior, cosmetic only.
```

**After at `rules/common/spec-driven.md` (caveman-compressed, ~30 tokens):**

```markdown
## Mandate by lane

- Trivial: spec optional
- Standard: spec required if behavior changes
- High-stakes: spec required, always

Spec = contract between Plan and Build. Each scenario → 1 test. Each clause → 1 Stage-1 check.
```

**Diff explanation:** old binary skip-condition replaced by lane-based mandate per doc 05 `remaining-skills.md` §"Rules updates summary". Body shrinks ~50 %.

### 3.4 Commands

#### Example — `commands/plan.md` REFACTOR (P1)

The current `/plan` does not check for `align` or `brainstorm` artifacts.

**Pseudocode for the new behavior block (agent-facing, caveman-compressed):**

```markdown
## First Action (MANDATORY)

1. Read `.claude/memory/current-triage.json` → require `lane`
2. Read `.claude/memory/preflight/plan-*.md` → require latest artifact for this gate
3. If lane == high-stakes: require `.claude/memory/brainstorm-artifacts/` non-empty
4. If lane != trivial AND no `align-artifacts/`: warn + suggest `/align`
5. Update `.claude/workflow-state.json` { phase: PLAN, lane, gate_inputs: [...] }
```

**Diff explanation:** adds lane + artifact preconditions; refuses for high-stakes without brainstorm output. The narrative body of `plan.md` (which the human user reads) stays natural; only the agent-facing "First Action" block is compressed.

**Tools:** `compress` (frontmatter + agent-facing blocks), `prompt-master` (command instructions to the agent).

**Effort:** 2.5 h.

### 3.5 Hooks

Doc 07 §"Hook implementation" gives the skeleton for `preflight-gate.sh` and `preflight-discovery.sh`. Drop those into `scripts/hooks/`, register in `hooks/hooks.json` under `PreToolUse` matched on the workflow slash commands.

#### Example — adding `preflight-gate.sh` (P0)

**New file `scripts/hooks/preflight-gate.sh` (caveman-compressed agent-facing stderr):**

```bash
#!/usr/bin/env bash
set -euo pipefail

GATE_NAME=$(detect_gate_from_command "$@") || exit 0
ARTIFACT_DIR=".claude/memory/preflight"
mkdir -p "$ARTIFACT_DIR"

LATEST=$(ls -t "$ARTIFACT_DIR/${GATE_NAME}-"*.md 2>/dev/null | head -1 || true)

if [[ -z "$LATEST" ]]; then
  cat <<EOF >&2
[preflight] MANDATORY: produce pre-flight artifact for gate=$GATE_NAME
Save to: $ARTIFACT_DIR/${GATE_NAME}-\$(date +%s).md
Enumerate ALL skills + rules >=1% relevant. Justify SKIP with concrete evidence.
EOF
  exit 1
fi

echo "[preflight] $GATE_NAME using $LATEST" >&2
exit 0
```

Note the caveman style in the stderr lines (no articles, no filler) but the script comments and `set -euo pipefail` are normal shell. Only agent-facing output is compressed.

**Wiring in `hooks/hooks.json`:**

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/preflight-gate.sh",
      "timeout": 10
    }
  ]
}
```

Insert before `workflow-gate.sh` in the existing `PreToolUse` chain.

**Effort:** 3 h (script) + 1 h (wiring + tests).

### 3.6 Memory system

Concrete migration:

1. `mkdir -p .claude/memory/{preflight,align-artifacts,brainstorm-artifacts,sessions}`
2. Add `.claude/memory/` to `.gitignore` if not already.
3. Move existing state JSON files into `.claude/memory/state/`:
   ```bash
   mkdir -p .claude/memory/state
   git mv .claude/workflow-state.json .claude/memory/state/
   git mv .claude/build-checkpoint.json .claude/memory/state/
   git mv .claude/verify-fix-state.json .claude/memory/state/
   git mv .claude/session-metrics.json .claude/memory/state/
   ```
4. Update every hook that reads those paths.
5. Create `templates/CONTEXT_TEMPLATE.md` with the structure from doc 06 §Step 3 (Domain vocabulary, Architecture decisions, Naming conventions, Tech stack). Apply caveman to the section-header prompts only.
6. Add `docs/adr/.gitkeep` and a one-page `docs/adr/0000-template.md` from doc 05 brainstorm §"Phase 4 — ADR".

**Effort:** 4 h.

### 3.6.1 Session-artifact pruning (P0 — multi-agent unblock)

Two-stage cleanup:

**Stage 1 — remove dead writes (no behavior change for agent):**

1. Delete the `compaction-log.txt` appender from `scripts/hooks/pre-compact.sh`. Keep only the JSON state write if `post-compact.sh` reads it; otherwise drop both.
2. Drop the `execution-trace.jsonl` open/write logic in `scripts/hooks/observability-trace.sh`. If nothing else is happening in that hook, demote H5 in §2.5 from KEEP+compress to REMOVE.
3. Drop `session-metrics.json` creation in `session-init.sh` / `session-save.sh`.
4. Stop committing `.last-retention-check` — runtime marker only.

**Stage 2 — replace `skills-loaded.json` blocking semantics with announcement-only (this unblocks multi-agent):**

Current behavior (per ewallet field evidence): subagent dispatch checks `skills-loaded.json` for prepopulated skills. Mismatch between main agent's loaded set and subagent's expected set blocks dispatch.

Replacement contract (caveman-style agent-facing spec):

```markdown
## Skill announcement (replaces skills-loaded.json gate)

1. Agent loads skills via skill-router.sh.
2. Agent emits ONE line in chat: `Skills loaded: skill-a, skill-b, ...`
3. No file write. No state. No gate.
4. Subagent does its own pre-flight (per doc 07) and announces its own.

Rationale: superpowers pattern — announcement is the contract, file is overhead.
```

Hook edits required:

- `scripts/hooks/skill-router.sh`: stop writing `skills-loaded.json`; emit announcement to stderr instead.
- `scripts/hooks/subagent-init.sh`: stop reading `skills-loaded.json`; subagent runs its own pre-flight discovery per doc 07 §"Subagent context".

Effort: ~3 h for both hook edits + a manual test that dispatches a multi-slice plan and confirms no block.

### 3.6.2 Ewallet rule merges (P1)

Per §2.5.6 mapping. Sequencing matters because most merges happen *inside* the rule files that the §3.3 rule-split is moving. Run §3.3 (flat → `common/` + `java/` split) first, then merge ewallet content into the split targets.

Example — `rules/java/migration.md` (new, imported from ewallet `migration-immutability.md`):

**Before — verbatim ewallet (~150 tokens):**

```markdown
# Migration Immutability Rule (NON-NEGOTIABLE — cluster-wide)

> **Established 2026-05-09.** 11 services. Vi phạm = CI reject + manual revert.

## Rule

Migration đã commit = đã apply ≥1 env → TUYỆT ĐỐI KHÔNG edit. Schema change = tạo `V{n+1}__description.sql` mới.

Flyway checksum: edit file → checksum mismatch → app boot fail.
```

**After — caveman-compressed, plugin-generic (~90 tokens):**

```markdown
# Migration Immutability (HARD BLOCK)

Committed migration = applied ≥1 env. NEVER edit. Schema change → create `V{n+1}__description.sql` new.

Flyway checksum: edit committed migration → checksum mismatch → app boot fail.

## Allowed direct edit
1. File uncommitted (local branch)
2. Verified unapplied (check `flyway_schema_history` all envs)

## Pattern
- Add column → new V file
- Drop column → new V file
- Index change → new V file
```

Dropped: cluster-specific "11 services" framing, dates, ewallet branding. Kept: rule substance, evidence, allowed exceptions.

Same compression pass applied to every imported rule.

### 3.6.4 Plan/Spec decomposition (P0 — split shape for large features)

Approved 2026-05-15 per `docs/proposals/2026-05-15-plan-spec-decomposition.md`. Option D (hierarchical index + per-slice).

**Threshold:** ≤2 slices = single-file (existing templates). 3+ slices = split shape.

**Templates added:**
- `templates/PLAN_INDEX_TEMPLATE.md`
- `templates/PLAN_SLICE_TEMPLATE.md`
- `templates/SPEC_INDEX_TEMPLATE.md`
- `templates/SPEC_SLICE_TEMPLATE.md`

Existing `PLAN_TEMPLATE.md` + `SPEC_TEMPLATE.md` retained for single-file shape.

**File structure (split):**
```
.claude/docs/plans/<feature>/
├── index.md
└── slices/<NN>-<slug>.md

.claude/docs/specs/<feature>/
├── index.md          # §1 Cross-cutting AUTHORITATIVE
└── slices/<NN>-<slug>.md  # §0 references index §1
```

**Cross-cutting authority (split shape):**
- `spec_index §1` defines auth + idempotency + logging + error envelope + perf budget ONCE
- Per-slice spec `§0` references index — does NOT duplicate
- Slice override forbidden without ADR + explicit `§Cross-cutting override`

**Approval semantics:**
- Per-slice `status: DRAFT | APPROVED | REVISED`
- Index aggregate: `APPROVED` (all slices APPROVED) | `PARTIALLY_APPROVED` (mixed) | `DRAFT`/`REVISED`
- `/build` requires aggregate `APPROVED` — `PARTIALLY_APPROVED` blocks dispatch (gate discipline)

**Stage 1 review (split shape):**
- Per-slice spec-compliance-reviewer dispatched in parallel
- Verdicts → `.claude/memory/state/review-stage1-<slice-id>.json`
- Aggregate → `review-stage1.json` (PASS iff all slices PASS)

**Stage 2 review (split shape):**
- Per-slice code-quality-reviewer scoped to slice files
- Aggregate verdict: Block (any Critical) → "Approve with caveats" (any Major) → Approve

**Migration:**
- Opt-in only via `scripts/migration/split-plan-spec.py`
- Existing single-file plans/specs preserved
- User reviews migrated TODO markers — auto-extraction best-effort

**Validator extended:**
- `scripts/ci/validate-plan-spec-templates.sh` detects shape per path (file vs directory)
- Cross-references: slice files in `slices/` MUST be listed in `index.md §3/§2`, vice versa
- Frontmatter keys per shape

**Subagent dispatch (split shape):**
- Orchestrator passes `artifacts.plan_slice` + `artifacts.spec_slice` per dispatch
- `subagent-init.sh` injects per-slice spec content + cross-cutting excerpt from `spec_index §1`
- Slice-executor reads ONE slice file (clean context isolation)

**Effort:** 8-12h (templates + validator + 4 agents + 4 commands + migration script + docs). Completed Phase 5.5.

### 3.6.3 Command merge opportunities (P2/P3)

Examination of `commands/` for shared-principal merges:

| Merge candidate | Decision | Rationale |
|---|---|---|
| `build-fix.md` + `verify.md` | **KEEP separate** | Different lifecycle: verify runs gates, build-fix repairs errors. Hook chain depends on the split. |
| `dc-setup.md` + `dc-status.md` + `dc-review.md` | **KEEP separate** | `dc-*` is a recognized subcommand prefix; consolidating breaks discoverability. The shared prefix is the grouping. |
| `pentest-scan.md` + `threat-model.md` | **MERGE — proposed** `/security {scan,threat-model}` umbrella OR keep both pointing to a shared skill. Both small (3.0 K + 1.0 K), both security, both invoke `pentest` agent. Recommendation: keep both as thin entry points but extract shared logic into `skills/pentest/SKILL.md`. | Reduces duplication without breaking either entry point |
| `meta.md` vs proposed `/evolve`, `/improve-architecture`, `/adr` | **COLLAPSE into `/meta` subcommands** — already proposed in §6.7 | Existing `/meta` already implements `learn`, `evolve`, `prune`, `create-skill`. Adding three new top-level slashes fragments the namespace. Re-scope `/meta` so the new commands are `/meta adr`, `/meta improve-architecture`, and the existing `/meta evolve` covers Phase 4 auto-promotion |
| `build.md` + `e2e.md` | **KEEP separate** | Build = slice dispatch; e2e = integration tests via test-runner agent |
| `refactor.md` standalone | **KEEP** | Used by refactorer agent on demand |

Net change: cancel four ADD_NEW commands (§2.4 new rows for `/adr`, `/improve-architecture`, `/evolve` if introduced) in favor of `/meta` subcommands. `/triage`, `/align`, `/brainstorm` stay top-level (they are workflow gates, not learning commands). Saves ~1 K tokens and reduces slash-command sprawl.

Reflect this in §2.4 by changing the ADD_NEW rows for `/adr`, `/improve-architecture` to "subcommand of `/meta`" with effort 0 (handled inside C8). The brief's `/evolve` already lives inside `/meta`.

### 3.7 Caveman ecosystem integration

Once §0.2 succeeds, integrate the skills into the refactor workflow as follows:

| Refactor action | Caveman skill | When invoked |
|---|---|---|
| Compress any SKILL.md description | `compress` | Each P1/P2 skill row in §2.2 |
| Compress agent system prompts | `compress` + `prompt-master` | Each agent row in §2.1 |
| Compress rule bodies | `compress` | Each rule row in §2.3 (post-move) |
| Compress command "First Action" blocks | `compress` | Each command row in §2.4 |
| Generate commit messages | `caveman-commit` | Every refactor commit (one per row when possible) |
| Self-review PRs (per phase) | `caveman-review` | End of each Phase 1–5 |
| Track token savings | `caveman-stats` | Snapshot before and after each phase |
| Parallel sub-investigations (e.g., audit all SKILL.md applicability blocks) | `cavecrew` (investigator subagent) | When investigating cross-cutting concerns |
| Scaffold new SKILL.md | `skill-creator` | Every ADD_NEW skill row |
| Prompt quality on agents | `prompt-master` | `planner`, `slice-executor`, the two reviewers, `spec-writer` |

**CLAUDE.md treatment:** the project-level CLAUDE.md is read both by agents (every session) and by humans during onboarding. Treat it as **hybrid (caveman lite)** — compress the directive blocks ("Hard Blocks", "Always") but keep the workflow-overview paragraph in natural prose. Target: 1.1 k → 0.6 k tokens, not 0.4 k.

---

## 4. Priority Matrix

| Priority | Theme | Items | Total effort | Token impact |
|---|---|---|---|---|
| **P0** | Foundation: pre-flight, triage, lane rules, bootstrap, session hooks, rule-split decision | S25 (triage scaffold), NEW preflight skill, NEW lanes + reactive rules, R8 + R9 (skill-enforcement + spec-driven), S3 (bootstrap), H10 (session-init), H16/H17/H18 (workflow hooks), NEW preflight-gate.sh + preflight-discovery.sh, hooks.json rewire, NEW commands/triage.md | ~28 h | enables all later reductions |
| **P1** | Reasoning gates + applicability rollout + reviewer split + slice-executor rename | NEW align + brainstorm skill + commands, A8 reviewer split, A6 planner refactor, A9 spec-writer refactor, **A4 implementer → slice-executor rename**, C10 plan.md, C12 spec.md, C4 dc-review.md, C5 dc-setup.md, S1/S2/S4/S6/S10/S13/S24 skill refactors, R1–R4/R7 rule moves + splits, H4/H12/H13 hook refactors | ~48 h | ~60 % reduction on touched files |
| **P2** | Execution wiring + secondary agent compression | A2/A3/A5/A7/A10 KEEP+compress, NEW subagent-dispatch + git-worktree skills, S5–S22 KEEP+compress+applicability, C1/C2/C3/C6/C7/C11/C13/C14 commands, R5/R6/R10 rule moves, H5/H7/H8/H14/H15 hooks | ~37 h | bulk of remaining token reduction |
| **P3** | Polish: architecture review, evolution loop, ADR, optional architect agent, low-leverage hooks | A11 architect (optional), S5 continuous-learning extension, S30 improve-architecture, NEW evolve + adr + improve-architecture commands, NEW auto-adr.sh + evolution-check.sh hooks, C8 meta.md decision, low-leverage agents | ~20 h | learning-loop infrastructure |
| **P4** | Documentation, examples, migration guide | `MIGRATION_v2.md`, `WORKING_WORKFLOW.md` rewrite, README updates, example walkthroughs (trivial/standard/high-stakes), release tagging | ~15 h | 0 % token change (human-facing) |

**Critical P0 decision (do this Week 1, before any other work):** the rule-flat vs rule-split decision (Open Question 6.1). Recommendation: **split**, matches docs 04 and 07. If split, all rule moves go in a single PR before any other P0 item to avoid cherry-pick conflicts.

---

## 5. Phase-by-phase Schedule (5 weeks)

Aligned to doc 04. Week labels are part-time effort estimates. Each phase ends with a `caveman-stats` snapshot and a `caveman-review` pass.

### Week 1 — Phase 1: Foundation

**Goal:** triage, CONTEXT.md infrastructure, and the Pre-flight Discovery Protocol.

Tasks:

1. Resolve Open Question 6.1 (rules flat vs split). Recommendation: split. Execute the move in one PR.
2. Complete `skills/triage/SKILL.md` from doc 05 §`triage.md`. Add `commands/triage.md`.
3. Author `skills/preflight/SKILL.md` from doc 05 §`preflight.md`. Caveman-compress description. **Must document all six variants per §3.0.1** (initial / brainstorm-prep / plan-prep / spec-prep / execute-prep / review-prep) including the trivial-lane light format and the Align-inherits-pre-flight-0 rule (§3.0.2). Include a one-page reference at `skills/preflight/references/gate-mappings.md` showing the diagram-1 linear path and the diagram-2 trivial bypass.
4. Author `rules/common/lanes.md`, `rules/java/reactive.md`, refactor `rules/common/spec-driven.md` and `rules/common/skill-enforcement.md`.
5. Implement `scripts/hooks/preflight-gate.sh` and `scripts/hooks/preflight-discovery.sh` (doc 07 §"Hook implementation"). **Matcher coverage:** `preflight-gate.sh` must fire on `/triage`, `/align`, `/brainstorm`, `/plan`, `/spec`, `/build`, `/dc-review` — one matcher per gate, each producing its own artifact filename (`initial-*.md`, `brainstorm-*.md`, `plan-*.md`, `spec-*.md`, `execute-*.md`, `review-*.md`). Align case is special: emit `preflight-align.md` only if new-skill discovery occurred during alignment, otherwise no write (Align reads from `initial-*.md`).
6. Refactor `scripts/hooks/session-init.sh` (load CONTEXT.md, smart skill load by keyword, invoke triage).
7. Refactor `workflow-gate.sh`, `workflow-phase-lock.sh`, `workflow-tracker.sh` to consume lane.
8. Update `hooks/hooks.json` to wire the new hooks. **Also in this PR:** apply §3.6.1 Stage 1 (remove dead session-artifact writes) and §3.6.1 Stage 2 (replace `skills-loaded.json` gate with announcement-only contract). Stage 2 unblocks the Phase 3 multi-agent dispatch pattern — do not defer it.
9. Refactor `skills/bootstrap/SKILL.md` to teach the 5-layer workflow and pre-flight rule.
10. Update `CLAUDE.md` (hybrid caveman) to add the "1% rule" mandate from doc 07 §"CLAUDE.md addition".
11. Create `templates/CONTEXT_TEMPLATE.md` and `docs/adr/0000-template.md`.
12. Apply the `applicability` block to the 24 existing skills. Hand-authored content, caveman-compressed. (Doc 07 migration script only flags; content is non-trivial — see Open Question 6.5.)

Acceptance: doc 04 Phase 1 §"Acceptance criteria" must all pass. **Plus diagram-compliance smoke test:** run one trivial task and one standard task end-to-end. Verify

- Trivial task produces `initial-*.md` (light), then jumps to Execute, then `review-*.md` (Stage 2 only), then Commit. No `brainstorm-*.md` / `plan-*.md` / `spec-*.md`.
- Standard task produces 6 pre-flight artifacts in order: `initial-*.md`, optional `align-*.md`, `brainstorm-*.md`, `plan-*.md`, `spec-*.md`, `execute-*.md`, `review-*.md`.
- High-stakes task (sample: "add new endpoint requiring DB migration") also writes an ADR to `docs/adr/`.
- Each artifact lists ALL skills present in `skills/` (count match via `find skills -name SKILL.md -type f | wc -l`).

Caveman pass: `caveman-stats snapshot --tag phase1-end`.

**Week 1.5 (parallel track):** apply §2.5.6 ewallet rule merges. Sequencing: §3.3 rule-flat-to-split lands first (single PR), then ewallet imports merge into the split targets (one PR per rule, ~10 h total). Run caveman pass after each merge.

### Week 2 — Phase 2: Reasoning Gates

**Goal:** add `align` + `brainstorm` skills and wire into Plan.

1. Author `skills/align/SKILL.md`, `commands/align.md`, `skills/align/references/grill-questions.md`.
2. Author `skills/brainstorm/SKILL.md`, `commands/brainstorm.md`, references and examples from doc 03.
3. Refactor `commands/plan.md` to read align + brainstorm artifacts (P1 pseudocode in §3.4).
4. Refactor `agents/planner.md` to consume brainstorm output (still single agent at this point; subagent isolation lands in Phase 3).
5. Update `rules/common/spec-driven.md` to mandate brainstorm for high-stakes (already done in Phase 1 if lane-rules went in then; verify).
6. Acceptance per doc 04 Phase 2.

### Week 3 — Phase 3: Execution Refactor

**Goal:** subagent isolation + worktree.

1. Author `skills/subagent-dispatch/SKILL.md`, `skills/git-worktree/SKILL.md`.
2. Refactor or rename `agents/implementer.md` → `agents/slice-executor.md` per §3.1 Example 3.
3. Refactor `scripts/hooks/subagent-init.sh` to inject pre-flight artifact + plan slice + spec.
4. Update `commands/build.md` to dispatch one subagent per slice.
5. Acceptance per doc 04 Phase 3.

### Week 4 — Phase 4: Review + Learning

**Goal:** two-stage review + auto-evolution + ADR.

1. Split `agents/reviewer.md` → `agents/spec-compliance-reviewer.md` + `agents/code-quality-reviewer.md` (§3.1 Example 2).
2. Refactor `commands/dc-review.md` to orchestrate two stages.
3. Extend `skills/continuous-learning/SKILL.md` with auto-promotion thresholds (doc 02 Layer 5).
4. Author `scripts/hooks/auto-adr.sh`, `scripts/hooks/evolution-check.sh`.
5. Author `commands/adr.md`, `commands/improve-architecture.md`, `skills/improve-architecture/SKILL.md`.
6. Refactor `commands/meta.md` (see §6.7) — keep umbrella subcommands, re-scope to consume Phase 4 auto-promotion thresholds.
7. Optional: add `agents/architect.md` for high-stakes pre-plan architectural review.
8. Acceptance per doc 04 Phase 4.

### Week 5 — Phase 5: Polish

**Goal:** documentation, migration, examples, release tagging.

1. Write `MIGRATION_v2.md`. **Important narrative correction:** doc 06 calls the current workflow "7-phase". The audit (see §7.3) confirms the codebase already runs a 5-phase pipeline (`PLAN → SPEC → BUILD → VERIFY → REVIEW`). Frame the migration as "5-phase rigid → 5-layer adaptive + triage", not "7→5". Port doc 06 sections that still apply; rewrite the comparison tables to use the actual baseline.
2. Rewrite `WORKING_WORKFLOW.md` for the 5-layer flow.
3. Add example walkthroughs at `examples/{trivial-fix,standard-feature,high-stakes-migration}-flow.md`.
4. Update `README.md`.
5. Run final `caveman-stats` snapshot and compare to baseline (record in §7.1).
6. Tag `v2.0.0-beta`.

---

## 6. Open Questions — ALL RESOLVED

All open questions locked to the recommended option on 2026-05-15 by user directive. Decisions are recorded below for traceability; the rest of the plan (sections 2–5, 7) has been updated to reflect them. No further input required to start Phase 1.

### 6.1 Rules flat vs split — **DECIDED: SPLIT**

Execute the flat → `rules/common/` + `rules/java/` migration as the first PR of Phase 1. Path updates in hooks, agents, and CLAUDE.md follow in the same PR to keep the diff atomic.

### 6.2 Preflight strictness — **DECIDED: Strict (Option A) with light version for trivial**

Every gate, every lane, runs pre-flight. Trivial lane uses the 3–5 line condensed format from doc 07 §"Light version". No bypass flag — pre-flight is foundational, intermittent enforcement does not build habit.

### 6.3 `messaging-patterns` — **DECIDED: KEEP MERGED**

`skills/messaging-patterns/SKILL.md` keeps both Kafka and RabbitMQ guidance. Applicability block lists keywords for both technologies. Re-evaluate after first 5 pre-flight artifacts in production — split only if SKIP justifications consistently target one technology.

### 6.4 `spring-patterns` — **DECIDED: SPLIT into `spring-webflux-patterns` + `spring-mvc-patterns`**

`skills/spring-patterns/SKILL.md` splits into two skills. Pre-flight artifacts can SKIP one technology cleanly per doc 07 §"Execute gate". Cascaded into §2.2: S13 now SPLIT decision; cross-references in agents (`requiredSkills.conditional.spring`) update to the matching skill per project profile. ~3 h.

### 6.5 Applicability blocks — **DECIDED: HAND-AUTHORED**

All 24 (or 25 after spring split) `applicability` blocks hand-authored. Budget 12–16 h across Phase 1. Migration script from doc 07 used only to flag missing blocks, not to populate content. Caveman-compress descriptions after authoring.

### 6.6 Legacy mode flag — **DECIDED: YES (workflow gates only, no pre-flight bypass)**

Implement `AGENT_SKILLS_PROFILE=legacy` for 30 days post v2.0 release. Scope: skip triage / align / brainstorm / two-stage review. Pre-flight stays mandatory regardless of the flag — `--no-preflight` is **never** valid. Trivial lane's light version covers cost concern.

### 6.7 `commands/meta.md` — **DECIDED: KEEP UMBRELLA, REFACTOR**

`/meta` retains `learn`, `evolve`, `prune`, `create-skill` subcommands. Phase 4 adds `/meta adr` and `/meta improve-architecture`. No new top-level slashes for these. 8.6 K body re-scoped to consume doc 04 Phase 4 auto-promotion thresholds (confidence ≥ 0.8, ≥ 3 occurrences, ≥ 2 sessions).

### 6.7.1 Session-artifact removal scope — **DECIDED: REMOVE ALL FIVE WRITERS**

Strip writers for `execution-trace.jsonl`, `compaction-log.txt`, `session-metrics.json`, `.last-retention-check`, `pre-compact-unknown.json`. If external consumer surfaces during Phase 1, restore the writer with proper population (not empty shells). Confirmed in Phase 1 PR alongside §3.6.1 Stage 1.

### 6.7.2 `skills-loaded.json` — **DECIDED: REMOVE FILE, ON-DEMAND ONLY**

File removed. Chat announcement is the contract per §3.6.1 Stage 2. Debug write happens only on explicit `/dc-status` invocation. No hook reads it.

### 6.7.3 Slash-command namespace — **DECIDED: SUBCOMMANDS UNDER /meta**

Top-level slashes reserved for workflow gates: `/triage`, `/align`, `/brainstorm`, `/plan`, `/spec`, `/build`, `/verify`, `/dc-review`. Learning + evolution lives under `/meta`. Cancels §2.4 ADD_NEW rows for `/adr` and `/improve-architecture`.

---

## 7. Appendix

### 7.1 Token efficiency report

Baseline measured from `wc -c` on 2026-05-15. Target totals computed from per-row reduction percentages in section 2. Actual post-refactor numbers should be filled in at the end of each phase using `caveman-stats`.

| Bucket | Baseline (bytes) | Baseline (~tokens) | Target (~tokens) | Reduction |
|---|---|---|---|---|
| Skills (24 SKILL.md) | 165 k | ~41 k | ~16 k | 60 % |
| Agents (10) | 78 k | ~19 k | ~8 k | 60 % |
| Rules (10) | 48 k | ~12 k | ~5 k | 60 % |
| Commands (14) | 98 k | ~25 k | ~10 k | 60 % |
| CLAUDE.md (hybrid) | 4.5 k | ~1.1 k | ~0.6 k | 45 % |
| **Plugin bundle total** | **393 k** | **~98 k** | **~40 k** | **~59 %** |

Note that the brief's "~50 k current → ~22 k target" estimate undercounted; the measured baseline is ~98 k. Per-artifact percentage targets stay aligned with the brief.

Per-session loaded context (auto-loaded files only, not every skill) is harder to estimate without running `session-init.sh` and counting; record this in Phase 1 by adding a `caveman-stats snapshot` call inside `session-init.sh` itself.

### 7.2 Caveman application matrix

| Content type | Audience | Caveman setting |
|---|---|---|
| `SKILL.md` descriptions | Agent | ON |
| `SKILL.md` body (rule-style sections) | Agent | ON |
| `SKILL.md` examples | Mixed | LITE |
| Frontmatter (`description`, `triggers`, `applicability`) | Agent | ON |
| Agent system prompts | Agent | ON |
| Rule files (`rules/**/*.md`) | Agent | ON |
| Hook stderr / agent-facing messages | Agent | ON |
| Hook script bodies (bash) | Maintainer | OFF (code) |
| Command "First Action" sections | Agent | ON |
| Command human-facing narrative | Human | OFF |
| `CLAUDE.md` directives | Mixed | LITE |
| `CLAUDE.md` workflow narrative | Human | OFF |
| Memory artifacts (`.claude/memory/**/*.md`) | Agent | ON |
| `CONTEXT_TEMPLATE.md` section prompts | Agent | ON |
| `CONTEXT.md` populated content (user-authored) | Human | OFF |
| ADR documents | Human (future) | OFF |
| `REFACTOR_PLAN.md` (this file) | Human | OFF |
| `MIGRATION_v2.md` | Human | OFF |
| `WORKING_WORKFLOW.md` | Human | OFF |
| Example walkthroughs | Human | OFF |
| Commit messages | Mixed | LITE (`caveman-commit`) |
| PR descriptions | Human | OFF (technical bullets can be LITE) |
| Review comments | Human | LITE (`caveman-review`) |

**Naming clarification carried from §0.2:** the marketplace skill the brief calls `caveman-compress` is published as `compress/`. The skill the brief calls `agent-development` does not exist and is dropped.

### 7.3 Verification log

These results were captured during the audit (2026-05-15). The plan reflects them.

| Check | Result | Notes |
|---|---|---|
| `ls .claude/docs/devco-improve-docs/agent-skills-improvement/` | 7 docs present (00–07) | doc 05 lives in `05-skill-specifications/` subdir |
| `ls .claude/docs/.../05-skill-specifications/` | 5 specs (triage, align, brainstorm, preflight, remaining-skills) | matches brief |
| `ls /Users/taiphan/Downloads/devco-improve-docs/` | ⚠️ Operation not permitted | sandbox blocks Downloads; vendored copy used instead |
| `ls agents/` count | 10 (including `_shared-protocol.md`) | matches plan |
| `find skills -name SKILL.md` count | 24 SKILL.md files; `skills/triage/` has `references/` but no SKILL.md | flagged as COMPLETE_SCAFFOLD |
| `find rules -name '*.md'` count | 10, all flat (no `common/` or `java/` subdir) | ⚠️ doc 04/07 assume split — Open Question 6.1 |
| `find commands -name '*.md'` count | 14 | matches plan |
| `find scripts/hooks -name '*.sh'` count | 18 | matches plan |
| `ls memory/` | no such directory | state lives in `.claude/*.json` |
| `ls ~/.claude/skills/` | `agent-builder`, `graphify`, `prompt-master`, `skill-creator`, `solution-design` | caveman family NOT installed; only in marketplace |
| `ls ~/.claude/plugins/marketplaces/caveman/skills/` | `caveman`, `caveman-commit`, `caveman-help`, `caveman-review`, `caveman-stats`, `cavecrew`, `compress` | ⚠️ `compress` is the actual name, not `caveman-compress` |
| `ls ~/.claude/plugins/marketplaces/caveman/skills/agent-development` | missing | ⚠️ brief's `agent-development` does not exist |
| Current CLAUDE.md workflow line | `PLAN → SPEC → BUILD → VERIFY → REVIEW` (5-phase, not 7-phase) | doc 04/06 narrative still calls it 7-phase; treat as legacy phrasing |
| `grep -l "applicability:" skills/*/SKILL.md` | empty | ⚠️ no existing skill has the doc 07 block |

### 7.4 Glossary

- **Lane** — one of `trivial | standard | high-stakes`, decided by the triage skill.
- **Gate** — a workflow checkpoint with its own pre-flight artifact (Align, Brainstorm, Plan, Spec, Execute, Review).
- **Pre-flight artifact** — markdown file in `.claude/memory/preflight/<gate>-<ts>.md` enumerating every skill and rule with ≥1 % relevance to the upcoming gate, with APPLY/SKIP decisions and concrete SKIP justifications.
- **1 % rule** — doc 07 principle: enumerate everything with ≥1 % relevance; SKIP justification must reference concrete evidence (a file path, a missing dependency, a grep result).
- **Applicability block** — YAML block in a skill's frontmatter declaring when the skill triggers and how to score relevance. Mandatory after Phase 1.
- **Slice** — an independently testable vertical unit emitted by the planner, executed by a `slice-executor` subagent.
- **CONTEXT.md** — project-root file capturing domain vocabulary, architecture decisions, naming conventions, and tech-stack specifics. Git-tracked.
- **ADR** — Architecture Decision Record, auto-generated for high-stakes lane.
- **Caveman (full / lite / off)** — compression policy applied per audience, per §7.2 matrix.

### 7.5 References

- `.claude/docs/devco-improve-docs/agent-skills-improvement/00-README.md` — index, top-6 decisions, 5-week roadmap summary.
- `.claude/docs/devco-improve-docs/agent-skills-improvement/01-comparative-analysis.md` — strengths/weaknesses matrix of the four source plugins.
- `.claude/docs/devco-improve-docs/agent-skills-improvement/02-optimized-workflow.md` — 5-layer architecture, memory tiers, lane skipping rules.
- `.claude/docs/devco-improve-docs/agent-skills-improvement/03-brainstorming-skill.md` — tournament-style brainstorm deep dive.
- `.claude/docs/devco-improve-docs/agent-skills-improvement/04-refactor-roadmap.md` — phase-by-phase plan, acceptance criteria, risk mitigation.
- `.claude/docs/devco-improve-docs/agent-skills-improvement/05-skill-specifications/{triage,align,brainstorm,preflight,remaining-skills}.md` — copy-ready SKILL.md content for every new skill.
- `.claude/docs/devco-improve-docs/agent-skills-improvement/06-migration-guide.md` — v1→v2 migration, deprecation flags, FAQ.
- `.claude/docs/devco-improve-docs/agent-skills-improvement/07-skill-rule-discovery-protocol.md` — the foundational 1 % rule and pre-flight protocol.
- `hooks/hooks.json` — current hook registration; will need rewiring in Phase 1.
- `.claude-plugin/plugin.json` — version `3.3.1`; bump to `4.0.0-beta` at the end of Phase 5.

---

*End of plan. Begin with §0 prerequisites, then Phase 1.*
