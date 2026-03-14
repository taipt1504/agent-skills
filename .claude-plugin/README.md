# agent-skills — Claude Code Plugin

A battle-tested Claude Code plugin purpose-built for **Java/Spring WebFlux** reactive microservices development.

## What It Provides

- **Specialized Agents** — Purpose-built agents for hexagonal architecture, reactive patterns, TDD, gRPC, Kafka, and more
- **Skills** — Deep knowledge modules for Spring WebFlux, R2DBC, Redis caching, PostgreSQL optimization, and production patterns
- **Hooks** — Automated compile checks, debug statement detection, Java formatting, session lifecycle management
- **Commands** — Slash commands for common Java/Spring workflows (`/tdd`, `/refactor`, `/review`, etc.)
- **Rules** — Enforced coding standards for reactive microservices, hexagonal architecture, and clean code
- **Templates** — Starter templates for services, controllers, repositories, tests, and configuration

## Installation

### Via Claude Code Marketplace

```bash
claude plugin install agent-skills
```

### Via Git

```bash
cd ~/.claude/plugins
git clone https://github.com/taipt1504/agent-skills.git
```

### Via npm

```bash
npm install -g agent-skills
```

## Key Features

| Feature | Description |
|---------|-------------|
| **Hexagonal Architecture** | Enforces ports & adapters pattern across all generated code |
| **Reactive-First** | All patterns use Spring WebFlux (`Mono`/`Flux`), never blocking APIs |
| **TDD Workflow** | Red-green-refactor cycle with `StepVerifier` for reactive testing |
| **Compile Guard** | Pre-tool hook catches compilation errors before they propagate |
| **Debug Cleanup** | Blocks accidental `System.out.println` and debug statements from reaching commits |
| **Auto-Format** | Post-edit hook ensures consistent Java formatting |
| **Session Context** | Preserves architectural decisions and learnings across compactions |

## Stack Coverage

Java 17+ · Spring Boot 3.x · Spring WebFlux · R2DBC · gRPC · Kafka · RabbitMQ · Redis · PostgreSQL · Docker · Testcontainers

## License

MIT — built by [TaiPT](https://github.com/taipt1504)
