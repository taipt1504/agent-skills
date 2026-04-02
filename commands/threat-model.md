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

1. Map application architecture (controllers, services, external integrations)
2. Identify trust boundaries (user input, external APIs, database, message queues)
3. Apply STRIDE to each component:
   - **S**poofing: Can identity be faked?
   - **T**ampering: Can data be modified in transit?
   - **R**epudiation: Can actions be denied?
   - **I**nformation Disclosure: Can data leak?
   - **D**enial of Service: Can service be overwhelmed?
   - **E**levation of Privilege: Can access be escalated?
4. Generate threat matrix with risk ratings
5. Suggest mitigations for each threat

## Output

Threat model saved to `.claude/docs/security/threat-model-{date}.md`
