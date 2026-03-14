# Project Guidelines Skill

## Purpose

This skill provides quick access to the comprehensive AML Service project guidelines. Use this when you need to
understand project-specific conventions, patterns, and standards that all agents must follow.

---

## When to Use

**ALWAYS read this skill** when:

- Starting work on the AML Service project
- Creating new features or handlers
- Writing tests for AML Service code
- Reviewing code in this project
- Setting up database migrations
- Integrating with external services (Kafka, gRPC, MinIO)
- Configuring deployment or infrastructure

---

## Primary Reference

The authoritative project guidelines are maintained in:

**📄 [PROJECT_GUIDELINES.md](../../../PROJECT_GUIDELINES.md)**

This comprehensive document contains:

1. **Project Overview** - Business context, purpose, and domain
2. **Architecture & Design Principles** - Reactive architecture patterns
3. **Technology Stack** - Java 21, Spring Boot 3.5.8, WebFlux, R2DBC, Kafka
4. **Project Structure** - Handler-based architecture, package organization
5. **Domain Model** - Case Monitor, Negative List, Rules, EDD, Scorecard
6. **Code Standards** - Java 21 features, reactive patterns, immutability
7. **API Design Guidelines** - RESTful conventions, request/response patterns
8. **Database Guidelines** - R2DBC, Liquibase, indexing strategies
9. **Testing Requirements** - 80%+ coverage, unit/integration/e2e tests
10. **Security Requirements** - Input validation, sensitive data handling
11. **Logging & Monitoring** - Structured logging, metrics, observability
12. **Development Workflow** - Git workflow, code review checklist
13. **Deployment & Operations** - Environment setup, health checks
14. **Critical Rules** - Never/Always do lists

---

## Quick Architecture Overview

### Tech Stack Summary

- **Language**: Java 21 (Records, Pattern Matching, Virtual Threads)
- **Framework**: Spring Boot 3.5.8 with WebFlux (Reactive)
- **Database**: PostgreSQL 15+ with R2DBC (Reactive)
- **Migration**: Liquibase 4.33.0
- **Caching**: Redis 7+ with Lettuce (Reactive)
- **Messaging**: Apache Kafka 3.x with Reactor Kafka
- **Storage**: MinIO (S3-compatible)
- **gRPC**: Reactive gRPC 1.2.4
- **Testing**: JUnit 5, Reactor Test, Testcontainers, AssertJ
- **Build**: Gradle 8.x
- **Deployment**: Docker, Kubernetes

### Handler-Based Architecture

AML Service uses a **Handler-Based Reactive Architecture**:

```
┌─────────────────────────────────────────────────────────────┐
│                  AML Service (WebFlux/Netty)                 │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │           Handler Layer (Business Logic)           │     │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ │     │
│  │  │  Case    │ │ Negative │ │   Rule   │ │ EDD  │ │     │
│  │  │ Monitor  │ │   List   │ │  Engine  │ │      │ │     │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────┘ │     │
│  └────────────────────────────────────────────────────┘     │
│                          ↓                                   │
│  ┌────────────────────────────────────────────────────┐     │
│  │       Core Infrastructure (Reactive)               │     │
│  │  ┌─────────┐ ┌────────┐ ┌───────┐ ┌──────────┐   │     │
│  │  │  R2DBC  │ │ Redis  │ │ Kafka │ │   HTTP   │   │     │
│  │  │  Repo   │ │ Cache  │ │ Queue │ │  Client  │   │     │
│  │  └─────────┘ └────────┘ └───────┘ └──────────┘   │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
       │           │           │            │
       ▼           ▼           ▼            ▼
   ┌────────┐ ┌────────┐ ┌────────┐  ┌─────────┐
   │Postgres│ │ Redis  │ │ Kafka  │  │  MinIO  │
   │(R2DBC) │ │(Cache) │ │(Events)│  │ (Files) │
   └────────┘ └────────┘ └────────┘  └─────────┘
```

### Domain Areas

The AML Service manages 5 core domain areas:

1. **Case Monitor** - AML investigation case management
2. **Negative List** - Sanctions/PEP watchlist screening
3. **Rule Engine** - Configurable transaction monitoring rules
4. **EDD (Enhanced Due Diligence)** - Additional customer verification
5. **Scorecard** - Customer risk assessment and scoring

## Project File Structure

### Handler-Based Package Organization

AML Service uses a **Handler-Based Architecture** (not CQRS). Business logic is organized by domain handlers.

