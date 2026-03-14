# PROJECT_GUIDELINES.md

> **Instructions**: Copy this file to your project root as `PROJECT_GUIDELINES.md`.
> Fill in the `[PLACEHOLDER]` sections. Remove this instruction block when done.
> The `project-guidelines` skill auto-reads this file at session start.

---

## 1. Project Overview

- **Name**: `[PROJECT_NAME]`
- **Description**: `[One-line description of what this service does]`
- **Domain**: `[e.g., Payment Processing, User Management, AML Compliance]`
- **Team**: `[Team name or owner]`
- **Repository**: `[Git URL]`
- **Status**: `[Development / UAT / Production]`

---

## 2. Tech Stack

| Component | Technology | Version | Notes |
|-----------|-----------|---------|-------|
| Language | Java | 17+ | Use records, sealed classes, pattern matching |
| Framework | Spring Boot | 3.x | WebFlux (reactive) |
| Reactive | Project Reactor | 3.6+ | Mono/Flux — never `.block()` |
| Database | PostgreSQL | 15+ | R2DBC (reactive driver) |
| Migrations | Flyway | 9.x+ | `db/migration/` — SQL-based versioned migrations |
| Caching | Redis | 7+ | Lettuce (reactive client) |
| Messaging | Apache Kafka | 3.x | Reactor Kafka |
| RPC | gRPC | `[version]` | `[if used, otherwise remove]` |
| Build | Gradle | 8.x | Kotlin DSL (`build.gradle.kts`) |
| Testing | JUnit 5 | 5.10+ | + Testcontainers, AssertJ, StepVerifier |
| Containers | Docker | 24+ | + Docker Compose for local dev |

> **Customize**: Remove unused technologies. Add project-specific tools.

---

## 3. Architecture

### Primary Pattern: `[Choose one]`
<!-- Uncomment the one you use, delete the rest -->

<!-- ### Hexagonal Architecture (Ports & Adapters) -->
<!-- ### Handler-Based Architecture -->
<!-- ### Layered Architecture (Controller-Service-Repository) -->

```
[PASTE YOUR ARCHITECTURE DIAGRAM HERE]

Example (Hexagonal):
┌─────────────────────────────────────────────┐
│                 Application                  │
│  ┌─────────────────────────────────────┐    │
│  │          Domain (Core)              │    │
│  │  Entities · Value Objects · Events  │    │
│  │  Repository Interfaces (Ports)      │    │
│  └──────────┬──────────────┬───────────┘    │
│             │              │                 │
│  ┌──────────▼──┐  ┌───────▼──────────┐     │
│  │  Application │  │  Infrastructure  │     │
│  │  Use Cases   │  │  R2DBC · Kafka   │     │
│  │  Services    │  │  Redis · gRPC    │     │
│  └──────────────┘  └─────────────────┘      │
│             │              │                 │
│  ┌──────────▼──────────────▼───────────┐    │
│  │           Interfaces                 │    │
│  │  REST Controllers · Event Listeners  │    │
│  └──────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

### Additional Patterns in Use
- [ ] CQRS (Command Query Responsibility Segregation)
- [ ] DDD (Domain-Driven Design) with Bounded Contexts
- [ ] Event Sourcing
- [ ] Saga Pattern (distributed transactions)
- [ ] Outbox Pattern (reliable event publishing)

---

## 4. Module Structure

### Package Layout

```
[BASE_PACKAGE]/                          # e.g., com.example.myservice
├── [ServiceName]Application.java        # Main class
│
├── domain/                              # ═══ DOMAIN CORE ═══
│   ├── model/                           # Entities, value objects, enums
│   │   ├── [Entity].java
│   │   └── [ValueObject].java
│   ├── event/                           # Domain events
│   │   └── [Entity]CreatedEvent.java
│   ├── port/                            # Repository interfaces (ports)
│   │   └── [Entity]Repository.java
│   └── exception/                       # Domain exceptions
│       └── [Entity]NotFoundException.java
│
├── application/                         # ═══ APPLICATION (USE CASES) ═══
│   ├── command/                         # Write operations
│   │   ├── Create[Entity]UseCase.java
│   │   └── Update[Entity]UseCase.java
│   ├── query/                           # Read operations
│   │   ├── Get[Entity]Query.java
│   │   └── Search[Entity]Query.java
│   └── service/                         # Shared application services
│       └── [Domain]Service.java
│
├── infrastructure/                      # ═══ INFRASTRUCTURE (ADAPTERS) ═══
│   ├── persistence/                     # Database implementations
│   │   ├── [Entity]R2dbcRepository.java
│   │   └── entity/
│   │       └── [Entity]Entity.java      # DB entity (separate from domain)
│   ├── messaging/                       # Kafka producers/consumers
│   │   ├── producer/
│   │   └── consumer/
│   ├── cache/                           # Redis cache implementations
│   ├── client/                          # External HTTP/gRPC clients
│   └── config/                          # Spring configuration classes
│
├── interfaces/                          # ═══ INTERFACES (ENTRY POINTS) ═══
│   ├── rest/                            # REST controllers
│   │   ├── [Entity]Controller.java
│   │   └── dto/                         # Request/Response DTOs
│   │       ├── Create[Entity]Request.java
│   │       └── [Entity]Response.java
│   └── event/                           # Kafka event listeners
│       └── [Event]Listener.java
│
├── shared/                              # ═══ SHARED / CROSSCUTTING ═══
│   ├── exception/                       # Global exception handler
│   ├── mapper/                          # MapStruct mappers
│   ├── util/                            # Pure utility functions
│   └── constant/                        # Application constants
│
└── resources/
    ├── application.yml
    ├── application-local.yml
    ├── application-uat.yml
    ├── application-prod.yml
    └── db/
        └── migration/                   # Flyway migrations
            ├── V1__create_[table].sql
            └── V2__add_[column].sql
