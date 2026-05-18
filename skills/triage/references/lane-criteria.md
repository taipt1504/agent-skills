# Lane Criteria — Extended Reference

Decision criteria for triage. Use when `skills/triage/SKILL.md` decision tree is ambiguous.

## Trivial lane — strict criteria

ALL of:
- Code change ≤5 lines (after format)
- 1 file affected (rarely 2 if mechanically linked, e.g., rename + import update)
- No behavior change visible from any caller
- No new dependency (build.gradle/pom.xml untouched)
- No public API change (signatures, response shapes, status codes)
- No persistence change (no migration, no schema, no Flyway/Liquibase)
- No security boundary change (auth, secrets, encryption)

If ANY fails → not trivial.

### Trivial examples (canonical)

- Fix typo in log message / error string
- Rename internal private variable
- Add Javadoc / inline comment
- Reformat indentation
- Update copyright year
- Bump version in non-functional config (e.g., README badge)
- Add missing `final` keyword
- Remove unused import

### Borderline → escalate to standard

- "Fix one-line bug" — bug fix usually requires spec scenario, escalate to standard
- "Rename public method" — public API change, escalate (high-stakes if cross-service)
- "Add @Valid annotation" — behavior change (new validation rejects previously-accepted input), escalate to standard

## Standard lane — bounded scope

Default for most tasks. Criteria:
- Feature, bugfix, or refactor
- Bounded to 1-3 components/services
- No architectural reshape
- Reversible without significant cost (rollback ≤ 1 day work)
- New dependencies allowed only if widely-used + well-scoped (e.g., adding `@Valid`, MapStruct)

### Standard examples

- Add pagination to existing list endpoint
- Fix race condition in OrderService
- Refactor PaymentProcessor to extract notification logic
- Add validation rule to user registration
- Optimize slow query in OrderRepository
- Add new use case (CreateOrderUseCase) within existing bounded context
- Add new event consumer for existing topic

## High-stakes lane — architecture + risk

ANY of:
- Architecture / system design change (new bounded context, new layer, pattern reshape)
- Data persistence change (schema migration, partitioning, sharding, denormalization)
- Security-sensitive change (auth flow, secrets management, encryption, audit)
- Public API contract change (new endpoint exposed externally, contract version bump, breaking change)
- Breaking change to existing behavior (consumer must adapt)
- New external dependency (new library, new service, new infrastructure)
- Cluster-wide change (touches ≥2 services)
- Performance-critical hot path (>1k req/s, p99 < 50ms target)

### High-stakes examples

- Split UserService → Auth + Profile microservices
- Migrate MySQL → PostgreSQL (or any DB change)
- Implement OAuth 2.0 replacing session auth
- Change Order API to cursor-based pagination (breaking)
- Adopt Kafka for inter-service communication
- Add distributed transaction / saga pattern
- Upgrade Spring Boot major version
- Add new external integration (payment provider, KYC vendor)

## Decision aids

### Cost-of-mistake heuristic

If wrong choice in this task could:
- Break production for >1 hour → high-stakes
- Require coordinated rollback across services → high-stakes
- Block another team's work → high-stakes
- Be reverted by single commit revert → standard
- Be undone before next commit → trivial

### Time-to-impact

- Trivial: change deployable in <1 day, observable impact in <1 hour
- Standard: change deployable in <1 week, observable impact in <1 day
- High-stakes: change requires coordination, deployment in days-weeks, observable impact over weeks

## Override audit

Every user override logged in `.claude/memory/state/current-triage.json` with `user_override: true`. Reviewers should scrutinize overrides — frequent downgrades indicate process problem (deadline pressure, scope creep) and may need ADR.
