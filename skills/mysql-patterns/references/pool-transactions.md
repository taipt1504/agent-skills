# Connection Pooling & Transactions — MySQL

---

## HikariCP Pool Sizing Formula

```
pool_size = (vCPU × 2) + effective_spindle_count
```

**Why**: Threads waiting on I/O can be context-switched out, so a CPU can serve more than one thread.
The `×2` accounts for I/O wait. `spindle_count` represents disk-level parallelism.

**SSD math**: SSDs have essentially unlimited concurrent I/O → treat as 1 spindle.

| Server | vCPU | Spindle | Max Pool Size |
|--------|------|---------|---------------|
| 2-vCPU cloud (SSD) | 2 | 1 | **5** |
| 4-vCPU cloud (SSD) | 4 | 1 | **9** |
| 8-vCPU cloud (SSD) | 8 | 1 | **17** |
| 4-vCPU + 2 HDD | 4 | 2 | **10** |

> A pool of 5 on a 2-vCPU server outperforms a pool of 100 — extra connections queue at MySQL and increase lock contention. See [HikariCP pool sizing](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing).

---

## HikariCP — Full application.yml

```yaml
spring:
  datasource:
    url: jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}?useUnicode=true&characterEncoding=UTF-8&serverTimezone=UTC
    username: ${DB_USER}
    password: ${DB_PASS}
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      pool-name: HikariPool-Main
      maximum-pool-size: 10           # Set to vCPU*2+1 for SSD; see formula above
      minimum-idle: 2                 # Keep a few connections warm
      connection-timeout: 30000       # 30s — fail fast if pool exhausted
      idle-timeout: 600000            # 10 min — return idle connections to server
      max-lifetime: 1800000           # 30 min — must be < MySQL wait_timeout (default 8h)
      keepalive-time: 60000           # 1 min — send keepalive to prevent server-side close
      connection-test-query: SELECT 1
      data-source-properties:
        cachePrepStmts: true
        prepStmtCacheSize: 250
        prepStmtCacheSqlLimit: 2048
        useServerPrepStmts: true
        useLocalSessionState: true
        rewriteBatchedStatements: true   # Required for saveAll() batching to work
        cacheResultSetMetadata: true
        cacheServerConfiguration: true
        elideSetAutoCommits: true
        maintainTimeStats: false
```

---

## Deadlock Prevention

Deadlocks occur when two transactions hold locks and each waits for the other to release.
MySQL automatically detects deadlocks and rolls back the younger transaction (error 1213, SQLState 40001).

### Rule 1 — Consistent Lock Ordering

Always access tables and rows in the same order across all transactions.

```java
// ❌ Transaction A: locks account 1 then account 2
// ❌ Transaction B: locks account 2 then account 1  → deadlock
void transfer(Account from, Account to, BigDecimal amount) {
    // Accesses depend on call order — non-deterministic locking
}

// ✅ Always lock the lower ID first
void transfer(Account a, Account b, BigDecimal amount) {
    Account first  = a.getId() < b.getId() ? a : b;
    Account second = a.getId() < b.getId() ? b : a;
    // Debit first, credit second — consistent order for all callers
    accountRepo.debit(first.getId(), amount);
    accountRepo.credit(second.getId(), amount);
}
```

### Rule 2 — Keep Transactions Short

```java
// ❌ Long transaction: holds locks while doing I/O (HTTP call, file read)
@Transactional
public Order createOrder(CreateOrderCommand cmd) {
    var order = orderRepo.save(Order.create(cmd));
    var confirmation = paymentGateway.charge(cmd);   // External HTTP call inside TX!
    notificationService.sendEmail(cmd.email());       // More I/O inside TX!
    return order;
}

// ✅ Fetch outside transaction; write inside a short transaction
public Order createOrder(CreateOrderCommand cmd) {
    var confirmation = paymentGateway.charge(cmd);    // I/O outside TX
    return persistOrder(cmd, confirmation);
}

@Transactional
protected Order persistOrder(CreateOrderCommand cmd, PaymentConfirmation confirmation) {
    return orderRepo.save(Order.create(cmd, confirmation));
}
```

