---
name: skill-enforcement
description: Mandatory skill loading before file operations — agents must load matching skills before editing code
globs: "*.java,*.sql,*.yml,*.yaml,*.properties,*.gradle"
---

# Skill Enforcement

The skill system ensures consistent, high-quality patterns by loading domain-specific knowledge before code changes. Operating without the matching skill produces code that may compile but violates architectural patterns, miss framework conventions, or introduce subtle bugs.

## Protocol

Before editing ANY Java, SQL, YAML, or Gradle file, you MUST:

1. **Match** the file against the skill registry below
2. **Load** the matching skill via Skill tool (e.g., `devco-agent-skills:spring-patterns`)
3. **Announce**: "Using skill: {name} for {reason}"
4. If no match: state "No matching skill found, proceeding with general knowledge"

## Skill Registry

| File Pattern | Skill | Why |
|-------------|-------|-----|
| `*Controller.java`, `*Handler.java` | spring-patterns | Controller patterns, WebFlux/MVC conventions |
| `*SecurityConfig*`, JWT, CORS, `*Auth*` | spring-security | Security filter chains, auth patterns |
| `*Repository.java`, `*Entity.java`, `*.sql`, `*Migration*` | database-patterns | Schema design, query optimization, Flyway |
| `*Test.java`, `*Spec.java`, `*IT.java` | testing-workflow | TDD patterns, StepVerifier, Testcontainers |
| `Kafka*`, `Rabbit*`, `*Listener*`, `*Producer*`, `*Consumer*` | messaging-patterns | Producer/consumer patterns, DLT/DLQ |
| `Redis*`, `*Cache*`, `Redisson*`, `*Lock*` | redis-patterns | Cache-aside, distributed locking, Lua scripts |
| `*Config.java`, `application*.yml`, `*.properties` | spring-patterns | Configuration patterns, profiles, @ConfigurationProperties |
| `build.gradle*`, `settings.gradle*` | coding-standards | Dependency management, plugin configuration |
| `*Metric*`, `*Health*`, `*Trace*`, `logback*` | observability-patterns | Logging config, Micrometer, tracing |
| Any other `*.java` file | coding-standards | General Java patterns, immutability, naming |

## Summer Override

If `build.gradle` contains `io.f8a.summer`: load `devco-agent-skills:summer-core` FIRST — Summer patterns supersede standard Spring patterns. Then load the domain-specific skill as secondary.

Summer sub-skills take precedence over their generic counterparts:
- `summer-security` over `spring-security` for auth
- `summer-rest` over `spring-patterns` for controllers
- `summer-data` over `database-patterns` for Summer-specific DB patterns
- `summer-test` over `testing-workflow` for blackbox/container tests
- `summer-ratelimit` over `redis-patterns` for rate limiting

## Multi-Skill Loading

Some files need multiple skills. Load all matching skills:
- `SecurityConfig.java` in Summer project → `summer-core` + `summer-security` + `spring-security`
- `OrderRepositoryTest.java` → `testing-workflow` + `database-patterns`
- `KafkaConsumerTest.java` → `testing-workflow` + `messaging-patterns`

## This is non-negotiable

Operating without loading the matching skill is a protocol violation. The skill system exists to ensure consistent, high-quality patterns across all code changes.
