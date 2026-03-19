# Solution Design & Service Design Templates

Templates for system architecture documentation with Mermaid diagrams, C4, NFRs, and deployment.

## Table of Contents
- [Document Structure](#document-structure)
- [Solution Design Template](#solution-design-template)
- [Service Design Template](#service-design-template)
- [Key Principles](#key-principles)

---

## Document Structure

| Document | Purpose | Audience |
|----------|---------|----------|
| **Solution Design** | Overview — architecture, cross-service flows, NFRs | All stakeholders |
| **Service Design** | Detail — per-service implementation specs | Dev team |

```
Solution Design (overview)
├── Service Design: Service A (detail)
├── Service Design: Service B (detail)
└── ADRs (architecture decisions)
```

---

## Solution Design Template

### Sections

1. **Executive Summary** — Problem, solution, impact (3-5 sentences)
2. **Use Cases (Overview)** — Table with ID, name, actor, priority, link to Service Design
3. **User Journeys** — Mermaid journey diagrams, touchpoints, services involved
4. **High-Level Architecture**
   - System Context (C4 Level 1) — who/what interacts with system
   - Container Diagram (C4 Level 2) — services, databases, queues
   - Service Overview Table — service, responsibility, tech stack, link to Service Design
   - Communication Patterns — from/to, protocol, sync/async
5. **Key Sequence Diagrams** — Cross-service flows only (Mermaid)
6. **Non-Functional Requirements**
   - Performance (p95 latency, throughput, concurrent users)
   - Scalability (horizontal/vertical, growth, bottlenecks)
   - Availability (uptime target, failover, DR RPO/RTO)
   - Security (auth, encryption, API security)
   - Observability (logging, metrics, tracing, alerting)
7. **Deployment & Infrastructure** — Topology, environments, CI/CD
8. **Migration & Rollout** — Phased rollout, data migration, rollback
9. **Risks & Mitigations** — Risk table with probability, impact
10. **Key Architecture Decisions** — Summary + ADR links

### Naming Convention

```
designs/
├── YYYY-MM-DD-{project}-solution-design.md
├── YYYY-MM-DD-{service-a}-service-design.md
```

---

## Service Design Template

### Sections

1. **Service Overview** — Purpose, responsibilities, boundaries
2. **Tech Stack** — Table: layer, technology, version, rationale
3. **Use Cases (Detailed)** — Per UC: main flow (step table), alternative flows, exception flows, business rules
4. **User Journeys (Detailed)** — Flowchart, screen-by-screen breakdown, error states
5. **Sequence Diagrams** — Internal flows: Controller -> Service -> Repo -> DB -> Cache -> Queue
6. **Database Design**
   - ER Diagram (Mermaid)
   - DDL with constraints, indexes
   - Data considerations (soft delete, audit, partitioning)
   - Migration plan (Flyway versions)
7. **API Design**
   - Endpoints with request/response JSON, validation rules, error codes
   - Standards (naming, pagination, filtering, sorting, versioning, date format)
8. **Event/Message Design** — Events produced/consumed, schema, idempotency
9. **Security** — Auth per endpoint, data protection, input validation
10. **Error Handling & Resilience** — Exception strategy, circuit breaker, retry, timeout
11. **Performance & Caching** — Cache strategy (TTL, invalidation), query optimization
12. **Testing Strategy** — Unit, integration, API/contract, E2E
13. **Configuration** — Properties per environment, secrets management
14. **Monitoring** — Key metrics, health checks, log events

---

## Key Principles

1. **Templates are frameworks, not rigid forms** — add/remove sections based on actual system
2. **Solution Design links to Service Design** for details, don't duplicate
3. **Use Mermaid diagrams** — version-control friendly
4. **Evidence over opinion** — include benchmarks, data, rationale

### Adapting

**Remove**: No async events? Skip Event Design. Simple service? Merge sections.
**Add**: Multi-tenant? Add tenancy design. Real-time? Add WebSocket/SSE. Complex auth? Expand security.
