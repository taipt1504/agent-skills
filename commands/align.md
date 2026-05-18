---
name: align
description: Grill ambiguity, surface assumptions, extract vocabulary. Run before Plan when requirements vague (standard lane) or always (high-stakes lane). Output feeds Plan + Spec gates.
---

# /align — Requirements Grilling Gate

## Usage

```
/align                          # Re-align current task
/align <task description>       # Align a new task
/no-align                       # Skip (warns for high-stakes)
```

## First Action (MANDATORY)

1. Load `skills/align/SKILL.md`
2. Read pre-flight `.claude/memory/preflight/initial-*.md` (latest)
3. Read lane from `.claude/memory/state/current-triage.json`
4. If lane=trivial: refuse — Align skipped for trivial. Suggest Execute.
5. If lane=high-stakes OR (standard AND vague): proceed.

## Process

5-step protocol from `skills/align/SKILL.md`:

1. Restate problem (user confirms)
2. List assumptions (user corrects)
3. Surface unstated requirements (3-5 probes, `references/grill-questions.md`)
4. Extract vocabulary → CONTEXT.md
5. Produce alignment artifact

## Output

Save to `.claude/memory/align-artifacts/<YYYY-MM-DD>-<task-slug>.md`. Update CONTEXT.md if new vocab surfaced.

State explicitly:
```
## Alignment complete
**Lane:** <Standard | High-stakes>
**Requirements:** <count>
**Vocabulary added:** <count terms>
**Open questions for Brainstorm/Plan:** <count>
**Next gate:** <Brainstorm | Plan>
**Artifact:** <path>
```

## Lane behavior

| Lane | Behavior |
|---|---|
| Trivial | Refuse (skip) |
| Standard, request specific | Skip with one-line confirmation |
| Standard, request vague | Run full protocol |
| High-stakes | Run full protocol always |

## User override

"/no-align" → skip with warning if high-stakes ("flagged for reviewer attention"). Log `align_skipped: true` in workflow-state.

## Related

- `skills/align/SKILL.md` — full process
- `skills/align/references/grill-questions.md` — question library
- `commands/brainstorm.md` — typical next gate
- `templates/CONTEXT_TEMPLATE.md` — vocabulary destination
