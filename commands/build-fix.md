---
name: build-fix
description: Incrementally fix Java/Gradle/Maven build and compilation errors for Spring Boot projects. One error at a time for safety.
---

# /build-fix -- Fix Build/Compile Errors

Incrementally fix Java/Gradle build and compilation errors for Spring Boot (MVC and WebFlux) projects.

## Instructions

1. **Run build:**
   ```bash
   ./gradlew clean build 2>&1 | tee build-output.log
   ```

2. **Parse error output:**
    - Group by file
    - Sort by severity (compilation > runtime > warnings)
    - Identify error category

3. **For each error:**
    - Show error context (5 lines before/after)
    - Explain the issue
    - Propose minimal fix
    - Apply fix
    - Re-run build
    - Verify error resolved

4. **Stop if:**
    - Fix introduces new errors
    - Same error persists after 3 attempts
    - User requests pause

5. **Show summary:**
    - Errors fixed
    - Errors remaining
    - New errors introduced (if any)

Fix one error at a time for safety!

## Common Error Categories

### 1. Compilation Errors

```bash
# Symbol not found -> Add missing import
# Type mismatch (Mono<Order> vs Order) -> Keep reactive chain, don't unwrap
```

### 2. Spring Boot Configuration Errors

```bash
# Bean not found -> Add @Repository/@Component or check component scan
# Circular dependency -> Use @Lazy, refactor, or use ApplicationEventPublisher
```

### 3. Gradle Dependency Errors

```bash
# Dependency resolution failed -> Check repositories, version, or --refresh-dependencies
# Version conflict -> Add exclusions in build.gradle
```

### 4. Liquibase/Flyway Migration Errors

```bash
# Migration failed -> Check changeset format, ensure valid SQL
```

### 5. JPA/Database Errors (Spring MVC)

```bash
# Entity mapping error -> Add @Column annotation or check field type
# LazyInitializationException -> Use @Transactional or @EntityGraph
```

### 6. R2DBC/Database Errors (Spring WebFlux)

```bash
# Mapping error -> Check @Table, @Id annotations match DB schema
```

### 7. Reactive Stream Errors (Spring WebFlux)

```bash
# Blocking call detected -> Remove .block(), use flatMap/then instead
```

### 8. Spring MVC Specific Errors

```bash
# Request mapping conflict -> Ensure unique URL patterns or HTTP methods
# RestTemplate timeout -> Configure timeouts in bean
```

## Diagnostic Commands

```bash
# Full build with stack trace
./gradlew clean build --stacktrace

# Compile only (faster)
./gradlew compileJava

# Check dependencies
./gradlew dependencies --configuration compileClasspath

# Refresh dependencies
./gradlew --refresh-dependencies

# Check for dependency conflicts
./gradlew dependencyInsight --dependency spring-boot
```

## Fix Strategy

### Priority Order

1. **Compilation errors first** - Code won't run without these
2. **Spring context errors** - Bean wiring issues
3. **Database/migration errors** - Data layer issues
4. **Runtime warnings** - Less critical

### Minimal Diff Approach

- Change only what's necessary
- Don't refactor while fixing
- Keep existing code style
- Add imports, not rewrite classes

## Output Format

```
BUILD FIX REPORT
================

Initial State: 5 errors, 3 warnings

FIXED:
[1/5] OrderService.java:23 - Added missing import
[2/5] OrderRepository.java:45 - Fixed R2DBC mapping annotation
[3/5] build.gradle:12 - Added missing dependency
[4/5] OrderConfig.java:8 - Fixed circular dependency with @Lazy
[5/5] changelog-001.xml:15 - Fixed Liquibase syntax

REMAINING: 0 errors

Final State: BUILD SUCCESSFUL

Next Steps:
- Run tests: ./gradlew test
- Review warnings when convenient
```

## Quick Fix Reference

| Error                         | Quick Fix                          |
|-------------------------------|------------------------------------|
| `cannot find symbol`          | Add import or dependency           |
| `incompatible types`          | Check generics, reactive types     |
| `bean not found`              | Add @Component/@Repository         |
| `circular dependency`         | Use @Lazy or refactor              |
| `block() not supported`       | Use flatMap/then instead (WebFlux) |
| `R2DBC mapping failed`        | Check @Table, @Column annotations  |
| `JPA MappingException`        | Check @Entity, @Column annotations |
| `LazyInitializationException` | Use @Transactional or @EntityGraph |
| `Liquibase validation`        | Check XML/YAML syntax              |
| `dependency not found`        | Check version, repositories        |
| `RestTemplate timeout`        | Configure timeout in bean          |
