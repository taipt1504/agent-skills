# Connection Pooling & Transactions — PostgreSQL

---

## HikariCP Pool Sizing Formula

```
pool_size = (vCPU × 2) + effective_spindle_count
```

**Why**: Threads waiting on I/O can be context-switched, so each CPU can serve more than one thread. The `×2` accounts for I/O wait. `spindle_count` represents disk-level parallelism.

**SSD math**: SSDs have essentially unlimited concurrent I/O → treat as 1 spindle.

| Server | vCPU | Spindle | Max Pool Size |
|--------|------|---------|---------------|
| 2-vCPU cloud (SSD) | 2 | 1 | **5** |
| 4-vCPU cloud (SSD) | 4 | 1 | **9** |
| 8-vCPU cloud (SSD) | 8 | 1 | **17** |

> PostgreSQL's `max_connections` is a hard limit shared across all clients (application servers, migrations, admin tools). For multi-instance deployments, use **PgBouncer** to multiplex — see below.

---

## HikariCP — Full application.yml

```yaml
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require&reWriteBatchedInserts=true
    username: ${DB_USER}
    password: ${DB_PASS}
    driver-class-name: org.postgresql.Driver
    hikari:
      pool-name: HikariPool-Main
      maximum-pool-size: 10           # Set to vCPU*2+1 for SSD — see formula above
      minimum-idle: 2
      connection-timeout: 30000       # 30s — fail fast if pool exhausted
      idle-timeout: 600000            # 10 min
      max-lifetime: 1800000           # 30 min — must be < PostgreSQL tcp_keepalives_idle
      keepalive-time: 60000           # 1 min keepalive ping
      connection-test-query: SELECT 1
```

