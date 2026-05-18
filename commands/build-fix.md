---
name: build-fix
description: Incrementally fix Java/Gradle/Maven build and compilation errors for Spring Boot projects. One error at a time for safety.
---

# /build-fix -- Fix Build/Compile Errors

Incrementally fix Java/Gradle build and compilation errors for Spring Boot (MVC and WebFlux) projects.

## Subagent Context (pass to spawned agent)

- **Phase**: BUILD (exception path) of SDD (PLAN → SPEC → BUILD → VERIFY → REVIEW)
- **Skill protocol**: Load `devco-agent-skills:bootstrap` first. Announce skill before every file operation.
- **Summer check**: Scan `build.gradle` for `io.f8a.summer` → load `devco-agent-skills:summer-core` first
- **Hard blocks**: No `.block()` in src/main/. No git commit/push. No code without approved plan+spec.
- **Exception path**: Fix errors only, no architecture changes. PLAN/SPEC gates do not apply.
- **Suggested skill**: `devco-agent-skills:coding-standards` for Java patterns/imports

## Instructions

1. **Run build:** `./gradlew clean build 2>&1 | tee build-output.log`

2. **Parse errors:** group by file, sort by severity (compilation > runtime > warnings), identify category

3. **Per error:** show context (5 lines before/after), explain, propose minimal fix, apply, re-run, verify

4. **Stop if:** fix introduces new errors, same error after 3 attempts, user requests pause

5. **Summary:** errors fixed, remaining, new errors introduced

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

**Priority:** Compilation → Spring context → Database/migration → Runtime warnings

**Minimal diff:** change only what's necessary, no refactor, match existing style, add imports not rewrite classes

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
