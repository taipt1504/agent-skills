# Hooks System

Lifecycle hook scripts in `scripts/hooks/` run automatically during Claude Code sessions.
Registered in `hooks/hooks.json` (plugin-distributed) and `.claude/settings.json` (project-local).

## Hook Profiles

Hooks are gated by the `HOOK_PROFILE` environment variable. Each hook sources `run-with-flags.sh` at the top — if the hook isn't enabled for the active profile, it exits silently.

| Profile | Hooks Enabled | Use Case |
|---------|---------------|----------|
| `minimal` | session-start, session-end, cost-tracker | Low overhead, CI environments |
| `standard` (default) | + suggest-compact, java-compile-check, check-debug-statements | Normal development |
| `strict` | + java-format, evaluate-session, pre-compact | Full enforcement, pre-release |

Set profile: `export HOOK_PROFILE=strict`

## Hook Types

| Type | When It Fires |
|------|--------------|
| **SessionStart** | Once when Claude Code session begins |
| **PreToolUse** | Before a tool executes (can block or modify) |
| **PostToolUse** | After a tool executes (runs async unless sync flag set) |
| **PreCompact** | Before context compaction |
| **Stop** | At the end of each Claude response turn |

## Active Hooks

### SessionStart

**`session-start.sh`** — Loads project context at session open.
- Detects project type (Spring WebFlux, Spring MVC, Gradle, Maven)
- Loads most recent session file content (< 7 days, max 80 lines) for context continuity
- Queries `claude-mem` for previous session summaries
- Reports git branch, uncommitted changes, last commit
- Prints workflow reminder

### PreToolUse

**`suggest-compact.sh`** — Monitors context window usage.
- Triggers on `Edit|Write|MultiEdit` tool calls (async, 5s timeout)
- Counts total tool calls in session
- Suggests `/compact` when approaching threshold (default: 50 tool calls)
- Repeats every 25 calls after threshold

### PostToolUse

**`java-compile-check.sh`** — Validates Java compilation after edits.
- Triggers on `Edit|Write|MultiEdit` for `*.java` files (sync, 90s timeout)
- Runs `./gradlew compileJava` and reports errors for the edited file
- Passes through stdin JSON unchanged

**`java-format.sh`** — Auto-formats Java source after edits.
- Triggers on `Edit|Write|MultiEdit` for `*.java` files (async, 60s timeout)
- Runs `./gradlew spotlessApply` in background

### PreCompact

**`pre-compact.sh`** — Preserves state before context compression.
- Saves active files snapshot for post-compact recovery
- Writes compaction marker to session log
- Posts to claude-mem if available

### Stop

**`check-debug-statements.sh`** — Scans for debug artifacts.
- Checks modified Java files for `System.out.println`, `e.printStackTrace()`, `@Disabled`
- Prints warnings to stderr (sync, 15s timeout)

**`cost-tracker.sh`** — Token usage and cost tracking.
- Reads stdin JSON for token usage data (async, 10s timeout)
- Appends JSONL to `.claude/sessions/cost-log.jsonl`
- Estimates cost per model tier (opus/sonnet/haiku)
- Warns when daily cost exceeds `$COST_DAILY_THRESHOLD` (default: $5.00)

**`session-end.sh`** — Captures session state.
- Writes structured session summary file (async, 60s timeout)
- Idempotent — skips if session file already written for this session ID
- Invokes cost-tracker inline
- Signals learning extraction for qualifying sessions (>= 10 messages)
- Posts to claude-mem if available

## Unwired Utility (manual execution only)

**`evaluate-session.sh`** — Deep session pattern evaluator.
- NOT wired as a hook — run manually: `bash scripts/hooks/evaluate-session.sh`
- Reads session transcript and counts message depth
- Signals Claude to extract reusable patterns when session is long enough (>= 10 messages)
- Config: `skills/continuous-learning-v2/config.json`

## Hook Registration

Both config files should be kept in sync. The canonical mapping:

| Event | Matcher | Scripts |
|-------|---------|---------|
| SessionStart | `*` | session-start.sh |
| PreToolUse | `Edit\|Write\|MultiEdit` | suggest-compact.sh (async) |
| PostToolUse | `Edit\|Write\|MultiEdit` | java-compile-check.sh + java-format.sh (async) |
| PreCompact | `*` | pre-compact.sh (async) |
| Stop | `*` | check-debug-statements.sh + cost-tracker.sh (async) + session-end.sh (async) |

## Notes

- `$CLAUDE_PROJECT_DIR` is set by Claude Code to the project root when hooks run inside a project
- `${CLAUDE_PLUGIN_ROOT}` is set when hooks are loaded from a plugin installation
- The `hooks[].hooks[]` double-nesting is the correct Claude Code format for hooks with event matchers
- Hook scripts use bash; they must be executable (`chmod +x scripts/hooks/*.sh`)
- All hooks source `run-with-flags.sh` for profile gating
