---
name: migration
description: Flyway/Liquibase migration immutability — committed migration = applied to ≥1 env, NEVER edit. Schema change always creates new V file. Checksum mismatch blocks app boot.
globs: "**/db/migration/*.sql,**/db/migration/*.xml"
applicability:
  always: false
  triggers:
    files_match: ["**/db/migration/**/*.sql", "**/db/migration/**/*.xml", "**/db/changelog/**/*.xml"]
    code_patterns: ["flyway", "liquibase", "schema_history"]
    task_keywords: ["migration", "Flyway", "Liquibase", "schema change", "DDL"]
    related_rules:
      - rules/common/git-workflow.md
      - rules/common/development-workflow.md
---

# Migration Immutability (HARD BLOCK)

Committed migration = applied to ≥1 env → TUYỆT ĐỐI KHÔNG edit. Schema change → create new `V{n+1}__description.sql`.

Flyway checksum: edit file → checksum mismatch → app boot fail. CI rejects PR.

## Allowed direct edit

1. File uncommitted (local branch, not pushed)
2. Verified unapplied in ALL envs (`SELECT * FROM flyway_schema_history WHERE version = '<v>'` returns 0 across dev/staging/prod)

Either condition uncertain → assume committed → create new V file.

## Pattern — Adding a column

```sql
-- V11__create_merchant_bank_account_table.sql  -- committed, untouchable

-- V12__add_swift_code_to_merchant_bank_account.sql  -- NEW
ALTER TABLE merchant_bank_account ADD COLUMN swift_code VARCHAR(11);
```

NEVER edit V11 to add the column.

## Pattern — Dropping a column

Two-phase, two migrations, two deploys:


```sql
-- V13__deprecate_legacy_swift_code.sql
-- Application: stop writing to legacy_swift_code (code change in same deploy)
-- DDL: no-op or comment marking deprecation

-- V14__drop_legacy_swift_code.sql  (NEXT release, after V13 baked-in prod)
ALTER TABLE merchant_bank_account DROP COLUMN legacy_swift_code;
```

Why: rolling deploys mean old + new code coexist briefly — dropping column while old code reads → NPE / runtime errors.

## Pattern — Renaming a column

Expand-contract pattern, 3 migrations:

```sql
-- V20__add_new_column.sql
ALTER TABLE orders ADD COLUMN order_status VARCHAR(20);
-- Backfill from old column
UPDATE orders SET order_status = status WHERE order_status IS NULL;

-- V21__sync_dual_writes.sql -- application writes to BOTH columns
-- DDL: trigger to keep them in sync (optional, defense-in-depth)

-- V22__drop_old_column.sql -- after V21 baked-in prod, all reads migrated
ALTER TABLE orders DROP COLUMN status;
```

3 deploys minimum: add+backfill / dual-write / drop.

## Pattern — Index changes

Use `CONCURRENTLY` (Postgres) or `ONLINE` (MySQL 8+) to avoid table locks:

```sql
-- V30__add_orders_status_idx.sql
CREATE INDEX CONCURRENTLY orders_status_idx ON orders(status);
```

NEVER `CREATE INDEX` blocking on large tables in production migration.

## Pattern — Data backfill on large tables

Schema migrations MUST NOT run heavy backfills (lock time, deploy timeout). Use:

```sql
-- V40__add_normalized_phone_column.sql  -- schema only, fast
ALTER TABLE customers ADD COLUMN phone_e164 VARCHAR(20);
```

Run backfill via separate batch job / scheduled task in chunks.

## Schema history table integrity

```sql
-- Verify before claiming "uncommitted":
SELECT version, description, success, installed_on
FROM flyway_schema_history
WHERE version = '11'
ORDER BY installed_on DESC;
```

Empty across ALL envs → genuinely uncommitted → safe to edit. ANY non-empty result → create new V file.

## Anti-patterns

| Anti-pattern | Fix |
|---|---|
| Edit committed V file to fix "small typo" | New V file with corrective DDL |
| Drop column in same migration as code that stopped writing | 2-phase: deploy deprecation, then drop next release |
| Rename column in single migration | 3-phase expand-contract |
| `CREATE INDEX` (blocking) on million-row table | `CREATE INDEX CONCURRENTLY` (Postgres) |
| Schema migration with `UPDATE` over 100k+ rows | Schema-only migration + separate batch backfill |
| Delete + recreate migration file with same version number | New version number always |

## CI enforcement

`scripts/ci/check-migration-immutability.sh` (Phase 5 candidate): for each committed `V*.sql`, verify it hasn't been edited since the previous commit unless explicitly allowed via `[migration-revert-allowed]` commit tag.

## Related

- `skills/database-patterns` — Flyway / Liquibase setup, schema design
- `rules/common/git-workflow.md` — commit conventions
- `rules/common/development-workflow.md` — definition-of-done includes migration verification
