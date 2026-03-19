---
name: database-patterns
description: >
  Unified database patterns for Java Spring — PostgreSQL, MySQL, JPA/Hibernate, R2DBC,
  connection pooling, and Flyway migrations. Use when designing schemas, writing Repository
  or Entity classes, configuring SQL queries, planning migrations, tuning pool/connection
  settings, or reviewing database-related code.
triggers:
  - Repository
  - Entity
  - SQL
  - migration
  - schema
  - pool config
  - JPA
  - R2DBC
  - Flyway
  - HikariCP
  - database
---

# Database Patterns

Production-ready database patterns for Java 17+ / Spring Boot 3.x.

## Stack Decision

| Criterion | JPA / HikariCP | R2DBC / R2DBC Pool |
|-----------|---------------|-------------------|
| Runtime | Spring MVC (blocking) | Spring WebFlux (reactive) |
| Repository | `JpaRepository` | `ReactiveCrudRepository` |
| Transaction | `@Transactional` | `@Transactional` + `TransactionalOperator` |
| PG driver | `org.postgresql:postgresql` | `org.postgresql:r2dbc-postgresql` |
| MySQL driver | `com.mysql.cj.jdbc.Driver` | `io.asyncer:r2dbc-mysql` |

## Engine Differences

| Aspect | PostgreSQL | MySQL |
|--------|-----------|-------|
| PK strategy | `GENERATED ALWAYS AS IDENTITY` / `SEQUENCE` | `BIGINT UNSIGNED AUTO_INCREMENT` |
| JPA `@GeneratedValue` | `SEQUENCE` + `@SequenceGenerator` | `IDENTITY` |
| Strings | `text` (no storage diff vs varchar) | `VARCHAR(n)` + `utf8mb4` required |
| Timestamps | `timestamptz` (always TZ-aware) | `DATETIME(3)` (store in UTC) |
| Covering index | `INCLUDE (col)` | List all cols in key (no INCLUDE) |
| Partial index | `WHERE` clause on index | Not supported (use composite) |
| Concurrent index | `CREATE INDEX CONCURRENTLY` | `ALGORITHM=INPLACE, LOCK=NONE` |
| Transactional DDL | Yes | No (implicit commit) |
| Default isolation | `READ_COMMITTED` | `REPEATABLE_READ` (gap locks) |

## Critical Rules (Both Engines)

1. **`@SQLRestriction` not `@Where`** -- Hibernate 6+
2. **`FetchType.LAZY` always** -- JOIN FETCH / `@EntityGraph` at call site
3. **No `.block()` in reactive** -- use R2DBC on WebFlux
4. **`open-in-view: false`** -- always disable
5. **Parameterized queries only** -- never concatenate user input
6. **Index all FK columns**
7. **Pool size = `vCPU * 2 + 1`** (SSD); smaller pools outperform oversized ones
8. **DTO projections for read-only** -- skip entity lifecycle overhead

## Migration Safety (Expand-Contract)

1. **Expand** -- add nullable column; deploy new code writing to both old+new
2. **Migrate** -- backfill in batches (1000 rows), not single UPDATE
3. **Contract** -- add NOT NULL / drop old column in separate deployment

**Always safe**: add nullable column, add index (CONCURRENTLY/INPLACE), add table.
**Never in prod**: DROP without expand-contract, ALTER to smaller type, TRUNCATE.

## Verification Checklist

- [ ] No `@Data` on entities; use `@Getter` + `@NoArgsConstructor(PROTECTED)` + builder
- [ ] `@EntityGraph` / JOIN FETCH for known N+1 paths
- [ ] DTO projections for read-only queries
- [ ] `@Transactional(readOnly = true)` on query methods
- [ ] HikariCP leak detection enabled in non-prod
- [ ] Migrations follow `V{n}__{description}.sql` naming
- [ ] Large table changes use online DDL or batch strategy
- [ ] Migration tested with Testcontainers

## References

| File | Contents |
|------|----------|
| [postgresql.md](references/postgresql.md) | Schema, indexing (B-tree/GIN/GiST/BRIN/covering/partial), UPSERT, keyset pagination, SKIP LOCKED, RLS, JPA config, R2DBC config, pool sizing, Flyway |
| [mysql.md](references/mysql.md) | Schema, indexing (covering without INCLUDE, invisible, generated columns), utf8mb4, JPA config, R2DBC asyncer driver, pool sizing, Flyway |
| [jpa-hibernate.md](references/jpa-hibernate.md) | Entity design, N+1 prevention (EntityGraph/JOIN FETCH/DTO projections), HikariCP config, pagination (offset + cursor), batch writes, specifications |
| [r2dbc.md](references/r2dbc.md) | ReactiveCrudRepository, R2dbcEntityTemplate, DatabaseClient, reactive transactions, pool config, Testcontainers testing |
| [migrations.md](references/migrations.md) | Flyway naming, expand-contract, safety rules, large table strategies (PG vs MySQL), Testcontainers validation |
