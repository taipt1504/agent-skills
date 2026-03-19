# SDD Workflow Research Report — Optimization & Upgrade Plan

> Research date: 2026-03-17
> Sources: Thoughtworks, Martin Fowler, GitHub Blog, Anthropic Engineering, arXiv, ECC, Addy Osmani, Panaversity
> Scope: Optimize CLAUDE.md + WORKING_WORKFLOW.md + agent assignments for the 7-phase SDD workflow

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Analysis](#2-current-state-analysis)
3. [SDD Best Practices from Research](#3-sdd-best-practices-from-research)
4. [Critical Issues (Top 10)](#4-critical-issues-top-10)
5. [Proposed Workflow v2](#5-proposed-workflow-v2)
6. [Agent Roster Redesign](#6-agent-roster-redesign)
7. [CLAUDE.md Rewrite Strategy](#7-claudemd-rewrite-strategy)
8. [WORKING_WORKFLOW.md Rewrite Strategy](#8-working_workflowmd-rewrite-strategy)
9. [Implementation Roadmap](#9-implementation-roadmap)
10. [Sources](#10-sources)

---

## 1. Executive Summary

The current 7-phase SDD workflow has the right structure but three fundamental problems:

1. **Agent gaps in critical phases** — Only 3 of 7 phases have assigned agents (PLAN, BUILD, REVIEW). The SPEC phase — the most cognitively demanding — has no agent at all.
2. **Context bloat** — CLAUDE.md is 336 lines (~216 lines noise); WORKING_WORKFLOW.md is 1,055 lines with ~300 lines of redundancy. LLMs reliably follow ~150 instructions; we're burning budget on reference tables.
3. **Inconsistencies between files** — Verify modes, plan output formats, skip conditions, and test naming conventions differ between CLAUDE.md, WORKING_WORKFLOW.md, and commands/*.md.

### Key Numbers

| Metric | Current | Target |
|--------|---------|--------|
| CLAUDE.md lines | 336 | ~120 |
| WORKING_WORKFLOW.md lines | 1,055 | ~500 |
| Phases with assigned agents | 3/7 | 5/7 |
| Agents using opus | 3 (planner, architect, refactor-cleaner) | 3 (planner, architect, **spec-writer**) |
| Cross-file inconsistencies | 8+ identified | 0 |

---

## 2. Current State Analysis

### 2.1 Phase → Agent → Skill Matrix (Current)

| Phase | Command | Agent (model) | Skills/Rules Used |
|-------|---------|--------------|-------------------|
| **① BOOT** | `/setup`, `/resume-session` | **None** | hooks: `session-start.sh` |
| **② PLAN** | `/plan` | `planner` (opus), `architect` (opus, conditional) | — |
| **③ SPEC** | `/spec` | **None (CRITICAL GAP)** | `rules/common/spec-driven.md` |
| **④ BUILD** | `/build-fix`, `/e2e` | `tdd-guide` (sonnet), `build-error-resolver` (sonnet), `e2e-runner` (sonnet) | hooks: `java-compile-check`, `java-format` |
| **⑤ VERIFY** | `/verify` | **None** | `verification` skill |
| **⑥ REVIEW** | `/code-review`, `/orchestrate` | `code-reviewer` (sonnet), `security-reviewer` (sonnet), + conditional reviewers | — |
| **⑦ LEARN** | `/learn`, `/evolve`, `/save-session` | **None** | `continuous-learning-v2`, hooks: `evaluate-session`, `session-end` |

### 2.2 CLAUDE.md Content Audit

| Content Block | Lines | Verdict |
|---------------|-------|---------|
| Setup instructions | 20 | **Keep** — essential for first-time setup |
| Workflow mandate + link | 5 | **Keep** |
| Tech Stack | 4 | **Keep** |
| Architecture table | 8 | **Keep** |
| Workflow Enforcement table | 10 | **Keep** — hard-stop rules, critical |
| Key Conventions (style, naming, packages) | 30 | **Keep** — prevents violations |
| Skills table (25 rows) | 30 | **REMOVE** — human README, not agent instruction |
| Agents table (14 rows) | 18 | **REMOVE** — agents are loaded on demand |
| Commands table (21 rows) | 25 | **REMOVE** — commands are invoked by name |
| Contexts table | 6 | **REMOVE** — rarely used |
| Rules listing | 4 | **REMOVE** — rules auto-load |
| Hooks listing | 4 | **REMOVE** — hooks are deterministic |
| Memory section | 8 | **TRIM** to 2 lines |
| Quick Reference | 15 | **Keep** (trim to 8 lines) |
| CI/Build commands | 12 | **MOVE** to README |
| Project Guidelines pointer | 6 | **MOVE** to top |
| Critical Rules NEVER/ALWAYS | 22 | **Keep** — highest-signal rules |
| **Total essential** | **~120** | |
| **Total noise** | **~216** | |

### 2.3 WORKING_WORKFLOW.md Content Audit

| Section | Lines | Verdict |
|---------|-------|---------|
| Header + ToC | 44 | **Trim** to 20 |
| Phase 1: BOOT | 65 | **Trim** — 30 lines are ASCII art |
| Phase 2: PLAN | 98 | **Trim** to ~50 (remove non-Java example) |
| Phase 3: SPEC | 83 | **Keep** ~50 essential lines |
| Phase 4: BUILD | 130 | **Keep** ~70 (Java examples valuable) |
| Phase 5: VERIFY | 85 | **Reconcile** modes with commands/verify.md |
| Phase 6: REVIEW | 110 | **Trim** to ~70, add performance-reviewer |
| Phase 7: LEARN | 115 | **Trim** to ~50 |
| Enforcement Rules | 70 | **Keep** (high signal) |
| Memory Flow | 65 | **REMOVE** — repeats Phase 1/7 |
| Quick Reference | 90 | **REMOVE** — repeats phase sections |
| **Appendix A: Phase Diagram** | **108** | **REMOVE** — 100% redundant |
| Appendix B: Hook-to-Phase | 12 | **Keep** |
| Appendix C: Error Recovery | 14 | **Keep** |
| **Target total** | **~500** | |

### 2.4 Agent Model Audit

| Agent | Current Model | Recommended | Reasoning |
|-------|--------------|-------------|-----------|
| `planner` | opus | opus | Complex reasoning, cross-system analysis |
| `architect` | opus | opus | Architectural judgment |
| `refactor-cleaner` | opus | **sonnet** | Mechanical grep-based work |
| `tdd-guide` | sonnet | sonnet | Focused execution |
| `build-error-resolver` | sonnet | sonnet | Error pattern matching |
| `code-reviewer` | sonnet | sonnet | Quality checks |
| `security-reviewer` | sonnet | sonnet | Pattern-based analysis |
| All other reviewers | sonnet | sonnet | Correct |
| **NEW: `spec-writer`** | — | **opus** | Highest cognitive demand in workflow |

---

## 3. SDD Best Practices from Research

### 3.1 What Is SDD (Thoughtworks 2025 Radar)

SDD is recognized by Thoughtworks as one of 2025's most significant emerging practices. Core principle: **specifications — not code — are the primary artifact**.

Three implementation levels:
- **Spec-First**: Write spec upfront, discard after task (prototypes)
- **Spec-Anchored**: Spec evolves alongside code with automated enforcement (production — **this is what we want**)
- **Spec-as-Source**: Humans only modify specs; machines regenerate code (future)

### 3.2 What Makes a Good Spec (arXiv 2602.00180)

Research reports **error reductions of up to 50%** when specs guide LLM implementations. A good spec:
- Defines **external behavior only** — input/output mappings, preconditions, postconditions, invariants
- Uses **domain-oriented ubiquitous language** (not tech jargon)
- Structures scenarios as **Given/When/Then**
- **Complete yet concise** — covers critical path + explicit edge cases, skips redundant permutations
- Maps scenarios directly to test method names

### 3.3 The GitHub Spec-Kit 4-Phase Model

| Phase | Purpose | Gate |
|-------|---------|------|
| **Specify** | User journeys, problems, success metrics | Human approval |
| **Plan** | Stack, architecture, constraints | Human approval |
| **Tasks** | Break spec+plan into atomic work units | Human approval |
| **Implement** | Sequential per-task execution | Each task verified |

**Key insight**: GitHub adds an explicit **Tasks decomposition** step between spec and implementation. Our workflow lacks this.

### 3.4 Context Window Constraints (Anthropic Engineering)

- LLMs reliably follow **~150 instructions**. Claude Code system prompt uses ~50. Budget for CLAUDE.md: **~100 instructions**.
- **Hooks are deterministic; CLAUDE.md instructions are advisory.** Move must-execute behaviors to hooks.
- **Just-in-time context**: maintain lightweight identifiers, load data via tools at runtime.
- **Progressive disclosure**: only skill frontmatter loads at startup; full SKILL.md on demand.
- Repository-specific rules yield **+10.87% accuracy** vs +5.19% from generic rules.

### 3.5 Multi-Agent Orchestration (Codebridge, Azure Architecture Center)

Four universal agent roles:

| Role | Agents in Our Plugin |
|------|---------------------|
| **Planner** | `planner`, `architect` |
| **Executor** | `tdd-guide`, `build-error-resolver`, `e2e-runner` |
| **Evaluator** | `code-reviewer`, `security-reviewer`, all domain reviewers |
| **Retriever** | (missing — currently Claude's built-in tools handle this) |

Key principles:
- Sub-agents should return **1,000–2,000 token summaries** (not raw dumps)
- Parallel for independent tasks; sequential for dependent tasks
- Context isolation is the main benefit (clean windows, less hallucination)

### 3.6 Addy Osmani's Workflow (2026)

- "Waterfall in 15 minutes" — spend 15 min on spec before any code
- Break work into **single-function/single-feature prompts** — LLMs degrade on large scopes
- **Commit after each small task** (save-point strategy)
- Treat AI output as **junior developer code** — always review

---

## 4. Critical Issues (Top 10)

| # | Severity | Issue | Impact |
|---|----------|-------|--------|
| 1 | **CRITICAL** | Phase 3 (SPEC) has no agent | The most cognitively demanding phase runs without opus. Spec quality is the #1 driver of implementation quality. |
| 2 | **CRITICAL** | CLAUDE.md is 336 lines; ~216 lines noise | Agent instruction compliance degrades. Critical rules buried after line 200 are likely ignored. |
| 3 | **HIGH** | `commands/plan.md` example is TypeScript/Supabase | Planner uses non-Java examples as orientation. Actively misdirects agents. |
| 4 | **HIGH** | Verify modes conflict: WORKING_WORKFLOW.md (4 modes) vs commands/verify.md (3 modes) | Agent running `/verify pre-commit` gets undefined behavior. |
| 5 | **HIGH** | `performance-reviewer` is orphaned from Phase 6 | Performance issues (N+1, blocking, caching) never caught automatically. |
| 6 | **HIGH** | Phase 6 review has no spec-adherence check | The entire point of SDD — verifying code matches spec — is not enforced at review time. |
| 7 | **MEDIUM** | Planner Spec Handoff is too thin | Missing: validation rules, NFRs, external services. Spec phase gets incomplete inputs. |
| 8 | **MEDIUM** | Appendix A in WORKING_WORKFLOW.md is 108 lines of pure repetition | 10% of document adds zero information. |
| 9 | **MEDIUM** | `refactor-cleaner` uses opus unnecessarily | Mechanical grep work burns opus budget. Free up opus allocation for spec-writer. |
| 10 | **MEDIUM** | No Tasks decomposition between SPEC and BUILD | GitHub Spec-Kit and Panaversity both have this step. Atomic work units improve TDD reliability. |

---

## 5. Proposed Workflow v2

### 5.1 Phase Structure

```
① BOOT → ② PLAN → ③ SPEC → ④ TASKS → ⑤ BUILD (TDD) → ⑥ VERIFY → ⑦ REVIEW → ⑧ LEARN
```

**Change: Add Phase ④ TASKS** — explicit decomposition of spec into atomic, ordered implementation units before BUILD.

### 5.2 Phase → Agent → Model Matrix (Proposed)

| Phase | Command | Agent | Model | Role |
|-------|---------|-------|-------|------|
| **① BOOT** | `/setup` | — | — | Hooks handle this (deterministic) |
| **② PLAN** | `/plan` | `planner` | **opus** | Decompose requirements, risk assessment |
| | | `architect` | **opus** | Conditional: new modules, DDD changes |
| **③ SPEC** | `/spec` | **`spec-writer` (NEW)** | **opus** | Generate behavioral contracts from plan |
| **④ TASKS** | `/spec` (sub-step) | `planner` | opus | Break spec into ordered atomic units |
| **⑤ BUILD** | `/build-fix` | `tdd-guide` | sonnet | Red-Green-Refactor per task |
| | | `build-error-resolver` | sonnet | Fix compilation errors |
| | `/e2e` | `e2e-runner` | sonnet | Integration/E2E tests |
| **⑥ VERIFY** | `/verify` | — | — | Shell commands (deterministic) |
| **⑦ REVIEW** | `/code-review` | `code-reviewer` | sonnet | Quality + **spec adherence** |
| | | `security-reviewer` | sonnet | OWASP, secrets, auth |
| | | `spring-webflux-reviewer` | sonnet | Conditional: reactive code |
| | | `spring-reviewer` | sonnet | Conditional: MVC/config |
| | | `database-reviewer` | sonnet | Conditional: queries/schema |
| | | `performance-reviewer` | sonnet | **Conditional: services/controllers** |
| | | `architect` | opus | Conditional: new modules, DDD |
| **⑧ LEARN** | `/learn`, `/save-session` | — | — | Hooks handle this |

### 5.3 Key Design Decisions

**Why add TASKS phase?**
- GitHub Spec-Kit, Kiro, and Panaversity all have it
- Atomic tasks improve TDD reliability (one test class per task)
- Enables progress tracking and checkpoint per task
- Avoids the "implement entire spec at once" anti-pattern

**Why TASKS inside `/spec` instead of a new command?**
- Reduces command sprawl
- Natural extension: spec defines WHAT → tasks define ORDER
- User approves both in one interaction

**Why `spec-writer` as opus?**
- Spec is the highest-leverage artifact (50% error reduction per arXiv)
- Requires reading existing code, understanding domain, generating concrete field names
- Planner produces abstract plan → spec-writer makes it concrete → this is the cognitive bottleneck

**Why add `performance-reviewer` to Phase 7?**
- 417-line fully-developed agent that never fires automatically
- For any Controller/Service/Repository change, performance is critical
- Trigger condition: `*Controller.java`, `*Service.java`, `*Repository.java`, `application*.yml`

---

## 6. Agent Roster Redesign

### 6.1 New Agent: `spec-writer`

```yaml
---
model: opus
description: >
  Generates behavioral specifications (contracts) from approved plans.
  Use when: /spec is invoked after plan approval.
  Produces: input/output types, error cases, Given/When/Then scenarios,
  spec-to-test mapping, and task decomposition.
---
```

**Responsibilities:**
1. Read approved plan from conversation context
2. Detect task type (REST, Domain, Messaging, Migration, Job)
3. Read existing codebase to determine real field names, types, exceptions
4. Generate spec with: Inputs, Outputs, Contracts, Error Cases, Scenarios
5. Map each scenario to a test method name (`shouldDoXWhenY`)
6. Decompose into ordered atomic tasks
7. Present for user approval

### 6.2 Agent Model Changes

| Agent | Before | After | Reason |
|-------|--------|-------|--------|
| `spec-writer` | (new) | opus | Highest cognitive demand |
| `refactor-cleaner` | opus | **sonnet** | Mechanical work |
| All others | unchanged | unchanged | Already correct |

### 6.3 `code-reviewer` Enhancement

Add to code-reviewer's checklist:

```markdown
## Spec Adherence Check
- Read the approved spec (from /spec output or checkpoint)
- For each spec scenario, verify implementation handles it correctly
- Flag any behavior NOT in the spec (scope creep)
- Flag any spec scenario NOT implemented (missing behavior)
```

### 6.4 `performance-reviewer` Wiring

Add to Phase 7 REVIEW conditional triggers:

```markdown
| Trigger Files | Reviewer |
|---------------|----------|
| `*Controller.java`, `*Service.java`, `*Repository.java` | `performance-reviewer` |
| `application*.yml`, `*Config.java` (with pool/cache settings) | `performance-reviewer` |
```

---

## 7. CLAUDE.md Rewrite Strategy

### 7.1 Target: ~120 Lines

Structure:
```
1. Project Guidelines override (3 lines)
2. First-time setup (15 lines)
3. Workflow mandate + phase overview (10 lines)
4. Tech stack (4 lines)
5. Architecture patterns (8 lines)
6. Workflow enforcement table (10 lines)
7. Key conventions: style, naming, packages (30 lines)
8. Critical rules: NEVER/ALWAYS (22 lines)
9. Quick reference: top 8 commands (10 lines)
10. Compaction preservation instruction (3 lines)
```

### 7.2 What to Remove

- **"Available Resources" section** (~90 lines of skills/agents/commands tables) — agents don't need a table of contents; they load resources on demand
- **CI/Build commands** — move to README
- **Hooks listing** — hooks are deterministic, don't need CLAUDE.md mention
- **Memory section** — trim to 2 lines or remove
- **Contexts section** — rarely referenced

### 7.3 What to Add

```markdown
## Compaction Preservation
When compacting, always preserve: current workflow phase, last checkpoint,
modified files list, approved plan summary, approved spec summary, failing tests.
```

```markdown
## Project-Specific Guidelines (PRIORITY)
If `PROJECT_GUIDELINES.md` exists at the project root, read it FIRST.
It overrides all generic conventions below.
```

---

## 8. WORKING_WORKFLOW.md Rewrite Strategy

### 8.1 Target: ~500 Lines

Key cuts:
- **Delete Appendix A** (108 lines, pure repetition)
- **Delete Memory Flow section** (65 lines, repeats Phase 1/7)
- **Delete Quick Reference section** (90 lines, repeats phase sections)
- **Replace ASCII diagrams** with numbered process lists (~200 lines saved)
- **Reconcile verify modes** to one canonical set: `quick`, `full`, `pre-commit`, `gate`

### 8.2 Per-Phase Template

Each phase should follow this consistent format (no more, no less):

```markdown
## Phase N: NAME

**Trigger:** What starts this phase
**Agent:** agent-name (model) — or "None (hooks/commands)"
**Input:** What this phase receives from previous phase
**Output:** Named artifact this phase produces
**Gate:** What must happen before moving to next phase

### Process
1. Step one
2. Step two
3. ...

### Skip Conditions
- When to skip this phase (if applicable)
```

### 8.3 Reconcile Conflicts

| Conflict | Resolution |
|----------|------------|
| Verify modes: 4 in WORKING_WORKFLOW vs 3 in commands/verify.md | Canonical 4 modes: `quick`, `full`, `pre-commit`, `gate`. Update commands/verify.md. |
| Plan output format differs between WORKING_WORKFLOW and planner.md | Planner.md is authoritative. Update WORKING_WORKFLOW to match. |
| Spec approval keywords: "approve/revise/reject" vs "Approve/Revise/Return to plan" | Canonical: `approve`, `revise`, `reject`. Update both files. |
| Test naming: `shouldCreateOrderWhenValidInput` vs `shouldFindOrderById` | Both follow `shouldDoXWhenY` — no conflict, but add explicit convention doc. |
| plan.md example is TypeScript/Supabase | Replace with Java/Spring WebFlux example. |

---

## 9. Implementation Roadmap

### Phase 1: Critical Fixes (high-impact, low-effort)

| # | Task | Files | Effort |
|---|------|-------|--------|
| 1 | Create `spec-writer` agent (opus) | `agents/spec-writer.md` | Medium |
| 2 | Replace TypeScript example in `commands/plan.md` | `commands/plan.md` | Small |
| 3 | Add `performance-reviewer` to review chain triggers | `WORKING_WORKFLOW.md`, `commands/code-review.md` | Small |
| 4 | Change `refactor-cleaner` from opus to sonnet | `agents/refactor-cleaner.md` | Trivial |
| 5 | Add spec-adherence check to `code-reviewer` | `agents/code-reviewer.md` | Small |

### Phase 2: Context Optimization (high-impact, medium-effort)

| # | Task | Files | Effort |
|---|------|-------|--------|
| 6 | Rewrite CLAUDE.md to ~120 lines | `CLAUDE.md` | Medium |
| 7 | Rewrite WORKING_WORKFLOW.md to ~500 lines | `WORKING_WORKFLOW.md` | Large |
| 8 | Reconcile verify modes across all files | `WORKING_WORKFLOW.md`, `commands/verify.md` | Small |
| 9 | Add Tasks decomposition to `/spec` command | `commands/spec.md` | Medium |

### Phase 3: Polish & Consistency (medium-impact)

| # | Task | Files | Effort |
|---|------|-------|--------|
| 10 | Add compaction preservation instruction | `CLAUDE.md` | Trivial |
| 11 | Expand planner Spec Handoff section | `agents/planner.md` | Small |
| 12 | Add structured handoff format to `/orchestrate` | `commands/orchestrate.md` | Medium |
| 13 | Update `commands/spec.md` to invoke `spec-writer` agent | `commands/spec.md` | Small |

---

## 10. Sources

### Spec-Driven Design
- [Thoughtworks: SDD — Unpacking 2025's New Engineering Practices](https://www.thoughtworks.com/insights/blog/agile-engineering-practices/spec-driven-development-unpacking-2025-new-engineering-practices)
- [Martin Fowler: SDD Tools](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)
- [arXiv: Specification-Driven Development with LLMs (2602.00180)](https://arxiv.org/html/2602.00180v1)
- [GitHub Blog: Spec-Driven Development with AI](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/)
- [Augment Code: What is SDD](https://www.augmentcode.com/guides/what-is-spec-driven-development)
- [Kinde: Beyond TDD — Why SDD is the Next Step](https://www.kinde.com/learn/ai-for-software-engineering/best-practice/beyond-tdd-why-spec-driven-development-is-the-next-step/)
- [Specmatic: SDD API Design First](https://specmatic.io/article/spec-driven-development-api-design-first-with-github-spec-kit-and-specmatic-mcp/)

### AI Agent Workflows
- [Addy Osmani: AI Coding Workflow (2026)](https://addyosmani.com/blog/ai-coding-workflow/)
- [Panaversity: SDD with Claude Code](https://agentfactory.panaversity.org/docs/General-Agents-Foundations/spec-driven-development)
- [eesel.ai: Claude Code Best Practices](https://www.eesel.ai/blog/claude-code-best-practices)

### Context Engineering
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Arize: CLAUDE.md Best Practices](https://arize.com/blog/claude-md-best-practices-learned-from-optimizing-claude-code-with-prompt-learning/)
- [Anthropic: Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [HumanLayer: Writing a Good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
- [builder.io: CLAUDE.md Guide](https://www.builder.io/blog/claude-md-guide)

### Multi-Agent Orchestration
- [Codebridge: Mastering Multi-Agent Orchestration](https://www.codebridge.tech/articles/mastering-multi-agent-orchestration-coordination-is-the-new-scale-frontier)
- [Azure Architecture Center: AI Agent Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [DEV.to: Agent Orchestration Patterns](https://dev.to/jose_gurusup_dev/agent-orchestration-patterns-swarm-vs-mesh-vs-hierarchical-vs-pipeline-b40)

### Claude Code Plugin Development
- [Anthropic: Create Plugins](https://code.claude.com/docs/en/plugins)
- [Anthropic: Create Custom Subagents](https://code.claude.com/docs/en/sub-agents)
- [Anthropic: Extend Claude with Skills](https://code.claude.com/docs/en/skills)
- [Anthropic: Model Configuration](https://code.claude.com/docs/en/model-config)
- [ECC: everything-claude-code](https://github.com/affaan-m/everything-claude-code)
