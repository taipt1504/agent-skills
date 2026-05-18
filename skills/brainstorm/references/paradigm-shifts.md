# Paradigm-Shift Catalog

Reference for Round 2 challenge ("different paradigm entirely?").

## Communication patterns

| Existing | Shift |
|---|---|
| HTTP request/response | Server-Sent Events / WebSocket |
| Synchronous REST | Async messaging (Kafka, SQS) |
| Polling | Webhook / push notification |
| Two-phase commit | Saga pattern with compensations |
| Direct service call | Mediator / API gateway |
| Single response | Streaming response (chunked, gRPC stream) |

## Data patterns

| Existing | Shift |
|---|---|
| Relational schema (RDBMS) | Document store (MongoDB) |
| Document store | Columnar (Cassandra) |
| Single-write DB | CQRS (separate read + write stores) |
| Eager loading | Lazy / on-demand |
| Snapshot state | Event sourcing |
| Synchronous DB write | Outbox pattern |
| Caching (read-through) | Materialized view |
| Index everything | Full-text search engine |
| ACID transactions | Eventual consistency |

## Computation patterns

| Existing | Shift |
|---|---|
| Imperative loop | Declarative (SQL, stream API) |
| Server-side render | Client-side render |
| Just-in-time compute | Pre-computation (cron, batch) |
| Single-machine | Distributed (Spark, Flink) |
| Cold start each request | Warm pool / connection reuse |
| Algorithm complexity | Approximation (sketch, bloom) |

## Architecture patterns

| Existing | Shift |
|---|---|
| Monolith | Decomposed services |
| Many services | Modular monolith (intentional) |
| In-house service | Managed (SaaS) |
| Build framework | Adopt established (Spring, Quarkus) |
| Custom protocol | Industry standard (gRPC, GraphQL) |
| Stateful service | Stateless + external state store |
| Tightly-coupled | Strangler Fig migration |

## Lifecycle patterns

| Existing | Shift |
|---|---|
| Big-bang deploy | Canary / blue-green |
| Cron schedule | Event trigger |
| Manual config | GitOps / declarative IaC |
| Tribal knowledge | Documentation + runbook |
| Reactive monitoring | Proactive (alerts on leading indicators) |
| Synchronous validation | Async with rollback |

## Code patterns

| Existing | Shift |
|---|---|
| Inheritance | Composition |
| Mutation | Immutability |
| Exceptions for flow | Result / Either type |
| Locks for sync | Lock-free (CAS, queues) |
| Hand-written validation | Schema-driven (JSON Schema, Bean Validation) |
| Custom DI | Framework DI |

## Negative-space shifts (subtraction)

Often overlooked. Ask: "Can we DELETE something to solve this?"

| Existing | Shift |
|---|---|
| Add new feature | Remove the friction that made feature needed |
| Add cache | Remove the slow query that needs caching |
| Add retry logic | Remove the dependency that fails |
| Add migration | Remove the column that needs migrating |
| Add abstraction | Remove the variant that needed abstraction |
| Add service | Remove the boundary that needed crossing |

## Selection guidance

Pick a shift if:
- Your A1, A2 cluster in one row of these tables
- The shift opens a new dimension on the comparison matrix
- The shift's downsides are different from A1, A2's downsides (not just "more of the same")

Don't pick a shift if:
- It violates a constraint (not assumption — constraint)
- Team has zero familiarity AND task is time-pressured
- It only differs cosmetically

## Honest stop

If after considering this catalog the agent genuinely sees no shift that opens new dimensions → state: "Considered paradigm shifts: <list checked>. None open new dimensions vs A1/A2. Tournament continues with A1/A2 only or proceeds to Round 3 assumption challenge."
