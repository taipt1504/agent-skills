# Verification Pipeline Reference

Full 7-phase verification pipeline for Java Spring projects.

---

## When to Run

- After implementing a feature or fixing a bug
- Before creating a pull request
- When `/verify` command is invoked
- After refactoring or before any deployment

---

## Phase 1: Compile

```bash
# Gradle
./gradlew compileJava compileTestJava

# Maven
./mvnw compile test-compile
```

**STOP on failure.** All subsequent phases depend on compilation.

---

## Phase 2: Unit Tests

```bash
# Gradle -- unit tests only (exclude integration tests)
./gradlew test --tests "*Test" -x integrationTest

# Maven
./mvnw test -Dtest="*Test"
```

Report: pass/fail count, failing test names with assertion messages.

---

## Phase 3: Integration Tests

```bash
# Gradle
./gradlew integrationTest
# or
./gradlew test --tests "*IT"

# Maven
./mvnw verify -Dtest="*IT" -DfailIfNoTests=false
```

Requires Docker for Testcontainers. Skip with `--skip-integration` if Docker unavailable.

---

## Phase 4: Coverage Gate

```bash
# Gradle (JaCoCo)
./gradlew jacocoTestReport jacocoTestCoverageVerification

# Maven
./mvnw jacoco:report jacoco:check
```

| Threshold | Level | Action |
|-----------|-------|--------|
| >= 80% | PASS | Proceed |
| 60-79% | WARN | Flag for review |
| < 60% | BLOCK | Must increase coverage |

---

## Phase 5: Security Scan

```bash
# OWASP dependency check
./gradlew dependencyCheckAnalyze
# or
./mvnw org.owasp:dependency-check-maven:check
```

### Secrets Scan

```bash
# Hardcoded passwords
grep -rn "password\s*=\s*['\"][^$]" src/ --include="*.java" --include="*.yml" --include="*.properties"

# Hardcoded secrets
grep -rn "secret\s*=\s*['\"][^$]" src/ --include="*.java" --include="*.yml" --include="*.properties"

# Hardcoded API keys
grep -rn "api[._-]key\s*=\s*['\"][^$]" src/ --include="*.java" --include="*.yml" --include="*.properties"
```

**BLOCK** on hardcoded credentials. **WARN** on HIGH CVEs. **BLOCK** on CRITICAL CVEs.

---

## Phase 6: Static Analysis

### .block() Detection (WebFlux -- CRITICAL)

```bash
grep -rn "\.block()\|\.blockFirst()\|\.blockLast()\|Thread\.sleep" src/main/ --include="*.java"
```

### Field Injection Detection

```bash
grep -rn "@Autowired" src/main/ --include="*.java" | grep -v "constructor"
```

### Debug Statements

```bash
grep -rn "System\.out\.println\|System\.err\.println\|\.printStackTrace()" src/main/ --include="*.java"
```

### SELECT * Detection

```bash
grep -rn "SELECT \*" src/ --include="*.java" --include="*.sql"
```

### Formatting (Gradle)

```bash
./gradlew spotlessCheck   # Check
./gradlew spotlessApply   # Fix
```

### Severity Table

| Check | Severity |
|-------|----------|
| `.block()` in main source | CRITICAL (WebFlux) |
| `@Autowired` field injection | WARN |
| `System.out.println` | WARN |
| `SELECT *` | WARN |
| Entity in controller return | WARN |
| `Thread.sleep` in main source | WARN |
| `.printStackTrace()` | WARN |

---

## Phase 7: Diff Review

```bash
# Show what changed
git diff --stat
git diff HEAD~1 --name-only

# Review staged changes
git diff --cached
```

Review each changed file for:

- Unintended changes
- Missing error handling (`Mono.error`, `onErrorResume`)
- Potential edge cases
- CQRS violations (mixing command/query logic)
- Entities exposed in controller responses
- Missing `@Valid` on request bodies

---

## Pipeline Summary Output

```
VERIFICATION PIPELINE
====================
Phase 1 -- Compile:     PASS
Phase 2 -- Unit Tests:  PASS (45/45 passed)
Phase 3 -- Integration: PASS (12/12 passed)
Phase 4 -- Coverage:    PASS (83.2%)
Phase 5 -- Security:    PASS (0 critical, 1 high suppressed)
Phase 6 -- Static:      WARN (2 @Autowired fields found)
Phase 7 -- Diff:        3 files changed

VERDICT: PASS (1 warning)
Ready for PR: YES
```

---

## Quick Verification Modes

| Mode | Phases | Command (Gradle) | Use Case |
|------|--------|-------------------|----------|
| `quick` | 1-2 | `./gradlew clean build` | During development |
| `standard` | 1-4 | `./gradlew build test jacocoTestReport` | Before committing |
| `full` | 1-7 | `./gradlew clean build test jacocoTestReport dependencyCheckAnalyze` | Before PR / release |
| `security` | 5-6 only | `./gradlew dependencyCheckAnalyze` | Security-focused review |

## Continuous Mode

Run verification at mental checkpoints during long sessions:

```
After each handler/service  -> /verify quick
Tests written               -> /verify full
Before commit               -> /verify standard
Before PR                   -> /verify full
```

---

## Gradle Tasks Reference

```bash
./gradlew tasks                    # List all tasks
./gradlew build                    # Full build with tests
./gradlew build -x test            # Build without tests
./gradlew test                     # Run unit tests
./gradlew integrationTest          # Run integration tests
./gradlew test --tests "*.MyTest"  # Run specific test
./gradlew test --continuous        # Watch mode
./gradlew checkstyleMain           # Run Checkstyle
./gradlew spotbugsMain             # Run SpotBugs
./gradlew spotlessCheck            # Check formatting
./gradlew spotlessApply            # Apply formatting
./gradlew jacocoTestReport         # Generate coverage report
./gradlew dependencyCheckAnalyze   # OWASP vulnerability scan
```

## Maven Tasks Reference

```bash
./mvnw compile                     # Compile main sources
./mvnw test-compile                # Compile test sources
./mvnw test                        # Run unit tests
./mvnw verify                      # Run all tests including integration
./mvnw test -Dtest="*Test"         # Run specific test pattern
./mvnw jacoco:report               # Generate coverage report
./mvnw jacoco:check                # Verify coverage thresholds
./mvnw org.owasp:dependency-check-maven:check  # OWASP scan
```

---

## Integration with Hooks

| Hook | Coverage | Timing |
|------|----------|--------|
| PostToolUse | Single file | Immediate |
| Stop | Modified files | Session end |
| **This Pipeline** | Full project | On demand |

## Verification Checklist

- [ ] All 7 phases pass (or warnings acknowledged)
- [ ] Coverage >= 80% line coverage
- [ ] No CRITICAL CVEs in dependencies
- [ ] No `.block()` calls in main source (WebFlux)
- [ ] No `@Autowired` field injection
- [ ] No hardcoded secrets
- [ ] No debug statements (`System.out.println`, `printStackTrace`)
- [ ] No `SELECT *` queries
- [ ] Entities not exposed in controller responses
- [ ] Diff reviewed -- no unintended changes
