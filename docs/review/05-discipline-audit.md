# Discipline Audit — Why Agents Don't Follow SDD Workflow & Skills

> **Date**: 2026-03-24
> **Trigger**: User feedback after 1 week of real usage
> **Team**: discipline-audit (3 specialists + team lead)
> **Verdict**: Enforcement architecture is fundamentally broken — right ideas, wrong delivery mechanism

---

## User-Reported Problems

1. Agents DON'T follow SDD workflow (PLAN→SPEC→BUILD→VERIFY→REVIEW) despite bootstrap being loaded
2. Agents DON'T use available skills, commands, or rules during work
3. Summer Framework auto-detection and skill loading doesn't work for Summer projects

---

## Root Causes (Prioritized)

### RC1 — CRITICAL: Subagent Bootstrap Gap

**Problem**: Subagents (implementer, reviewer, planner, spec-writer) that do actual work **never receive bootstrap instructions**.

- `SessionStart` hook fires for main session only
- No `SubagentStart` hook exists in `hooks.json`
- Subagents get: agent definition + CLAUDE.md + rules (system level L1)
- Subagents DON'T get: bootstrap skill, skill registry, workflow phase, Summer detection

**Impact**: Complete failure — the agents doing implementation/review have zero awareness of the skill system.

### RC2 — CRITICAL: All Enforcement Hooks Are Invisible

**Problem**: Every hook outputs to **stderr** (invisible to agent) and/or is **async** (fire-and-forget).

| Hook | Async? | Output | Agent Sees? |
|------|--------|--------|-------------|
| skill-router.sh | YES | stderr | **NO** |
| compact-advisor.sh | YES | stderr | **NO** |
| git-guard.sh | YES | stderr | **NO** |
| quality-gate.sh | No | stderr | **NO** |

- No hook uses **exit code 2** (block) to prevent non-compliant actions
- No hook outputs **structured JSON** with `additionalContext` on stdout
- The entire enforcement layer is a no-op from the agent's perspective

### RC3 — CRITICAL: Self-Contained Agent Anti-Pattern

**Problem**: All 8 agents embed ~2,317 lines of domain patterns that duplicate the skill system.

| Agent | Lines | Skills Made Redundant |
|-------|-------|----------------------|
| planner | 378 | architecture, spring-patterns, coding-standards |
| implementer | 295 | testing-workflow, spring-patterns |
| reviewer | 384 | ALL skills (7 embedded checklists) |
| database-reviewer | 229 | database-patterns (near-complete duplication) |
| build-fixer | 294 | spring-patterns, database-patterns |
| test-runner | 252 | testing-workflow (E2E section) |

**Impact**: Agents have zero incentive to load external skills — everything they need is embedded in their prompt.

### RC4 — HIGH: Bootstrap at Wrong Authority Level

**Problem**: Bootstrap arrives as context injection (L4 — lowest priority), not system prompt (L1 — highest).