### Rule 3 — Pre-Acquire Locks with SELECT … FOR UPDATE

```java
// ❌ Read-then-update causes gap between read and write — race condition
Order order = orderRepo.findById(id).orElseThrow();
order.confirm();                   // Another TX may have changed state between read and here
orderRepo.save(order);

// ✅ Lock the row at read time
@Query("SELECT o FROM Order o WHERE o.id = :id FOR UPDATE")
Optional<Order> findByIdForUpdate(@Param("id") Long id);

@Transactional
public Order confirmOrder(Long id) {
    Order order = orderRepo.findByIdForUpdate(id).orElseThrow();
    order.confirm();
    return orderRepo.save(order);
}
```

### Rule 4 — Retry on Deadlock

```java
// Retry on SQLState 40001 (deadlock) or 40P01 (lock wait timeout)
@Retryable(
    retryFor = { MySQLTransactionRollbackException.class, CannotAcquireLockException.class },
    maxAttempts = 3,
    backoff = @Backoff(delay = 100, multiplier = 2, random = true)
)
@Transactional
public Order confirmOrder(Long id) {
    // ...
}

@Recover
public Order handleDeadlock(MySQLTransactionRollbackException ex, Long id) {
    log.error("Order {} deadlock after retries", id, ex);
    throw new OrderProcessingException("Concurrent modification detected — please retry", ex);
}
```

---

## Isolation Level Truth Table

| Level | Dirty Read | Non-Repeatable Read | Phantom Read | Gap Locks | Deadlock Risk |
|-------|-----------|---------------------|-------------|-----------|--------------|
| `READ_UNCOMMITTED` | ✅ possible | ✅ possible | ✅ possible | No | Lowest |
| `READ_COMMITTED` | ❌ prevented | ✅ possible | ✅ possible | Minimal | Low |
| `REPEATABLE_READ` *(MySQL default)* | ❌ prevented | ❌ prevented | ❌ prevented (gap locks) | Yes | Medium–High |
| `SERIALIZABLE` | ❌ prevented | ❌ prevented | ❌ prevented | Full range | Highest |

**Critical Clarification** (common misconception fixed):
- `REPEATABLE_READ` *prevents* phantom reads in MySQL via gap locks — it does NOT cause them
- `READ_COMMITTED` *allows* phantom reads but *reduces* gap lock contention and deadlock frequency
- Choosing `READ_COMMITTED` trades phantom read safety for lower lock contention — acceptable for most OLTP workloads

```java
// ✅ Default — REPEATABLE_READ — correct for financial operations
@Transactional

// ✅ READ_COMMITTED — use when deadlocks are frequent and phantom reads are tolerable
@Transactional(isolation = Isolation.READ_COMMITTED)

// ✅ SERIALIZABLE — only for strict audit / balance critical paths
@Transactional(isolation = Isolation.SERIALIZABLE)
```

---

## Service Transaction Pattern

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)   // Default read-only — applied to all public methods
public class OrderService {

    private final OrderRepository orderRepository;

    // Read method — inherits readOnly = true from class; uses read replica if configured
    public Optional<Order> findById(Long id) {
        return orderRepository.findById(id);
    }

    // Write method — overrides to readOnly = false
    @Transactional
    public Order create(CreateOrderCommand cmd) {
        return orderRepository.save(Order.create(cmd));
    }

    // Nested transaction (uses SAVEPOINT — partial rollback)
    @Transactional(propagation = Propagation.NESTED)
    public void processItem(OrderItem item) {
        // Rolls back only this method on error; outer TX continues
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

Key metrics to monitor:

| Metric | Alert Threshold | Meaning |
|--------|----------------|---------|
| `hikaricp.connections.pending` | > 0 sustained | Pool exhausted — increase size or optimize queries |
| `hikaricp.connections.timeout` | Any | Connection wait timeout — pool too small or queries too long |
| `hikaricp.connections.acquire` (p99) | > 100ms | High contention — review query performance |
| `hikaricp.connections.usage` (p99) | > 5s | Long-running transactions or slow queries holding connections |
