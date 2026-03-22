---
name: review
description: Multi-aspect code review -- security, quality, reactive correctness, and performance. Blocks commit on critical issues.
---

# /review -- Multi-Aspect Code Review

Comprehensive security and quality review of uncommitted changes for Java Spring projects. Consolidates code-review, security-review, and Spring-specific checks into a single command.

## Usage

```
/review              -> review all uncommitted changes
/review security     -> security-focused review only
/review performance  -> performance-focused review only
/review <file>       -> review specific file
```

## Prerequisites

- Run `/verify` before `/review` to catch compilation and test failures first
- If reviewing a feature implementation, ensure the approved spec is available for adherence checking

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

## Verdict Rules

- **BLOCK** if any CRITICAL or unresolved HIGH issues
- **APPROVE** with warnings if only MEDIUM/LOW issues
- Never approve code with security vulnerabilities or blocking calls in WebFlux
