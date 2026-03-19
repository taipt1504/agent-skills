# Summer Data — DDL Scripts

## audit_log Table

```sql
CREATE TABLE IF NOT EXISTS audit_log
(
    id                UUID PRIMARY KEY                  DEFAULT gen_random_uuid(),
    action            VARCHAR(50),
    intent            VARCHAR(50)              NOT NULL,
    actor_id          VARCHAR(100),
    actor_username    VARCHAR(100),
    actor_family_name VARCHAR(255),
    actor_given_name  VARCHAR(255),
    actor_email       VARCHAR(100),
    actor_roles       TEXT,
    request_id        VARCHAR(50),
    trace_id          VARCHAR(50),
    ip_address        VARCHAR(45),
    user_agent        TEXT,
    request_method    VARCHAR(10),
    request_uri       TEXT,
    entity_type       VARCHAR(255),
    entity_id         VARCHAR(100),
    comment           TEXT,
    old_values        JSONB,
    new_values        JSONB,
    diff_values       JSONB,
    timestamp         TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log (entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_intent ON audit_log (intent, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log (action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_trace ON audit_log (trace_id) WHERE trace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity_intent ON audit_log (entity_type, intent, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity_action ON audit_log (entity_type, action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_old_values ON audit_log USING GIN (old_values);
CREATE INDEX IF NOT EXISTS idx_audit_log_new_values ON audit_log USING GIN (new_values);

-- Immutability trigger (prevents UPDATE and DELETE)
CREATE OR REPLACE FUNCTION prevent_audit_log_modification()
    RETURNS TRIGGER AS
$$
BEGIN
    IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'Audit logs cannot be updated'; END IF;
    IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Audit logs cannot be deleted'; END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

**23 columns.** `AuditTableValidator` verifies all columns exist on startup.

## outbox_events Table

```sql
CREATE TABLE outbox_events
(
    id            UUID PRIMARY KEY,
    aggregate_id  VARCHAR(255) NOT NULL,
    event_type    VARCHAR(255) NOT NULL,
    payload       JSONB        NOT NULL,
    published     BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    published_at  TIMESTAMPTZ,
    retry_count   INTEGER      NOT NULL DEFAULT 0,
    error_message TEXT
);

CREATE INDEX idx_outbox_unpublished ON outbox_events (published, created_at)
    WHERE published = FALSE;
```

**9 columns.** `OutboxTableValidator` validates column names and types on startup.

## Flyway Migration Notes

Place DDL scripts in `src/main/resources/db/migration/`:

```sql
-- V1__Create_audit_log.sql
-- (paste audit_log DDL above)

-- V2__Create_outbox_events.sql
-- (paste outbox_events DDL above)
```

Embedded Flyway scripts were deleted from `data-audit` in 0.2.1 — you must include them in your project migrations.
