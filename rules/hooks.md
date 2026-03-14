# Hooks System

Lifecycle hook scripts in `scripts/hooks/` run automatically during Claude Code sessions.
Registered in `~/.claude/settings.json`.

## Hook Types

| Type | When It Fires |
|------|--------------|
| **SessionStart** | Once when Claude Code session begins |
| **PreToolUse** | Before a tool executes (can block or modify) |
| **PostToolUse** | After a tool executes (runs async unless sync flag set) |
| **PreCompact** | Before context compaction |
| **Stop** | At the end of each Claude response turn |

## Active Hooks (wired in settings.json)

### SessionStart

**`session-start.sh`** — Loads project context at session open.
- Runs `git status` and recent commit log
- Detects project type (Spring WebFlux, Spring MVC, etc.)
- Queries `claude-mem` for previous session summaries and unresolved blockers
- Prints 6-phase workflow reminder

### PreToolUse

**`suggest-compact.sh`** — Monitors context window usage.
- Triggers on `Edit` and `Write` tool calls
- Counts total tool calls in session
- Suggests `/compact` when approaching threshold (default: 50 tool calls)
- Helps preserve context for remaining work in long sessions

### PostToolUse

**`java-compile-check.sh`** — Validates Java compilation after edits.
- Triggers on `Edit` and `Write` tool calls to `*.java` files
- Runs `./gradlew compileJava` (90-second timeout, synchronous)
- Blocks if compilation fails — forces fix before proceeding
- Skips if no Gradle wrapper found

**`java-format.sh`** — Auto-formats Java source after edits.
- Triggers on `Edit` and `Write` tool calls to `*.java` files
- Runs `./gradlew spotlessApply` (60-second timeout, async)
- Applies Google Java Format conventions
- Does not block — runs in background

### PreCompact

**`pre-compact.sh`** — Preserves state before context compression.
- Saves list of currently modified files
- Writes current workflow phase checkpoint
- Ensures important context survives `/compact`

### Stop

**`check-debug-statements.sh`** — Scans for debug artifacts before response ends.
- Checks all Java files modified this session
- Flags: `System.out.println`, `e.printStackTrace()`, `TODO:`, `FIXME:`
- Prints warnings to stderr — does not block, but surfaces issues

**`session-end.sh`** — Captures session state at response end.
- Writes session summary file (timestamps, modified files, commands run)
- Signals `continuous-learning-v2` observer to score session for extractable patterns
- Note: Stop fires at end of each response; sufficient for end-of-session capture

## Unwired Utility (manual execution only)

**`evaluate-session.sh`** — Deep session pattern evaluator.
- NOT wired as a hook — run manually: `bash scripts/hooks/evaluate-session.sh`
- Reads session transcript and counts message depth
- Signals Claude to extract reusable patterns when session is long enough (≥10 messages)
- Config: `skills/continuous-learning-v2/config.json`

## Hook Registration Example

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/hooks/session-start.sh" }] }
    ],
    "PreToolUse": [
      { "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/hooks/suggest-compact.sh" }] }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/hooks/java-compile-check.sh" },
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/hooks/java-format.sh" }
        ]
      }
    ],
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/hooks/pre-compact.sh" }] }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/hooks/check-debug-statements.sh" },
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/hooks/session-end.sh" }
        ]
      }
    ]
  }
}
```

## Notes

- `$CLAUDE_PROJECT_DIR` is set by Claude Code to the project root when hooks run inside a project
- The `hooks[].hooks[]` double-nesting is the correct Claude Code format for hooks with event matchers
- Hook scripts use bash; they must be executable (`chmod +x scripts/hooks/*.sh`)
