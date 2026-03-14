# agent-skills — Claude Code Plugin

A battle-tested Claude Code plugin purpose-built for **Java/Spring WebFlux** reactive microservices development.

## What It Provides

- **14 Specialized Agents** — Architecture, reactive patterns, TDD, security, performance, database, and more
- **24 Skills** — Deep knowledge modules for Spring WebFlux, JPA, Redis, PostgreSQL, Kafka, and production patterns
- **19 Commands** — Slash commands for planning, spec-driven design, verification, code review, and more
- **15 Rules** — Enforced coding standards for reactive microservices, hexagonal architecture, and clean code
- **10 Hooks** — Automated compile checks, debug statement detection, Java formatting, session lifecycle management

## Installation

### Method 1: GitHub Marketplace (Recommended)

```bash
# Register the marketplace source (one-time)
/plugin marketplace add taipt1504/agent-skills

# Install the plugin
/plugin install agent-skills
```

### Method 2: npm

```bash
npm install -g @devco/agent-skills
claude plugin install ./node_modules/@devco/agent-skills
```

### Method 3: Manual Clone (Fallback)

```bash
git clone https://github.com/taipt1504/agent-skills.git ~/.claude/plugins/agent-skills
claude plugin install ~/.claude/plugins/agent-skills
```

## Verify Installation

```bash
# Confirm the plugin is loaded
/plugin list
```

You should see `agent-skills` in the output. Start any session and run `/plan` for a non-trivial task.

## Key Features

| Feature | Description |
|---------|-------------|
| **Hexagonal Architecture** | Enforces ports & adapters pattern across all generated code |
| **Reactive-First** | All patterns use Spring WebFlux (`Mono`/`Flux`), never blocking APIs |
| **TDD Workflow** | Red-green-refactor cycle with `StepVerifier` for reactive testing |
| **Spec-Driven Design** | Behavioral contracts (inputs, outputs, errors) before implementation |
| **Compile Guard** | Pre-tool hook catches compilation errors before they propagate |
| **Debug Cleanup** | Blocks accidental `System.out.println` and debug statements |
| **Auto-Format** | Post-edit hook ensures consistent Java formatting |
| **Session Context** | Preserves architectural decisions and learnings across compactions |

## Stack Coverage

Java 17+ · Spring Boot 3.x · Spring WebFlux · Spring MVC · R2DBC · JPA/Hibernate · gRPC · Kafka · RabbitMQ · Redis · PostgreSQL · MySQL · Docker · Testcontainers

## License

MIT — built by [TaiPT](https://github.com/taipt1504)
