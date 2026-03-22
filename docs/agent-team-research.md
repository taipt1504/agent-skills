# Agent Team Support — Deep Dive Research Report

> **Date**: 2026-03-22
> **Team**: agent-team-research (4 specialists + team lead)
> **Plugin**: devco-agent-skills v3.0.0
> **Purpose**: Comprehensive research to add automatic Agent Team support to the SDD workflow

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Agent Team Architecture & API](#2-agent-team-architecture--api)
3. [SDD vs Agent Team Workflow Routing](#3-sdd-vs-agent-team-workflow-routing)
4. [Settings, Hooks & Memory Configuration](#4-settings-hooks--memory-configuration)
5. [Skill Enforcement for Teammates](#5-skill-enforcement-for-teammates)
6. [Implementation Roadmap](#6-implementation-roadmap)

---

## 1. Executive Summary

### Goal

Enable the devco-agent-skills plugin to **automatically decide** whether to use the traditional SDD workflow (sequential agent spawning) or an Agent Team (parallel teammates) based on user prompt analysis and spec task decomposition.

### Key Findings

| Area | Finding | Impact |
|------|---------|--------|
| **API** | Agent Teams require `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (already enabled) | Ready to use |
| **Custom Agents as Teammates** | NOT yet supported (GitHub #24316) — teammates are `general-purpose` only | Must use spawn `prompt` for specialization |
| **Hooks** | Most hooks (SessionStart, PreToolUse, PostToolUse) fire for teammates | Bootstrap skill injection works for teammates |
| **Missing Hooks** | `TeammateIdle`, `TaskCompleted`, `SubagentStop` not configured | Need new hook scripts |
| **Skill Enforcement** | Hybrid approach: condensed protocol in agent defs + dynamic skill injection | ~250 tokens overhead per teammate |
| **Routing** | Scoring algorithm based on spec task decomposition — score ≥12 triggers team mode | Automatic with user confirmation for borderline cases |
| **Memory** | Filesystem-shared, needs locking for concurrent writes | Race condition risk without locks |

### Architecture Decision

```
User Prompt → /plan → /spec (with task decomposition) → /build
                                                           │
                                                    ROUTING ENGINE
                                                    analyzes tasks
                                                           │
                                    ┌──────────────────────┼──────────────────────┐
                                    │                      │                      │
                              Score < 8              Score 8-11             Score ≥ 12
                            SDD-Sequential         SDD-Team (ask)          SDD-Team
                          (current behavior)       user confirms          (auto-suggest)
```

---

## 2. Agent Team Architecture & API

### 2.1 Enabling Agent Teams

```json
// .claude/settings.local.json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Required: Claude Code v2.1.32+. One team per session. No nested teams.

### 2.2 API Surface

#### TeamCreate

Creates team config + task list + inbox directories:

```
~/.claude/teams/{team-name}/config.json    — team metadata + members
~/.claude/tasks/{team-name}/               — task files (1.json, 2.json, ...)
~/.claude/teams/{team-name}/inboxes/       — inbox per agent
```

#### Agent Tool (Spawning Teammates)

| Parameter | Type | Description |
|-----------|------|-------------|
| `team_name` | string | Team to join (required) |
| `name` | string | Addressable name for messaging |
| `subagent_type` | string | Agent type (currently only `general-purpose` for teams) |
| `prompt` | string | Instructions — **the only way to specialize teammates** |
| `model` | string | `haiku`, `sonnet`, `opus` |
| `mode` | string | `plan`, `acceptEdits`, `bypassPermissions`, `default`, `dontAsk`, `auto` |
| `run_in_background` | boolean | Always `true` for teammates |
| `isolation` | string | `"worktree"` for git worktree isolation |

#### SendMessage

| Mode | Syntax | Use Case |
|------|--------|----------|
| Direct | `{ to: "name", message: "text" }` | Normal communication |
| Broadcast | `{ to: "*", message: "text" }` | Emergency only (expensive) |
| Shutdown | `{ to: "name", message: { type: "shutdown_request" } }` | Graceful termination |
| Plan Approval | `{ to: "name", message: { type: "plan_approval_response", approve: true } }` | Approve teammate plans |

#### Task Tools

```
TaskCreate  → { subject, description, activeForm }        → returns task ID
TaskUpdate  → { taskId, status, owner, addBlockedBy }     → claim, progress, complete
TaskList    → returns all tasks with status/owner/deps
TaskGet     → { taskId } → full task details
```

Auto-unblocking: when a blocking task completes, blocked tasks automatically unblock.

### 2.3 Teammate Lifecycle

```
SPAWN → CONTEXT LOAD → WORK LOOP → IDLE → SHUTDOWN
  │         │              │          │        │
  │    CLAUDE.md +     TaskList →    Auto     shutdown_request
  │    hooks +         claim →      idle      → approve/reject
  │    spawn prompt    execute →    notif
  │                    complete →
  │                    loop
  │
  └── Each teammate = full Claude Code instance with own 1M context window
      Lead's conversation history does NOT carry over
```

### 2.4 Environment Variables Auto-Injected for Teammates

```
CLAUDE_CODE_TEAM_NAME="my-project"
CLAUDE_CODE_AGENT_ID="worker-1@my-project"
CLAUDE_CODE_AGENT_NAME="worker-1"
CLAUDE_CODE_AGENT_TYPE="Explore"
CLAUDE_CODE_AGENT_COLOR="#4A90D9"
CLAUDE_CODE_PLAN_MODE_REQUIRED="false"
CLAUDE_CODE_PARENT_SESSION_ID="session-xyz"
```

### 2.5 Key Constraints

| Constraint | Impact |
|------------|--------|
| One team per session | Can't run multiple teams simultaneously |
| No nested teams | Teammates can't spawn their own teams |
| No custom agents as teammates (#24316) | Must specialize via spawn prompt only |
| Plugin agents can't use hooks/mcpServers/permissionMode | Security restriction |
| Token costs scale linearly | 3 teammates ≈ 3-4x token cost |
| Subagents cannot spawn subagents | Only lead can delegate |
| No per-teammate env vars at spawn | Shared settings only |

### 2.6 Agent Type Capabilities

| Type | Tools | Best For |
|------|-------|----------|
| `general-purpose` | All tools | Implementation, multi-step work |
| `Explore` | Read-only (Read, Grep, Glob) | Codebase search, research |
| `Plan` | Read-only | Architecture, strategy |
| Custom `.claude/agents/*.md` | Configurable | Specialized roles (NOT as teammates yet) |

### 2.7 Team Coordination Patterns

| Pattern | Description | Best For |
|---------|-------------|----------|
| **Parallel Specialists** | Multiple teammates review same code from different angles | Code review, security audit |
| **Pipeline** | Tasks chained via blockedBy dependencies | Sequential workflows |
| **Swarm** | N workers poll TaskList, claim, execute, loop | Batch processing, independent tasks |
| **Plan Approval Gate** | Teammate in plan mode, lead approves | Architecture decisions |
| **Layer-Based DAG** | Tasks grouped by dependency layers, layers run parallel | Feature implementation (Ralphinho pattern) |

---

## 3. SDD vs Agent Team Workflow Routing

### 3.1 Prompt Analysis Signal Taxonomy

#### Complexity Signals

| Signal | Detection | Weight |
|--------|-----------|--------|
| File count | Count file paths, class names in prompt | Medium |
| Package spread | Count distinct packages affected | Medium |
| Task type diversity | REST + Domain + Messaging + Migration mix | Medium |
| Architectural scope | "new module", "new service", "cross-cutting" | High |
| Integration points | Kafka, Redis, DB, external APIs mentioned | Low |

#### Parallelism Signals (→ Team Mode)

- Multiple independent endpoints ("Add CRUD for orders, products, customers")
- Independent domain services
- Separate bounded contexts
- No shared state between subtasks
- Keywords: "simultaneously", "in parallel", "independently"

#### Sequential Signals (→ Sequential Mode)

- Dependency chain ("first...then...")
- Single feature flow
- Bug fix / hotfix
- Shared mutable state
- Single entity CRUD

### 3.2 Decision Matrix

| Criterion | SDD-Sequential | SDD-Team | Weight |
|-----------|---------------|----------|--------|
| Independent task count | 1-2 | 3+ | **HIGH** |
| Package/module spread | 1-2 packages | 3+ distinct packages | MEDIUM |
| File conflict risk | Tasks share files | Disjoint file sets | **HIGH** |
| Task type diversity | Single type | Mixed types | MEDIUM |
| Dependency graph shape | Linear chain | Wide DAG (Layer 0 ≥ 3 nodes) | **HIGH** |
| Estimated total tasks | 1-4 | 5+ | LOW |

### 3.3 Scoring Algorithm

```python
def route_workflow(approved_spec):
    tasks = approved_spec.task_decomposition
    dep_graph = build_dependency_graph(tasks)
    layers = topological_sort_into_layers(dep_graph)

    # Hard overrides
    if has_file_conflicts(tasks):
        return "sdd-sequential"  # Merge conflict guaranteed
    if len(tasks) <= 2:
        return "sdd-sequential"  # Team overhead not worth it
    if all_tasks_linear(dep_graph):
        return "sdd-sequential"  # Fully linear chain

    # Compute score
    independent_count = count_no_dependency_tasks(tasks)
    packages = count_distinct_packages(tasks)
    task_types = count_distinct_task_types(tasks)
    max_layer_width = max(len(layer) for layer in layers)
    file_conflicts = has_any_file_overlap(tasks)

    score = (
        independent_count * 3          # max 15
        + packages * 2                 # max 8
        + (4 if not file_conflicts else 0)  # binary
        + task_types                   # max 5
        + max_layer_width * 2          # max 10
    )

    if score >= 12: return "sdd-team"           # Auto-suggest
    if score >= 8:  return "sdd-team-suggested"  # Ask user
    return "sdd-sequential"                      # Default
```

#### Hard Overrides

| Condition | Forced Mode |
|-----------|-------------|
| Any two tasks modify same file | Sequential |
| User says "one at a time" | Sequential |
| User says "in parallel" | Team |
| All tasks depend on same predecessor | Sequential |
| Single bug fix or hotfix | Sequential |
| Spec has ≤2 tasks | Sequential |

### 3.4 Team Composition Templates

#### Template A: Feature Implementation Team

**Trigger**: 3+ independent implementation tasks across multiple packages

```yaml
team:
  name: feature-implementation
  members:
    - role: coordinator (team lead — opus)
    - role: implementer-1 (sonnet, worktree)
    - role: implementer-2 (sonnet, worktree)
    - role: implementer-3 (sonnet, worktree)
    - role: reviewer (sonnet)
  execution:
    strategy: layer-parallel
    max_parallel: 3
    merge: sequential-merge-after-layer
```

#### Template B: Bug Investigation + Fix

**Trigger**: Complex multi-component bug

```yaml
team:
  name: bug-fix
  members:
    - role: investigator (planner on opus)
    - role: implementer (sonnet)
    - role: reviewer (sonnet)
  execution:
    strategy: sequential (investigate → fix → review)
```

#### Template C: Refactoring Team

**Trigger**: Large refactoring across 3+ modules

```yaml
team:
  name: refactoring
  members:
    - role: analyzer (planner on opus)
    - role: refactorer-1..N (sonnet, worktree)
    - role: test-verifier (sonnet)
  execution:
    strategy: layer-parallel
    merge: merge-and-test-after-each-layer
```

#### Template D: Multi-Endpoint / CRUD

**Trigger**: Multiple independent REST endpoints

```yaml
team:
  name: multi-endpoint
  members:
    - role: implementer per entity (sonnet, worktree each)
    - role: reviewer (sonnet)
  execution:
    strategy: all-parallel
    merge: merge-all-then-review
```

### 3.5 SDD Compliance in Team Mode

**CRITICAL**: Only the BUILD phase gets parallelized. All other phases remain sequential with user approval gates.

```
Phase          | Execution Mode        | User Gate?
───────────────┼───────────────────────┼───────────
PLAN           | Single (planner)      | YES — user approves
SPEC           | Single (spec-writer)  | YES — user approves
BUILD          | *** PARALLEL ***      | No (automated per-task)
  └─ Layer 0   | N implementers        | (merge after layer)
  └─ Layer 1   | N implementers        | (merge after layer)
  └─ Layer N   | N implementers        | (merge after layer)
VERIFY         | Single (pipeline)     | No
REVIEW         | Single (reviewer)     | YES — user reviews
```

#### BUILD Phase Orchestration

```
SPEC APPROVED → ROUTING ENGINE → Team Mode
    │
    ├── Parse tasks into dependency layers
    ├── Create worktrees for implementers
    ├── Distribute spec to all implementers
    │
    ├── LAYER 0 (parallel): implementer-1: Task 1, implementer-2: Task 2, ...
    ├── MERGE LAYER 0 + run tests
    │
    ├── LAYER 1 (parallel): tasks that depended on Layer 0
    ├── MERGE LAYER 1 + run tests
    │
    └── ... until all layers complete → VERIFY
```

#### Layer Handoff Document

Each implementer starting a new layer receives:

```markdown
## LAYER HANDOFF: Layer 0 → Layer 1

### Completed Tasks
- Task 1: Created OrderRequest, OrderResponse DTOs
- Task 2: Created OrderNotFoundException

### Files Added/Modified
- src/.../dto/OrderRequest.java (NEW)
- src/.../exception/OrderNotFoundException.java (NEW)

### Test Status: 3 passing, 0 failing

### Your Task
- Task 3: Implement OrderRepository
- Spec scenarios: shouldFindByIdWhenExists, shouldReturnEmptyWhenNotFound
```

### 3.6 Edge Cases & Fallbacks

| Edge Case | Resolution |
|-----------|------------|
| **File conflicts** | Reorder into same layer → auto-merge → fallback to sequential |
| **Implementer failure** | Isolate failed task, continue others, report to user |
| **Worktree merge conflicts** | Auto-merge → coordinator resolves → nuclear: re-run sequential |
| **Discovered mid-execution dependency** | Pause dependent task, merge prerequisite first |
| **Team overhead exceeds sequential** | Minimum 3 truly independent tasks threshold |
| **Context window exhaustion** | Each implementer gets fresh context; inject only task-specific content |

#### Fallback Cascade

```
sdd-team (parallel)
    ├─ file conflict → reorder → retry
    ├─ merge conflict → auto-resolve → if fail → sequential
    ├─ implementer failure → isolate + continue → user decides
    └─ overhead too high → switch to sequential (preserve completed work)
```

### 3.7 Spec Enhancement: Package Column

Add "Package" column to spec task decomposition for routing:

```
| # | Task | Package | File | Test Method | Depends On |
|---|------|---------|------|-------------|------------|
| 1 | DTOs | interfaces | XxxRequest.java | — | — |
| 2 | Exceptions | domain | XxxNotFoundException.java | — | — |
| 3 | Repository | infrastructure | XxxRepository.java | shouldFind... | 1 |
```

---

## 4. Settings, Hooks & Memory Configuration

### 4.1 Environment Variables Reference

#### Team-Related

| Variable | Purpose | Set By |
|----------|---------|--------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enable teams (`"1"`) | User in settings |
| `CLAUDE_CODE_TEAM_NAME` | Current team name | Auto-injected for teammates |
| `CLAUDE_CODE_AGENT_NAME` | Teammate's name | Auto-injected |
| `CLAUDE_CODE_AGENT_ID` | Teammate's ID | Auto-injected |
| `CLAUDE_CODE_PLAN_MODE_REQUIRED` | Plan mode flag | Auto-injected |
| `CLAUDE_CODE_PARENT_SESSION_ID` | Lead's session ID | Auto-injected |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Override teammate model | User configurable |
| `CLAUDE_CODE_TASK_LIST_ID` | Share tasks across sessions | User configurable |

#### Inheritance

- Teammates **inherit all env vars** from lead's `settings.json` `env` section
- Team-specific vars are auto-injected on top
- No per-teammate env var mechanism at spawn time

### 4.2 Settings Configuration

#### Required `settings.local.json` Updates

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Bash", "Read", "Write", "Edit", "MultiEdit",
      "Glob", "Grep", "WebFetch", "WebSearch", "Task",
      "SendMessage",
      "mcp__sequential-thinking__sequentialthinking"
    ]
  },
  "teammateMode": "in-process"
}
```

**Changes from current:**
- Add `SendMessage` to allow list (agent team communication)
- Add `teammateMode: "in-process"` (or `"tmux"` for split panes)

#### Permission Inheritance

- Teammates inherit lead's permission settings at spawn
- Pre-approve all common operations to avoid permission friction
- Permission requests from teammates bubble up to lead (UX friction)

### 4.3 Hooks Analysis

#### Hooks That Fire for Teammates

| Hook | Fires? | Plugin Script | Status |
|------|--------|---------------|--------|
| `SessionStart` | **YES** | `session-init.sh` → bootstrap injection | WORKING |
| `PreToolUse` (Edit/Write) | **YES** | `skill-router.sh` → skill routing | WORKING |
| `PreToolUse` (Edit/Write) | **YES** | `compact-advisor.sh` | WORKING |
| `PostToolUse` (Edit/Write) | **YES** | `quality-gate.sh` → compile check | WORKING |
| `PreCompact` | **YES** | `pre-compact.sh` | WORKING |
| `Stop` | **NO** | `session-save.sh` | **GAP** — use SubagentStop |

#### New Team-Specific Hook Events

| Event | Purpose | Exit Code 2 Effect |
|-------|---------|---------------------|
| `TeammateIdle` | Quality gate before idle | Feedback keeps teammate working |
| `TaskCompleted` | Quality gate before task closure | Task NOT completed, feedback sent |
| `SubagentStop` | Replace Stop for teammates | Session save for teammates |
| `SubagentStart` | Context injection at spawn | `additionalContext` injected |

#### Proposed New Hooks

```json
{
  "TeammateIdle": [
    {
      "hooks": [{
        "type": "command",
        "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/teammate-idle.sh",
        "timeout": 30
      }]
    }
  ],
  "TaskCompleted": [
    {
      "hooks": [{
        "type": "command",
        "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/task-completed.sh",
        "timeout": 90
      }]
    }
  ],
  "SubagentStop": [
    {
      "hooks": [{
        "type": "command",
        "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/session-save.sh",
        "timeout": 60,
        "async": true
      }]
    }
  ]
}
```

#### New Hook Scripts

**`teammate-idle.sh`** — Quality gate before idle:
- Check compilation errors in modified Java files
- Check for uncommitted changes
- Verify tests pass if test files were modified
- Exit code 2 + stderr to keep teammate working if issues found

**`task-completed.sh`** — Quality gate before task closure:
- Run `./gradlew compileJava` for modified files
- Run tests for modified test files
- Check for `.block()` / `System.out.println` violations
- Exit code 2 to prevent task completion if gate fails

#### Hook Profile Updates

```bash
# New team profiles in run-with-flags.sh
team-minimal:   session-init, session-save, teammate-idle
team-standard:  + skill-router, quality-gate, compact-advisor, task-completed
team-strict:    + pre-compact
```

Auto-detect: when `CLAUDE_CODE_TEAM_NAME` is set, use team profile.

### 4.4 Memory Sharing

#### Current Memory Tiers

| Tier | Location | Teammate Access |
|------|----------|-----------------|
| L1 Session | `.claude/memory/sessions/` | YES (shared filesystem) |
| L2 Project | `.claude/memory/knowledge/` | YES (shared filesystem) |
| L2 Context | `.claude/memory/context/` | YES (shared filesystem) |
| L3 Knowledge Graph | MCP memory tools | YES (if MCP inherited) |
| Auto Memory | `.claude/memory/MEMORY.md` | YES (shared filesystem) |

#### Race Condition Risk

Multiple teammates writing to same memory files simultaneously. Solution:

```bash
# File locking in write-session.sh
LOCK_FILE="$SESSIONS_DIR/.write.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0
# ... write operations ...
```

#### Communication Between Teammates

| Mechanism | Overhead | Use For |
|-----------|----------|---------|
| SendMessage (direct) | Low | Task instructions, findings |
| SendMessage (broadcast) | High (N messages) | Critical alerts only |
| Shared task list | Built-in | Progress tracking |
| Filesystem (`.claude/`) | Risky | Avoid for writes |

### 4.5 Plugin Loading for Teammates

| Component | Loaded? | Via |
|-----------|---------|-----|
| CLAUDE.md | YES | Working directory |
| hooks.json hooks | YES | CLAUDE_PLUGIN_ROOT |
| Skills (bootstrap, etc.) | YES | SessionStart hook |
| MCP servers | YES | Inherited from lead |
| Settings | YES | Inherited from lead |
| Lead's conversation | **NO** | Must pass via spawn prompt |
| Current phase tracking | **NO** | Must communicate via task/message |

---

## 5. Skill Enforcement for Teammates

### 5.1 Current Enforcement Mechanism

```
SessionStart → session-init.sh → reads bootstrap/SKILL.md → injects into context
PreToolUse   → skill-router.sh → routes file patterns to skills
PostToolUse  → quality-gate.sh → compile + debug checks
```

The "1% rule": bootstrap SKILL.md mandates skill search before every action.

### 5.2 The Problem

**Critical Finding**: Since SessionStart DOES fire for teammates, and PreToolUse/PostToolUse DO fire, the existing enforcement mechanism **already works for teammates**.

However, there are gaps:

| Layer | Main Session | Teammates |
|-------|-------------|-----------|
| Bootstrap injection (SessionStart) | YES | **YES** |
| CLAUDE.md rules | YES | YES |
| Skill router (PreToolUse) | YES | **YES** |
| Quality gate (PostToolUse) | YES | **YES** |
| Skill loading on-demand | YES | DEPENDS on tools |
| Lead's conversation context | YES | **NO** |

The main gap: teammates don't have the lead's conversation context (approved plan, spec, phase tracking). This must be injected via spawn prompt.

### 5.3 Recommended Strategy: Hybrid (Option D)

**Static (in agent definitions — ~250 tokens):**

```markdown
## MANDATORY: Skill Usage Protocol

You are enhanced with a domain skill system. Before EVERY code-related action:

1. **Identify** which files you will touch
2. **Match** file patterns to the skill registry below
3. **Announce**: "Using skill: {name} for {reason}"
4. **Load** the skill via the Skill tool if not already loaded
5. If no match: state "No matching skill found"

**There are NO exceptions.** Even if 1% unsure, search skills first.

### Quick Skill Registry

| File Pattern | Skill |
|-------------|-------|
| *Controller.java, *Handler.java | spring-patterns |
| *SecurityConfig*, JWT, CORS | spring-security |
| *Repository.java, *.sql, Entity | database-patterns |
| *Test.java, test commands | testing-workflow |
| Kafka*, Rabbit*, *Listener | messaging-patterns |
| Redis*, cache config | redis-patterns |
| Any Java file | coding-standards |
| Package structure, CQRS | architecture |

### Workflow Gates (Hard Blocks)

- Writing code without approved plan/spec → STOP → report to team lead
- No tests → BLOCK — code does not ship without tests
- `.block()` in src/main/ → CRITICAL — fix immediately
- Never commit to git — only the user commits
```

**Dynamic (via team lead SendMessage at task assignment):**

```
SendMessage to implementer:
"Task: Implement scenario 3 from approved spec.

Spec excerpt: [paste relevant scenario]

Required skill: Load `database-patterns` — this task touches Repository files.

Files to modify:
- src/main/.../OrderRepository.java
- src/test/.../OrderRepositoryTest.java"
```

### 5.4 Role-Skill Mapping

| Role | Static Skills (agent def) | Dynamic Skills (team lead) | Optional (self-load) |
|------|--------------------------|---------------------------|---------------------|
| **planner** | skill-protocol, workflow-gates | architecture | spring-patterns, database-patterns |
| **spec-writer** | skill-protocol, workflow-gates | coding-standards | api-design, database-patterns |
| **implementer** | skill-protocol, workflow-gates, self-check | testing-workflow + 1 domain skill | spring-patterns, database-patterns |
| **reviewer** | skill-protocol, workflow-gates, all-checklists | coding-standards | All (on demand per file) |

### 5.5 Quality Gate for Teammates

1. **quality-gate.sh continues to run** — compile checks happen automatically
2. **Self-check in implementer agent definition:**
   ```
   Before completing task:
   - [ ] No .block() in reactive code
   - [ ] No @Autowired field injection
   - [ ] No entities in API responses
   - [ ] All tests pass
   - [ ] Test names follow shouldDoXWhenY
   ```
3. **Cross-teammate consistency via reviewer** — reviews ALL modified files after merge
4. **Team lead runs /verify** before declaring overall completion

### 5.6 Command Enforcement in Teams

In teams, SDD workflow phases are enforced via **task dependencies**, not commands:

```
Task: "Plan feature X"          → assigned to planner, no deps
Task: "Write spec for feature X" → blocked by plan task
Task: "Implement scenario 1"     → blocked by spec task
Task: "Implement scenario 2"     → blocked by spec task
Task: "Review implementation"    → blocked by all implement tasks
```

Team lead is the workflow engine — no teammate advances past a phase gate without the blocking task completing.

---

## 6. Implementation Roadmap

### Phase 1: Foundation (Immediate — works today)

#### 1.1 Update `settings.local.json`

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Bash", "Read", "Write", "Edit", "MultiEdit",
      "Glob", "Grep", "WebFetch", "WebSearch", "Task",
      "SendMessage",
      "mcp__sequential-thinking__sequentialthinking"
    ]
  },
  "teammateMode": "in-process"
}
```

#### 1.2 Add Skill Protocol to Agent Definitions

Add the 250-token Skill Usage Protocol section (from §5.3) to all agent definitions:
- `agents/implementer.md` (most critical)
- `agents/reviewer.md`
- `agents/spec-writer.md`
- `agents/planner.md`
- `agents/build-fixer.md`
- `agents/test-runner.md`

#### 1.3 Add Self-Check Lists to Agents

Add phase-specific hard blocks:
- Implementer: require spec context in task
- Reviewer: require spec for adherence checking
- Spec-writer: require plan context

#### 1.4 Create New Hook Scripts

- `scripts/hooks/teammate-idle.sh` — quality gate before idle
- `scripts/hooks/task-completed.sh` — quality gate before task closure

#### 1.5 Update `hooks.json`

Add `TeammateIdle`, `TaskCompleted`, `SubagentStop` events.

#### 1.6 Add Memory Locking

Add file locking to `scripts/memory/write-session.sh` for concurrent safety.

### Phase 2: Routing Engine (Short-term)

#### 2.1 Enhance Spec Writer

Add "Package" column to task decomposition table for routing analysis.

#### 2.2 Implement Routing Algorithm

Embed routing logic in `/build` command:
- Parse spec task decomposition
- Build dependency graph
- Compute parallelism score
- Suggest team mode when score ≥ 12

#### 2.3 Create Team Templates

Define pre-built team configurations:
- Feature Implementation Team
- Bug Investigation Team
- Refactoring Team
- Multi-Endpoint Team

#### 2.4 Create Spawn Prompt Templates

For each agent role, create optimized spawn prompts that include:
- Condensed agent instructions (from agent definitions)
- Skill protocol
- Task-specific context (spec excerpt, file list)
- Layer handoff document (for Layer 1+ tasks)

### Phase 3: Polish (Medium-term)

#### 3.1 Update Hook Profiles

Add team-aware profiles to `run-with-flags.sh`:
- Auto-detect `CLAUDE_CODE_TEAM_NAME` env var
- Switch to team profile (team-standard by default)

#### 3.2 Layer Handoff Documents

Implement structured handoffs between layers:
- Completed tasks summary
- Files added/modified
- Test status
- Next task context

#### 3.3 Fallback Mechanisms

Implement graceful fallback from team to sequential:
- Detect file conflicts mid-execution
- Detect merge failures
- Preserve completed worktree work

#### 3.4 Bootstrap Skill Update

Add team-awareness section to `skills/bootstrap/SKILL.md`:
- Team delegation guidelines
- When to use team vs subagents
- Communication patterns

### Phase 4: When #24316 Lands (Future)

When custom agents as teammates is supported:
- Use `.claude/agents/*.md` definitions directly as teammate types
- Per-teammate tool restrictions
- Per-teammate hooks
- Per-teammate skill preloading
- Per-teammate persistent memory

---

## Appendix A: Decision Tree Summary

```
User prompt arrives
    │
    ▼
Trivial? (≤5 lines, single file, no new behavior)
    │yes → SKIP SDD
    │no
    ▼
/plan → user approves plan
    │
    ▼
/spec → spec-writer generates task decomposition → user approves
    │
    ▼
/build → ROUTING ENGINE
    │
    ├── Hard override? → SEQUENTIAL
    │   (file conflicts, user intent, ≤2 tasks, linear chain)
    │
    ├── Score ≥ 12 → TEAM MODE (auto-suggest)
    │   "I recommend parallel execution with N implementers. Proceed?"
    │
    ├── Score 8-11 → TEAM MODE (ask)
    │   "Parallel possible but borderline. Use team? (yes/no)"
    │
    └── Score < 8 → SEQUENTIAL (current behavior)
```

## Appendix B: Scoring Formula

```
parallelism_score = (
    independent_task_count * 3        # max 15 (cap at 5)
  + distinct_packages * 2             # max 8  (cap at 4)
  + (4 if no_file_conflicts else 0)   # binary, high weight
  + task_type_diversity * 1           # max 5
  + max_dag_layer_width * 2           # max 10
)

Thresholds:
  score >= 12  → sdd-team (auto-suggest)
  score >= 8   → sdd-team (suggest, user confirms)
  score < 8    → sdd-sequential (default)
```

## Appendix C: Files to Modify

| File | Change |
|------|--------|
| `.claude/settings.local.json` | Add SendMessage permission, teammateMode |
| `hooks/hooks.json` | Add TeammateIdle, TaskCompleted, SubagentStop |
| `scripts/hooks/teammate-idle.sh` | NEW — quality gate before idle |
| `scripts/hooks/task-completed.sh` | NEW — quality gate before task closure |
| `scripts/hooks/run-with-flags.sh` | Add team profiles |
| `scripts/memory/write-session.sh` | Add file locking |
| `agents/implementer.md` | Add skill protocol + self-check |
| `agents/reviewer.md` | Add skill protocol + all-checklists |
| `agents/spec-writer.md` | Add skill protocol + Package column |
| `agents/planner.md` | Add skill protocol |
| `agents/build-fixer.md` | Add skill protocol |
| `agents/test-runner.md` | Add skill protocol |
| `skills/bootstrap/SKILL.md` | Add team-awareness section |
| `commands/build.md` | Add routing engine logic |

## Appendix D: Sources

- Official docs: Claude Code Agent Teams, Sub-agents, Hooks
- GitHub issue #24316: Custom agents as teammates
- ECC patterns: Ralphinho/RFC-DAG, De-Sloppify
- Plugin research: `docs/research/06-multi-agent-orchestration.md`
- Plugin research: `docs/research/03-agent-design-guide.md`
