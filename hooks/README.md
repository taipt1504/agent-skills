# Hook System (v3.0)

6 lifecycle hooks + 1 utility, all defined in `hooks.json` and executed via `${CLAUDE_PLUGIN_ROOT}`.

## Hook Inventory

| Hook | Event | Responsibility |
|------|-------|---------------|
| `session-init.sh` | SessionStart | Inject bootstrap skill, detect project type, restore L2 memory |
| `session-save.sh` | Stop | Save session summary, persist files list, learning signals |
| `skill-router.sh` | PreToolUse (Edit/Write/MultiEdit) | File-to-skill matching, suggest relevant skill |
| `quality-gate.sh` | PostToolUse (Edit/Write/MultiEdit) | Java compile check + debug statement audit |
| `compact-advisor.sh` | PreToolUse (Edit/Write/MultiEdit) | 3-stage progressive unloading guidance |
| `pre-compact.sh` | PreCompact | State checkpoint before context compaction |
| `run-with-flags.sh` | (utility) | Profile-based hook gating, sourced by all hooks |

## Hook Profiles

Controlled via `HOOK_PROFILE` env var.

| Profile | Hooks Active | Default |
|---------|-------------|---------|
| `minimal` | session-init, session-save | |
| `standard` | + skill-router, quality-gate, compact-advisor | yes |
| `strict` | + pre-compact | |

## hooks.json Configuration

Source of truth for hook registration. Claude Code auto-discovers this file on plugin install.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/session-init.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/skill-router.sh",
            "timeout": 5,
            "async": true
          },
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/compact-advisor.sh",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/quality-gate.sh",
            "timeout": 90
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/pre-compact.sh",
            "timeout": 30,
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/session-save.sh",
            "timeout": 60,
            "async": true
          }
        ]
      }
    ]
  }
}
```

## How Hooks Work

- All hooks use `${CLAUDE_PLUGIN_ROOT}` for portable paths across machines
- All hooks exit 0 -- they never block the agent
- stderr for logging, stdout for context injection (`session-init.sh` only)
- `run-with-flags.sh` provides profile gating -- sourced at the top of each hook to check `HOOK_PROFILE`
- Hooks receive tool input as JSON on stdin (PreToolUse/PostToolUse events)
- `/setup` writes equivalent paths to `.claude/settings.json` using `$CLAUDE_PROJECT_DIR` as a fallback

## Script Locations

```
scripts/hooks/
+-- session-init.sh       # SessionStart: bootstrap + memory restore
+-- session-save.sh       # Stop: session persist + learning
+-- skill-router.sh       # PreToolUse: file-to-skill matching
+-- quality-gate.sh       # PostToolUse: compile + debug audit
+-- compact-advisor.sh    # PreToolUse: progressive unloading
+-- pre-compact.sh        # PreCompact: state checkpoint
+-- run-with-flags.sh     # Utility: profile gating (sourced, not a hook)
```
