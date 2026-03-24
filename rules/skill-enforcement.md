---
name: skill-enforcement
description: Mandatory skill loading before file operations — agents must load matching skills
globs: "*.java,*.sql,*.yml,*.yaml"
---

# Skill Enforcement

Before editing ANY Java, SQL, or YAML file, you MUST:

1. **Match** the file against the skill registry below
2. **Load** the matching skill via Skill tool (e.g., `devco-agent-skills:spring-patterns`)
3. **Announce**: "Using skill: {name} for {reason}"
4. If no match: state "No matching skill found, proceeding with general knowledge"

## Skill Registry

| File Pattern | Skill |
|-------------|-------|
| *Controller.java, *Handler.java | devco-agent-skills:spring-patterns |
| *SecurityConfig*, JWT, CORS | devco-agent-skills:spring-security |
| *Repository.java, *Entity.java, *.sql | devco-agent-skills:database-patterns |
| *Test.java, *Spec.java | devco-agent-skills:testing-workflow |
| Kafka*, Rabbit*, *Listener, *Producer | devco-agent-skills:messaging-patterns |
| Redis*, cache, Redisson | devco-agent-skills:redis-patterns |
| Any other Java file | devco-agent-skills:coding-standards |

## Summer Override

If `build.gradle` contains `io.f8a.summer`: load `devco-agent-skills:summer-core` FIRST — Summer patterns supersede standard Spring patterns.

## This is non-negotiable

Operating without loading the matching skill is a protocol violation. The skill system exists to ensure consistent, high-quality patterns.
