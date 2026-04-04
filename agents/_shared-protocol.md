# Shared Agent Protocol

> This file defines the common protocol that ALL agents follow.
> Agent-specific `.md` files reference this via: `protocol: _shared-protocol.md`
> The SubagentStart hook (`subagent-init.sh`) injects this protocol automatically.

---

## First Action (MANDATORY — before any work)

1. **Announce loaded skills** to user: "**Skills loaded**: {list your requiredSkills.always}"
2. If conditional skills activated based on project profile: "**Conditional**: {list}"
3. Read `.claude/devco-config.json` for runtime config (mode, autoVerify, autoReview, team settings)
4. Read `.claude/project-profile.json` for project context (springType, dependencies, Java version)

## Loaded Skills (auto-injected by SubagentStart hook)

The following skills have been pre-loaded based on your role and project profile.
You MUST apply their patterns in every file operation.

### Skill Usage Protocol (MANDATORY — no exceptions)

1. Before EVERY file edit: identify which loaded skill applies
2. Announce: "Applying skill: {name} — {specific pattern being applied}"
3. If no skill matches: state "No matching skill — using general Java/Spring knowledge"
4. If you need a skill NOT in the loaded list: request it via "SKILL_REQUEST: {name}"

## Skill Usage Report (MANDATORY — output at task end)

Before completing, output this table filled with actual usage:

| Skill | Times Applied | Key Patterns Used |
|-------|--------------|-------------------|
| {skill} | {count} | {patterns} |

## Memory (Automatic Learning)

**Before work**: `mcp__memory__search_nodes` for entities related to files/services you'll work with.
**After work**: `mcp__memory__create_entities` for new decisions/patterns discovered. `mcp__memory__add_observations` to update existing entities with new evidence.

Entity naming: PascalCase for services/tech (e.g., OrderService, PostgreSQL), kebab-case for decisions/patterns (e.g., chose-cqrs-over-crud, n-plus-one-fix).

## Workflow Context

All agents operate within the 5-phase SDD workflow: **PLAN → SPEC → BUILD → VERIFY → REVIEW**.
Your phase is declared in your agent frontmatter. Stay within your phase's responsibilities.

## Hard Rules (apply to ALL agents)

1. **Never** use `.block()` in reactive code (CRITICAL)
2. **Never** use `@Autowired` field injection — use `@RequiredArgsConstructor`
3. **Never** expose entities in API responses — use record DTOs
4. **Never** log sensitive data (PII, credentials, tokens)
5. **Never** commit secrets to git
6. **Never** skip input validation on API boundaries
7. **Never** use `SELECT *` — explicit column selection
8. **Never** commit to git — only the user commits (Hard Block #9)
9. **Never** stop at BUILD — drive to VERIFY + REVIEW
10. **Never** self-assess — only external verification (tests, compile, lint) counts
