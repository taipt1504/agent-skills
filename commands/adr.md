# Architecture Decision Record (ADR)

Create a structured ADR for the current architectural decision or design choice.

## Instructions

1. Gather context for the ADR:

```bash
# Find existing ADRs
find . -path "*/docs/adr/*.md" -o -path "*/adr/*.md" 2>/dev/null | head -20

# Check the latest ADR number
ls docs/adr/ 2>/dev/null | sort -n | tail -5
```

2. Understand the decision context:
   - Ask the user: "What is the architectural decision or design choice you want to document?"
   - If not provided, check `git log --oneline -10` to identify recent significant changes

3. Create the ADR file in `docs/adr/` (create directory if it doesn't exist):
   - File naming: `ADR-{number}-{short-title-kebab-case}.md`
   - Increment from the last existing ADR number (start at ADR-001 if none exist)

4. Populate the ADR with the following template:

```markdown
# ADR-{NUMBER}: {Title}

**Date**: {YYYY-MM-DD}
**Status**: Proposed | Accepted | Deprecated | Superseded by ADR-XXX
**Deciders**: {team members or roles involved}

## Context

{Describe the situation, problem, or forces that led to this decision.
Include relevant constraints, requirements, and background.}

## Decision

{State the decision clearly in one sentence.
Example: "We will use R2DBC instead of JPA for database access in the order service."}

## Rationale

{Explain WHY this decision was made. Reference the evaluation criteria.}

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **Option A (Chosen)** | ... | ... |
| Option B | ... | ... |
| Option C | ... | ... |

### Evaluation Criteria

- {Criterion 1 and how it was weighted}
- {Criterion 2}

## Consequences

### Positive
- {Expected benefit 1}
- {Expected benefit 2}

### Negative / Trade-offs
- {Trade-off 1}
- {Mitigation strategy if applicable}

### Neutral
- {Impact that is neither positive nor negative}

## Implementation Notes

{Optional: specific implementation details, migration steps, or code examples.}

```java
// Example code if applicable
```

## Related Decisions

- Supersedes: ADR-XXX (if replacing a previous decision)
- Related to: ADR-XXX
```

5. After creating the ADR:
   - Print the full path of the created file
   - Summarize the key decision in 1-2 sentences
   - Suggest adding a link to the ADR in the relevant code module's README or in CLAUDE.md

## Output

```
ADR created: docs/adr/ADR-{NUMBER}-{title}.md

Decision: {1-sentence summary}

Next steps:
- Review and update Status from "Proposed" to "Accepted" when approved
- Link this ADR from relevant code: // See ADR-{NUMBER} for rationale
- Share with team for feedback
```
