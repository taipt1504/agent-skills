# Performance Optimization

## Model Selection Strategy

**`claude-haiku-4-5`** (lightweight, cost-efficient):

- Lightweight agents with frequent invocation
- Pair programming and code generation
- Worker agents in multi-agent systems
- Simple search, grep, or read tasks

**`claude-sonnet-4-6`** (best for coding — default):

- Main development work
- Orchestrating multi-agent workflows
- Complex coding tasks
- Most agent definitions should default to this

**`claude-opus-4-6`** (deepest reasoning):

- Complex architectural decisions
- Maximum reasoning requirements
- Research and analysis tasks
- Use sparingly — highest cost

## Context Window Management

Avoid last 20% of context window for:

- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:

- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

Use `/compact` at strategic workflow boundaries (e.g., after PLAN phase, after each BUILD step).
The `suggest-compact.sh` hook automatically suggests this when approaching the threshold.

## Ultrathink + Plan Mode

For complex tasks requiring deep reasoning:

1. Use `ultrathink` for enhanced thinking
2. Enable **Plan Mode** for structured approach
3. "Rev the engine" with multiple critique rounds
4. Use split role sub-agents for diverse analysis

## Token Budget Optimization

### Auto-Compact Threshold

Set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` to trigger auto-compaction earlier, preserving more room for complex tasks.

### Lazy Skill Loading

Skills are loaded on-demand via `/load` or agent references. Do NOT preload all skills at session start — this wastes context window. Let the hook system and agent descriptions handle routing.

### Context Budget Rules

- Keep CLAUDE.md under 200 lines (tables, not prose)
- Skills: load only when the task matches "When to Activate" criteria
- Agent descriptions: concise (under 3 lines) with clear trigger keywords
- Use `/compact` at phase boundaries: after PLAN, after each BUILD step

## Build Troubleshooting

If build fails:

1. Use **build-error-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix
