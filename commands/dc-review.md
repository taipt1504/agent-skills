---
name: dc-review
description: Multi-aspect code review -- security, quality, reactive correctness, and performance. Blocks commit on critical issues.
---

# /dc-review -- Multi-Aspect Code Review

## First Action (MANDATORY)

Before anything else, update the workflow state:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
mkdir -p "$PROJECT_ROOT/.claude"
python3 -c "
import json, datetime, os
path = os.environ['PROJECT_ROOT'] + '/.claude/workflow-state.json'
state = {}
if os.path.exists(path):
    with open(path) as f:
        state = json.load(f)
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
state['phase'] = 'REVIEW'
state.setdefault('phaseHistory', [])
already = any(e.get('phase') == 'VERIFY' for e in state['phaseHistory'])
if not already:
    state['phaseHistory'].append({'phase': 'VERIFY', 'completedAt': now, 'verdict': 'PASS'})
with open(path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
print('workflow-state.json updated: phase=REVIEW')
" 2>/dev/null || echo "workflow-state.json update skipped"
```

Comprehensive security and quality review of uncommitted changes for Java Spring projects. Consolidates code-review, security-review, and Spring-specific checks into a single command.

## Usage

```
/dc-review              -> review all uncommitted changes
/dc-review security     -> security-focused review only
/dc-review performance  -> performance-focused review only
/dc-review <file>       -> review specific file
```

## Prerequisites

- Run `/verify` before `/dc-review` to catch compilation and test failures first
- If reviewing a feature implementation, ensure the approved spec is available for adherence checking

## Subagent Context (pass to spawned agent)

When invoking the **reviewer** agent, include in its prompt:

- **Phase**: You are in the **REVIEW** phase of SDD (PLAN → SPEC → BUILD → VERIFY → REVIEW)
- **Skill protocol**: Load `devco-agent-skills:bootstrap` first — contains the skill registry. Before every file operation, load the matching skill and announce it.
- **Summer check**: Scan `build.gradle` for `io.f8a.summer` → if found, load `devco-agent-skills:summer-core` first
- **Hard blocks**: No `.block()` in src/main/. No git commit/push. No code without approved plan+spec.
- **Classify first**: For each changed file, classify its type, then load the matching skill BEFORE running that checklist (e.g., `devco-agent-skills:spring-security` for security files, `devco-agent-skills:database-patterns` for repositories)
- **Suggested skill**: Dynamic — determined per file classification

## Instructions

1. Get changed files:

```bash
git diff --name-only HEAD -- '*.java' '*.yml' '*.yaml' '*.gradle'
```

2. For each changed file, run all review aspects:

### Security Issues (CRITICAL)

- Hardcoded credentials, API keys, tokens, DB passwords
- SQL injection vulnerabilities (string concatenation in queries)
- Missing input validation (`@Valid`, Bean Validation)
- Insecure dependencies (run `./gradlew dependencyCheckAnalyze`)
- Secrets in configuration files
- Missing `@PreAuthorize` on sensitive endpoints

### Reactive Issues (CRITICAL -- WebFlux)

- `.block()`, `.blockFirst()`, `.blockLast()` calls
- `Thread.sleep()` in reactive chains
- `.subscribe()` inside reactive pipelines (fire-and-forget)
- Missing error handling (no `onErrorResume`/`onErrorMap`)

### Performance Issues (HIGH)

- N+1 query patterns (findAll in loops, missing @EntityGraph)
- Missing connection pool configuration
- Unbounded collections without pagination
- Missing caching for repeated expensive calls
- Missing timeouts on WebClient/external service calls

### Code Quality (HIGH)

- Methods > 50 lines
- Classes > 800 lines
- Nesting depth > 4 levels
- Missing error handling
- `System.out.println` or `printStackTrace` statements
- TODO/FIXME comments without tickets
- Missing Javadoc for public APIs
- Field injection (`@Autowired` on fields)

### Best Practices (MEDIUM)

- Mutation patterns (use immutable builders instead)
- Missing tests for new code
- Magic numbers without constants
- Circular dependencies

3. Generate report with:
    - Severity: CRITICAL, HIGH, MEDIUM, LOW
    - File location and line numbers
    - Issue description
    - Suggested fix with code example

4. Block commit if CRITICAL or HIGH issues found

## Output Format

```
CODE REVIEW REPORT
==================
Files Reviewed: X

CRITICAL (Must Fix)
-------------------
[CRITICAL] SQL Injection
File: OrderRepository.java:45
Issue: String concatenation in SQL query
Fix: Use parameterized query with .bind()

[CRITICAL] Blocking call in reactive chain
File: OrderService.java:78
Issue: .block() used in WebFlux service
Fix: Return Mono/Flux, compose with flatMap

HIGH (Should Fix)
-----------------
[HIGH] Field injection
File: UserService.java:15
Issue: @Autowired on field
Fix: Use constructor injection with @RequiredArgsConstructor

[HIGH] Missing error handling
File: PaymentService.java:42
Issue: No onErrorResume in reactive chain
Fix: Add error handling for downstream failures

MEDIUM (Consider)
-----------------
[MEDIUM] Method too long
File: OrderService.java:100
Issue: Method is 67 lines (limit: 50)
Fix: Extract helper methods

VERDICT: [APPROVE / BLOCK]
```

## Two-Stage Review Orchestration

This command orchestrates two sequential review stages:

### Stage 1: Spec Compliance Review

1. Read the approved spec from `.claude/docs/specs/`
2. Read the git diff (baseline SHA from `workflow-state.json` → current SHA)
3. Check **every** acceptance criterion in the spec is met
4. Check no over-engineering beyond spec scope
5. Check no missing requirements

**Output**: `SPEC_COMPLIANT` or `SPEC_ISSUES: [list]`

**If SPEC_ISSUES**: Send issues back to implementer. Do NOT proceed to Stage 2.

### Stage 2: Code Quality Review (only after Stage 1 passes)

1. Run the full code quality review (all checklists above: Security, Reactive, Performance, Code Quality, Best Practices)
2. Spring-specific checks from CLAUDE.md NEVER rules
3. Categorize findings: **CRITICAL** / **IMPORTANT** / **MINOR**

### Verdict Logic

| Condition | Verdict | Action |
|-----------|---------|--------|
| 0 CRITICAL issues | **APPROVED** | Task is done |
| IMPORTANT items only (no CRITICAL) | **APPROVED WITH NOTES** | Task done, notes logged |
| ≥1 CRITICAL issue | **REJECTED** | Back to implementer with feedback |

### After Review Complete

1. Update `.claude/workflow-state.json`:
   - Add `{"phase": "REVIEW", "completedAt": "{ISO timestamp}", "verdict": "{APPROVED|REJECTED}"}` to `phaseHistory`
   - Set `phase` to `"COMPLETE"` (if approved) or `"BUILD"` (if rejected, for re-implementation)
2. Output final verdict with summary
3. Task is now **DONE** (if approved)

## Verdict Rules

- **BLOCK** if any CRITICAL or unresolved HIGH issues
- **APPROVE** with warnings if only MEDIUM/LOW issues
- Never approve code with security vulnerabilities or blocking calls in WebFlux
