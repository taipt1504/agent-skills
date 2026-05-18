# Shared Agent Protocol (v4.0)

> Common protocol ALL agents follow. Referenced via `protocol: _shared-protocol.md` frontmatter.
> SubagentStart hook (`subagent-init.sh`) injects this protocol + pre-flight artifact + cross-cutting (split shape) automatically.

---

## First Action (MANDATORY — before any work)

1. **Read pre-flight** at `.claude/memory/preflight/<gate>-<latest>.md` (variant per gate). Apply 1% rule.
2. **Read lane** from `.claude/memory/state/current-triage.json` → adapt behavior per lane.
3. **Announce skills loaded** (pre-flight APPLY list + requiredSkills):
   `Skills loaded: <comma-separated>`
4. **Conditional skills** per project profile:
   `Conditional: <list>`
5. Read `.claude/devco-config.json` — runtime config (mode, autoVerify, autoReview, team settings)
6. Read `.claude/project-profile.json` — project context (springType, dependencies, summer flag)

## 1% Rule (every gate — non-negotiable)

Before EVERY gate (Triage, Align, Brainstorm, Plan, Spec, Execute, Review):

- Enumerate ALL skills + rules with ≥1% relevance
- Score each (90-100% / 60-89% / 30-59% / 1-29% / 0%)
- APPLY or SKIP per item
- SKIP requires concrete evidence (grep result, file path, missing dep — NOT "not relevant")
- Over-enumerate: false positive << false negative cost

`scripts/hooks/preflight-discovery.sh` enumerates filesystem. `rules/summer/*` loaded only if `summer:true` in project-profile.json.

## Skill Announcement Contract

Applying skill/rule:
1. Announce: `Applying skill: <name> — <pattern>` OR `Apply rule: <path> — <reason>`
2. Cite in result summary
3. No `skills-loaded.json` gate (removed v4.0) — announcement IS the contract

No match: `No matching skill — using general Java/Spring knowledge`.
Need skill not in pre-flight APPLY: `SKILL_REQUEST: <name>` + justification.

## Plan/Spec Shape Awareness (HARD BLOCK)

Single-file (≤2 slices) or split (3+). Templates: `templates/{PLAN,SPEC}_{TEMPLATE,INDEX_TEMPLATE,SLICE_TEMPLATE}.md`.

Before executing:

1. **Validate conformance** — `bash scripts/ci/validate-plan-spec-templates.sh --plan <path> --spec <path>`
2. Fails → STOP, route back to planner/spec-writer
3. **Split:** read ONLY assigned slice + `spec_index §1` cross-cutting. No other slice files (context pollution).
4. **Cross-cutting override** in slice → forbidden without ADR

## Workflow Context (5-Layer Adaptive)

```
REQ → BOOT → PREFLIGHT0 → TRIAGE
                            ├── trivial → EXECUTE (light) → REVIEW (S2) → COMMIT
                            └── standard / high-stakes →
                                ALIGN → BRAINSTORM (if needed) → PLAN → SPEC →
                                EXECUTE (subagent per slice) → REVIEW (S1+S2) → LEARN → COMMIT
```

Your phase declared in agent frontmatter. Stay within phase responsibilities. Pre-flight runs before every gate.

## Skill Usage Report (MANDATORY at task end)

| Skill | Times Applied | Key Patterns Used |
|---|---|---|
| <skill> | <count> | <patterns> |

| Rule | Applied? | Evidence |
|---|---|---|
| <rule> | yes/no | <one-line> |

## Memory (Automatic Learning)

- **Native auto-memory (primary):** Claude writes to `~/.claude/projects/<project>/memory/MEMORY.md`. Cap: 200 lines/25KB auto-loaded; topic files load on-demand via Read.
- **MCP memory (optional):** `mcp__memory__search_nodes` before work + `mcp__memory__create_entities` after. Degrades to filesystem-only if absent.
- **Pattern observations:** appended to `.claude/memory/shared/pattern-observations.jsonl` during session
- **Session end:** `evolution-check.sh` → promotion candidates in `.claude/memory/shared/promotion-candidates.md` → `/meta evolve` OR `remember: <pattern>`

Entity naming: PascalCase (OrderService, PostgreSQL); kebab-case for decisions (chose-cqrs-over-crud, n-plus-one-fix).

## Hard Rules (apply to ALL agents — match CLAUDE.md hard blocks)

1. NEVER `.block()` in reactive code → CRITICAL
2. NEVER `@Autowired` field injection — use `@RequiredArgsConstructor`
3. NEVER expose entities in API — use record DTOs
4. NEVER log sensitive data (PII, credentials, tokens)
5. NEVER commit secrets to git
6. NEVER skip input validation at API boundaries
7. NEVER `SELECT *` — explicit columns
8. NEVER commit to git — only user commits (CLAUDE.md hard block #9)
9. NEVER stop at BUILD — drive to VERIFY + REVIEW
10. NEVER self-assess — only external verification (tests, compile, lint) counts
11. NEVER write plan/spec missing required template sections → workflow violation
12. NEVER override cross-cutting in spec slice without ADR
13. NEVER dispatch slices when split plan/spec status is `PARTIALLY_APPROVED` — full approval required

## Lane-Aware Behavior

| Lane | Pre-flight format | Plan/Spec | Review |
|---|---|---|---|
| Trivial | Light (3-5 lines) | Skipped | Stage 2 only |
| Standard | Full artifact | Required | Stage 1 + Stage 2 |
| High-stakes | Full artifact | Required + ADR | Stage 1 + Stage 2 (security deep-dive) |

Read lane from `current-triage.json`. Adjust enumeration depth + verification rigor accordingly.

## Subagent Dispatch Context (Execute gate)

If subagent (slice-executor, reviewer):
- Orchestrator passes per-slice paths (split) or whole-file paths (single-file)
- Pre-flight 4/5 artifact auto-injected by `subagent-init.sh`
- `spec_index §1` cross-cutting auto-injected (split shape)
- Report results to orchestrator — do NOT commit

## Verification External (NEVER Self-Assess)

Tests, compile, lint, security scan determine PASS/FAIL. Hooks run automatically:
- `quality-gate.sh` — compile + format after Edit
- `verify-fix-loop.sh` — auto-retry on failure
- `evolution-check.sh` — Stop hook, instinct promotion scan

External verification declares "passed" — not you.
