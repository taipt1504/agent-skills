# Summer Data — DDL Scripts & Implementation Reference

> Read when: setting up audit_log or outbox_events tables, implementing AuditService or OutboxService.

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

CREATE TRIGGER trg_audit_log_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_modification();
```

**23 columns.** `AuditTableValidator` verifies all columns exist on startup.

## AuditService Implementation

### Builder Pattern Usage

```java
// Basic audit entry
auditService.audit()
    .action("CREATE")
    .intent("order.placed")
    .entityType("Order")
    .entityId(orderId)
    .newValues(orderDto)
    .save();

// With actor context (auto-extracted from SecurityContext)
auditService.audit()
    .action("UPDATE")
    .intent("order.status_changed")
    .entityType("Order")
    .entityId(orderId)
    .oldValues(previousState)
    .newValues(newState)
    .comment("Status changed from PENDING to CONFIRMED")
    .save();
```

### Annotation-Based Auditing

```java
@Audit(action = "DELETE", intent = "order.cancelled", entityType = "Order")
public Mono<Void> cancelOrder(@AuditEntityId String orderId) {
    return orderRepository.deleteById(orderId);
}
```

### Querying Audit Logs

```java
// By entity
auditService.findByEntity("Order", orderId)
    .collectList();

// By actor in time range
auditService.findByActor(actorId, startTime, endTime)
    .collectList();

// By intent with pagination
auditService.findByIntent("order.placed", PageRequest.of(0, 50))
    .collectList();
```

## outbox_events Table (0.3.1+ shape)

```sql
CREATE TABLE outbox_events
(
    id            UUID PRIMARY KEY,                                  -- Ufid stored as UUID
    aggregate_id  VARCHAR(255) NOT NULL,
    event_type    VARCHAR(255) NOT NULL,
    payload       JSONB        NOT NULL,
    published     BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    published_at  TIMESTAMPTZ,
    retry_count   INTEGER      NOT NULL DEFAULT 0,
    error_message TEXT,
    next_retry_at TIMESTAMPTZ,                                       -- 0.2.8+ — used by OutboxRetryTask
    lsn           BIGINT                                              -- 0.3.1+ — preserved across CDC retries for consumer watermark
);

-- Essential: serves the scheduler publisher (retry_count=0) and monitoring
CREATE INDEX idx_outbox_unpublished ON outbox_events (created_at)
    WHERE published = FALSE;

-- Essential: serves OutboxRetryTask — partial index keeps it tiny
CREATE INDEX idx_outbox_retry ON outbox_events (next_retry_at)
    WHERE published = FALSE AND retry_count > 0;

-- Optional: history lookups by aggregate / type
CREATE INDEX idx_outbox_aggregate ON outbox_events (aggregate_id, created_at DESC);
CREATE INDEX idx_outbox_type      ON outbox_events (event_type,   created_at DESC);
```

**11 columns.** `OutboxTableValidator` validates column names and types on startup.

### Adding the 0.2.8 / 0.3.1 columns to an existing table

```sql
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;     -- 0.2.8
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS lsn           BIGINT;          -- 0.3.1
CREATE INDEX IF NOT EXISTS idx_outbox_retry ON outbox_events (next_retry_at)
    WHERE published = FALSE AND retry_count > 0;
```

`OutboxRetryTask` re-emits the same `ob.lsn` Kafka header on retry to keep consumer watermarks consistent (CDC-mode only). Existing pre-0.3.1 rows with `NULL lsn` fall back to the old epoch-nanos behaviour.

## outbox_consumer_watermark Table (0.3.1+)

For services that consume Summer outbox events with LSN-watermark idempotency. Column names are validated literally by `ConsumerWatermarkValidator` — using `lsn` / `updated_at` here will fail boot.

```sql
CREATE TABLE outbox_consumer_watermark
(
    consumer_group  VARCHAR(255) NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    partition       INTEGER      NOT NULL,
    last_lsn        BIGINT       NOT NULL,
    last_event_id   UUID,                                            -- debug/audit only
    last_updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (consumer_group, topic, partition)
);
```

Storage cost: O(groups × topics × partitions) — typically under a few hundred rows per service, regardless of message volume.

See [`summer-kafka`](../../summer-kafka/SKILL.md) for the consumer-side listener wiring.

## PostgreSQL prereqs for CDC mode

Required when `f8a.outbox.publisher.mode=cdc`. No effect under `mode=scheduler`.

```sql
-- 1. wal_level must be 'logical' (set in postgresql.conf or via docker -c wal_level=logical)
SHOW wal_level;                                      -- must return 'logical'