```

> **Customize**: Adjust package names and structure to match your project.
> Delete unused packages. Keep only what you actually need.

---

## 5. API Conventions

### REST Endpoints

```
Base URL: /api/v1/[resource]

GET    /api/v1/[resources]          → List (paginated)
GET    /api/v1/[resources]/{id}     → Get by ID
POST   /api/v1/[resources]          → Create
PUT    /api/v1/[resources]/{id}     → Full update
PATCH  /api/v1/[resources]/{id}     → Partial update
DELETE /api/v1/[resources]/{id}     → Delete (soft delete preferred)
```

### Error Response Format

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "status": 400,
  "error": "Bad Request",
  "code": "VALIDATION_ERROR",
  "message": "Validation failed for request",
  "details": [
    {
      "field": "email",
      "message": "must be a valid email address",
      "rejectedValue": "not-an-email"
    }
  ],
  "traceId": "abc123def456"
}
```

### Pagination

```
Request:  GET /api/v1/orders?page=0&size=20&sort=createdAt,desc
Response:
{
  "content": [...],
  "page": {
    "number": 0,
    "size": 20,
    "totalElements": 142,
    "totalPages": 8
  }
}
```

### HTTP Status Codes

| Code | When |
|------|------|
| 200 | Successful GET, PUT, PATCH |
| 201 | Successful POST (resource created) |
| 204 | Successful DELETE |
| 400 | Validation errors, malformed request |
| 401 | Missing/invalid authentication |
| 403 | Authenticated but insufficient permissions |
| 404 | Resource not found |
| 409 | Conflict (duplicate, stale data) |
| 422 | Business rule violation |
| 500 | Unexpected server error |

---

## 6. Database

### Schema Conventions

| Convention | Rule | Example |
|-----------|------|---------|
| Table names | lowercase, snake_case, plural | `user_accounts` |
| Column names | lowercase, snake_case | `created_at`, `user_id` |
| Primary key | `id` (UUID preferred) | `id UUID DEFAULT gen_random_uuid()` |
| Foreign key | `{table_singular}_id` | `order_id` |
| Timestamps | Always include both | `created_at`, `updated_at` |
| Soft delete | Use `deleted_at` nullable timestamp | `deleted_at TIMESTAMPTZ` |
| Boolean cols | `is_` prefix | `is_active`, `is_verified` |
| Index naming | `idx_{table}_{columns}` | `idx_orders_customer_id` |
| Unique naming | `uq_{table}_{columns}` | `uq_users_email` |

