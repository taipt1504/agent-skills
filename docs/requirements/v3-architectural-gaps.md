# v3.0 Architectural Notes

Remaining platform constraints and design decisions.

## Resolved Gaps

### 1. Subagent-per-task Isolation (Requirement 2.4) — RESOLVED

**Implementation**: `commands/build.md` instructs the agent to spawn 1 separate Agent (implementer) per task with pre-loaded context (task description + spec scenario + relevant skills + prior task summary). `bootstrap/SKILL.md` documents the pattern in the workflow section.

**Enforcement**: Agent-driven — the `/build` command and bootstrap skill instruct the pattern. Claude Code's Agent tool supports this natively.

### 2. Skill Router (Requirement 5.1) — PARTIALLY RESOLVED

**Implementation**: `skill-router.sh` outputs a strong directive to stderr: `[SkillRouter] LOAD skill 'X' for file → read path`. The agent sees stderr output from hooks.

**Platform limitation**: Hooks cannot inject content into conversation context mid-session (only SessionStart can). The bootstrap skill teaches agents to self-load skills, and the hook reinforces which skill to load.

**Cross-check**: Hooks cannot access agent conversation state to verify announced skill matches file pattern. This relies on agent instruction compliance.

### 3. Pattern Extraction (Requirement 3.2) — RESOLVED

**Implementation**: Two-layer approach:
- `session-save.sh` auto-appends fix patterns to `.claude/memory/debug-knowledge.md` (detects "fix" commits)
- `/meta learn` command handles full semantic pattern extraction via AI analysis

### 4. Session Start Loading (Requirement 3.1) — RESOLVED

**Implementation**: `bootstrap/SKILL.md` Skill Loading Protocol now specifies:
- Session start → load bootstrap + summer-core (if detected)
- On-demand → load domain skills when touching relevant files

## True Platform Limitations (cannot fix)

### Context Size Monitoring (Requirement 3.3)

Claude Code hooks have no API to read actual context token count. `compact-advisor.sh` uses tool call count as a proxy (3-stage: 50/75/100 calls). This is the best available heuristic.

### Skill Router Context Injection

PreToolUse hooks can output to stderr (visible to agent) but cannot inject text into the agent's conversation context. Only SessionStart hooks support stdout→context injection. Skill loading is therefore agent-driven via bootstrap instruction, reinforced by hook suggestions.
