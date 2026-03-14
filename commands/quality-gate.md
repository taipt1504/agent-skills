# Quality Gate

Run comprehensive quality checks across the codebase before merge/release.

## Instructions

Execute all quality checks in sequence. Report failures clearly. Block if CRITICAL threshold exceeded.

### 1. Compile Check

```bash
./gradlew compileJava compileTestJava --no-daemon 2>&1 | tail -20
# or
./mvnw compile test-compile -q 2>&1 | tail -20
```

**Gate**: BLOCK if compilation fails.

### 2. Unit & Integration Tests

```bash
./gradlew test --no-daemon 2>&1 | tail -30
# or
./mvnw test -q 2>&1 | tail -30
```

**Gate**: BLOCK if any test fails.

### 3. Code Coverage

```bash
./gradlew jacocoTestReport --no-daemon 2>&1 | tail -20
# Check coverage report
cat build/reports/jacoco/test/html/index.html 2>/dev/null |
  grep -o 'Total[^%]*%' | head -5
# or for Maven
cat target/site/jacoco/index.html 2>/dev/null |
  grep -o 'Total[^%]*%' | head -5
```

**Gate**: WARN if line coverage < 70%, BLOCK if < 50%.

### 4. Code Style / Checkstyle

```bash
./gradlew checkstyleMain --no-daemon 2>&1 | grep -E "ERROR|WARNING|violations" | head -20
# or
./mvnw checkstyle:check -q 2>&1 | grep -E "ERROR|WARNING" | head -20
```

**Gate**: WARN on style violations; BLOCK only if configured as required.

### 5. Security Scan

```bash
# Check for hardcoded secrets
grep -rn --include="*.java" --include="*.yml" --include="*.properties" \
  -E "password\s*=\s*['\"][^'\"\$\{]|api.key\s*=\s*['\"][^'\"\$\{]|secret\s*=\s*['\"][^'\"\$\{]" \
  src/ | grep -v "test\|spec\|example\|placeholder" | head -20

# Check for known vulnerable patterns
grep -rn --include="*.java" \
  -E "Runtime\.exec|ProcessBuilder|\.block\(\)|Thread\.sleep" \
  src/main/ | head -20

# Dependency vulnerability check (if OWASP plugin configured)
./gradlew dependencyCheckAnalyze --no-daemon 2>/dev/null | grep -E "CRITICAL|HIGH" | head -10
```

**Gate**: BLOCK if hardcoded credentials found. WARN on high-severity vulnerabilities.

### 6. Static Analysis — Key Anti-Patterns

```bash
# Find blocking calls in reactive code
echo "=== Blocking calls in reactive code ==="
grep -rn --include="*.java" "\.block()\|\.blockFirst()\|\.blockLast()" src/main/ | grep -v "test" | head -10

# Find field injection (should use constructor injection)
echo "=== Field injection ==="
grep -rn --include="*.java" "@Autowired" src/main/java | grep -v "//\|test\|Test" | head -10

# Find System.out usage
echo "=== System.out usage ==="
grep -rn --include="*.java" "System\.out\.\|System\.err\.\|e\.printStackTrace()" src/main/ | head -10

# Find TODO/FIXME without ticket
echo "=== Unresolved TODOs ==="
grep -rn --include="*.java" "TODO\|FIXME\|HACK\|XXX" src/main/ | grep -v "//.*#[0-9]" | head -10

# Find N+1 patterns
echo "=== Potential N+1 queries ==="
grep -rn --include="*.java" "findAll()\|getAll()" src/main/ | grep -v "test\|@Bean" | head -10
```

### 7. Build Artifact Check

```bash
# Verify JAR builds successfully
./gradlew bootJar --no-daemon 2>&1 | tail -10
# or
./mvnw package -DskipTests -q 2>&1 | tail -10

# Check JAR size (warn if > 100MB)
find build/libs target -name "*.jar" 2>/dev/null | xargs ls -lh 2>/dev/null | grep -v "plain"
```

**Gate**: BLOCK if build fails.

### 8. Actuator Health Check (if running)

```bash
# Check if app is running and healthy
curl -sf http://localhost:8080/actuator/health 2>/dev/null |
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','UNKNOWN'))" 2>/dev/null ||
  echo "App not running — skipping health check"
```

## Output Format

```
QUALITY GATE REPORT
===================
Project: {project name from settings.gradle or pom.xml}
Date: {today}
Branch: {git branch}
Commit: {git rev-parse --short HEAD}

RESULTS
-------
✅ Compilation           — PASS
✅ Tests                 — PASS (142 tests, 0 failures)
⚠️  Coverage             — WARN (68% line coverage, threshold: 70%)
✅ Code Style            — PASS
❌ Security Scan         — BLOCK (hardcoded password in application-dev.yml:12)
✅ Static Analysis       — PASS
✅ Build                 — PASS (42MB)
➖ Health Check          — SKIPPED (app not running)

CRITICAL FINDINGS
-----------------
[BLOCK] Hardcoded credential
File: src/main/resources/application-dev.yml:12
Issue: spring.datasource.password=mypassword123
Fix: Use ${DB_PASSWORD} environment variable

VERDICT: ❌ BLOCKED
Reason: 1 CRITICAL issue must be resolved before merge
```

## Threshold Summary

| Check | WARN | BLOCK |
|-------|------|-------|
| Tests | any failure | any failure |
| Coverage | < 70% | < 50% |
| Blocking calls in reactive code | any found | — |
| Hardcoded credentials | — | any found |
| Build | — | failure |
| Compilation | — | failure |
