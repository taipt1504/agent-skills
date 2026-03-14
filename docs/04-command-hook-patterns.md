# Command and Hook Patterns

> How ECC structures commands and hooks for maximum effectiveness.

---

## Part 1: Commands

### File Format

Commands are Markdown files in `commands/` with optional YAML frontmatter:

```markdown
---
description: Brief description shown in /help listing
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]  # optional
---

# Command Name

Instructions for what to do when this command is invoked.
```

### Two Command Styles

**Style 1: Minimal (Instruction-focused)**

Good for simple commands that just need clear instructions:

```markdown
---
description: Run build verification pipeline
---

# /verify

Run the following verification steps in order:

1. Run `./gradlew clean build` — must pass
2. Run `./gradlew test` — must pass with 80%+ coverage
3. Run `./gradlew spotlessCheck` — must pass
4. Check for `.block()` calls in reactive code — must be zero
5. Run `git status` to show uncommitted changes
6. Report results as a summary table
```

**Style 2: Full Documentation**

Good for complex commands with arguments and workflows:

```markdown
---
description: Create implementation plan for a feature or task
---

# /plan

## Purpose
Create a structured implementation plan before writing code.

## Usage
/plan [description of feature/task]

## Workflow
1. Restate the requirements in your own words
2. Identify risks and edge cases
3. Break into phases with clear deliverables
4. Estimate complexity per phase
5. Present plan and wait for user approval

## Output Format
### Phase 1: [Name]
- **Deliverable:** ...
- **Files:** ...
- **Risk:** ...

## Related
- Agent: `planner` (invoked internally)
- Skill: `tdd-workflow` (for test planning phase)
```

### Command Design Patterns

| Pattern | Description | Example |
|---------|-------------|---------|
| Agent delegation | Command invokes a specialized agent | `/plan` invokes `planner` agent |
| Multi-step pipeline | Sequential verification steps | `/verify` runs build → test → lint → security |
| Argument forwarding | `$ARGUMENTS` placeholder | `/code-review $ARGUMENTS` passes user input |
| Orchestration | Multiple agents in sequence | `/orchestrate` chains planner → tdd → reviewer |

### Key Commands from ECC (Worth Adopting)

| Command | What it Does | Why it's Valuable |
|---------|-------------|-------------------|
| `/plan` | Requirement restatement → risk → implementation plan | Prevents "code without thinking" |
| `/verify` | Build → typecheck → lint → tests → security scan | Single command for full verification |
| `/code-review` | Review uncommitted changes with severity classification | Quality gate before commit |
| `/checkpoint` | Create named checkpoint with git SHA | Track workflow phases |
| `/orchestrate` | Sequential multi-agent workflow | Complex tasks with handoffs |
| `/quality-gate` | All reviewers + coverage check | Final check before PR |
| `/build-fix` | Incrementally fix build errors | Minimal-diff error resolution |
| `/learn` | Extract patterns from current session | Continuous improvement |
| `/eval` | Eval-driven development framework | Measure AI quality |

---

## Part 2: Hooks

### Hook Architecture

ECC uses a `hooks.json` file for configuration, with Node.js scripts for implementation:

```
hooks/
└── hooks.json        # Trigger definitions (which events, which matchers)

scripts/hooks/
├── session-start.js      # Load previous context
├── session-end.js        # Persist session state
├── evaluate-session.js   # Extract patterns
├── suggest-compact.js    # Strategic compaction
├── pre-compact.js        # Save state before compaction
├── post-edit-format.js   # Auto-format after edits
├── quality-gate.js       # Quality checks after edits
├── cost-tracker.js       # Token/cost metrics
└── run-with-flags.js     # Profile-based gating wrapper
```

