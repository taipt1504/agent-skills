---
name: mysql-patterns
description: >
  MySQL 8.x best practices for Java Spring applications. Use when designing schemas,
  writing queries, configuring JPA/Hibernate or R2DBC with MySQL, reviewing MySQL-specific
  performance, or setting up connection pooling and transactions. Covers both blocking
  (Spring MVC / JPA) and reactive (Spring WebFlux / R2DBC) stacks.
---

# MySQL Patterns for Java Spring

Production-ready MySQL patterns for Java 17+ / Spring Boot 3.x.

---

## Stack Decision: JPA vs R2DBC

| Criterion | JPA / HikariCP | R2DBC / R2DBC Pool |
|-----------|---------------|-------------------|
| **Runtime model** | Spring MVC (servlet / blocking) | Spring WebFlux (reactive / non-blocking) |
| **When to use** | Existing servlet apps, heavy ORM, complex entity graphs | New reactive services, streaming data, high-concurrency I/O |
| **Transaction API** | `@Transactional` (Spring TX) | `@Transactional` + `TransactionalOperator` |
| **Repository base** | `JpaRepository` / `CrudRepository` | `ReactiveCrudRepository` |
| **Driver** | `com.mysql.cj.jdbc.Driver` | `io.asyncer:r2dbc-mysql` |
| **Pool config** | `spring.datasource.hikari.*` | `spring.r2dbc.pool.*` |
| **Testing** | `MySQLContainer` + `@DynamicPropertySource` | same container + `R2dbcEntityTemplate` |

> Reference: [r2dbc.md](references/r2dbc.md) for full reactive setup.

---

## 8 Critical Rules

1. **utf8mb4 always** — every `CREATE TABLE` must declare `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`
2. **No covering index `INCLUDE`** — MySQL does not support `INCLUDE`; list all needed columns in the index itself: `(col_a, col_b, col_c)`
3. **`@SQLRestriction` not `@Where`** — Hibernate 6 / Spring Boot 3.x deprecates `@Where`; use `@SQLRestriction("deleted_at IS NULL")`
4. **Isolation levels** — `REPEATABLE_READ` (MySQL default) *prevents* phantom reads via gap locks; `READ_COMMITTED` *reduces* gap lock contention at the cost of phantom reads — not the other way around
5. **HikariCP pool size** — formula: `pool = (vCPU × 2) + effective_spindle_count`; SSD = 1 spindle; a 2-vCPU cloud instance → max pool = 5; bigger is not better
6. **LAZY everywhere** — never `FetchType.EAGER` on collections; always fetch with JOIN FETCH or `@EntityGraph` at the call site
7. **No `.block()` in reactive code** — if you are on WebFlux, use R2DBC; never mix blocking JDBC with a reactive pipeline
8. **Parameterized queries only** — never concatenate user input into SQL; Spring Data and `DatabaseClient` both parameterize automatically

---

## Anti-Pattern Table

| ❌ Anti-Pattern | ✅ Fix | Reference |
|----------------|--------|-----------|
| `SELECT *` in queries | Select only required columns | [schema-indexing.md](references/schema-indexing.md) |
| UUID as primary key | `BIGINT UNSIGNED AUTO_INCREMENT`; store UUID as `BINARY(16)` | [schema-indexing.md](references/schema-indexing.md) |
| `FLOAT`/`DOUBLE` for money | `DECIMAL(10,2)` always | [schema-indexing.md](references/schema-indexing.md) |
| Missing charset/collation on DDL | Add `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci` | [schema-indexing.md](references/schema-indexing.md) |
| `ON orders(user_id) INCLUDE (status)` | `ON orders(user_id, status)` — MySQL has no INCLUDE | [schema-indexing.md](references/schema-indexing.md) |
| Missing FK indexes | Always index foreign key columns | [schema-indexing.md](references/schema-indexing.md) |
| `@Where(clause="deleted_at IS NULL")` | `@SQLRestriction("deleted_at IS NULL")` (Hibernate 6+) | [jpa-hibernate.md](references/jpa-hibernate.md) |
| `FetchType.EAGER` on collections | `FetchType.LAZY` + JOIN FETCH / EntityGraph at call site | [jpa-hibernate.md](references/jpa-hibernate.md) |
| N+1 queries on associations | JOIN FETCH, `@EntityGraph`, or `@BatchSize` | [jpa-hibernate.md](references/jpa-hibernate.md) |
| `@Transactional` on repository layer | Put `@Transactional` on service, not repository | [pool-transactions.md](references/pool-transactions.md) |
| REPEATABLE_READ "causes phantom reads" | REPEATABLE_READ *prevents* phantom reads; READ_COMMITTED may allow them | [pool-transactions.md](references/pool-transactions.md) |
| Oversized HikariCP pool | `pool = vCPU×2 + spindles`; 2-vCPU + SSD → max 5 | [pool-transactions.md](references/pool-transactions.md) |
| Blocking JDBC in WebFlux pipeline | Use R2DBC + `ReactiveCrudRepository` | [r2dbc.md](references/r2dbc.md) |
| No retry on deadlock | Catch `MySQLTransactionRollbackException` (SQLState 40001) and retry | [pool-transactions.md](references/pool-transactions.md) |

---

## Reference Files

| File | Contents |
|------|----------|
| [schema-indexing.md](references/schema-indexing.md) | DDL with utf8mb4, data types, composite/covering index syntax, generated columns, EXPLAIN / EXPLAIN ANALYZE, MySQL 8 CTEs and window functions, invisible indexes |
| [jpa-hibernate.md](references/jpa-hibernate.md) | Entity design, `@SQLRestriction`, column mapping, N+1 prevention (JOIN FETCH / EntityGraph / BatchSize), Spring Data Specifications, pagination strategies, projections, batch writes |
| [r2dbc.md](references/r2dbc.md) | `io.asyncer:r2dbc-mysql` dependency, application.yml config, `R2dbcEntityTemplate`, `DatabaseClient`, reactive transactions, `TransactionalOperator`, Testcontainers R2DBC testing |
| [pool-transactions.md](references/pool-transactions.md) | HikariCP sizing formula (explained), full yaml config, deadlock prevention patterns, isolation level truth table, Micrometer connection pool metrics |
| [flyway-testing.md](references/flyway-testing.md) | Flyway MySQL charset enforcement, migration file header, large table migration strategies, Testcontainers MySQL config, test cleanup trade-offs |
