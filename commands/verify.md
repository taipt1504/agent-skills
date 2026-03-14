# Verification Command

Run comprehensive verification on current Java/Spring codebase state.

## Instructions

Execute verification in this exact order:

1. **Build Check**
   ```bash
   ./gradlew clean build -x test
   ```
    - If it fails, report errors and STOP

2. **Compile Check**
   ```bash
   ./gradlew compileJava compileTestJava
   ```
    - Report all compilation errors with file:line

3. **Lint/Style Check**
   ```bash
   ./gradlew checkstyleMain spotbugsMain
   ```
    - Report warnings and errors

4. **Test Suite**
   ```bash
   ./gradlew test
   ```
    - Report pass/fail count
    - Report coverage percentage (if Jacoco configured)

5. **Security Scan**
   ```bash
   ./gradlew dependencyCheckAnalyze
   ```
    - Report any HIGH/CRITICAL CVEs

6. **Debug Statement Audit**
   ```bash
   grep -rn "System.out.println\|printStackTrace" --include="*.java" src/main/
   ```
    - Report locations of debug statements

7. **Git Status**
   ```bash
   git status --short
   git diff --stat HEAD~1
   ```
    - Show uncommitted changes
    - Show files modified since last commit

## Output

Produce a concise verification report:

```
VERIFICATION: [PASS/FAIL]
=========================

Build:      [OK/FAIL]
Compile:    [OK/X errors]
Checkstyle: [OK/X issues]
SpotBugs:   [OK/X bugs]
Tests:      [X/Y passed, Z% coverage]
Security:   [OK/X CVEs found]
Debug:      [OK/X statements found]

Ready for PR: [YES/NO]

Issues to Address:
------------------
1. [Issue description and fix]
2. [Issue description and fix]
```

## Arguments

$ARGUMENTS can be:

- `quick` - Only build + compile
- `full` - All checks (default)
- `pre-commit` - Build + tests + debug audit
- `pre-pr` - Full checks plus security scan

## Quick Commands

```bash
# Quick verification
./gradlew clean build

# Full verification with coverage
./gradlew clean build test jacocoTestReport

# Pre-PR verification
./gradlew clean build test dependencyCheckAnalyze
```
