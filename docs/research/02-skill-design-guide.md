# Skill Design Guide

> Best practices for creating effective skills, extracted from ECC's 94 skills.

---

## Skill File Structure

```
skills/
└── skill-name/
    ├── SKILL.md          # Required: main skill definition
    ├── references/       # Optional: additional reference files
    ├── config.json       # Optional: skill configuration
    ├── hooks/            # Optional: skill-specific hooks
    └── scripts/          # Optional: utility scripts
```

## SKILL.md Anatomy

### 1. YAML Frontmatter (Required)

```yaml
---
name: skill-name              # lowercase, hyphenated
description: Brief description # Used for trigger matching and skill list display
origin: ECC                    # or "community", "project"
version: 1.0.0                 # optional but recommended
tools: Read, Write, Edit, Bash, Grep, Glob  # optional: tools this skill may need
---
```

**Critical:** The `description` field determines when Claude auto-loads the skill. Be specific about the domain and trigger scenarios.

### 2. Title and Overview

```markdown
# Skill Name

One-line overview of what this skill provides.
```

### 3. When to Activate (Critical Section)

```markdown
## When to Activate

- When implementing Kafka producers or consumers
- When configuring Kafka topics, partitions, or replication
- When debugging Kafka consumer lag or rebalancing issues
- When setting up exactly-once semantics or idempotent producers
```

**This section is the most important for triggering accuracy.** Be explicit about scenarios. Use action verbs ("implementing", "configuring", "debugging").

### 4. Core Content (Domain-Specific)

Organized by domain concepts with practical guidance:

```markdown
## Core Concepts

### Concept 1: Topic Design
- Partition strategy...
- Naming conventions...

### Concept 2: Producer Patterns
- Idempotent configuration...
- Error handling...
```

### 5. Code Examples (Critical for Quality)

**Best practice: Side-by-side BAD/GOOD comparisons:**

```markdown
## Code Examples

### Producer Configuration

```java
// BAD: No error handling, no idempotency
@Bean
public ProducerFactory<String, String> producerFactory() {
    Map<String, Object> props = new HashMap<>();
    props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092");
    return new DefaultKafkaProducerFactory<>(props);
}

// GOOD: Idempotent, with proper serialization and error handling
@Bean
public ProducerFactory<String, OrderEvent> producerFactory(KafkaProperties properties) {
    Map<String, Object> props = properties.buildProducerProperties();
    props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
    props.put(ProducerConfig.ACKS_CONFIG, "all");
    props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);
    return new DefaultKafkaProducerFactory<>(props);
}
```

### 6. Verification Checklist

```markdown
## Verification Checklist

- [ ] Idempotent producer enabled (`enable.idempotence=true`)
- [ ] Consumer group ID configured
- [ ] Dead letter topic configured for failed messages
- [ ] Offset commit strategy documented
- [ ] Partition count matches expected throughput
```

### 7. Related Components

```markdown
## Related

- Agent: `spring-webflux-reviewer` — for reactive Kafka integration review
- Skill: `backend-patterns` — for general messaging patterns
- Command: `/verify` — to validate Kafka configuration
```

## Quality Indicators for Excellent Skills

| Indicator | Description |
|-----------|-------------|
| Explicit triggers | "When to Activate" lists concrete scenarios |
| BAD/GOOD examples | Side-by-side code comparisons |
| Verification checklist | `- [ ]` checkbox items |
| Cross-references | Links to related agents/skills |
| Under 500 lines | Focused, not encyclopedic |
| Actionable guidance | "Do X" not "X is possible" |
| Framework-specific | Concrete code, not abstract theory |

## Anti-Patterns to Avoid

| Anti-Pattern | Problem |
|-------------|---------|
| Encyclopedia skill | >500 lines, tries to cover everything |
| Theory-only | No code examples, no actionable steps |
| No triggers | Missing "When to Activate" section |
| Duplicate content | Repeating what an agent already covers |
| Generic advice | "Follow best practices" without specifics |
| Missing checklist | No verification or quality gates |

## Skill Categories (from ECC's 94 skills)

| Category | Examples | Pattern |
|----------|----------|---------|
| Language patterns | `java-patterns`, `golang-patterns`, `python-patterns` | Language idioms + best practices |
| Framework patterns | `springboot-patterns`, `django-patterns`, `kotlin-ktor-patterns` | Framework-specific conventions |
| Infrastructure | `postgres-patterns`, `kafka-patterns`, `redis-patterns` | Config + optimization + debugging |
| Process/workflow | `tdd-workflow`, `verification-loop`, `coding-standards` | Step-by-step methodology |
| Agentic/meta | `eval-harness`, `continuous-learning-v2`, `strategic-compact` | Meta-skills for the plugin itself |
| Domain/vertical | `customs-trade-compliance`, `energy-procurement` | Business domain knowledge |

## Size Guidelines

From CONTRIBUTING.md:

| Metric | Guideline |
|--------|-----------|
| Total lines | Under 500 |
| Code examples | 3-7 per skill |
| Sections | 4-8 |
| Checklist items | 5-15 |
| "When to Activate" triggers | 3-6 |

## Trigger Description Best Practices

The `description` field in frontmatter is used by Claude to decide when to load a skill. Optimize for trigger accuracy:

```yaml
# BAD: Too vague
description: Database patterns

# GOOD: Specific domain + actions
description: PostgreSQL optimization, indexing strategies, RLS policies, query performance tuning

# BAD: Too narrow
description: Redis SET command usage

# GOOD: Covers the domain breadth
description: Redis caching strategies, distributed locks, rate limiting, pub/sub patterns
```