> `reWriteBatchedInserts=true` in JDBC URL enables PostgreSQL-side INSERT batching (equivalent to MySQL's `rewriteBatchedStatements`).

---

## PgBouncer — Connection Multiplexing

When running multiple service instances, each has its own HikariCP pool. Without a proxy, `max_connections` on the PostgreSQL server is quickly exhausted.

```
[Service A: 3 instances × 10 pool = 30 connections]
[Service B: 2 instances × 10 pool = 20 connections]
→ Total: 50 connections → PostgreSQL at 100 max_connections limit is a problem
```

**PgBouncer in transaction pooling mode** multiplexes N application connections to M server connections:

```ini
# pgbouncer.ini
[databases]
mydb = host=postgres port=5432 dbname=mydb

[pgbouncer]
pool_mode        = transaction          # Release server connection after each transaction
max_client_conn  = 1000                 # Application connections PgBouncer accepts
default_pool_size = 20                  # Server connections PgBouncer maintains to PostgreSQL
reserve_pool_size = 5                   # Extra connections for spikes
server_idle_timeout = 600
```

Application points to PgBouncer:
```yaml
spring.datasource.url: jdbc:postgresql://${PGBOUNCER_HOST}:6432/${DB_NAME}
```

> In transaction pooling mode, **prepared statements are disabled** — use `preferQueryMode=simple` in JDBC URL or disable `prepStmtCache` in HikariCP.

---

## PostgreSQL Server Configuration

```sql
-- Tune for application workload (adjust per RAM; these are conservative defaults)
ALTER SYSTEM SET max_connections = 100;         -- Set LOWER than you think; PgBouncer handles scale
ALTER SYSTEM SET shared_buffers = '256MB';      -- 25% of RAM rule-of-thumb
ALTER SYSTEM SET effective_cache_size = '1GB';  -- Estimated OS + PG cache (affects planner)
ALTER SYSTEM SET work_mem = '4MB';              -- Per sort/hash operation per query

-- work_mem math: work_mem × max_connections × parallel_workers = potential memory usage
-- 4MB × 100 connections × 2 workers = 800MB minimum — keep this low
ALTER SYSTEM SET maintenance_work_mem = '64MB'; -- For VACUUM, CREATE INDEX (can be higher)

-- Timeouts
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';  -- Kill idle-in-transaction
ALTER SYSTEM SET statement_timeout = '30s';                     -- Kill long-running queries

-- Monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT pg_reload_conf();
```

---

## Deadlock Prevention

PostgreSQL detects deadlocks automatically and aborts one transaction (error code 40P01).

### Rule 1 — Consistent Lock Ordering

Always acquire locks on rows/tables in the same order across all code paths:

```java
// ❌ Transaction A: locks account 1 then 2
// ❌ Transaction B: locks account 2 then 1 → deadlock

// ✅ Always lock lower ID first
void transfer(Account a, Account b, BigDecimal amount) {
    Account first  = a.getId() < b.getId() ? a : b;
    Account second = a.getId() < b.getId() ? b : a;
    accountRepo.debit(first.getId(), amount);
    accountRepo.credit(second.getId(), amount);
}
```

### Rule 2 — Keep Transactions Short

```java
// ❌ External I/O inside a transaction holds locks
@Transactional
public Order createOrder(CreateOrderCommand cmd) {
    var order = orderRepo.save(Order.create(cmd));
    paymentGateway.charge(cmd);     // HTTP call inside TX — holds DB locks!
    return order;
}

// ✅ I/O outside TX; only DB writes inside
public Order createOrder(CreateOrderCommand cmd) {
    var confirmation = paymentGateway.charge(cmd);   // Outside TX
    return persistOrder(cmd, confirmation);
}

@Transactional
protected Order persistOrder(CreateOrderCommand cmd, PaymentConfirmation conf) {
    return orderRepo.save(Order.create(cmd, conf));
}
```

### Rule 3 — Pre-Acquire with `SELECT ... FOR UPDATE`

```java
// ❌ Read-then-update: race condition between read and write
Order order = orderRepo.findById(id).orElseThrow();
order.confirm();
orderRepo.save(order);

// ✅ Lock the row at read time
@Query("SELECT o FROM Order o WHERE o.id = :id FOR UPDATE")
Optional<Order> findByIdForUpdate(@Param("id") Long id);

@Transactional
public Order confirm(Long id) {
    Order order = orderRepo.findByIdForUpdate(id).orElseThrow();
    order.confirm();
    return orderRepo.save(order);
}
```

### Rule 4 — Retry on Deadlock / Serialization Failure

```java
@Retryable(
    retryFor = { CannotSerializeTransactionException.class,
                 CannotAcquireLockException.class },
    maxAttempts = 3,
    backoff = @Backoff(delay = 50, multiplier = 2, random = true)
)
@Transactional
public Order confirmOrder(Long id) { ... }
```

PostgreSQL error codes:
- `40001` — serialization failure (REPEATABLE READ / SERIALIZABLE)
- `40P01` — deadlock detected

---

## Isolation Level Truth Table

| Level | Dirty Read | Non-Repeatable Read | Phantom Read | Serialization Anomaly | Deadlock Risk |
|-------|-----------|---------------------|-------------|----------------------|--------------|
| `READ_UNCOMMITTED` | ❌ prevented¹ | ✅ possible | ✅ possible | ✅ possible | Lowest |
| `READ_COMMITTED` *(PG default)* | ❌ prevented | ✅ possible | ✅ possible | ✅ possible | Low |
| `REPEATABLE_READ` | ❌ prevented | ❌ prevented | ❌ prevented | ✅ possible | Medium |
| `SERIALIZABLE` | ❌ prevented | ❌ prevented | ❌ prevented | ❌ prevented | High (aborts) |

¹ PostgreSQL does not implement `READ_UNCOMMITTED` — it behaves as `READ_COMMITTED`.

**PostgreSQL vs MySQL isolation semantics differ**:
- PostgreSQL `REPEATABLE_READ` uses MVCC snapshots — no gap locks, no phantom reads
- PostgreSQL `SERIALIZABLE` uses SSI (Serializable Snapshot Isolation) — detects conflicts without full locking; serialization failures trigger retries, not deadlocks

```java
// ✅ Default — READ_COMMITTED — correct for most OLTP
@Transactional

// ✅ REPEATABLE_READ — consistent snapshot; retry on 40001
@Transactional(isolation = Isolation.REPEATABLE_READ)

// ✅ SERIALIZABLE — strictest guarantee; retry on 40001 required
@Transactional(isolation = Isolation.SERIALIZABLE)
```

---

## Service Transaction Pattern

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)   // Default read-only — uses read replica if configured
public class OrderService {

    private final OrderRepository orderRepository;

    public Optional<Order> findById(Long id) {
        return orderRepository.findById(id);
    }

    @Transactional   // readOnly = false for writes
    public Order create(CreateOrderCommand cmd) {
        return orderRepository.save(Order.create(cmd));
    }

    @Transactional(propagation = Propagation.NESTED)
    public void processItem(OrderItem item) {
        // Uses SAVEPOINT — partial rollback possible; outer TX continues on error
    }
}
```

---

## HikariCP Metrics via Micrometer

```yaml
management:
  metrics:
    enable:
      hikaricp: true
```

| Metric | Alert Threshold | Meaning |
|--------|----------------|---------|
| `hikaricp.connections.pending` | > 0 sustained | Pool exhausted |
| `hikaricp.connections.timeout` | Any | Connection wait timeout |
| `hikaricp.connections.acquire` (p99) | > 100ms | High contention |
| `hikaricp.connections.usage` (p99) | > 5s | Long-running transactions |
