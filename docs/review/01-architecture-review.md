# Plugin Architecture Review

> **Reviewer**: arch-reviewer | **Grade**: B+ (Strong)
> **Scope**: Plugin code only. `docs/` excluded (document storage, not plugin structure).

---

## 1. Directory Structure & Organization

### Current Structure (Plugin Code Only)

```
agent-skills/
├── .claude-plugin/     # Plugin metadata (plugin.json, marketplace.json)
├── .claude/            # Dev-time skills (skill-creator, agent-development) + settings
├── agents/             # 8 agent definitions (.md)
├── commands/           # 12 slash commands (.md)
├── hooks/              # hooks.json (Claude Code hook config)
├── mcp-configs/        # MCP server configs (core/, optional/, productivity/)
├── rules/              # 9 rule files (.md)
├── schemas/            # JSON schema for hooks
├── scripts/            # hooks/, memory/, ci/, setup.sh
├── skills/             # 18 skills — FLAT structure (v3.0 completed)
│   ├── bootstrap/      #   core enforcement engine
│   ├── spring-patterns/#   Spring MVC/WebFlux
│   ├── database-patterns/# DB patterns
│   ├── summer-core/    #   Summer gate skill
│   ├── ...             #   (all skills at same level)
│   └── testing-workflow/#  TDD + verification
└── templates/          # PROJECT_GUIDELINES_TEMPLATE.md
```

> **Key**: Skills are **flat** since v3.0 — all 18 skills live directly under `skills/`. No `skills/generic/`, `skills/summer/`, or `skills/meta/` subdirectories.

### Strengths
- **Flat skill structure** — all 18 skills at `skills/{name}/SKILL.md`, clean and simple
- Clear separation of agents, commands, rules, skills at root level
- MCP configs categorized (core/, optional/, productivity/)
- CI validation scripts in `scripts/ci/`
- Dev-only skills isolated in `.claude/skills/` (not shipped to users)

### Path Remnants (3 files still reference old nested structure)

These are log/display issues — the actual skill routing logic works correctly:

1. **skill-router.sh:82-83** — stderr log message uses `skills/generic/$SKILL/SKILL.md` and `skills/summer/$SKILL/SKILL.md` (cosmetic — routing itself is correct)
2. **status.md:111-148** — scans for `skills/generic/`, `skills/summer/`, `skills/meta/` directories that don't exist → **functional bug** (reports 0 skills)
3. **test-runner.md:157** — instruction says `Read skills/generic/testing-workflow/references/blackbox-test.md` → **functional bug** (agent reads wrong path)

### Recommendations
- Fix status.md to scan flat `skills/*/SKILL.md`
- Fix test-runner.md path to `skills/testing-workflow/references/blackbox-test.md`
- Fix skill-router.sh log path to `skills/$SKILL/SKILL.md`

---

## 2. Plugin Configuration

| File | Quality | Notes |
|------|---------|-------|
| `plugin.json` | Good | Clean metadata, missing `$schema` |
| `marketplace.json` | Good | Proper `$schema`, keyword-rich |
| `package.json` | Good | `files` array, `postinstall`, scripts |
| `.mcp.json` | OK | Empty `mcpServers: {}` — templates in `mcp-configs/` |
| `CLAUDE.md` | Excellent | ~400 tokens, passive by design |

### Issue
Package name inconsistency: `plugin.json` → `devco-agent-skills`, `package.json` → `@devco/agent-skills`

---

## 3. 3-Tier Lazy Loading

| Tier | Content | When | Token Budget |
|------|---------|------|-------------|
| **1 (Always)** | CLAUDE.md + 9 rules + bootstrap | Session start | ~5,050 tokens |
| **2 (On-demand)** | 17 SKILL.md files | File edit triggers | ~800 each |
| **3 (Deep ref)** | `references/*.md` | Explicit need | 3-32KB each |

### Strengths
- Auto-loaded ≤5K tokens — well-calibrated
- Skill bodies ≤800 tokens — consistent
- 15K max-with-lazy-load budget is realistic
- Bootstrap-as-enforcement-engine via SessionStart hook is brilliant
- Profile-based hook gating (minimal/standard/strict) is excellent UX
- 3-stage compact advisor prevents context rot

### Weaknesses
- Tier 1 budget (~5,050) slightly over 5K target
- Skill router is filename-based, misses content routing on new files
- No explicit skill unloading mechanism

---

## 4. Token Cost Analysis

| Component | Count | Avg Size | Est. Tokens | When |
|-----------|-------|----------|-------------|------|
| CLAUDE.md | 1 | 2.2KB | ~400 | Always |
| Rules | 9 | 1.6KB | ~3,150 | Always |
| Bootstrap | 1 | 5.4KB | ~1,500 | Session start |
| **Tier 1 Total** | | | **~5,050** | |
| Skills (each) | 17 | 4.1KB | ~800 | On-demand |
| References (each) | ~30 | 10.5KB | ~2,500 | Deep reference |
| Agent prompts (each) | 8 | 8.8KB | ~2,200 | Subagent spawn |

### Largest Reference Files (risk)
- `spring-webflux.md`: 32.6KB (~8,000 tokens)
- `security-patterns.md`: 21.7KB (~5,400 tokens)
- `kafka.md`: 19.8KB (~4,950 tokens)

### Recommendations
- Add CI check: SKILL.md ≤5KB, reference ≤15KB
- Compress/split largest references
- Monitor Tier 1 budget growth

---

## 5. Cross-Cutting Issues

### Content Duplication

| Concept | Duplicated In |
|---------|--------------|
| 5-phase workflow | bootstrap, development-workflow rule, CLAUDE.md |
| Spec templates | spec-writer agent, /spec command |
| TDD cycle | implementer, /build, testing rule, testing-workflow skill |
| .block() prohibition | CLAUDE.md, architecture rule, spring-patterns skill, reviewer |
| Constructor injection | CLAUDE.md, coding-style rule, spring-patterns skill, reviewer |

**Estimated waste: ~2,000-3,000 tokens**

### Inconsistencies Found
1. **Path remnants** — 3 files still reference old nested skill paths (see §1 above)
2. **Implementer model** — opus in `agents/implementer.md`, sonnet in `commands/build.md`
3. **Hook profile default** — `run-with-flags.sh` defaults to standard, `commands/status.md` defaults to strict
4. **Package naming** — `devco-agent-skills` in plugin.json vs `@devco/agent-skills` in package.json

---

## Overall

**Grade: B+** — Exceptional understanding of LLM context management. The 3-tier loading, bootstrap enforcement, and profile gating are impressive. Main issues are post-v3.0 path cleanup and content duplication.