-- 2. The DB user the connector authenticates as needs REPLICATION
ALTER ROLE <db_user> WITH REPLICATION;

-- 3. The outbox table needs REPLICA IDENTITY DEFAULT (uses PK) or FULL
ALTER TABLE outbox_events REPLICA IDENTITY DEFAULT;  -- DEFAULT uses primary key (id)

-- 4. Create a filtered publication for the outbox table only
--    (publication.autocreate.mode is typically 'disabled' so the publication must exist before connector startup)
DROP PUBLICATION IF EXISTS dbz_<svc>_outbox;
CREATE PUBLICATION dbz_<svc>_outbox FOR TABLE public.outbox_events;
```

The replication slot itself (`slot.name` in the connector config) is created automatically by Debezium on first connect, with `pgoutput` plugin. If the slot already exists with a different plugin, drop it before the connector starts:

```sql
SELECT pg_drop_replication_slot('<slot_name>') WHERE EXISTS (
    SELECT 1 FROM pg_replication_slots WHERE slot_name = '<slot_name>' AND plugin <> 'pgoutput'
);
```

## OutboxService Implementation

### Saving Events (Transactional)

```java
@Service
@RequiredArgsConstructor
public class OrderService {
    private final OrderRepository orderRepository;
    private final OutboxService outboxService;

    @Transactional
    public Mono<Order> createOrder(CreateOrderCommand cmd) {
        return orderRepository.save(Order.create(cmd))
            .flatMap(order -> outboxService.save(
                OutboxEvent.builder()
                    .aggregateId(order.getId())
                    .eventType("OrderCreated")
                    .payload(order)
                    .build()
            ).thenReturn(order));
    }
}
```

### Outbox Scheduler (Polling Publisher)

The `OutboxScheduler` runs at a configurable interval, fetching unpublished events and publishing them:

```yaml
f8a:
  outbox:
    scheduler:
      enabled: true
      interval: 5s             # polling interval
      batch-size: 100          # max events per poll
      max-retries: 5           # retry limit before dead-lettering
    circuit-breaker:
      enabled: true
      failure-rate-threshold: 50
      wait-duration-in-open-state: 30s
```

### Error Handling & Dead Letter

Events exceeding `max-retries` are marked with `published = true` and `error_message` populated. Query dead-lettered events:

```sql
SELECT * FROM outbox_events
WHERE published = TRUE AND error_message IS NOT NULL
ORDER BY created_at DESC;
```

## Flyway Migration Notes

Place DDL scripts in `src/main/resources/db/migration/`:

```sql
-- V1__Create_audit_log.sql
-- (paste audit_log DDL above)

-- V2__Create_outbox_events.sql
-- (paste outbox_events DDL above)
```

Embedded Flyway scripts were deleted from `data-audit` in 0.2.1 — you must include them in your project migrations.

## Partition Strategy (High-Volume)

For audit_log with >10M rows/month, consider range partitioning:

```sql
CREATE TABLE audit_log (
    -- same columns as above
) PARTITION BY RANGE (created_at);

CREATE TABLE audit_log_2024_01 PARTITION OF audit_log
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Auto-create partitions with pg_partman
CREATE EXTENSION IF NOT EXISTS pg_partman;
SELECT create_parent('public.audit_log', 'created_at', 'native', 'monthly');
```

For outbox_events, partition by `published` status:

```sql
CREATE TABLE outbox_events (
    -- same columns as above
) PARTITION BY LIST (published);

CREATE TABLE outbox_events_pending PARTITION OF outbox_events FOR VALUES IN (FALSE);
CREATE TABLE outbox_events_done PARTITION OF outbox_events FOR VALUES IN (TRUE);
```
