# Hook System (v3.2)

13 lifecycle hooks + 1 utility, all defined in `hooks.json` and executed via `${CLAUDE_PLUGIN_ROOT}`.

## Hook Inventory

| Hook | Event | Responsibility |
|------|-------|---------------|
| `session-init.sh` | SessionStart | Inject bootstrap skill, detect project type, restore session state |
| `session-save.sh` | Stop | Save session summary, persist metrics, learning signals |
| `skill-router.sh` | PreToolUse (Edit/Write/MultiEdit) | File-to-skill matching, suggest relevant skill |
| `git-guard.sh` | PreToolUse (Bash) | Block `git commit/push/rebase/reset --hard` — Hard Block #9 |
| `compact-advisor.sh` | PreToolUse (Edit/Write/MultiEdit) | 3-stage progressive context unloading guidance |
| `quality-gate.sh` | PostToolUse (Edit/Write/MultiEdit) | Compile check + anti-patterns + debug audit + secret scanning |
| `workflow-tracker.sh` | PostToolUse | Track workflow phase transitions (PLAN→SPEC→BUILD→VERIFY→REVIEW) |
| `verify-fix-loop.sh` | PostToolUse | Verify/fix cycle with circuit breaker (max 3 retries) |
| `build-checkpoint.sh` | PostToolUse | Save build state for recovery after compaction |
| `observability-trace.sh` | PostToolUse | Emit structured trace events for session telemetry |
| `pre-compact.sh` | PreCompact | State checkpoint before context compaction |
| `post-compact.sh` | PostCompact | Restore state after context compaction |
| `subagent-init.sh` | SubagentStart | Inject context into spawned sub-agents |
| `run-with-flags.sh` | (utility) | Profile-based hook gating, sourced by all hooks |

## Hook Profiles

Controlled via `.claude/devco-config.json` → `hooks.profile`, or `HOOK_PROFILE` env var. Default: `standard`.

| Profile | Hooks Active | Behavior |
|---------|-------------|----------|
| `off` | None | All hooks disabled — zero overhead |
| `minimal` | session-init, session-save, subagent-init | Lifecycle only, no enforcement |
| `standard` | All 12 hooks | **Default** — quality gates warn on HIGH, block on CRITICAL |
| `strict` | All 12 hooks + `STRICT_MODE=true` | Quality gates block on HIGH violations too |

Disable specific hooks: `DISABLED_HOOKS="verify-fix-loop,observability-trace"` or in config:

```json
{ "hooks": { "profile": "standard", "disabled": ["observability-trace"] } }
```

## How Hooks Work

- All hooks use `${CLAUDE_PLUGIN_ROOT}` for portable paths across machines
- `run-with-flags.sh` provides profile gating — sourced at the top of each hook
- PreToolUse hooks can **block** tool execution by returning `{"decision":"block","reason":"..."}` + exit 2
- PostToolUse hooks can **block** via same protocol (quality-gate.sh blocks on CRITICAL / strict HIGH)
- PostToolUse hooks inject context via `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"..."}}`
- Hooks receive tool input as JSON on stdin (PreToolUse/PostToolUse events)
- Shared dependency detection: `_HAS_PYTHON3`, `_HAS_JQ` exported by `run-with-flags.sh`
- Shared JSON parser: `_json_get "file" "key1" "key2"` (python3 → jq → grep fallback)

## Script Locations

```
scripts/hooks/
├── session-init.sh         # SessionStart: bootstrap + project detection
├── session-save.sh         # Stop: session persist + learning
├── skill-router.sh         # PreToolUse: file-to-skill matching
├── git-guard.sh            # PreToolUse: block agent git operations
├── compact-advisor.sh      # PreToolUse: progressive unloading
├── quality-gate.sh         # PostToolUse: compile + anti-patterns + secrets
├── workflow-tracker.sh     # PostToolUse: phase tracking
├── verify-fix-loop.sh      # PostToolUse: verify/fix cycle
├── build-checkpoint.sh     # PostToolUse: build state snapshots
├── observability-trace.sh  # PostToolUse: structured traces
├── pre-compact.sh          # PreCompact: state checkpoint
├── post-compact.sh         # PostCompact: state restore
├── subagent-init.sh        # SubagentStart: sub-agent context
└── run-with-flags.sh       # Utility: profile gating (sourced, not a hook)
```