### Migration Rules (Flyway)

```sql
-- db/migration/V1__create_users.sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- db/migration/V2__create_orders.sql
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Rules:**
1. **Versioned naming**: `V{n}__{description}.sql` — e.g., `V3__add_email_index.sql`
2. **One logical change per file** — don't mix table creation with data migration
3. **Never modify existing migrations** — create new versioned files for alterations
4. **Descriptive names**: `V4__add_email_to_users.sql`, not `V4__update.sql`
5. **Repeatable migrations** use `R__{description}.sql` prefix (views, functions)
6. **Test migrations locally** before committing

### Required Indexes

```sql
-- Always index:
-- 1. Foreign keys
-- 2. Columns in WHERE clauses
-- 3. Columns in ORDER BY
-- 4. Columns in JOIN conditions
-- 5. Unique constraints

-- Example:
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status_created ON orders(status, created_at DESC);
```

---

## 7. Messaging

### Kafka Topic Naming

```
Pattern: {domain}.{entity}.{event-type}

Examples:
  payment.order.created
  payment.order.completed
  user.account.verified
  notification.email.sent
```

### Event Schema

```json
{
  "eventId": "uuid",
  "eventType": "ORDER_CREATED",
  "timestamp": "2024-01-15T10:30:00Z",
  "source": "[SERVICE_NAME]",
  "version": "1.0",
  "correlationId": "trace-id",
  "payload": {
    // event-specific data
  }
}
```

**Rules:**
1. Events are immutable — never modify published event schemas
2. Add new fields with defaults (backward compatible)
3. Use Avro/JSON Schema for schema registry `[if applicable]`
4. Dead letter topic: `{topic-name}.dlq`
5. Consumer group: `{service-name}-{topic-name}-group`
6. Idempotent consumers — handle duplicate events gracefully

---

## 8. Caching

### Redis Key Patterns

```
Pattern: {service}:{entity}:{identifier}

Examples:
  myservice:user:12345
  myservice:user:email:john@example.com
  myservice:order:list:customer:12345:page:0
  myservice:config:feature-flags
```

### TTL Policies

| Data Type | TTL | Rationale |
|-----------|-----|-----------|
| User profile | 30 min | Moderate change frequency |
| Session data | 24 hours | Aligned with session expiry |
| Configuration | 5 min | Short TTL for quick updates |
| List/search results | 2 min | Frequently changing |
| Idempotency keys | 24 hours | Prevent duplicate processing |
| Rate limit counters | 1 min | Sliding window |

> **Customize TTLs** based on your data freshness requirements.

**Rules:**
1. **Always set TTL** — no keys without expiry (except explicit permanent keys)
2. **Cache-aside pattern** — read cache → miss → read DB → write cache
3. **Invalidate on write** — delete cache key when data changes
4. **Never cache sensitive data** (tokens, passwords, PII) unless encrypted
5. **Use hash types** for object storage, not serialized JSON strings

---

## 9. Testing Requirements

### Coverage Targets

| Type | Target | Tool |
|------|--------|------|
| Line coverage | **80%+** | JaCoCo |
| Branch coverage | **70%+** | JaCoCo |
| Mutation coverage | **60%+** | PIT (optional) |

### Required Test Types

| Type | Scope | Required? | Tool |
|------|-------|-----------|------|
| **Unit tests** | Use cases, domain logic, mappers | ✅ Required | JUnit 5 + Mockito |
| **Reactive tests** | Mono/Flux chains | ✅ Required | StepVerifier |
| **Integration tests** | Repository, Kafka, Redis | ✅ Required | Testcontainers |
| **E2E API tests** | Full request/response cycle | ✅ Required | WebTestClient |
| **Contract tests** | API compatibility | ⚡ Recommended | Spring Cloud Contract |
| **Performance tests** | Load/stress | ⚡ Recommended | Gatling / k6 |

### Test Naming Convention

```java
// Pattern: shouldDoXWhenY
@Test
void shouldReturnOrderWhenIdExists() { ... }

@Test
void shouldThrowNotFoundWhenIdDoesNotExist() { ... }

@Test
void shouldCreateOrderWithPendingStatus() { ... }

