# Hook System (v3.3)

17 lifecycle hooks + 1 utility, all defined in `hooks.json` and executed via `${CLAUDE_PLUGIN_ROOT}`.

## Hook Inventory

| Hook | Event | Responsibility | Sync? |
|------|-------|---------------|:-----:|
| `session-init.sh` | SessionStart | Validate manifest, inject bootstrap skill, detect project type, restore session state, **pre-populate skills-loaded.json** | sync |
| `subagent-init.sh` | SubagentStart | Inject context into spawned sub-agents | sync |
| `workflow-gate.sh` | PreToolUse (Edit/Write/MultiEdit) | Block `src/main/*.java` writes when phase is PLAN/SPEC/VERIFY_PENDING/REVIEW_PENDING (Hard Block #10) | **sync, can block** |
| `skill-router.sh` | PreToolUse (Edit/Write/MultiEdit) | File-to-skill matching with soft-block enforcement | **sync, can block** |
| `compact-advisor.sh` | PreToolUse (all) | 3-stage progressive context unloading guidance | async |
| `git-guard.sh` | PreToolUse (Bash) | Block `git commit/push/rebase/reset --hard` (Hard Block #9) | async |
| `quality-gate.sh` | PostToolUse (Edit/Write/MultiEdit) | Compile check + anti-patterns + debug audit + secret scanning | **sync, can block** |
| `build-checkpoint.sh` | PostToolUse (Edit/Write/MultiEdit) | Save build state for recovery after compaction | async |
| `memory-gate.sh` | PostToolUse (Edit/Write/MultiEdit) | Memory-graph update gating | async |
| `workflow-phase-lock.sh` | PostToolUse (Bash) | Auto-transition BUILD→VERIFY_PENDING and VERIFY→REVIEW_PENDING on gradle success | async |
| `workflow-tracker.sh` | PostToolUse (Bash) | Track workflow phase transitions (PLAN→SPEC→BUILD→VERIFY→REVIEW) | async |
| `verify-fix-loop.sh` | PostToolUse (Bash) | Verify/fix cycle with circuit breaker (max 3 retries) | sync |
| `team-spawn-evaluator.sh` | PostToolUse (Bash) | Decide whether to spawn additional teammates based on spec workload | async |
| `observability-trace.sh` | PostToolUse (all) | Emit structured trace events for session telemetry | async |
| `pre-compact.sh` | PreCompact | State checkpoint before context compaction | async |
| `post-compact.sh` | PostCompact | Restore state after context compaction | sync |
| `session-save.sh` | Stop | Save session summary, persist metrics, learning signals | async |
| `run-with-flags.sh` | (utility) | Profile-based hook gating, sourced by all hooks | — |

## Hook Profiles

Controlled via `.claude/devco-config.json` → `hooks.profile`, or `HOOK_PROFILE` env var. Default: `standard`.

| Profile | Hooks Active | Behavior |
|---------|-------------|----------|
| `off` | None | All hooks disabled — zero overhead |
| `minimal` | session-init, session-save, subagent-init | Lifecycle only, no enforcement |
| `standard` | All 17 hooks | **Default** — quality gates warn on HIGH, block on CRITICAL |
| `strict` | All 17 hooks + `STRICT_MODE=true` | Quality gates block on HIGH violations too |

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

## Non-Interactive Mode (claude -p, subagents)

`session-init.sh` pre-populates `.claude/sessions/skills-loaded.json` with all skills the project profile suggests are likely needed (Java MVC → spring-webflux-patterns + coding-standards + testing-workflow + architecture; WebFlux adds the same; Summer adds summer-core + variants). This avoids the `skill-router.sh` soft-block in non-interactive mode where the agent cannot get user approval to update the file.

If you want to disable this pre-population (interactive mode preferred), set `DEVCO_PREPOPULATE_SKILLS=0` in your environment or settings.

## Script Locations

```
scripts/hooks/
├── session-init.sh         # SessionStart: validate + bootstrap + project detection + skill prepop
├── session-save.sh         # Stop: session persist + learning
├── subagent-init.sh        # SubagentStart: sub-agent context
├── workflow-gate.sh        # PreToolUse(Edit/Write): production-code phase guard
├── skill-router.sh         # PreToolUse(Edit/Write): file-to-skill matching
├── git-guard.sh            # PreToolUse(Bash): block agent git operations
├── compact-advisor.sh      # PreToolUse(all): progressive unloading
├── quality-gate.sh         # PostToolUse(Edit/Write): compile + anti-patterns + secrets
├── build-checkpoint.sh     # PostToolUse(Edit/Write): build state snapshots
├── memory-gate.sh          # PostToolUse(Edit/Write): memory-graph gate
├── workflow-phase-lock.sh  # PostToolUse(Bash): auto-transition phases
├── workflow-tracker.sh     # PostToolUse(Bash): phase tracking
├── verify-fix-loop.sh      # PostToolUse(Bash): verify/fix cycle
├── team-spawn-evaluator.sh # PostToolUse(Bash): teammate spawn decision
├── observability-trace.sh  # PostToolUse(all): structured traces
├── pre-compact.sh          # PreCompact: state checkpoint
├── post-compact.sh         # PostCompact: state restore
└── run-with-flags.sh       # Utility: profile gating (sourced, not a hook)
```