| Priority | Source | Authority |
|----------|--------|-----------|
| L1 (highest) | CLAUDE.md, rules/*.md, agent definitions | System prompt |
| L2 | Tool definitions | Built-in |
| L3 | User messages | Direct input |
| **L4 (lowest)** | **Bootstrap (SessionStart hook output)** | **Context injection** |

When bootstrap says "search skills before EVERY action" but agent definition says "implement tasks from spec" — the agent follows L1 (its own definition) and ignores L4 (bootstrap).

### RC5 — HIGH: 0/8 Agents Have Skill-Loading Instructions

**Problem**: Not a single agent definition includes a "Before Starting Work → Load Skills" section.

- 0/8 agents reference the skill registry
- 0/8 agents announce "Using skill: X for Y"
- 0/8 agents mention summer detection
- 1/8 (test-runner) partially references one skill file (blackbox only)

Agent prompts jump straight to "do your thing" without checking skills.

### RC6 — HIGH: Passive Summer Detection

**Problem**: Summer is detected but nobody acts on it.

Detection chain trace:
```
session-init.sh detects "io.f8a.summer" ✓
  → Adds text "· Summer Framework v0.2.3" to context ✓
  → Bootstrap says "load summer-core if detected" ✓
  → BUT: No mechanism force-loads summer-core ✗
  → Agent must parse text + voluntarily load skill ✗
  → Subagents don't even get this text ✗
  → skill-router fires on Edit only (async + stderr) ✗
  → 0/8 agent definitions mention "summer" ✗
```

6 failure points in the chain. Detection succeeds but action never happens.

### RC7 — MEDIUM: Commands Don't Inject Bootstrap Context

**Problem**: When /plan, /spec, /build, /review spawn agents, they pass task-specific context but NOT:
- Bootstrap skill-loading protocol
- Skill registry
- Current workflow phase
- Summer detection result

---

## The Core Insight

> The bootstrap system is like a security guard who writes warnings on sticky notes and puts them in a room nobody enters.

1. **SessionStart injects to main session only** — subagents never see it
2. **All hooks output to stderr** — invisible to agents
3. **All PreToolUse hooks are async** — fire-and-forget
4. **No hook uses exit code 2** — nothing BLOCKS non-compliant behavior
5. **Bootstrap is L4 (lowest authority)** — loses to L1 (agent definitions)
6. **Agents are self-contained** — no need to load external skills
7. **Summer detection is passive** — detected but never acted upon

---

## Recommended Fixes (Priority Order)

### Fix 1 — CRITICAL: Add SubagentStart Hook

```json
// hooks.json
"SubagentStart": [{
  "hooks": [{
    "type": "command",
    "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/subagent-init.sh",
    "timeout": 10
  }]
}]
```

Create `subagent-init.sh` that outputs structured JSON with `additionalContext` containing:
- Compact skill registry (table only)
- Skill loading protocol (3-line instruction)
- Summer detection result (if applicable)
- Current workflow phase

This ensures EVERY subagent gets the enforcement context.

### Fix 2 — CRITICAL: Make Skill-Router Synchronous + Structured JSON

```json
// hooks.json — change async to false
{
  "matcher": "Edit|Write|MultiEdit",
  "hooks": [{
    "type": "command",
    "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/skill-router.sh",
    "timeout": 5,
    "async": false
  }]
}
```

Rewrite skill-router.sh to output structured JSON:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "LOAD SKILL: spring-patterns — read skills/spring-patterns/SKILL.md before proceeding"
  }
}
```

### Fix 3 — CRITICAL: Slim Agents → Defer to Skills

Transform agents from self-contained encyclopedias to lightweight dispatchers:

| Agent | Current | Target | Strategy |
|-------|---------|--------|----------|
| planner | 378 lines | ~120 lines | Remove embedded CQRS/DDD/Hexagonal code → defer to `architecture` skill |
| implementer | 295 lines | ~80 lines | Remove test examples → defer to `testing-workflow` skill |
| reviewer | 384 lines | ~100 lines | Remove 7 embedded checklists → load from skills dynamically |
| database-reviewer | 229 lines | ~60 lines | Remove patterns → defer to `database-patterns` skill |
| build-fixer | 294 lines | ~80 lines | Remove recipes → keep only error resolution flow |
| test-runner | 252 lines | ~80 lines | Remove E2E patterns → defer to `testing-workflow` skill |

### Fix 4 — HIGH: Embed Skill Protocol in Agent Definitions (L1)

Add to EVERY agent definition as the FIRST section after role description:

```markdown
## Before Starting Work (MANDATORY)

1. **Skill Discovery**: For each file you'll modify:
   - Match against skill registry: Controller→spring-patterns, Repository→database-patterns, Test→testing-workflow, etc.
   - Load matching skill: use Skill tool (e.g., `devco-agent-skills:spring-patterns`)
   - Announce: "Using skill: {name} for {reason}"
2. **Summer Check**: If build.gradle contains `io.f8a.summer`, load `devco-agent-skills:summer-core` first
3. **Workflow Phase**: Verify prerequisites for your phase (spec approved? plan approved?)
```

This puts skill enforcement at L1 (system prompt) — maximum authority.

### Fix 5 — HIGH: Active Summer Detection

Modify `session-init.sh` to inject summer-core SKILL.md content directly (same as bootstrap):

```bash
if [ "$SUMMER_DETECTED" = true ]; then
  SUMMER_CORE="${CLAUDE_PLUGIN_ROOT:-}/skills/summer-core/SKILL.md"
  if [ -f "$SUMMER_CORE" ]; then
    SUMMER_CONTENT="$(cat "$SUMMER_CORE" 2>/dev/null || true)"
    CONTEXT="${CONTEXT}${SUMMER_CONTENT}\n\n"
  fi
fi
```

### Fix 6 — MEDIUM: Make Quality-Gate Output Visible

Rewrite quality-gate.sh to output structured JSON with `additionalContext`:

```bash
if [ -n "$VIOLATIONS" ]; then
  echo "{\"hookSpecificOutput\":{\"additionalContext\":\"$VIOLATIONS\"}}"
else
  echo "$DATA"
fi
```

### Fix 7 — MEDIUM: Move Core Bootstrap Rules to L1

Move the essential enforcement rules from bootstrap SKILL.md (L4) to either:
- A new rule file `rules/skill-enforcement.md` (L1 — always loaded)
- Or CLAUDE.md (L1 — always loaded)

Keep bootstrap for dynamic content (project detection, Summer detection) but put the mandatory protocol at L1.

---

## Implementation Priority

| Phase | Fix | Impact | Effort |
|-------|-----|--------|--------|
| **P0** | Fix 4: Embed skill protocol in agent definitions | Immediate L1 enforcement | Low (add ~15 lines to each agent) |
| **P0** | Fix 3: Slim agents → defer to skills | Remove duplication, force skill loading | High (rewrite 6 agents) |
| **P1** | Fix 1: SubagentStart hook | All subagents get context | Medium (new hook + script) |
| **P1** | Fix 5: Active Summer detection | Summer skills auto-loaded | Low (add to session-init.sh) |
| **P2** | Fix 2: Sync skill-router + structured JSON | Agent sees skill suggestions | Medium (rewrite hook output) |
| **P2** | Fix 7: Move rules to L1 | Higher authority enforcement | Low (new rule file) |
| **P3** | Fix 6: Visible quality-gate output | Agent sees violations | Medium (rewrite hook output) |

**Estimated total effort**: P0 fixes alone (agent slimming + embedded protocol) would solve ~70% of the discipline problem. P1 fixes (SubagentStart + Summer) would solve the remaining ~25%.
