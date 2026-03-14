---
name: verification-loop
description: Comprehensive verification system for Java Spring backend projects. Use after completing features, before PR, after refactoring. Runs build, compile, tests, security, and diff review with Gradle.
---

# Verification Loop Skill

Comprehensive verification for Java 17+ Spring WebFlux/Boot backend projects.

## When to Use

Invoke this skill:

- After completing a feature or significant code change
- Before creating a PR
- When you want to ensure quality gates pass
- After refactoring

## Verification Phases

### Phase 1: Build Verification

```bash
# Clean build (skip tests for speed)
./gradlew clean build -x test 2>&1 | tail -30
```

If build fails, **STOP and fix** before continuing.

### Phase 2: Compile Check

```bash
# Compile main and test sources
./gradlew compileJava compileTestJava 2>&1 | tail -30
```

Report all compilation errors with file:line. Fix before continuing.

### Phase 3: Static Analysis

```bash
# Checkstyle (if configured)
./gradlew checkstyleMain 2>&1 | tail -20

# SpotBugs (if configured)
./gradlew spotbugsMain 2>&1 | tail -20

# Spotless format check
./gradlew spotlessCheck 2>&1 | tail -20
```

Fix or apply formatting:

```bash
./gradlew spotlessApply
```

### Phase 4: Test Suite

```bash
# Run all tests with coverage
./gradlew test jacocoTestReport 2>&1 | tail -50

# Coverage report location
cat build/reports/jacoco/test/html/index.html 2>/dev/null | grep -oP 'Total.*?[0-9]+%' | head -1
```

Report:

- Total tests: X
- Passed: X
- Failed: X
- Coverage: X% (target: 80% minimum)

### Phase 5: Integration Tests (Optional)

```bash
# If Testcontainers configured
./gradlew integrationTest 2>&1 | tail -30
```

Requires Docker running for Testcontainers.

### Phase 6: Security Scan

```bash
# OWASP Dependency Check (if configured)
./gradlew dependencyCheckAnalyze 2>&1 | tail -30

# Check for hardcoded secrets
grep -rn "password\s*=" --include="*.java" --include="*.yml" --include="*.properties" . 2>/dev/null | grep -v "test" | head -10
grep -rn "secret\s*=" --include="*.java" --include="*.yml" . 2>/dev/null | grep -v "test" | head -10

# Check for debug statements
grep -rn "System.out.println\|System.err.println\|\.printStackTrace()" --include="*.java" src/main/ 2>/dev/null | head -10
```

### Phase 7: Reactive Code Check (Spring WebFlux)

```bash
# Check for blocking calls in reactive code
grep -rn "\.block()\|\.blockFirst()\|\.blockLast()" --include="*.java" src/main/ 2>/dev/null | head -10

# Check for Thread.sleep in main code
grep -rn "Thread.sleep" --include="*.java" src/main/ 2>/dev/null | head -5
```

### Phase 8: Diff Review

```bash
# Show what changed
git diff --stat
git diff HEAD~1 --name-only

# Review changes in detail
git diff --cached
```

Review each changed file for:

- Unintended changes
- Missing error handling (Mono.error, onErrorResume)
- Potential edge cases
- CQRS violations (mixing command/query logic)

## Output Format

After running all phases, produce a verification report:

```
VERIFICATION REPORT
==================

Build:      [PASS/FAIL]
Compile:    [PASS/FAIL] (X errors)
Checkstyle: [PASS/FAIL] (X issues)
SpotBugs:   [PASS/FAIL] (X bugs)
Tests:      [PASS/FAIL] (X/Y passed, Z% coverage)
Security:   [PASS/FAIL] (X issues)
Reactive:   [PASS/FAIL] (X blocking calls)
Diff:       [X files changed]

Overall:    [READY/NOT READY] for PR

Issues to Fix:
1. [High] ...
2. [Medium] ...
3. [Low] ...
```

## Quick Verification Modes

### `/verify quick`

```bash
./gradlew clean build
```

### `/verify full`

All phases above.

### `/verify pre-commit`

```bash
./gradlew build test
grep -rn "System.out.println\|\.block()" --include="*.java" src/main/
```

### `/verify pre-pr`

```bash
./gradlew clean build test jacocoTestReport dependencyCheckAnalyze
```

## Continuous Mode

For long sessions, run verification:

- After completing each handler/service
- After finishing a component
- Before moving to next task

Set mental checkpoints at:

```
Feature complete → /verify quick
Tests written   → /verify full
Before commit   → /verify pre-commit
Before PR       → /verify pre-pr
```

## Integration with Hooks

This skill complements hooks but provides deeper verification:

| Hook           | Coverage       | Timing      |
|----------------|----------------|-------------|
| PostToolUse    | Single file    | Immediate   |
| Stop           | Modified files | Session end |
| **This Skill** | Full project   | On demand   |

## Gradle Tasks Reference

```bash
# Common tasks
./gradlew tasks                    # List all tasks
./gradlew build                    # Full build with tests
./gradlew build -x test            # Build without tests
./gradlew test                     # Run unit tests
./gradlew integrationTest          # Run integration tests
./gradlew test --tests "*.MyTest"  # Run specific test

# Quality tasks
./gradlew checkstyleMain           # Run Checkstyle
./gradlew spotbugsMain             # Run SpotBugs
./gradlew spotlessCheck            # Check formatting
./gradlew spotlessApply            # Apply formatting

# Reports
./gradlew jacocoTestReport         # Generate coverage report
./gradlew dependencyCheckAnalyze   # OWASP vulnerability scan
```
