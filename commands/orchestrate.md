# Orchestrate Command

Sequential agent workflow for complex tasks.

## Usage

`/orchestrate [workflow-type] [task-description]`

## Workflow Types

### feature

Full feature implementation workflow:

```
planner -> tdd-guide -> code-reviewer -> security-reviewer
```

### bugfix

Bug investigation and fix workflow:

```
explorer -> tdd-guide -> code-reviewer
```

### refactor

Safe refactoring workflow:

```
architect -> code-reviewer -> tdd-guide
```

### security

Security-focused review:

```
security-reviewer -> code-reviewer -> architect
```

### review

Parallel multi-reviewer workflow (all reviewers run simultaneously):

```
[parallel: code-reviewer, spring-reviewer, security-reviewer, database-reviewer]
-> merge results -> final report
```

Use for comprehensive pre-PR review when changes span multiple layers.

## Execution Pattern

For each agent in the workflow:

1. **Invoke agent** with context from previous agent
2. **Collect output** as structured handoff document
3. **Pass to next agent** in chain
4. **Aggregate results** into final report

## Handoff Document Format (v2)

Between agents, create structured handoff:

```markdown
## HANDOFF: [previous-agent] -> [next-agent]

### Context
[Summary of what was done]

### Findings
| # | Severity | Finding | File | Line |
|---|----------|---------|------|------|
| 1 | CRITICAL | .block() in reactive chain | OrderService.java | 45 |
| 2 | WARN | Missing @Valid annotation | OrderController.java | 23 |

### Files Modified
[List of files touched]

### Open Questions
[Unresolved items for next agent]

### Recommendations
[Suggested next steps]
```

### Parallel Results Table (for review workflow)

When merging results from parallel agents:

```markdown
## PARALLEL RESULTS

| Agent | Status | Critical | Warnings | Summary |
|-------|--------|----------|----------|---------|
| code-reviewer | PASS | 0 | 2 | Naming, complexity |
| security-reviewer | WARN | 1 | 0 | Hardcoded timeout |
| database-reviewer | PASS | 0 | 1 | Missing index |

### Merged Findings (deduplicated, sorted by severity)
[Combined findings from all agents]
```

## Example: Feature Workflow

```
/orchestrate feature "Add user authentication"
```

Executes:

1. **Planner Agent**
    - Analyzes requirements
    - Creates implementation plan
    - Identifies dependencies
    - Output: `HANDOFF: planner -> tdd-guide`

2. **TDD Guide Agent**
    - Reads planner handoff
    - Writes tests first
    - Implements to pass tests
    - Output: `HANDOFF: tdd-guide -> code-reviewer`

3. **Code Reviewer Agent**
    - Reviews implementation
    - Checks for issues
    - Suggests improvements
    - Output: `HANDOFF: code-reviewer -> security-reviewer`

4. **Security Reviewer Agent**
    - Security audit
    - Vulnerability check
    - Final approval
    - Output: Final Report

## Final Report Format

```
ORCHESTRATION REPORT
====================
Workflow: feature
Task: Add user authentication
Agents: planner -> tdd-guide -> code-reviewer -> security-reviewer

SUMMARY
-------
[One paragraph summary]

AGENT OUTPUTS
-------------
Planner: [summary]
TDD Guide: [summary]
Code Reviewer: [summary]
Security Reviewer: [summary]

FILES CHANGED
-------------
[List all files modified]

TEST RESULTS
------------
[Test pass/fail summary]

SECURITY STATUS
---------------
[Security findings]

RECOMMENDATION
--------------
[SHIP / NEEDS WORK / BLOCKED]
```

## Parallel Execution

For independent checks, run agents in parallel:

```markdown
### Parallel Phase
Run simultaneously:
- code-reviewer (quality)
- security-reviewer (security)
- architect (design)

### Merge Results
Combine outputs into single report
```

## Arguments

$ARGUMENTS:

- `feature <description>` - Full feature workflow
- `bugfix <description>` - Bug fix workflow
- `refactor <description>` - Refactoring workflow
- `security <description>` - Security review workflow
- `review <description>` - Parallel multi-reviewer workflow
- `custom <agents> <description>` - Custom agent sequence

## Custom Workflow Example

```
/orchestrate custom "architect,tdd-guide,code-reviewer" "Redesign caching layer"
```

## Tips

1. **Start with planner** for complex features
2. **Always include code-reviewer** before merge
3. **Use security-reviewer** for auth/payment/PII
4. **Keep handoffs concise** - focus on what next agent needs
5. **Run verification** between agents if needed
