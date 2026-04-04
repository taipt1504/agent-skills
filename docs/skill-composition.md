# Skill Composition Patterns

> How skills combine, layer, and interact in devco-agent-skills.

## Skill Tiers

Skills are organized in 3 tiers with different loading strategies:

| Tier | When loaded | Token budget | Examples |
|------|------------|-------------|---------|
| **Bootstrap** | SessionStart (always) | ~2K tokens | `bootstrap` |
| **Generic** | On demand (skill-router or agent spawn) | ~1-3K each | `coding-standards`, `spring-patterns`, `api-design` |
| **Summer** | On demand (only if `project-profile.json` → `summer: true`) | ~1-2K each | `summer-core`, `summer-rest`, `summer-security` |

## Composition Rules

### Rule 1: Bootstrap is always present

Every skill assumes `bootstrap` is loaded. Bootstrap defines the workflow phases, skill announcement protocol, and verification rules. Never skip it.

### Rule 2: Generic skills are additive

Skills don't override each other — they stack. When `spring-patterns` and `database-patterns` are both loaded, apply patterns from both when editing a JPA repository.

### Rule 3: Summer skills extend generic skills

Summer skills (`summer-*`) are specializations that layer on top of generic skills. For example, `summer-rest` extends `api-design` with Summer-specific handler patterns. Always load the generic skill first.

```
api-design ← summer-rest
spring-patterns ← summer-core
spring-security ← summer-security
database-patterns ← summer-data
testing-workflow ← summer-test
```

### Rule 4: Conditional loading via project profile

The `project-profile.json` determines which conditional skills activate:

```json
{
  "springType": "WebFlux",
  "summer": true,
  "dependencies": ["postgresql", "redis", "kafka"]
}
```

This profile activates: `spring-patterns`, `database-patterns`, `redis-patterns`, `messaging-patterns`, and all `summer-*` skills.

## Agent → Skill Mapping

Each agent declares its skills in frontmatter:

```yaml
requiredSkills:
  always: ["bootstrap", "coding-standards"]    # Always loaded
  conditional:
    spring: ["spring-patterns"]                # If Spring detected
    database: ["database-patterns"]            # If DB layer touched
    summer: ["summer-core", "summer-rest"]     # If Summer Framework
```

The `subagent-init.sh` hook resolves conditional skills against the project profile at spawn time.

## Common Compositions

### REST API Feature (non-Summer)
```
bootstrap + coding-standards + api-design + spring-patterns + testing-workflow
```

### REST API Feature (Summer)
```
bootstrap + coding-standards + api-design + summer-core + summer-rest + summer-test
```

### Database Migration
```
bootstrap + coding-standards + database-patterns + architecture
```

### Security Audit
```
bootstrap + spring-security + pentest + spring-patterns
```

### Messaging Integration
```
bootstrap + coding-standards + messaging-patterns + spring-patterns + observability-patterns
```

### Full Feature (maximum stack)
```
bootstrap + coding-standards + architecture + api-design + spring-patterns
  + database-patterns + messaging-patterns + redis-patterns + testing-workflow
  + observability-patterns + spring-security
```

## Anti-Patterns

1. **Loading all skills at once** — exceeds context budget. Let skill-router handle it.
2. **Summer skills without generic base** — always load the generic skill first (e.g., `api-design` before `summer-rest`).
3. **Embedding patterns from memory** — always load the skill file; don't rely on cached knowledge.
4. **Skipping skill announcement** — announce before use: "Applying skill: {name} — {pattern}".

## Adding New Skills

1. Create `skills/{name}/SKILL.md` with frontmatter: `name`, `description`, `triggers`, `version`
2. If it extends a generic skill, add `requires: ["{base-skill}"]` to frontmatter
3. Add to `skill-router.sh` file-pattern matching if it has specific file triggers
4. Add to relevant agent `requiredSkills.conditional` entries
5. Document the composition in this file
