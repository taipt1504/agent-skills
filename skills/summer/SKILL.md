---
name: summer
description: >
  Guide for developing with the Summer Framework (io.f8a.summer) — a reactive
  Spring Boot library for building microservices. Use this skill whenever working
  on Java projects that use summer modules (summer-core, summer-rest, summer-data,
  summer-security, summer-keycloak, summer-test). Also trigger when: creating new
  microservices, adding handlers/controllers, configuring APISIX security, setting
  up audit logging, implementing the outbox pattern, integrating Keycloak, writing
  tests, or when you see io.f8a.summer imports in the codebase. Even if the user
  just mentions "summer framework" or you see f8a.common/f8a.security/f8a.outbox
  properties, use this skill.
---

# Summer Framework Skill

Reactive Spring Boot 3.x library (Java 21+) on WebFlux + Reactor Netty.
**Group ID:** `io.f8a.summer` | **BOM:** `summer-platform`

## Step 1: Detect Version

Before doing anything, determine which version the user is on:

1. Read `gradle.properties` — look for `version=X.Y.Z`
2. Check `build.gradle` for `io.f8a.summer:summer-platform` dependency version
3. Look for version-specific imports/patterns in existing code:

- `SummerGlobalExceptionHandler` → 0.2.1+
- `RateLimiterService` → 0.2.2+
- `sync-role.enabled` (not `sync-role.enable`) → 0.2.3+
- `GroupRoleResolver` or `group-role-authorization` → 0.2.4+

4. If still unclear — ask the user before proceeding. Never guess.

## Step 2: Load the Right References

| Version | Read this file         | Key additions                                    |
|---------|------------------------|--------------------------------------------------|
| 0.2.1   | `references/v0.2.1.md` | Breaking: tracing, security modules, audit API   |
| 0.2.2   | `references/v0.2.2.md` | Rate limiting module                             |
| 0.2.3   | `references/v0.2.3.md` | Keycloak exception expansion, role sync defaults |
| 0.2.4   | `references/v0.2.4.md` | Group-role auth, keycloak API expansion          |

**Always also read** `references/common.md` for shared patterns across all versions.

For detailed API reference, read: `references/api_reference.md`
For usage examples and best practices, read: `references/usage_guide.md`

## Step 3: Follow Version-Specific Instructions

Proceed using ONLY the loaded references. Do not mix instructions across versions.
If a user is migrating, read BOTH the source and target version files.
