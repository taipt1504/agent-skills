# Refactor Clean

Safely identify and remove dead code with test verification for Java/Spring projects.

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

2. Generate comprehensive report in `.reports/dead-code-analysis.md`

3. Categorize findings by severity:
    - **SAFE**: Test utilities, unused private methods
    - **CAUTION**: Services, Repositories (check for Spring autowiring)
    - **DANGER**: Config classes, @Bean definitions, Event handlers

4. Propose safe deletions only

5. Before each deletion:
   ```bash
   # Run full test suite
   ./gradlew test
   
   # Verify tests pass
   # Apply change (delete file/method)
   
   # Re-run tests
   ./gradlew test
   
   # Rollback if tests fail
   git checkout -- <file>
   ```

6. Update DELETION_LOG.md with:
    - Files/methods deleted
    - Reason for deletion
    - Test verification status

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
- `@Component`/`@Service`/`@Repository` beans
- `@EventListener` / `@KafkaListener` handlers
- Domain events and aggregates
- Liquibase migration files

Never delete code without running tests first!
