---
name: triage
description: Classify task scope. Routes to trivial / standard / high-stakes lane. Auto-fires SessionStart with user task description. Output decides which downstream gates are mandatory vs optional.
triggers:
  natural: ["triage task", "classify task", "which lane"]
  code: ["SessionStart"]
  command: ["/triage"]
applicability:
  always: false
  triggers:
    auto_fire: ["SessionStart with new user task"]
    task_keywords: ["I want to", "let's", "can you", "implement", "fix", "add", "refactor", "migrate"]
relevance_assessment: |
  Auto-fires on session start with task description. After triage, this skill becomes 0% — replaced by lane-specific skills.
---

# Triage — Route to Workflow Lane

Classify task. Choose depth, not skip phases — choose lane.

## Decision tree

```
Is task ≤5 lines code AND no behavior change?
├── Yes → Trivial lane
│         (skip Align/Brainstorm/Plan/Spec, lighter Verify, Stage 2 review only)
│
└── No → Touches ANY of:
    ├── System architecture or design pattern? → High-stakes
    ├── DB migration / schema change? → High-stakes
    ├── Auth / secrets / security boundary? → High-stakes
    ├── Public API contract? → High-stakes
    ├── Breaking change to existing behavior? → High-stakes
    ├── New external dependency (library, service)? → High-stakes
    │
    └── None above → Standard lane
        (full reasoning gates, normal execution, two-stage review)
```

## Lane summary

| Lane | Code change | Behavior change | New dep | Public API | Persistence | Skipped gates |
|---|---|---|---|---|---|---|
| Trivial | ≤5 lines | No | No | No | No | Align, Brainstorm, Plan, Spec, Review S1 |
| Standard | bounded | possible | No | No | minor | Brainstorm (if obvious solution) |
| High-stakes | any | yes | possible | possible | yes | none |

## Output template

```
## Triage decision

**Lane:** [Trivial | Standard | High-stakes]
**Reasoning:** [1-2 sentences]
**Next gate:** [What runs next]
**Skipped gates:** [What's intentionally skipped]
**Override:** State "treat as [lane]" to force.
```

## User override

- "treat as high-stakes" → upgrade
- "treat as trivial, just do it" → downgrade (warn first; agent acknowledges)

## Edge cases

| Case | Default |
|---|---|
| Ambiguous task description | Standard + surface ambiguity for clarification |
| Multi-task request | Triage each sub-task; process highest-lane first |
| Hotfix under time pressure | High-stakes by default; user can downgrade with explicit ack |
| Exploratory / prototype | Standard (skip Spec, keep Plan) |

## Examples

| Request | Lane | Why |
|---|---|---|
| "Fix typo in error message" | Trivial | 1 line, no behavior change |
| "Add pagination to user API" | Standard | Feature, bounded scope |
| "Migrate from MySQL to TigerBeetle" | High-stakes | New tech, data layer |
| "Refactor PaymentService" | Standard | Bounded refactor |
| "Update Spring Boot 3.1 → 3.2" | High-stakes | New dep version, cluster impact |
| "Add Javadoc to method" | Trivial | No behavior change |
| "Fix slow query in OrderRepository" | Standard | Bounded perf fix |
| "Switch Redis → Hazelcast" | High-stakes | New dep, ops change |
| "Rename internal method" | Trivial | If not public API |
| "Add OAuth login" | High-stakes | Security boundary |

Target: ≥9/10 on this set.

## Integration

State file: `.claude/memory/state/current-triage.json`

```json
{
  "lane": "standard",
  "task_description": "...",
  "timestamp": "ISO-8601",
  "reasoning": "...",
  "user_override": false
}
```

`session-init.sh` auto-invokes triage on fresh task. Downstream gates read `TRIAGE_LANE` env var or state file.

## Related

- `rules/common/lanes.md` — lane definitions
- `skills/preflight/SKILL.md` — pre-flight artifact format per lane
- `commands/triage.md` — manual override
