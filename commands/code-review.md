# Code Review

Comprehensive security and quality review of uncommitted changes for Java Spring projects.

## Instructions

1. Get changed files:

```bash
git diff --name-only HEAD -- '*.java' '*.yml' '*.yaml' '*.gradle'
```

2. For each changed file, check for:

**Security Issues (CRITICAL):**

- Hardcoded credentials, API keys, tokens, DB passwords
- SQL injection vulnerabilities (string concatenation in queries)
- Missing input validation (`@Valid`, Bean Validation)
- Insecure dependencies (run `./gradlew dependencyCheckAnalyze`)
- Secrets in configuration files
- Missing `@PreAuthorize` on sensitive endpoints

**Reactive Issues (CRITICAL - WebFlux):**

- `.block()`, `.blockFirst()`, `.blockLast()` calls
- `Thread.sleep()` in reactive chains
- `.subscribe()` inside reactive pipelines (fire-and-forget)
- Missing error handling (no `onErrorResume`/`onErrorMap`)

**Code Quality (HIGH):**

- Methods > 50 lines
- Classes > 800 lines
- Nesting depth > 4 levels
- Missing error handling
- `System.out.println` or `printStackTrace` statements
- TODO/FIXME comments without tickets
- Missing Javadoc for public APIs
- Field injection (`@Autowired` on fields)

**Best Practices (MEDIUM):**

- Mutation patterns (use immutable builders instead)
- Missing tests for new code
- Magic numbers without constants
- Circular dependencies
- N+1 query patterns

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

HIGH (Should Fix)
-----------------
[HIGH] Blocking call in reactive chain
File: OrderService.java:78
Issue: .block() used in WebFlux service
Fix: Return Mono/Flux, compose with flatMap

MEDIUM (Consider)
-----------------
[MEDIUM] Field injection
File: UserService.java:15
Issue: @Autowired on field
Fix: Use constructor injection

VERDICT: [APPROVE / BLOCK]
```

Never approve code with security vulnerabilities or blocking calls in WebFlux!
