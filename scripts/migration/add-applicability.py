#!/usr/bin/env python3
"""One-shot migration: inject applicability block into existing SKILL.md frontmatter.

Per doc 07 §"Integration với existing skills". Hand-authored content per skill.
Run once per skill (idempotent: re-run is no-op if block already present).
"""
import re
import sys
from pathlib import Path

# Skill → applicability block (hand-authored per doc 07)
BLOCKS = {
    "api-design": """applicability:
  always: false
  triggers:
    files_match: ["**/*Controller.java", "**/*Handler.java", "**/*RouterFunction*.java", "**/openapi*.yml", "**/openapi*.yaml"]
    code_patterns: ["@RestController", "@RequestMapping", "ResponseEntity", "ProblemDetail", "@Operation", "@ApiResponse"]
    task_keywords: ["endpoint", "REST", "API", "OpenAPI", "Swagger", "ProblemDetail", "pagination design", "HTTP status"]
    related_rules:
      - rules/java/api-design.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 80%+: new endpoint OR contract change OR OpenAPI annotations
  MEDIUM 40-79%: existing endpoint behavior tweak, no contract change
  LOW 1-39%: caller refactor without endpoint touch
  ZERO: no REST surface in scope (verify: grep -r '@RestController' src/main/ = 0)""",
    "architecture": """applicability:
  always: false
  triggers:
    files_match: ["**/domain/**/*.java", "**/application/**/*.java", "**/infrastructure/**/*.java", "**/interfaces/**/*.java", "docs/architecture/**", "docs/adr/**"]
    code_patterns: ["UseCase", "Aggregate", "DomainEvent", "Port", "Adapter", "BoundedContext"]
    task_keywords: ["architecture", "hexagonal", "DDD", "CQRS", "event sourcing", "bounded context", "ADR", "package structure"]
    related_rules:
      - rules/common/patterns.md
      - rules/common/spec-driven.md
relevance_assessment: |
  HIGH 90%+: new bounded context, new layer, architectural reshape
  HIGH 80%+: cross-layer refactor (e.g., add Port + Adapter pair)
  MEDIUM 40-79%: in-layer refactor that respects existing boundaries
  LOW 1-39%: small feature addition within existing structure
  ZERO: trivial fix, single-method change""",
    "coding-standards": """applicability:
  always: true
  triggers:
    files_match: ["**/*.java"]
    code_patterns: ["@Value", "@RequiredArgsConstructor", "record", "@Builder"]
    task_keywords: ["coding style", "immutability", "naming", "records", "Lombok"]
    related_rules:
      - rules/common/coding-style.md
      - rules/java/coding-style.md
relevance_assessment: |
  Always 100% when project has Java files — applies to every code change.""",
    # continuous-learning skill removed v4.1 — replaced by Claude native auto-memory + /meta evolve subcommand
    "database-patterns": """applicability:
  always: false
  triggers:
    files_match: ["**/*Repository.java", "**/*Entity.java", "**/db/migration/**/*.sql", "**/*Migration.java"]
    code_patterns: ["@Entity", "@Repository", "JpaRepository", "ReactiveCrudRepository", "R2dbcRepository", "@Table", "@Column"]
    task_keywords: ["entity", "repository", "JPA", "R2DBC", "Hibernate", "schema", "migration", "Flyway", "Liquibase", "N+1", "HikariCP"]
    related_rules:
      - rules/java/security.md
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: new @Entity OR new repository OR new query OR schema migration
  MEDIUM 40-79%: existing repo modification (e.g., add finder method) OR connection pool config
  LOW 1-39%: service that uses repository, no DB code change
  ZERO: project has no JPA / R2DBC (verify build.gradle)""",
    "deployment-patterns": """applicability:
  always: false
  triggers:
    files_match: ["**/application*.yml", "**/application*.properties", "**/Dockerfile", "**/docker-compose.yml", "**/build.gradle*", "**/pom.xml", ".github/workflows/**"]
    code_patterns: ["@Profile", "@ConditionalOn", "spring.profiles", "ENV "]
    task_keywords: ["deployment", "profile", "config", "Docker", "Kubernetes", "graceful shutdown", "actuator", "production"]
    related_rules:
      - rules/java/observability.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 80%+: new profile, deploy target, container/orchestration config
  MEDIUM 40-79%: app config tweak (timeouts, pool sizes, actuator endpoints)
  LOW 1-39%: dependency version bump
  ZERO: no infrastructure / config files touched""",
    "grpc-patterns": """applicability:
  always: false
  triggers:
    files_match: ["**/*.proto", "**/*GrpcService*.java", "**/*GrpcClient*.java"]
    code_patterns: ["@GrpcService", "@GrpcClient", "StreamObserver", "grpc.netty"]
    task_keywords: ["gRPC", "protobuf", "stream", "bidirectional", "unary"]
    related_rules:
      - rules/java/api-design.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 100%: gRPC code in scope (proto / @GrpcService / @GrpcClient)
  MEDIUM 40-79%: build.gradle gRPC dep change, no code touch
  LOW 1-39%: nearby code that calls gRPC service
  ZERO: no gRPC in project (verify: grep -rln '@GrpcService\\|grpc-spring-boot' = 0)""",
    "messaging-patterns": """applicability:
  always: false
  triggers:
    files_match: ["**/*KafkaListener*.java", "**/*Consumer*.java", "**/*Producer*.java", "**/*EventPublisher*.java", "**/*Outbox*.java"]
    code_patterns: ["@KafkaListener", "KafkaTemplate", "@RabbitListener", "RabbitTemplate", "OutboxService", "AbstractKafkaMessageHandler"]
    task_keywords: ["Kafka", "RabbitMQ", "event", "outbox", "consumer", "producer", "DLQ", "DLT", "idempotency", "saga"]
    related_rules:
      - rules/java/security.md
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: new consumer/producer OR new event type OR outbox table OR DLQ config
  MEDIUM 40-79%: existing handler modification, retry/DLQ tuning
  LOW 1-39%: caller emits event but handler in other service
  ZERO: project has neither Kafka nor RabbitMQ (verify build.gradle)""",
    "observability-patterns": """applicability:
  always: false
  triggers:
    files_match: ["**/*Metrics*.java", "**/*HealthCheck*.java", "**/*Tracing*.java", "**/logback*.xml", "**/*Trace*.java"]
    code_patterns: ["MeterRegistry", "@Observed", "Tracer", "MDC.put", "LogstashEncoder", "@Timed", "@Counted"]
    task_keywords: ["metrics", "logging", "tracing", "MDC", "Micrometer", "Prometheus", "OpenTelemetry", "health check", "alerting"]
    related_rules:
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: new metric / log / trace / health probe OR alert rule
  MEDIUM 40-79%: production code that should emit telemetry but currently doesn't
  LOW 1-39%: existing instrumented code minor change
  ZERO: trivial fix, no production code, no SLO impact""",
    "pentest": """applicability:
  always: false
  triggers:
    auto_fire: ["/pentest-scan invocation", "high-stakes lane security review"]
    command: ["/pentest-scan", "/threat-model"]
    task_keywords: ["security", "OWASP", "pentest", "vulnerability", "CVE", "threat model", "SSRF", "injection", "auth bypass"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 100%: /pentest-scan or /threat-model invoked OR security audit task
  HIGH 80%+: high-stakes lane Review S2 stage
  MEDIUM 40-79%: auth / crypto / input-validation code change
  LOW 1-39%: tangential security touch (e.g., logging level for security event)
  ZERO: pure refactor, no security boundary""",
    "redis-patterns": """applicability:
  always: false
  triggers:
    files_match: ["**/*Cache*.java", "**/*Lock*.java", "**/*RateLimit*.java", "**/*Redis*.java"]
    code_patterns: ["RedisTemplate", "ReactiveRedisTemplate", "Lettuce", "Redisson", "@Cacheable", "@CacheEvict"]
    task_keywords: ["Redis", "cache", "distributed lock", "Lua script", "rate limit", "session store", "TTL"]
    related_rules:
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: new cache layer, distributed lock, Redis-backed rate limiter
  MEDIUM 40-79%: cache invalidation tweak, TTL change, key naming refactor
  LOW 1-39%: service that uses cache, no Redis code touched
  ZERO: project has no Redis (verify: grep -r 'redis' build.gradle = 0)""",
    "spring-security": """applicability:
  always: false
  triggers:
    files_match: ["**/*SecurityConfig*.java", "**/*AuthConfig*.java", "**/*JwtConfig*.java", "**/*CorsConfig*.java"]
    code_patterns: ["SecurityFilterChain", "SecurityWebFilterChain", "@PreAuthorize", "@EnableReactiveMethodSecurity", "@EnableMethodSecurity", "PasswordEncoder"]
    task_keywords: ["security", "auth", "OAuth", "JWT", "CORS", "CSRF", "Keycloak", "SAML", "RBAC", "authorization"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
      - rules/java/reactive.md
relevance_assessment: |
  HIGH 90%+: SecurityFilterChain edit OR auth flow change OR @PreAuthorize add
  HIGH 80%+: CORS allowlist OR JWT config tweak
  MEDIUM 40-79%: endpoint added to existing auth scheme
  LOW 1-39%: caller of secured method, no auth change
  ZERO: no Spring Security dep (verify build.gradle)""",
    "summer-core": """applicability:
  always: false
  triggers:
    auto_fire: ["project-profile.json shows summer:true"]
    files_match: ["**/*.java", "**/build.gradle*"]
    code_patterns: ["io.f8a.summer", "summer-platform"]
    task_keywords: ["Summer", "f8a", "platform", "summer framework"]
    related_skills: ["summer-rest", "summer-data", "summer-security", "summer-test", "summer-ratelimit", "summer-kafka", "summer-file", "summer-payment-sdk"]
relevance_assessment: |
  HIGH 100%: io.f8a.summer detected in build.gradle (always load alongside Spring patterns)
  ZERO: project does not use Summer (verify build.gradle = no io.f8a.summer)""",
    "summer-data": """applicability:
  always: false
  triggers:
    files_match: ["**/*AuditService*.java", "**/*OutboxService*.java", "**/*Repository*.java"]
    code_patterns: ["AuditService", "OutboxService", "io.f8a.summer.core.outbox", "f8a.audit", "f8a.outbox"]
    task_keywords: ["audit", "outbox", "summer data", "f8a.audit", "f8a.outbox"]
    related_rules:
      - rules/java/security.md
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: AuditService / OutboxService usage OR new outbox event publisher
  MEDIUM 40-79%: repository touches audit fields (created_by, updated_by)
  LOW 1-39%: caller of summer-data service
  ZERO: project lacks io.f8a.summer or summer-data not used (verify build.gradle)""",
    "summer-file": """applicability:
  always: false
  triggers:
    files_match: ["**/*FileService*.java", "**/*Upload*.java", "**/*Download*.java"]
    code_patterns: ["io.f8a.summer.file", "f8a.file", "FileStorageService", "PresignedUrlService"]
    task_keywords: ["file upload", "file download", "presigned URL", "S3", "MinIO", "summer file"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 80%+: new file upload/download endpoint OR storage backend integration
  MEDIUM 40-79%: presigned URL generation, file metadata
  LOW 1-39%: service that references file URLs without storage interaction
  ZERO: project lacks io.f8a.summer:summer-file""",
    "summer-kafka": """applicability:
  always: false
  triggers:
    files_match: ["**/*KafkaListener*.java", "**/*MessageHandler*.java", "**/*OutboxPublisher*.java"]
    code_patterns: ["io.f8a.summer.kafka", "AbstractKafkaMessageHandler", "MessageHandlerRegistry", "OutboxEventPublisher"]
    task_keywords: ["summer Kafka", "outbox dispatcher", "message handler registry", "f8a.kafka"]
    related_skills: ["messaging-patterns", "summer-data"]
    related_rules:
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: new Summer Kafka consumer/producer OR outbox routing change
  MEDIUM 40-79%: handler registry registration tweak
  LOW 1-39%: caller publishes via Summer outbox but handler in other service
  ZERO: project lacks io.f8a.summer:summer-kafka""",
    "summer-payment-sdk": """applicability:
  always: false
  triggers:
    files_match: ["**/*Payment*.java"]
    code_patterns: ["io.f8a.summer.payment", "f8a.payment", "PaymentClient", "PaymentProvider"]
    task_keywords: ["payment", "summer payment", "VNPay", "Momo", "ZaloPay", "payment provider"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: payment flow integration OR new provider OR signature/verification logic
  MEDIUM 40-79%: payment status update or webhook handler
  LOW 1-39%: order code touches paymentId without provider interaction
  ZERO: project lacks io.f8a.summer:summer-payment""",
    "summer-ratelimit": """applicability:
  always: false
  triggers:
    files_match: ["**/*RateLimit*.java", "**/*Throttle*.java"]
    code_patterns: ["io.f8a.summer.ratelimit", "RateLimiterService", "f8a.rate-limiter"]
    task_keywords: ["rate limit", "throttle", "token bucket", "summer rate limit", "OTP rate limit"]
    related_skills: ["redis-patterns"]
    related_rules:
      - rules/common/security.md
relevance_assessment: |
  HIGH 80%+: new rate-limited endpoint OR rate config change
  MEDIUM 40-79%: rate-limit key strategy refactor
  LOW 1-39%: endpoint that should be rate-limited but currently isn't
  ZERO: project lacks io.f8a.summer:summer-rate-limiter""",
    "summer-rest": """applicability:
  always: false
  triggers:
    files_match: ["**/*Controller*.java", "**/*Handler*.java", "**/*Router*.java"]
    code_patterns: ["io.f8a.summer.rest", "BaseController", "RequestHandler", "@Handler", "WebClientBuilderFactory"]
    task_keywords: ["summer REST", "summer handler", "BaseController.execute", "SpringBus", "request handler"]
    related_skills: ["spring-webflux-patterns", "api-design"]
    related_rules:
      - rules/java/api-design.md
relevance_assessment: |
  HIGH 90%+: new endpoint using BaseController + RequestHandler dispatch
  HIGH 80%+: existing handler modification within Summer REST pattern
  MEDIUM 40-79%: WebClient builder factory usage
  LOW 1-39%: vanilla Spring controller in Summer project (should migrate)
  ZERO: project lacks io.f8a.summer:summer-rest""",
    "summer-security": """applicability:
  always: false
  triggers:
    files_match: ["**/*SecurityConfig*.java", "**/*AuthRoles*.java"]
    code_patterns: ["io.f8a.summer.security", "@AuthRoles", "ReactiveKeycloakClient", "f8a.security", "CallerAware", "RequestContextService"]
    task_keywords: ["summer security", "auth roles", "Keycloak", "APISIX", "caller context", "audit context"]
    related_skills: ["spring-security"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 90%+: @AuthRoles change OR Keycloak integration OR caller-context wiring
  HIGH 80%+: new secured Summer endpoint
  MEDIUM 40-79%: audit context propagation refactor
  LOW 1-39%: caller of secured Summer method
  ZERO: project lacks io.f8a.summer:summer-security""",
    "summer-test": """applicability:
  always: false
  triggers:
    files_match: ["**/*Test.java", "**/*IT.java", "**/*Spec.java"]
    code_patterns: ["io.f8a.summer.test", "AbstractBlackboxTest", "f8a.test"]
    task_keywords: ["summer test", "blackbox test", "summer testcontainer", "integration test"]
    related_skills: ["testing-workflow"]
    related_rules:
      - rules/java/testing.md
relevance_assessment: |
  HIGH 90%+: new blackbox integration test OR Summer-specific testcontainer setup
  HIGH 80%+: existing test using Summer test fixtures
  MEDIUM 40-79%: unit test for code that integrates with Summer services
  LOW 1-39%: test using vanilla Spring Boot Test (should migrate)
  ZERO: project lacks io.f8a.summer:summer-test""",
    "testing-workflow": """applicability:
  always: false
  triggers:
    files_match: ["**/*Test.java", "**/*IT.java", "**/*Spec.java", "**/*Mock*.java"]
    code_patterns: ["@Test", "@WebMvcTest", "@WebFluxTest", "@SpringBootTest", "MockMvc", "WebTestClient", "StepVerifier", "Testcontainers"]
    task_keywords: ["test", "TDD", "unit test", "integration test", "coverage", "mock", "JUnit", "Mockito", "Testcontainers"]
    related_rules:
      - rules/java/testing.md
      - rules/common/spec-driven.md
relevance_assessment: |
  HIGH 100%: BUILD phase (TDD mandatory)
  HIGH 90%+: any test file edit
  HIGH 80%+: production code change (new tests required to maintain 80%+ coverage)
  MEDIUM 40-79%: refactor without behavior change (existing tests must stay green)
  LOW 1-39%: documentation-only change
  ZERO: trivial typo fix in non-test, non-production file""",
}


def inject(path: Path, block: str) -> bool:
    text = path.read_text()
    if "applicability:" in text and "relevance_assessment:" in text:
        return False  # already injected

    # Match frontmatter `triggers:` block ending → end of triggers section.
    # Insert applicability block before closing `---` of frontmatter.
    fm_match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not fm_match:
        print(f"SKIP {path}: no frontmatter found")
        return False

    frontmatter = fm_match.group(1)
    new_frontmatter = frontmatter.rstrip() + "\n" + block
    new_text = f"---\n{new_frontmatter}\n---\n" + text[fm_match.end():]
    path.write_text(new_text)
    return True


def main() -> int:
    base = Path(__file__).parent.parent.parent / "skills"
    if not base.is_dir():
        print(f"ERR: {base} not a directory", file=sys.stderr)
        return 2

    changed = 0
    skipped = 0
    for name, block in BLOCKS.items():
        skill_md = base / name / "SKILL.md"
        if not skill_md.exists():
            print(f"MISSING {skill_md}")
            continue
        if inject(skill_md, block):
            print(f"INJECTED {name}")
            changed += 1
        else:
            print(f"SKIP    {name} (already has block)")
            skipped += 1

    print(f"\nDone: {changed} injected, {skipped} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
