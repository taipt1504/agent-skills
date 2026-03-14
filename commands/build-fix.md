# Build and Fix

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

---

## Common Error Categories

### 1. Compilation Errors

```bash
# Symbol not found
error: cannot find symbol
  symbol:   class OrderRepository
  location: class OrderService

# Fix: Add missing import
import com.example.order.OrderRepository;
```

```bash
# Type mismatch
error: incompatible types: Mono<Order> cannot be converted to Order

# Fix: Keep reactive chain, don't unwrap
return orderRepository.findById(id);  // Not .block()
```

### 2. Spring Boot Configuration Errors

```bash
# Bean not found
***************************
APPLICATION FAILED TO START
***************************
Parameter 0 of constructor in com.example.OrderService required a bean of type 'OrderRepository' that could not be found.

# Fix: Add @Repository annotation or check component scan
```

```bash
# Circular dependency
The dependencies of some of the beans in the application context form a cycle

# Fix: Use @Lazy, refactor, or use ApplicationEventPublisher
```

### 3. Gradle Dependency Errors

```bash
# Dependency resolution failed
Could not resolve org.springframework.boot:spring-boot-starter-webflux

# Fix: Check repositories, version, or run:
./gradlew --refresh-dependencies
```

```bash
# Version conflict
Duplicate class found in modules

# Fix: Add exclusions in build.gradle
implementation('org.example:lib') {
    exclude group: 'org.conflicting', module: 'conflict'
}
```

### 4. Liquibase Migration Errors

```bash
# Migration failed
liquibase.exception.ValidationFailedException: Validation Failed

# Fix: Check changeset format, ensure valid SQL
# Run: ./gradlew liquibaseValidate
```

### 5. JPA/Database Errors (Spring MVC)

```bash
# Entity mapping error
org.hibernate.MappingException: Could not determine type for

# Fix: Add @Column annotation or check field type
@Column(name = "created_at")
private LocalDateTime createdAt;
```

```bash
# LazyInitializationException
org.hibernate.LazyInitializationException: could not initialize proxy - no Session

# Fix: Use @Transactional or fetch eagerly
@EntityGraph(attributePaths = {"items"})
List<Order> findByCustomerId(String customerId);
```

### 6. R2DBC/Database Errors (Spring WebFlux)

```bash
# Mapping error
Could not read property @Id from Row

# Fix: Check @Table, @Id annotations match DB schema
```

### 7. Reactive Stream Errors (Spring WebFlux)

```bash
# Blocking call detected
java.lang.IllegalStateException: block()/blockFirst()/blockLast() are blocking, which is not supported in thread reactor-http-nio-X

# Fix: Remove .block(), use flatMap/then instead
```

### 8. Spring MVC Specific Errors

```bash
# Request mapping conflict
Ambiguous handler methods mapped for '/api/orders'

# Fix: Ensure unique URL patterns or HTTP methods
@GetMapping("/orders")      // GET
@PostMapping("/orders")     // POST - different method, OK
```

```bash
# RestTemplate timeout
org.springframework.web.client.ResourceAccessException: I/O error

# Fix: Configure timeouts
@Bean
public RestTemplate restTemplate() {
    var factory = new SimpleClientHttpRequestFactory();
    factory.setConnectTimeout(5000);
    factory.setReadTimeout(5000);
    return new RestTemplate(factory);
}

---

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

# Validate Liquibase
./gradlew liquibaseValidate
```

---

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

---

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

WARNINGS (not blocking):
- OrderService.java:67 - Deprecated method usage

Final State: ✅ BUILD SUCCESSFUL

Next Steps:
- Run tests: ./gradlew test
- Review warnings when convenient
```

---

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

---

## Related Commands

- `/verify` - Run full verification after fixes
- `/code-review` - Review fixed code quality
- Use **build-error-resolver** agent for complex issues
