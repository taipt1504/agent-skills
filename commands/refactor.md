---
name: refactor
description: Dead code cleanup and safe refactoring with test verification for Java/Spring projects.
---

# /refactor -- Dead Code Cleanup & Refactoring

Safely identify and remove dead code, clean up dependencies, and refactor with test verification.

## Usage

```
/refactor              -> full dead code analysis + refactoring suggestions
/refactor dead-code    -> identify and remove unused code only
/refactor dependencies -> clean unused Gradle/Maven dependencies
/refactor <file>       -> refactor specific file
```

## Instructions

1. Run dead code analysis:
   ```bash
   # Gradle dependency analysis
   ./gradlew dependencies --configuration compileClasspath
   ./gradlew buildHealth  # If using dependency-analysis plugin

   # SpotBugs for unused code
   ./gradlew spotbugsMain

   # Find potentially unused classes
   find src/main -name "*.java" -exec basename {} .java \; | while read class; do
     count=$(grep -r "import.*$class\|new $class\|$class\." --include="*.java" src/ | wc -l)
     if [ "$count" -le 1 ]; then echo "Potentially unused: $class"; fi
   done
   ```

2. Generate comprehensive report

3. Categorize findings by severity:
    - **SAFE**: Test utilities, unused private methods
    - **CAUTION**: Services, Repositories (check for Spring autowiring)
    - **DANGER**: Config classes, @Bean definitions, Event handlers

4. Propose safe deletions only

5. Before each deletion:
   ```bash
   # Run full test suite
   ./gradlew test

   # Apply change (delete file/method)

   # Re-run tests
   ./gradlew test

   # Rollback if tests fail
   git checkout -- <file>
   ```

6. Update report with deletion log

## Output Format

```
DEAD CODE ANALYSIS
==================

SAFE TO REMOVE (test verified):
- src/main/java/.../UnusedHelper.java - No references
- OrderService.legacyMethod() - Replaced by newMethod()

CAUTION (verify Spring usage):
- src/main/java/.../OldEventListener.java - Check @EventListener usage

DANGER (do not remove):
- src/main/java/.../AppConfig.java - Spring configuration

Dependencies to Remove (build.gradle):
- commons-lang3 - Not imported anywhere
- guava - Replaced by Java 17 features

Summary:
- Files to delete: X
- Methods to remove: Y
- Dependencies to clean: Z
```

## Never Remove

- `@Configuration` classes
- `@Bean` methods
- `@Component`/`@Service`/`@Repository` beans (unless confirmed unused by Spring context)
- `@EventListener` / `@KafkaListener` handlers
- Domain events and aggregates
- Flyway/Liquibase migration files

## Refactoring Patterns

### Extract Method (method > 50 lines)

Identify methods exceeding 50 lines and suggest extraction points based on logical grouping.

### Reduce Nesting (depth > 4)

Convert nested if/else chains to early returns or strategy pattern.

### Replace Mutation with Immutability

Convert mutable DTOs/entities to records or `@Value` classes with builders.

### Consolidate Duplicate Code

Find similar code blocks across files and extract shared utilities.

## Safety Rules

- Never delete code without running tests first
- One deletion at a time -- verify between each
- Keep git history clean -- each refactoring is one logical change
- Don't refactor while fixing bugs (separate concerns)
