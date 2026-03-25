# Knowledge Graph Conventions

Entity taxonomy and naming conventions for `@modelcontextprotocol/server-memory`.

## Entity Types

| Type | Description | Example |
|------|------------|---------|
| `service` | Microservice or module | `OrderService`, `PaymentGateway` |
| `technology` | Tech choice | `R2DBC`, `PostgreSQL`, `Redis`, `Kafka` |
| `pattern` | Architectural pattern | `CQRS`, `Event Sourcing`, `Hexagonal` |
| `anti_pattern` | Known problem | `N+1 Query`, `blocking-in-reactive` |
| `decision` | Architectural decision | `adr-use-cqrs`, `adr-choose-r2dbc` |
| `blocker` | Known issue | `flaky-kafka-tests`, `redis-timeout-prod` |
| `preference` | Team/user coding preference | `prefer-records-over-value`, `no-lombok-data` |

## Relation Types

| Relation | Direction | Example |
|----------|-----------|---------|
| `uses` | service → technology | `OrderService` uses `PostgreSQL` |
| `implements` | service → pattern | `OrderService` implements `CQRS` |
| `decided_in` | decision → session | `adr-use-cqrs` decided_in `session-2026-03-17` |
| `found_in` | anti_pattern → service | `N+1 Query` found_in `OrderService` |
| `blocks` | blocker → service | `flaky-kafka-tests` blocks `PaymentService` |
| `replaces` | decision → decision | `adr-use-r2dbc` replaces `adr-use-jpa` |
| `related_to` | any → any | generic association |

## Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| service | PascalCase | `OrderService` |
| technology | PascalCase | `PostgreSQL`, `R2DBC` |
| pattern | PascalCase | `CQRS`, `EventSourcing` |
| anti_pattern | kebab-case | `n-plus-one-query`, `blocking-in-reactive` |
| decision | kebab-case with prefix | `adr-use-cqrs`, `adr-choose-postgresql` |
| blocker | kebab-case | `flaky-kafka-tests` |
| preference | kebab-case | `prefer-records-over-value` |

## Agent Usage

Agents interact with the graph via `mcp__memory__*` tools:

**Before starting work:**
```
search_nodes(query) → find related entities
open_nodes(names)   → load specific decisions or patterns
```

**After completing work:**
```
create_entities(entities)      → new decisions, patterns, anti-patterns
add_observations(observations) → append findings to existing entities
create_relations(relations)    → link entities
```