```
io.f8a.amlservice/
├── AmlServiceApplication.java          # Main application
│
├── handler/                            # ═══ DOMAIN HANDLERS ═══
│   ├── casemonitor/                    # Case monitoring
│   │   ├── CreateCaseHandler.java
│   │   ├── UpdateCaseHandler.java
│   │   └── SearchCaseHandler.java
│   ├── negativelist/                   # Negative list screening
│   │   ├── ScreeningHandler.java
│   │   └── ImportNegativeListHandler.java
│   ├── rule/                           # Rule engine
│   │   └── EvaluateRuleHandler.java
│   ├── edd/                            # Enhanced Due Diligence
│   │   ├── CreateEddRequestHandler.java
│   │   └── ProcessEddSubmissionHandler.java
│   └── scorecard/                      # Risk scoring
│       └── CalculateRiskScoreHandler.java
│
├── repository/                         # ═══ DATA ACCESS ═══
│   ├── CaseMonitorRepository.java
│   ├── NegativeListRepository.java
│   └── projection/                     # Read projections
│       └── CaseDetailProjection.java
│
├── entity/                             # ═══ DATABASE ENTITIES ═══
│   ├── CaseMonitorEntity.java
│   ├── NegativeListEntity.java
│   └── wrapper/
│
├── model/                              # ═══ DOMAIN MODELS & DTOs ═══
│   ├── dto/                            # Request/Response DTOs
│   │   ├── CreateCaseRequest.java
│   │   └── CaseResponse.java
│   ├── transaction/                    # Transaction models
│   ├── negative/                       # Negative list models
│   └── scorecard/                      # Scorecard models
│
├── mapper/                             # ═══ OBJECT MAPPING ═══
│   ├── CaseMonitorMapper.java          # MapStruct mappers
│   └── NegativeListMapper.java
│
├── component/                          # ═══ INFRASTRUCTURE ═══
│   ├── ruleengine/                     # Rule engine
│   ├── file/                           # File processing
│   ├── grpc/                           # gRPC clients/services
│   ├── notification/                   # Notifications
│   ├── minio/                          # Object storage
│   ├── compliance/                     # External API client
│   └── queue/                          # Kafka messaging
│       ├── producer/
│       └── consumer/
│
├── core/                               # ═══ CORE INFRASTRUCTURE ═══
│   ├── handler/                        # Global handlers
│   ├── cache/                          # Cache abstraction
│   ├── http/                           # HTTP client
│   ├── persistence/                    # Database infrastructure
│   ├── exception/                      # Exception hierarchy
│   └── logging/                        # Logging infrastructure
│
├── config/                             # ═══ CONFIGURATION ═══
│   ├── database/                       # Database config
│   ├── web/                            # Web layer config
│   ├── docs/                           # API docs config
│   └── properties/                     # Config properties
│
├── constant/                           # Global constants
└── utils/                              # Utility classes
```

### Test Structure

```
src/test/java/io/f8a/amlservice/
├── handler/                            # Handler unit tests
│   ├── casemonitor/
│   │   └── CreateCaseHandlerTest.java
│   └── negativelist/
│       └── ScreeningHandlerTest.java
│
├── repository/                         # Repository tests
│   └── CaseMonitorRepositoryTest.java
│
├── component/                          # Component tests
│   ├── ruleengine/
│   │   └── RuleEvaluatorTest.java
│   └── grpc/
│       └── ComplianceGrpcClientTest.java
│
├── integration/                        # E2E integration tests
│   ├── CaseMonitorIntegrationTest.java
│   └── NegativeListScreeningIntegrationTest.java
│
└── fixtures/                           # Test data factories
    ├── CaseMonitorTestFactory.java
    ├── NegativeListTestFactory.java
    └── TestContainersConfig.java
```

---

## Key Code Patterns

For detailed code patterns, refer to [PROJECT_GUIDELINES.md](../../../PROJECT_GUIDELINES.md#code-standards).

### Quick Examples

#### Reactive Handler Pattern

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CreateCaseHandler {
    
    private final CaseMonitorRepository repository;
    private final AmlEventProducer eventProducer;
    private final CaseMonitorMapper mapper;
    
    public Mono<CaseResponse> handle(CreateCaseRequest request) {
        return Mono.just(request)
            .map(mapper::toDomain)
            .flatMap(repository::save)
            .flatMap(this::publishEvent)
            .map(mapper::toResponse)
            .doOnSuccess(response -> 
                log.info("Case created: id={}", response.id()));
    }
}
```

#### Request DTO with Validation

```java
public record CreateCaseRequest(
    @NotBlank(message = "Customer ID is required")
    @Pattern(regexp = "^CUST[0-9]{8}$")
    String customerId,
    
    @NotNull
    CaseType caseType,
    
    @NotBlank
    @Size(min = 10, max = 2000)
    String description
) {}
```

#### Response DTO with Factory Method

```java
public record CaseResponse(
    String id,
    String customerId,
    String caseType,
    String status,
    Instant createdAt
) {
    public static CaseResponse from(CaseMonitor domain) {
        return new CaseResponse(
            domain.id(),
            domain.customerId(),
            domain.caseType().name(),
            domain.status().name(),
            domain.createdAt()
        );
    }
}
```

---

## Testing Requirements

### Unit Tests

```bash
# Run unit tests only
./gradlew test --tests '*Test' --exclude-tags 'integration'
```

```java
@ExtendWith(MockitoExtension.class)
class MarketServiceTest {

    @Mock
    private MarketRepository repository;

    @InjectMocks
    private MarketService service;

    @Test
    @DisplayName("Should create market with generated ID")
    void shouldCreateMarket() {
        // Arrange
        var request = Market.builder()
            .name("Test Market")
            .description("Description")
            .build();

        when(repository.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));

        // Act & Assert
        StepVerifier.create(service.create(request))
            .assertNext(market -> {
                assertThat(market.id()).isNotBlank();
                assertThat(market.status()).isEqualTo(MarketStatus.PENDING);
            })
            .verifyComplete();
    }
}
```

### Integration Tests

```bash
# Run integration tests
./gradlew test --tests '*IntegrationTest'
```

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@Testcontainers
class MarketControllerIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () -> 
            "r2dbc:postgresql://" + postgres.getHost() + ":" + 
            postgres.getFirstMappedPort() + "/test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired
    private WebTestClient webTestClient;

    @Test
    @DisplayName("POST /api/markets creates new market")
    void shouldCreateMarket() {
        var request = new CreateMarketRequest("Test", "Description", Instant.now().plusDays(7));

        webTestClient.post()
            .uri("/api/markets")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.id").isNotEmpty()
            .jsonPath("$.name").isEqualTo("Test");
    }
}
```

