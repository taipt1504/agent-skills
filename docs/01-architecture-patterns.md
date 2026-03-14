# ECC Architecture Patterns

> How Everything Claude Code organizes its components and the design principles behind them.

---

## Component Taxonomy

ECC defines five primary component types, each with a distinct role:

```
┌─────────────────────────────────────────────────────────┐
│                    User Interaction                       │
│  /plan  /verify  /code-review  /e2e  /orchestrate        │
└──────────────────────┬──────────────────────────────────┘
                       │ Commands invoke
┌──────────────────────▼──────────────────────────────────┐
│                      Agents                               │
│  planner · architect · code-reviewer · tdd-guide          │
│  (lightweight coordinators with scoped tools + model)     │
└──────────────────────┬──────────────────────────────────┘
                       │ Agents reference
┌──────────────────────▼──────────────────────────────────┐
│                      Skills                               │
│  tdd-workflow · security-review · backend-patterns        │
│  (deep knowledge modules with code examples)              │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Rules (always-on, path-scoped guidelines)               │
│  coding-style · security · testing · git-workflow         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Hooks (lifecycle event handlers)                         │
│  PreToolUse · PostToolUse · SessionStart · Stop           │
│  (deterministic enforcement, cannot be ignored)           │
└─────────────────────────────────────────────────────────┘
```

## The Cross-Reference Pattern

A critical design principle: **agents are coordinators, skills are knowledge bases**.

```
tdd-guide agent ──references──► tdd-workflow skill
                                (detailed mocking patterns, framework examples)

security-reviewer agent ──references──► security-review skill
                                        (OWASP checklist, vulnerability patterns)

database-reviewer agent ──references──► postgres-patterns skill
                                        (index patterns, query optimization)

e2e-runner agent ──references──► e2e-testing skill
                                 (Playwright patterns, test structure)
```

**Why this matters:**
- Agents stay concise and action-oriented (~50-150 lines)
- Skills hold comprehensive reference content (~200-500 lines)
- No content duplication between agents and skills
- Each component can be updated independently

## Rules: Always-On Guidelines

Rules use path-scoped YAML frontmatter to apply only to relevant files:

```yaml
---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---
```

Structure:
```
rules/
├── common/           # Universal rules (all languages)
│   ├── coding-style.md
│   ├── git-workflow.md
│   ├── testing.md
│   ├── performance.md
│   ├── patterns.md
│   ├── hooks.md
│   ├── agents.md
│   ├── security.md
│   └── development-workflow.md
├── typescript/       # Each has: coding-style, hooks, patterns, security, testing
├── python/
├── golang/
├── kotlin/
├── swift/
├── perl/
└── php/
```

**Key insight:** Rules are short, imperative, always-loaded. They have no "when to use" — they're unconditional constraints. Keep them minimal to avoid context bloat.

## Contexts: Modal Behavior Injection

Three mode files that change Claude's operating style:

| Context | Behavior |
|---------|----------|
| `dev.md` | Code-first, prefer working over perfect, run tests, atomic commits |
| `research.md` | Read widely, ask questions, document findings, don't write code yet |
| `review.md` | Read thoroughly, prioritize by severity, suggest fixes, check security |

Loaded via `/load contexts/<name>.md` or CLI alias:
```bash
alias claude-dev='claude --system-prompt "$(cat ~/.claude/contexts/dev.md)"'
```

## Directory Conventions

| Convention | Pattern |
|------------|---------|
| Agent files | `agents/agent-name.md` (flat, no subdirectories) |
| Skill directories | `skills/skill-name/SKILL.md` (directory per skill) |
| Command files | `commands/command-name.md` (flat) |
| Rule files | `rules/{language}/{topic}.md` (language-scoped) |
| Hook scripts | `scripts/hooks/{hook-name}.js` (Node.js) |
| Hook config | `hooks/hooks.json` (single config file) |
| MCP configs | `mcp-configs/mcp-servers.json` (single file, copy what you need) |
| Examples | `examples/{project-type}-CLAUDE.md` |
| Schemas | `schemas/{component}.schema.json` |

## Plugin Manifest (plugin.json)

Critical lessons from ECC's documented pitfalls:

```json
{
  "version": "1.1.0",
  "agents": [
    "./agents/planner.md",
    "./agents/code-reviewer.md"
  ],
  "commands": ["./commands/"],
  "skills": ["./skills/"]
}
```

**Rules:**
- `version` is MANDATORY
- `agents`, `commands`, `skills`, `hooks` MUST be arrays
- `agents` MUST use explicit file paths (not directory paths)
- `commands` and `skills` accept directory paths wrapped in arrays
- Do NOT add `hooks` field — `hooks/hooks.json` is auto-loaded by convention

## Quality Assurance

ECC validates all components with CI scripts:

```
scripts/ci/
├── validate-agents.js     # Checks frontmatter, required fields
├── validate-commands.js   # Checks command format
├── validate-rules.js      # Checks rule structure
├── validate-skills.js     # Checks SKILL.md format
├── validate-hooks.js      # Checks hook config
├── validate-no-personal-paths.js  # No hardcoded paths
└── catalog.js             # Generates component catalog
```

**Takeaway for our plugin:** We should add similar validation scripts to catch structural issues in our agents, skills, and commands.
