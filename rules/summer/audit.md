---
name: summer-audit
description: SUMMER-SPECIFIC. Caller-aware audit pattern — single RequestContextService per service implementing Summer CallerAware. Loaded ONLY when project uses io.f8a.summer.
globs: "*.java"
applicability:
  always: false
  requires_summer: true
  triggers:
    project_profile: ["summer:true"]
    files_match: ["**/*Handler.java", "**/*Service.java", "**/*Consumer.java", "**/*Saga.java", "**/*Entity.java"]
    code_patterns: ["CallerAware", "RequestContextService", "ReactiveSecurityContextHolder", "@Caller", "createdBy", "updatedBy", "approvedBy"]
    task_keywords: ["audit", "caller context", "created_by", "audit trail", "Member", "authenticated user"]
    related_rules:
      - rules/java/security.md
      - rules/java/observability.md
relevance_assessment: |
  HIGH 90%+: Summer project (verified io.f8a.summer in build.gradle) AND code touches audit fields or CallerAware
  MEDIUM 40-79%: Summer project, handler/consumer modification (audit context propagation)
  LOW 1-39%: Summer project, tangential touch
  ZERO: project does NOT use Summer (verify: grep io.f8a.summer build.gradle = 0 results) — this rule does not apply
---

# Caller-Aware Audit Pattern (HARD BLOCK)

Each service: ONE `RequestContextService` bean implementing Summer `CallerAware`. Handlers / services / sagas / Kafka consumers inject this bean — NEVER call `ReactiveSecurityContextHolder` directly.

## Rule 1 — Single RequestContextService per service

```java
package io.f8a.<service>.security;

import io.f8a.summer.core.security.authentication.CallerAware;
import io.f8a.summer.core.security.authentication.IntoMember;
import io.f8a.summer.core.security.authentication.Member;
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/**
 * Single caller resolution bean. Implements Summer {@link CallerAware} contract.
 * Audit fields ({@code created_by}, {@code updated_by}, {@code approved_by}) MUST source
 * from {@link Member#getUsername()}.
 */
@Component
public class RequestContextService implements CallerAware {
    @Override
    public Mono<Member> getCurrentMember() {
        return ReactiveSecurityContextHolder.getContext()
            .map(ctx -> IntoMember.from(ctx.getAuthentication()));
    }
}
```

## Rule 2 — Audit fields source

| Field | Source | Anti-source |
|---|---|---|
| `created_by` | `requestContextService.getCurrentMember().map(Member::getUsername)` | hard-coded string, `null`, `"system"` (unless verified system flow) |
| `updated_by` | same | same |
| `approved_by` | same (4-eyes principle: must differ from `created_by`) | same |
| `deleted_by` | same (soft delete) | same |

## Rule 3 — Anti-patterns

- ❌ `ReactiveSecurityContextHolder.getContext()` inline in handler / service / consumer
- ❌ `@AuthenticationPrincipal` parameter on handler when audit fields need to be set in service layer
- ❌ Passing username through method parameters (security boundary leak)
- ❌ Reading from MDC for audit (MDC is logging-only, no authn semantics)
- ❌ Static / utility class holding auth state

## Rule 4 — Kafka consumer audit context

Consumer messages cross authn boundary (no session) — use event metadata:

```java
// In event payload
public record OrderCreatedEvent(
    String orderId,
    String createdBy,    // populated from publisher's CallerAware
    Instant occurredAt
) {}

// Consumer side
@KafkaListener(...)
public Mono<Void> handle(OrderCreatedEvent event) {
    return downstreamService.process(event.orderId(), event.createdBy()); // propagate
}
```

NEVER fabricate `current_user` in consumer — use event's audit fields.

## Rule 5 — System flows

For system-initiated work (cron, scheduled task):
- Use dedicated system service account (e.g., `"system:order-cleanup"`)
- Tag audit field with prefix to distinguish from user actions
- Document in ADR: which system accounts exist and why

## Related

- `skills/summer-security` — Summer CallerAware contract
- `skills/summer-data` — audit columns in JPA / R2DBC entities
- `rules/java/security.md` — broader security boundary rules
- `rules/common/lanes.md` — high-stakes lane includes audit field changes
