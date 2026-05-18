---
name: threat-model
description: Generate threat model for Spring Boot application using STRIDE methodology.
---

# /threat-model — STRIDE Threat Modeling

## Usage

```
/threat-model              # Full application threat model
/threat-model {component}  # Threat model for specific component
```

## Process

1. Map architecture (controllers, services, external integrations)
2. Identify trust boundaries (user input, external APIs, DB, message queues)
3. Apply STRIDE per component:
   - **S**poofing: identity faked?
   - **T**ampering: data modified in transit?
   - **R**epudiation: actions denied?
   - **I**nformation Disclosure: data leaks?
   - **D**enial of Service: service overwhelmed?
   - **E**levation of Privilege: access escalated?
4. Threat matrix with risk ratings
5. Mitigations per threat

## Output

Saved to `.claude/docs/security/threat-model-{date}.md`
