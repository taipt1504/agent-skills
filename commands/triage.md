---
name: triage
description: Classify task scope, route to workflow lane (trivial / standard / high-stakes). Use to override auto-triage from SessionStart.
---

# /triage — Workflow Lane Router

## Usage

```
/triage                     # Re-triage current task (re-reads task from workflow-state)
/triage trivial             # Force trivial lane
/triage standard            # Force standard lane
/triage high-stakes         # Force high-stakes lane
/triage <task description>  # Triage a new task description
```

## First Action (MANDATORY)

1. Load `skills/triage/SKILL.md`
2. Read pre-flight artifact `.claude/memory/preflight/initial-*.md` (latest)
3. If no pre-flight 0: generate one (light enumeration acceptable for triage)

## Decision

From `skills/triage/SKILL.md`:

1. ≤5 lines AND no behavior change? → Trivial
2. Architecture / DB migration / security / public API / breaking change / new dep? → High-stakes
3. Otherwise → Standard

## Output

State decision explicitly:

```
## Triage decision
**Lane:** <Trivial | Standard | High-stakes>
**Reasoning:** <1–2 sentences>
**Next gate:** <Execute | Align | Brainstorm>
**Skipped gates:** <list, if any>
**Override:** State "treat as <lane>" to force.
```

## State persistence

Write `.claude/memory/state/current-triage.json`:

```json
{
  "lane": "<chosen>",
  "task_description": "<task>",
  "timestamp": "<ISO-8601>",
  "reasoning": "<1-2 sentences>",
  "user_override": <true | false>
}
```

Export `TRIAGE_LANE` env var for downstream hooks.

## User override

"treat as high-stakes" → set `user_override: true`, `lane: high-stakes`. Acknowledge + proceed.

"treat as trivial, just do it" on risky task → warn first, require explicit second confirmation, then downgrade with `user_override: true`.

## Next steps by lane

| Lane | Next gate |
|---|---|
| Trivial | Execute (light TDD, Verify compile+format, Review S2) |
| Standard | Align (if vague) → Brainstorm (if multi-path) → Plan → Spec → Execute → Review S1+S2 |
| High-stakes | Align (mandatory) → Brainstorm (mandatory, ≥3 options) → ADR → Plan → Spec → Execute (worktree) → Verify (+security scan) → Review S1+S2 |

## Related

- `skills/triage/SKILL.md` — full decision logic + examples
- `rules/common/lanes.md` — lane definitions
- `scripts/hooks/workflow-gate.sh` — enforcement (blocks gates not allowed by lane)
