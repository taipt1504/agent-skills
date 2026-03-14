# Hooks

Event-driven automations that fire before/after Claude Code tool executions. Tailored for Java/Spring WebFlux development — enforcing compile checks, code quality, and session continuity.

## How Hooks Work

```
User request → Claude picks tool → PreToolUse hook → Tool executes → PostToolUse hook
```

- **PreToolUse** — Runs before tool execution. Can **block** (exit 2) or **warn** (stderr).
- **PostToolUse** — Runs after tool completion. Can analyze but not block.
- **PreCompact** — Runs before context compaction. Saves state.
- **SessionStart** — Fires when a new session begins. Loads context.
- **Stop** — Fires after each Claude response. Persists state.

## Available Hooks

### PreToolUse Hooks

| Hook | Matcher | What It Does | Exit Code |
|------|---------|-------------|-----------|
| **Java Compile Check** | `Bash` | Detects `mvn compile` / `gradle build` commands and validates compilation state before execution | 2 (blocks on known compile errors) |
| **Debug Statement Check** | `Bash` | Scans staged `.java` files for `System.out.println`, `e.printStackTrace()`, `@SuppressWarnings` before `git commit` | 2 (blocks if found) |

### PostToolUse Hooks

| Hook | Matcher | What It Does |
|------|---------|-------------|
| **Java Format** | `Write\|Edit\|MultiEdit` | Checks formatting of edited `.java` files using project formatter (google-java-format / spring-javaformat) |

### Lifecycle Hooks

| Hook | Event | What It Does |
|------|-------|-------------|
| **Session Start** | `SessionStart` | Loads previous context, detects Maven/Gradle, restores architectural decisions |
| **Pre-Compact** | `PreCompact` | Saves current task state, architectural decisions, and learnings before compaction |
| **Session End** | `Stop` | Persists session state, saves learnings to context files (async, non-blocking) |

## Hook Scripts

All hook scripts live in `scripts/hooks/`:

```
scripts/hooks/
├── java-compile-check.sh    # Pre-bash: compilation guard
├── check-debug-statements.sh # Pre-bash: debug statement blocker
├── java-format.sh           # Post-edit: format checker
├── pre-compact.sh           # Pre-compact: state saver
├── session-start.sh         # Session start: context loader
└── session-end.sh           # Session end: state persister
```

## Customizing

### Disabling a Hook

Remove or comment out the hook entry in `hooks/hooks.json`.

Or override in your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [],
        "description": "Override: disable compile check"
      }
    ]
  }
}
```

### Writing Your Own Hook

Hooks receive tool input as JSON on stdin and must output JSON on stdout.

```bash
#!/bin/bash
# my-hook.sh
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Warn (non-blocking): write to stderr
echo "[Hook] Warning message" >&2

# Block (PreToolUse only): exit with code 2
# exit 2

# Pass through input
echo "$INPUT"
```

**Exit codes:**
- `0` — Success (continue)
- `2` — Block the tool call (PreToolUse only)
- Other — Error (logged, does not block)

## Related

- [scripts/hooks/](../scripts/hooks/) — Hook script implementations
- [rules/](../rules/) — Coding rules enforced by the plugin
- [schemas/hooks.schema.json](../schemas/hooks.schema.json) — Hook configuration schema