### hooks.json Structure

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/script.js\"",
            "async": true,
            "timeout": 30
          }
        ],
        "description": "Human-readable description"
      }
    ],
    "PostToolUse": [...],
    "PreCompact": [...],
    "SessionStart": [...],
    "Stop": [...],
    "SessionEnd": [...]
  }
}
```

### Lifecycle Events

| Event | When | Use Case |
|-------|------|----------|
| `PreToolUse` | Before a tool runs | Block dangerous ops, warn, validate |
| `PostToolUse` | After a tool completes | Auto-format, type-check, quality gates |
| `PreCompact` | Before context compaction | Save state that would be lost |
| `SessionStart` | Session begins | Load previous context, detect project |
| `Stop` | After each response | Audit, persist session, evaluate |
| `SessionEnd` | Session terminates | Final cleanup, metrics |

### Matcher Patterns

```json
"Bash"                    // Single tool
"Edit|Write|MultiEdit"    // OR pattern (multiple tools)
"*"                       // All tools
```

### Async vs Sync

| Type | Behavior | Use For |
|------|----------|---------|
| Sync (`"async": false`) | Blocks until complete | Formatting, type-checking, blocking |
| Async (`"async": true`) | Runs in background | Analysis, learning, metrics |

### Exit Code Semantics

| Code | Meaning |
|------|---------|
| `0` | Success / allow operation |
| `2` | Block operation (PreToolUse only) |
| Other non-zero | Error (logged, does not block) |

### Hook Script Pattern

```javascript
// Standard hook script pattern
let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', () => {
  const input = JSON.parse(data);
  const toolName = input.tool_name;
  const toolInput = input.tool_input;

  // Warn: write to stderr (shown to user)
  console.error('[Hook] Warning: potential issue detected');

  // Block (PreToolUse only):
  // process.exit(2);

  // Always output original data to stdout
  console.log(data);
});
```

### Profile-Based Hook Gating

ECC wraps every hook in `run-with-flags.js` for conditional execution:

```bash
# Environment variables
ECC_HOOK_PROFILE=minimal|standard|strict  # default: standard
ECC_DISABLED_HOOKS=hook-id-1,hook-id-2   # disable specific hooks
```

Each hook has a profile CSV:
```javascript
// run-with-flags.js checks if current profile matches hook's allowed profiles
const allowedProfiles = 'standard,strict'; // This hook runs in standard and strict
if (!allowedProfiles.includes(process.env.ECC_HOOK_PROFILE || 'standard')) {
  process.exit(0); // Skip silently
}
```

**Why this matters:** In a heavy coding session, you may want `minimal` hooks (just formatting). During review, switch to `strict` (all quality gates active).

### Key Hook Patterns

#### Session Persistence (SessionStart + Stop)

```
SessionStart → session-start.js
  1. Find most recent session file (within 7 days)
  2. Read session summary
  3. Output to stdout (injected into context)

Stop → session-end.js (async)
  1. Parse current transcript
  2. Extract: tasks, files modified, tools used, stats
  3. Write to ~/.claude/sessions/YYYY-MM-DD-{id}-session.tmp
  4. Use marker blocks for idempotent updates
```

#### Strategic Compaction (PreToolUse)

```
Every ~50 tool calls → suggest-compact.js
  1. Count tool calls since last suggestion
  2. If threshold reached, emit suggestion to stderr
  3. Include what to preserve in compaction
```

#### Auto-Format (PostToolUse)

```
After Edit of .js/.ts → post-edit-format.js
  1. Detect formatter (Biome > Prettier > none)
  2. Run formatter on edited file
  3. Output formatted result
```

#### Quality Gate (PostToolUse, Async)

```
After Edit|Write of code files → quality-gate.js (async)
  1. Check for common issues (console.log, TODO, etc.)
  2. Run linter if available
  3. Report findings to stderr (non-blocking)
```

### What Survives Compaction

Important for designing hooks that persist context:

| Survives | Lost |
|----------|------|
| CLAUDE.md instructions | Intermediate reasoning |
| TodoWrite task list | Previously-read file contents |
| Memory files (`~/.claude/memory/`) | Tool call history |
| Git state | Verbally-stated preferences |
| Files on disk | Prior conversation context |
