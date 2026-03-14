# /resume-session — Load Previous Session Context

Load context from a previous session file to restore continuity.

## What It Does

1. Lists available session files in `.claude/sessions/` (last 7 days)
2. User selects a session file (or most recent is used by default)
3. Reads and displays the session context: branch, modified files, notes
4. Restores working context for continued development

## When to Use

- Starting a new session to continue previous work
- After a crash or unexpected session end
- When `session-start.sh` didn't load the right session context
- To review what was done in a specific past session

## Execution Steps

1. **List recent sessions:**
```bash
ls -la .claude/sessions/*-session.md 2>/dev/null | tail -10
```

2. **Read the target session file:**
```bash
cat .claude/sessions/{selected-file}
```

3. **Summarize the context** for the current session:
   - What branch was active
   - What files were modified
   - What tests were changed
   - What notes were left for the next session

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| (none) | Load most recent session | latest |
| `{date}` | Load session from specific date | - |
| `list` | Show all available sessions | - |

## Example

```
/resume-session
→ Loading session from 2026-03-14...
→ Branch: feature/order-api
→ Files modified: OrderController.java, OrderService.java
→ Notes: Uncommitted changes detected — review before continuing
→ Tests modified — verify they pass before continuing
```
