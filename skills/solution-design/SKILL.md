---
name: solution-design
description: >
  Create Solution Design and Service Design documents for system architecture.
  Use when asked to design a system, write architecture docs, create solution design,
  service design, or technical design documents. Covers: high-level architecture,
  use cases, user journeys, sequence diagrams, database design, API design, NFRs,
  deployment strategy. Produces two complementary documents: (1) Solution Design —
  overview of architecture, cross-service flows, and system-wide concerns,
  (2) Service Design — detailed per-service implementation specs including tech stack,
  DB schema, API endpoints, events, caching, security, and testing.
---

# Solution Design Skill

## Document Structure

A complete system design consists of **two complementary documents**:

| Document            | Purpose                                                        | Audience                                 |
|---------------------|----------------------------------------------------------------|------------------------------------------|
| **Solution Design** | Overview — architecture, cross-service flows, system-wide NFRs | All stakeholders, new members onboarding |
| **Service Design**  | Detail — per-service implementation specs for developers       | Dev team implementing the service        |

```
Solution Design (overview)
├── → Service Design: Service A (detail)
├── → Service Design: Service B (detail)
└── → ADRs (architecture decisions)
```

## Key Principles

1. **Templates are frameworks, not rigid forms.** Adapt sections based on the actual system — add what's needed, remove
   what's irrelevant. Not every section is mandatory.
2. **Solution Design links to Service Design** for detailed flows, DB, APIs. Don't duplicate.
3. **Service Design links back to Solution Design** for big-picture context.
4. **Use Mermaid diagrams** — version-control friendly, renders in Markdown.
5. **Evidence over opinion** — include benchmarks, data, rationale for decisions.

## Workflow

### Step 1: Gather Requirements

Understand before designing:

- What problem is being solved?
- What are the key use cases?
- What are the NFRs (performance, scale, security)?
- What existing systems need to integrate?

### Step 2: Solution Design

Read the template: [references/template-solution-design.md](references/template-solution-design.md)

Write the Solution Design covering:

- Executive summary
- Use cases overview (high-level, link to Service Design for detail)
- User journeys overview
- High-level architecture (C4 Level 1 & 2)
- Service overview table with links to each Service Design
- Communication patterns between services
- Cross-service sequence diagrams only
- NFRs, deployment topology, rollout plan
- Key architecture decisions (summary + ADR links)
- Risks & mitigations

### Step 3: Service Design (per service)

Read the template: [references/template-service-design.md](references/template-service-design.md)

Write a Service Design for each service covering:

- Tech stack with rationale
- Detailed use cases (step-by-step flows, alternative/exception flows, business rules)
- Detailed user journeys (screen-by-screen, error states)
- Internal sequence diagrams (Controller → Service → Repo → DB)
- Database design (ERD, DDL, indexes, migrations)
- API design (endpoints, request/response, validation, error codes)
- Event/message design (if applicable)
- Security, caching, error handling, resilience patterns
- Testing strategy, configuration, monitoring

### Step 4: Cross-link

- Solution Design use cases → link to Service Design sections
- Solution Design service table → link to each Service Design doc
- Service Design header → link back to Solution Design

## Adapting Templates

**Remove** sections that don't apply:

- No async events? → Skip Event/Message Design
- Simple service? → Merge sections, keep it lean
- No external integrations? → Skip integration sections

**Add** sections as needed:

- Multi-tenant? → Add tenancy design
- Real-time features? → Add WebSocket/SSE design
- Complex auth? → Expand security section

## Naming Convention

```
designs/
├── YYYY-MM-DD-{project}-solution-design.md
├── YYYY-MM-DD-{service-a}-service-design.md
├── YYYY-MM-DD-{service-b}-service-design.md
```
