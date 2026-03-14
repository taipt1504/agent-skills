# Everything Claude Code (ECC) - Deep Dive Analysis

> Research report synthesized from deep analysis of the `everything-claude-code` repository.
> Purpose: Extract best practices and patterns to inform building our own Claude Code plugin.

---

## What is ECC?

**Everything Claude Code** is a production-ready Claude Code plugin created by Affaan Mustafa (@affaanmustafa), built over 10+ months of intensive daily use. It won the Anthropic hackathon and has grown to 50K+ GitHub stars. Published as npm package `ecc-universal` (v1.8.0), it is cross-compatible with Claude Code, Cursor, OpenCode, Codex, and Antigravity.

## Repository Scale

| Metric | Count |
|--------|-------|
| Total files | 1,041 |
| Markdown files | 827 |
| Skills | 94 |
| Agents | 18 |
| Commands | 48 |
| Hook scripts | 25 |
| Rule files | ~45 (common + 7 languages) |
| MCP configs | 22 servers |
| Tests | 997 passing |

## Core Architecture

```
everything-claude-code/
├── agents/          # 18 specialized subagents (.md with YAML frontmatter)
├── skills/          # 94 domain knowledge modules (SKILL.md per directory)
├── commands/        # 48 slash commands (.md files)
├── hooks/           # hooks.json trigger definitions
├── rules/           # Always-on guidelines (common/ + language-specific/)
├── scripts/hooks/   # 25 Node.js hook implementation scripts
├── scripts/lib/     # Shared utilities
├── scripts/ci/      # Validation scripts for all component types
├── mcp-configs/     # 22 MCP server configurations
├── contexts/        # 3 mode injectors (dev, review, research)
├── examples/        # CLAUDE.md templates for various project types
├── schemas/         # JSON schemas for hooks, plugins, package-manager
├── tests/           # Automated test suite
└── docs/            # Architecture, token optimization, learning specs
```

## Documents in This Series

| Document | Content |
|----------|---------|
| [01-architecture-patterns](./01-architecture-patterns.md) | Component taxonomy, layering, cross-referencing |
| [02-skill-design-guide](./02-skill-design-guide.md) | Skill structure, frontmatter, content patterns |
| [03-agent-design-guide](./03-agent-design-guide.md) | Agent structure, model selection, tool scoping |
| [04-command-hook-patterns](./04-command-hook-patterns.md) | Commands, hooks, lifecycle events |
| [05-prompt-engineering](./05-prompt-engineering.md) | Prompt techniques, trigger tables, guardrails |
| [06-multi-agent-orchestration](./06-multi-agent-orchestration.md) | Orchestration patterns, pipelines, DAGs |
| [07-token-optimization](./07-token-optimization.md) | Token economics, context management, compaction |
| [08-security-patterns](./08-security-patterns.md) | Attack vectors, sandboxing, AgentShield |
| [09-continuous-learning](./09-continuous-learning.md) | Memory persistence, instincts, evolution |

## Key Takeaways for Our Plugin

### 1. Component Separation is Critical
Skills hold **deep knowledge** (reference content, code examples, checklists). Agents are **lightweight coordinators** that reference skills. Commands are **user-facing entry points** that invoke agents. This separation prevents duplication and keeps each component focused.

### 2. Hooks > Prompts for Reliability
"LLMs forget instructions ~20% of the time. PostToolUse hooks enforce checklists at the tool level." Hooks provide deterministic enforcement that prompt instructions cannot guarantee.

### 3. Token Economics Matter
Keep CLAUDE.md lean. Use trigger-table lazy loading for skills. Keep MCP count under 10. Use `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` instead of default 95%. Route to cheaper models (Haiku for simple tasks, Sonnet for coding, Opus for complex reasoning).

### 4. Test Your Plugin Configuration
ECC has 997 automated tests validating agents, commands, rules, skills, and hooks. Validation scripts in `scripts/ci/` catch structural issues before they reach users.

### 5. Cross-Reference, Don't Duplicate
Agents reference skills: "For detailed patterns, see skill: `skill-name`." Commands invoke agents. This creates a clean dependency graph and keeps each component small.

### 6. Profile-Based Hook Gating
`ECC_HOOK_PROFILE=minimal|standard|strict` controls which hooks run. Individual hooks can be disabled via `ECC_DISABLED_HOOKS`. This prevents hook fatigue in different usage contexts.

### 7. Eval-Driven Development
Treat evals as "unit tests of AI development." Define success criteria before implementation. Use pass@k (at least one success) and pass^k (all succeed) metrics.

---

## Comparison: ECC vs Our Plugin (agent-skills)

| Aspect | ECC | agent-skills |
|--------|-----|-------------|
| Focus | Universal (7+ languages) | Java Spring (WebFlux + MVC) |
| Skills | 94 (broad) | ~20 (deep, domain-specific) |
| Agents | 18 (language-agnostic) | 16 (Java/Spring-specific) |
| Commands | 48 | 14 |
| Hook runtime | Node.js | Shell/Node.js |
| Learning | v1 + v2 (instincts) | v2 (instincts) |
| Orchestration | tmux + worktrees | Sequential |
| MCP configs | 22 servers | Per-project |
| Testing | 997 automated tests | Manual |
| Cross-harness | Claude/Cursor/Codex/OpenCode | Claude Code only |

### What We Can Adopt
1. **Validation scripts** for our agents/skills/commands
2. **Hook profile gating** pattern
3. **Structured handoff documents** for multi-agent workflows
4. **Eval-driven development** framework
5. **Session persistence** via hooks
6. **Plugin.json best practices** from ECC's documented pitfalls
7. **Contexts** (dev/review/research modes) - we already have this
8. **Strategic compaction** patterns for token management
