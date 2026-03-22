---
name: verify
description: Run build, test, lint, security, and static analysis pipeline. Modes -- quick, pre-commit, full, gate.
---

# /verify -- Build + Test + Security Pipeline

Run verification on current Java/Spring codebase. Supports multiple modes.

## Usage

```
/verify              -> defaults to "full"
/verify quick        -> build + compile only
/verify pre-commit   -> build + compile + tests + debug audit
/verify full         -> build + compile + lint + tests + security + debug audit
/verify gate         -> full + all reviewers + coverage gate + PR readiness check
```

## Prerequisites

- BUILD phase should be complete before running verification
- If no recent test runs exist, consider running `/build` first
- For `gate` mode, ensure all implementation tasks from the spec are complete

## Instructions

### Mode: `quick`

1. **Build Check**
   ```bash
   ./gradlew clean build -x test       # Gradle
   ./mvnw clean package -DskipTests -q  # Maven
   ```
2. **Compile Check**
   ```bash
   ./gradlew compileJava compileTestJava  # Gradle
   ./mvnw compile test-compile -q         # Maven
   ```
   If either fails -> STOP and report errors with file:line.

### Mode: `pre-commit`

All `quick` steps plus:

3. **Test Suite**
   ```bash
   ./gradlew test        # Gradle
   ./mvnw test -q        # Maven
   ```
   Report: pass/fail count.

4. **Debug Statement Audit**
   ```bash
   grep -rn --include="*.java" "System\.out\.\|System\.err\.\|\.printStackTrace()" src/main/ | head -10
   ```

### Mode: `full` (default)

All `quick` steps plus:

3. **Lint/Style Check**
   ```bash
   ./gradlew checkstyleMain spotbugsMain    # Gradle
   ./mvnw checkstyle:check spotbugs:check -q # Maven
   ```

4. **Test Suite**
   ```bash
   ./gradlew test jacocoTestReport        # Gradle
   ./mvnw test jacoco:report              # Maven
   ```
   Report: pass/fail count, coverage percentage.

5. **Security Scan**
   ```bash
   # Dependency vulnerabilities
   ./gradlew dependencyCheckAnalyze                        # Gradle
   ./mvnw org.owasp:dependency-check-maven:check           # Maven

   # Hardcoded secrets
   grep -rn --include="*.java" --include="*.yml" --include="*.properties" \
     -E "password\s*=\s*['\"][^'\"\$\{]|api[._-]?key\s*=\s*['\"][^'\"\$\{]|secret\s*=\s*['\"][^'\"\$\{]|token\s*=\s*['\"][^'\"\$\{]" \
     src/ | grep -v "test\|example\|placeholder" | head -20
   ```

6. **Static Analysis**
   ```bash
   # Blocking calls in reactive code
   grep -rn --include="*.java" "\.block()\|\.blockFirst()\|\.blockLast()" src/main/ | head -10
   # Field injection
   grep -rn --include="*.java" "@Autowired" src/main/java | grep -v "//\|test" | head -10
   # Debug statements
   grep -rn --include="*.java" "System\.out\.\|System\.err\.\|\.printStackTrace()" src/main/ | head -10
   ```

7. **Git Status**
   ```bash
   git status --short
   git diff --stat
   ```

### Mode: `gate`

All `full` steps plus:

8. **Coverage Gate**

   | Threshold | Level | Action |
   |-----------|-------|--------|
   | >= 80% | PASS | Proceed |
   | 60-79% | WARN | Flag for review |
   | < 60% | BLOCK | Must increase coverage |

9. **Build Artifact Check**
   ```bash
   ./gradlew bootJar --no-daemon 2>&1 | tail -10  # Gradle
   ./mvnw package -DskipTests -q 2>&1 | tail -10   # Maven
   ```

10. **Anti-Pattern Sweep**
    ```bash
    # N+1 patterns
    grep -rn --include="*.java" "findAll()\|getAll()" src/main/ | grep -v "test\|@Bean" | head -10
    # TODO/FIXME without ticket
    grep -rn --include="*.java" "TODO\|FIXME\|HACK" src/main/ | grep -v "//.*#[0-9]" | head -10
    # SELECT *
    grep -rn "SELECT \*" src/ --include="*.java" --include="*.sql" | head -10
    ```

11. **PR Readiness Verdict**
    Summarize all findings and produce final PASS/BLOCK verdict.

## Output Format

```
VERIFICATION REPORT
===================
Mode: [quick|pre-commit|full|gate]
Branch: {branch}  Commit: {short SHA}

Build:      [PASS/FAIL]
Compile:    [PASS/FAIL]
Lint:       [PASS/FAIL/SKIP]
Tests:      [X/Y passed, Z% coverage]
Security:   [PASS/WARN/BLOCK]
Static:     [PASS/WARN]
Coverage:   [PASS/WARN/BLOCK]  (gate mode only)

VERDICT: [PASS / BLOCKED]

Issues to Address:
1. [BLOCK] ...
2. [WARN] ...
```