### Coverage Requirements

```kotlin
// build.gradle.kts
tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                minimum = "0.80".toBigDecimal() // 80% minimum
            }
        }
    }
}
```

---

## Deployment Workflow

### Pre-Deployment Checklist

- [ ] All tests passing (`./gradlew test`)
- [ ] Build succeeds (`./gradlew build`)
- [ ] No security vulnerabilities (`./gradlew dependencyCheckAnalyze`)
- [ ] No hardcoded secrets
- [ ] Database migrations ready (`./gradlew liquibaseUpdate`)
- [ ] Docker image builds (`docker build -t app:latest .`)

### Build Commands

```bash
# Clean build
./gradlew clean build

# Build Docker image
docker build -t market-service:latest .

# Push to registry
docker push registry.example.com/market-service:latest
```

### Environment Variables

```yaml
# application.yml
spring:
  r2dbc:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}

  redis:
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}

  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}

app:
  jwt:
    secret: ${JWT_SECRET}
    expiration: ${JWT_EXPIRATION:3600}
```

### Docker Compose (Development)

```yaml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=r2dbc:postgresql://postgres:5432/app
      - DATABASE_USERNAME=postgres
      - DATABASE_PASSWORD=postgres
      - REDIS_HOST=redis
      - KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    depends_on:
      - postgres
      - redis
      - kafka

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_PASSWORD: postgres

  redis:
    image: redis:7-alpine

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    # ... kafka config
```

---

## Critical Rules

1. **Immutability** - Use records, never mutate objects
2. **TDD** - Write tests before implementation
3. **80% Coverage** - Minimum test coverage
4. **No God Classes** - Max 400 lines per class
5. **Small Methods** - Max 30 lines per method
6. **Input Validation** - Bean Validation on all endpoints
7. **Proper Error Handling** - Domain exceptions, global handler
8. **No Secrets in Code** - Environment variables only
9. **Logging** - No sensitive data in logs
10. **Documentation** - JavaDoc for public APIs

---

---

## Critical Rules Summary

### 🔴 NEVER

1. Call `.block()` in reactive code
2. Use `@Autowired` field injection
3. Expose Entity classes in API responses
4. Log sensitive data (PII, credentials)
5. Commit secrets to git
6. Skip input validation
7. Ignore exceptions
8. Use `SELECT *` in queries
9. Deploy without migrations
10. Skip code formatting

### 🟢 ALWAYS

1. Use constructor injection (`@RequiredArgsConstructor`)
2. Validate input at API boundary (Bean Validation)
3. Use DTOs for API requests/responses
4. Use Records for immutable DTOs
5. Write tests (80%+ coverage)
6. Use `StepVerifier` for reactive tests
7. Log important business events
8. Use parameterized queries
9. Create indexes for query optimization
10. Handle errors gracefully

---

## Related Skills

- **📘 [PROJECT_GUIDELINES.md](../../../PROJECT_GUIDELINES.md)** - **START HERE** - Comprehensive project documentation
- [coding-standards](../coding-standards/SKILL.md) - Universal coding best practices
- [backend-patterns](../backend-patterns/SKILL.md) - API, database, and messaging patterns
- [java-patterns](../java-patterns/SKILL.md) - Java 21+ features and idioms
- [postgres-patterns](../postgres-patterns/SKILL.md) - PostgreSQL optimization
- [tdd-workflow](../tdd-workflow/SKILL.md) - Test-driven development process
- [security-review](../security-review/SKILL.md) - Security checklist and patterns

---

## Usage Instructions

When starting any work on the AML Service:

1. **READ** [PROJECT_GUIDELINES.md](../../../PROJECT_GUIDELINES.md) first
2. **FOLLOW** the handler-based architecture pattern
3. **USE** Java 21 features (Records, Pattern Matching)
4. **WRITE** reactive code with Project Reactor
5. **TEST** with 80%+ coverage using JUnit 5 + Reactor Test
6. **FORMAT** code with `./gradlew spotlessApply`
7. **VALIDATE** with Bean Validation at API boundary
8. **LOG** structured JSON logs with context
9. **DOCUMENT** using OpenAPI/Swagger annotations
10. **REVIEW** against the Critical Rules before committing