@Test
void shouldPublishEventWhenOrderCreated() { ... }
```

### Test Structure (AAA)

```java
@Test
void shouldCalculateTotalWithDiscount() {
    // Arrange
    var order = OrderTestFactory.createWithItems(3);
    var discount = Discount.percentage(10);

    // Act
    var result = order.applyDiscount(discount);

    // Assert
    assertThat(result.total()).isEqualTo(expected);
}
```

---

## 10. Security

### Authentication

- **Mechanism**: `[JWT / OAuth2 / Session — pick one]`
- **Token location**: `Authorization: Bearer {token}` header
- **Token expiry**: `[e.g., 1 hour access, 7 days refresh]`

### Input Validation Rules

1. **Bean Validation** (`@Valid`) on ALL request DTOs — no exceptions
2. **Size limits** on all string fields (`@Size(max = ...)`)
3. **Pattern matching** for structured fields (email, phone, IDs)
4. **Sanitize** HTML/script content before storage
5. **Parameterized queries** ONLY — never concatenate SQL

### Security Checklist

- [ ] No secrets in code or config files (use env vars)
- [ ] HTTPS only in production
- [ ] CORS configured (not `*` in production)
- [ ] Rate limiting on public endpoints
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (output encoding)
- [ ] CSRF protection `[if applicable]`
- [ ] Sensitive data excluded from logs
- [ ] Dependency vulnerability scanning in CI
- [ ] Authentication on all non-public endpoints
- [ ] Authorization checks (role/permission-based)

---

## 11. Deployment

### Docker

```dockerfile
# Multi-stage build
FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /app
COPY . .
RUN ./gradlew clean build -x test

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Environment Configuration

| Environment | Profile | Database | Notes |
|-------------|---------|----------|-------|
| Local | `local` | Docker Compose PostgreSQL | `application-local.yml` |
| UAT | `uat` | `[UAT DB URL]` | `application-uat.yml` |
| Production | `prod` | `[Prod DB URL]` | `application-prod.yml` |

### CI/CD Pipeline

```
Push → Lint → Compile → Unit Tests → Integration Tests → Security Scan → Build Image → Deploy
```

**Required CI checks:**
- [ ] `./gradlew build` passes
- [ ] Test coverage ≥ 80%
- [ ] No critical security vulnerabilities
- [ ] Docker image builds successfully
- [ ] Flyway migrations apply cleanly

---

## 12. Project-Specific Rules

> **This section is for rules unique to THIS project.**
> Add custom conventions, overrides, or exceptions here.

### Custom Rules

```
[ADD YOUR PROJECT-SPECIFIC RULES HERE]

Examples:
- All monetary values use BigDecimal with scale 2
- Customer IDs follow pattern: CUST-{8 alphanumeric}
- All API responses include X-Request-Id header
- Background jobs must be idempotent and retryable
- Feature flags managed via [tool/approach]
```

### Domain Glossary

| Term | Definition |
|------|-----------|
| `[Term 1]` | `[Definition]` |
| `[Term 2]` | `[Definition]` |

### Integration Points

| Service | Protocol | Purpose |
|---------|----------|---------|
| `[Service A]` | `[REST/gRPC/Kafka]` | `[What it does]` |
| `[Service B]` | `[REST/gRPC/Kafka]` | `[What it does]` |

### Known Limitations / Tech Debt

| Item | Priority | Notes |
|------|----------|-------|
| `[Item 1]` | `[High/Medium/Low]` | `[Description]` |

---

## Quick Reference Card

```
Build:    ./gradlew clean build
Test:     ./gradlew test
Format:   ./gradlew spotlessApply
Coverage: ./gradlew jacocoTestReport
Migrate:  ./gradlew flywayMigrate
Security: ./gradlew dependencyCheckAnalyze
Docker:   docker build -t [service-name]:latest .
```

### Agent Commands

```
/plan           → Plan before coding (mandatory)
/verify         → Build + test + security check
/code-review    → Review uncommitted changes
/build-fix      → Fix compilation errors
/checkpoint     → Mark phase completion
```

---

*Generated from agent-skills `PROJECT_GUIDELINES_TEMPLATE.md` — customize for your project.*
