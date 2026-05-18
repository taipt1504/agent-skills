# Applicability Block — Authoring Guide

Every `SKILL.md` needs an `applicability` block in YAML frontmatter. Pre-flight uses it to score relevance objectively.

## Template

```yaml
applicability:
  always: false                    # true = mandatory every gate (e.g., bootstrap, preflight)
  triggers:
    files_match:                   # glob patterns matching files this skill applies to
      - "**/*Repository.java"
      - "**/*Entity.java"
    code_patterns:                 # code constructs that signal applicability
      - "@Entity"
      - "@Repository"
      - "JpaRepository"
    task_keywords:                 # natural-language keywords in user request
      - "entity"
      - "JPA"
      - "Hibernate"
      - "repository"
    related_skills:                # skills typically loaded together
      - postgres-patterns
      - mysql-patterns
    related_rules:                 # rules typically loaded together
      - rules/java/observability.md
      - rules/java/security.md
relevance_assessment: |
  HIGH (80%+): <when this is central to task>
  MEDIUM (40-79%): <when this supports but isn't central>
  LOW (1-39%): <when tangentially related>
  ZERO (0%): <when not relevant at all — must be verifiable>
```

## Field rules

### `always`

- `true` only for meta-skills (bootstrap, preflight) that fire every gate regardless of task
- `false` for everything else — pre-flight decides per task

### `triggers.files_match`

Glob patterns relative to project root. Use `**` for recursive. Examples:
- `"**/*Controller.java"` — any controller
- `"src/main/resources/db/migration/*.sql"` — Flyway migrations
- `"**/application*.yml"` — Spring config

### `triggers.code_patterns`

String literals or regex-like patterns the pre-flight hook can grep for. Examples:
- `"@KafkaListener"` — Kafka consumers
- `"RedisTemplate"` — Redis usage
- `"ReactiveSecurityContextHolder"` — reactive security

### `triggers.task_keywords`

Natural-language tokens in user request that signal skill applicability:
- `"JPA"`, `"Hibernate"`, `"entity"` for jpa-patterns
- `"endpoint"`, `"REST"`, `"controller"` for api-design

### `triggers.related_skills` and `related_rules`

When this skill applies, these typically also apply. Helps pre-flight discover skill clusters.

### `relevance_assessment`

Prose rubric defining scoring bands. Write it like grading criteria. Be specific.

## Examples

### Meta-skill (always: true)

```yaml
applicability:
  always: true
  triggers:
    files_match: ["**"]
relevance_assessment: |
  Always 100% — meta-skill, fires before any other skill.
```

### Domain-specific (always: false)

```yaml
applicability:
  always: false
  triggers:
    files_match: ["**/*Repository.java", "**/*Entity.java"]
    code_patterns: ["@Entity", "@Repository", "JpaRepository"]
    task_keywords: ["entity", "JPA", "Hibernate", "repository"]
    related_rules: ["rules/java/observability.md"]
relevance_assessment: |
  HIGH (80%+): new @Entity/@Repository or JPA query
  MEDIUM (40-79%): touches repo layer, no new query
  LOW (1-39%): service that uses repository, no direct DB code
  ZERO (0%): project has no JPA dep (verified build.gradle)
```

### Framework-specific (mutually exclusive with sibling)

```yaml
# skills/spring-webflux-patterns
applicability:
  always: false
  triggers:
    code_patterns: ["Mono", "Flux", "WebClient", "RouterFunction"]
    task_keywords: ["webflux", "reactive"]
relevance_assessment: |
  HIGH (80%+): code uses Mono/Flux, reactive controllers
  ZERO (0%): project uses Spring MVC (servlet stack); verify in application.yml
```

## Anti-patterns

- ❌ Empty `triggers` — pre-flight can't score
- ❌ `always: true` for non-meta skills — defeats the 1% rule
- ❌ Vague `relevance_assessment` ("important when relevant")
- ❌ Overlapping `files_match` with sibling skill (e.g., webflux + mvc) without disambiguation guidance
