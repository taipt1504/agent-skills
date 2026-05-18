# Example: Architecture Decision Brainstorm

## User request

"Tôi cần xử lý 10k events/sec từ Kafka và write vào Postgres. Currently sync, latency cao."

## Phase 1 — Frame

**Problem:** Sync processing of high-throughput Kafka events causing high latency.

**Dimensions:**
- Throughput (events/sec)
- Latency (p95)
- Operational complexity
- Data consistency guarantees
- Failure recovery
- Implementation time

**Constraints:** at-least-once delivery (regulation)
**Assumptions:** must use Postgres (questionable)

## Phase 2 — Tournament

### A1: Async batch processing

**Approach:** consume in batches of 100, write batch to Postgres.

**Implementation sketch:**
- Reactor Kafka receiver
- Buffer 100 events / 1s
- Single SQL multi-row INSERT
- Manual ack after batch commits

**Self-assessment:**
| Dimension | Score | Notes |
|---|---|---|
| Throughput | 5k/sec | Limited by batch fill time |
| Latency p95 | 200ms | Buffering adds latency |
| Ops complexity | Low | Single component |
| Consistency | Strong | Batch transactional |
| Failure recovery | Easy | Replay from offset |
| Implementation | 1 week | Simple |

**Weakness:** latency for individual events.

### Challenge 1 — Beat A1 on latency

### A2: Streaming with bounded parallelism

**Targets A1 weakness:** latency.

**Approach:** parallel consumer groups, each writes async with backpressure.

**Implementation sketch:**
- N parallel consumers (bounded N=4)
- Each writes single-row INSERT
- Reactive backpressure via `onBackpressureBuffer`

**A1 vs A2:**
| Dimension | A1 | A2 | Winner |
|---|---|---|---|
| Throughput | 5k/sec | 15k/sec | A2 |
| Latency p95 | 200ms | 50ms | A2 |
| Ops complexity | Low | Medium | A1 |
| Consistency | Strong | Eventual (per partition) | A1 |
| Failure recovery | Easy | Per-partition tracking | A1 |
| Implementation | 1 week | 2 weeks | A1 |

**Champion: A2** (hits throughput + latency targets).

### Challenge 2 — Different paradigm

### A3: CDC-based via Kafka Connect

**Paradigm shift:** declarative (config-driven) vs imperative (app code).

**Approach:** Kafka Connect JDBC sink. No application code.

**Implementation sketch:**
- Deploy Kafka Connect cluster
- Configure JDBC sink connector
- Manage schema evolution via Schema Registry

**A2 vs A3:**
| Dimension | A2 | A3 | Winner |
|---|---|---|---|
| Throughput | 15k/sec | 10k/sec | A2 |
| Latency p95 | 50ms | 100ms | A2 |
| Ops complexity | Medium | High (Connect cluster) | A2 |
| Consistency | Eventual | Eventual | Tie |
| Failure recovery | Per-partition | Connect manages | A3 |
| Implementation | 2 weeks | 3 days | A3 |

**Champion: A2** (operational complexity of A3 outweighs faster ship).

### Challenge 3 — Question assumptions

**Assumption questioned:** "must use Postgres"

### A4: TigerBeetle for hot path, Postgres async read model

**Approach:** TigerBeetle for ledger writes (1M+ ops/sec ledger-optimized), Postgres async via CDC for read queries.

**Implementation sketch:**
- TigerBeetle cluster (3-node)
- App writes ledger ops to TigerBeetle
- Background CDC streams to Postgres for reports

**A2 vs A4:**
| Dimension | A2 | A4 | Winner |
|---|---|---|---|
| Throughput | 15k/sec | 50k+/sec | A4 |
| Latency p95 | 50ms | 5ms | A4 |
| Ops complexity | Medium | High (new tech) | A2 |
| Consistency | Eventual | Strong (ledger) | A4 |
| Failure recovery | Per-partition | TigerBeetle replication | A4 |
| Implementation | 2 weeks | 3 weeks | A2 |

**Champion: A2** for now, A4 if scale projection > 20k/sec.

## Phase 3 — Synthesis

### Comparison matrix

| Dimension | A1: Batch | A2: Parallel | A3: Connect | A4: TigerBeetle |
|---|---|---|---|---|
| Throughput | 5k/sec | 15k/sec | 10k/sec | 50k+/sec |
| Latency p95 | 200ms | 50ms | 100ms | 5ms |
| Ops complexity | Low | Medium | High | High (new tech) |
| Consistency | Strong | Eventual | Eventual | Strong (ledger) |
| Failure recovery | Easy | Per-partition | Connect-managed | TigerBeetle-managed |
| Implementation | 1 week | 2 weeks | 3 days | 3 weeks |

### Recommendation: A2 — Parallel streaming

**Why:** Hits 10k/sec target with manageable complexity. A4 has better numbers but new tech adds significant ops + onboarding cost — over-engineered for current scale.

**What we gain:**
- 15k/sec throughput (50% margin over target)
- 50ms p95 latency
- Reuses existing Kafka + Postgres ops knowledge

**What we sacrifice:**
- Eventual consistency per partition (acceptable for event ingestion)
- 2-week implementation vs A3's 3 days
- Per-partition failure tracking complexity

**Confidence:** High

**Caveats:**
- Revisit A4 if scale projection exceeds 20k/sec
- Revisit A3 if ops capacity to manage Connect cluster becomes available

**Close call?** No — A1 obviously too slow, A3 ops burden disqualifying, A4 over-engineered for current scale.

## ADR (high-stakes mandatory)

→ `docs/adr/0023-async-kafka-postgres-ingestion.md` with all 4 options + rejection rationale + revisit triggers.

## What the user learns

- Numbers > vibes (concrete throughput/latency, not "fast enough")
- Paradigm shift (CDC) considered + rejected with reason (not just "didn't think of it")
- Assumption questioned (Postgres) → A4 born, evaluated honestly, deferred
- Trade-offs explicit (operational cost vs throughput)
