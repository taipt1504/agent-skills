---
name: postgres-patterns
description: >
  PostgreSQL 15+ best practices for Java Spring applications. Use when designing schemas,
  writing queries, configuring JPA/Hibernate or R2DBC with PostgreSQL, reviewing performance,
  or setting up connection pooling and transactions. Covers both blocking
  (Spring MVC / JPA) and reactive (Spring WebFlux / R2DBC) stacks.
---

# PostgreSQL Patterns for Java Spring

Production-ready PostgreSQL patterns for Java 17+ / Spring Boot 3.x.

---

## Stack Decision: JPA vs R2DBC

| Criterion | JPA / HikariCP | R2DBC / R2DBC Pool |
|-----------|---------------|-------------------|
| **Runtime model** | Spring MVC (servlet / blocking) | Spring WebFlux (reactive / non-blocking) |
| **When to use** | Existing servlet apps, heavy ORM, complex entity graphs | New reactive services, streaming, high-concurrency I/O |
| **Transaction API** | `@Transactional` (Spring TX) | `@Transactional` + `TransactionalOperator` |
| **Repository base** | `JpaRepository` / `CrudRepository` | `ReactiveCrudRepository` |
| **Driver** | `org.postgresql:postgresql` | `org.postgresql:r2dbc-postgresql` |
| **Pool** | `spring.datasource.hikari.*` | `spring.r2dbc.pool.*` |
| **Testing** | `PostgreSQLContainer` + `@DynamicPropertySource` | same container + `R2dbcEntityTemplate` + `StepVerifier` |

> Reference: [r2dbc.md](references/r2dbc.md) for full reactive setup.

---

## Index Cheat Sheet

| Query Pattern | Index Type | Syntax |
|---------------|-----------|--------|
| `WHERE col = val` | B-tree (default) | `CREATE INDEX ON t (col)` |
| `WHERE col > val` | B-tree | `CREATE INDEX ON t (col)` |
| `WHERE a = x AND b > y` | Composite B-tree | `CREATE INDEX ON t (a, b)` |
| `WHERE jsonb @> '{}'` | GIN | `CREATE INDEX ON t USING gin (col)` |
| Full-text `WHERE tsv @@ q` | GIN | `CREATE INDEX ON t USING gin (to_tsvector('english', col))` |
| Nearest-neighbor geometry | GiST | `CREATE INDEX ON t USING gist (geom)` |
| Time-series append-only | BRIN | `CREATE INDEX ON t USING brin (created_at)` |
| Covering (avoid heap fetch) | B-tree + INCLUDE | `CREATE INDEX ON t (col) INCLUDE (a, b)` |
| Partial (filtered rows) | B-tree + WHERE | `CREATE INDEX ON t (email) WHERE deleted_at IS NULL` |

---

## 8 Critical Rules

1. **`GENERATED ALWAYS AS IDENTITY`** for surrogate PKs — not `SERIAL`; maps to JPA `@GeneratedValue(SEQUENCE)` with named sequence
2. **`timestamptz` not `timestamp`** — always store with timezone; query and compare in UTC
3. **`text` over `varchar(n)`** for most string columns — PostgreSQL stores both identically; `varchar(n)` adds a length-check constraint with no storage benefit
4. **`INCLUDE` for covering indexes** — PostgreSQL supports `INCLUDE (col_a, col_b)` to avoid heap fetch without adding columns to the sort key
5. **`@SQLRestriction` not `@Where`** — Hibernate 6 / Spring Boot 3.x deprecates `@Where`; use `@SQLRestriction("deleted_at IS NULL")`
6. **JPA uses `SEQUENCE` strategy** — PostgreSQL has no `AUTO_INCREMENT`; use `@GeneratedValue(strategy = SEQUENCE)` with `@SequenceGenerator`
7. **No `.block()` in reactive code** — if on WebFlux, use R2DBC; never mix blocking JDBC with a reactive pipeline
8. **`work_mem` scales with connections** — `work_mem × max_connections × parallel_workers` can OOM the server; tune carefully

---

## Anti-Pattern Table

| ❌ Anti-Pattern | ✅ Fix | Reference |
|----------------|--------|-----------|
| `SERIAL` / `BIGSERIAL` for PK | `bigint GENERATED ALWAYS AS IDENTITY` | [schema-indexing.md](references/schema-indexing.md) |
| `timestamp` without timezone | `timestamptz` — always | [schema-indexing.md](references/schema-indexing.md) |
| `varchar(255)` everywhere | `text` — no storage cost difference | [schema-indexing.md](references/schema-indexing.md) |
| `FLOAT` / `DOUBLE` for money | `numeric(10,2)` always | [schema-indexing.md](references/schema-indexing.md) |
| `SELECT *` in any query | Explicit column list | [schema-indexing.md](references/schema-indexing.md) |
| Missing FK indexes | Always index foreign key columns | [schema-indexing.md](references/schema-indexing.md) |
| `OFFSET` on large tables | Keyset (cursor) pagination | [schema-indexing.md](references/schema-indexing.md) |
| `@Where(clause="deleted_at IS NULL")` | `@SQLRestriction("deleted_at IS NULL")` (Hibernate 6+) | [jpa-hibernate.md](references/jpa-hibernate.md) |
| `FetchType.EAGER` on collections | `FetchType.LAZY` + JOIN FETCH / EntityGraph | [jpa-hibernate.md](references/jpa-hibernate.md) |
| `@GeneratedValue(IDENTITY)` in PostgreSQL | `@GeneratedValue(SEQUENCE)` + `@SequenceGenerator` | [jpa-hibernate.md](references/jpa-hibernate.md) |
| `open-in-view: true` (Spring Boot default) | `spring.jpa.open-in-view: false` — always | [jpa-hibernate.md](references/jpa-hibernate.md) |
| `auth.uid()` in RLS policies | `current_setting('app.current_user_id')::bigint` | [schema-indexing.md](references/schema-indexing.md) |
| Blocking JDBC in WebFlux pipeline | R2DBC + `ReactiveCrudRepository` | [r2dbc.md](references/r2dbc.md) |
| `work_mem = '8MB'` with 100 connections | `4MB` max; account for `parallel_workers` | [pool-transactions.md](references/pool-transactions.md) |

---

## Reference Files

| File | Contents |
|------|----------|
| [schema-indexing.md](references/schema-indexing.md) | DDL patterns, data types, all index types (B-tree/GIN/GiST/BRIN/covering/partial), `EXPLAIN (ANALYZE, BUFFERS)`, RLS with `current_setting`, UPSERT, keyset pagination, queue processing |
| [jpa-hibernate.md](references/jpa-hibernate.md) | PostgreSQL dialect, `SEQUENCE` ID strategy, entity design, `@SQLRestriction`, N+1 prevention, Spring Data Specifications, projections, batch writes |
| [r2dbc.md](references/r2dbc.md) | `r2dbc-postgresql` dependency, application.yml, `R2dbcEntityTemplate`, `DatabaseClient`, reactive transactions, `TransactionalOperator`, Testcontainers R2DBC testing |
| [pool-transactions.md](references/pool-transactions.md) | HikariCP sizing formula, PgBouncer, `work_mem` tuning, deadlock prevention, isolation level truth table, Micrometer metrics |
| [flyway-testing.md](references/flyway-testing.md) | Flyway PostgreSQL config, migration patterns, large table strategies (`NOT VALID` + `VALIDATE CONSTRAINT`), Testcontainers PostgreSQL, test isolation |
