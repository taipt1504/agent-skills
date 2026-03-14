# /save-session — Persist Current Session Context

Manually trigger session persistence to save current work context for cross-session continuity.

## What It Does

1. Invokes `scripts/hooks/session-end.sh` to write a structured session file
2. Captures: modified files, test changes, git branch, message count
3. Invokes cost-tracker to log token usage
4. Saves to `.claude/sessions/{date}-{id}-session.md`

## When to Use

- Before a long break — preserve context for later resumption
- After completing a major milestone — checkpoint your progress
- Before `/compact` — ensure state is persisted before context compression
- When switching tasks within a session

## Execution

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/hooks/session-end.sh"
```

## Output

```
Session file saved: .claude/sessions/2026-03-15-abc123-session.md
```

The saved session file will be automatically loaded by `session-start.sh` in the next session (if within 7 days).
