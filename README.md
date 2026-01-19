# Agent Skills

Skill management system for Claude Code CLI.

## Quick Links

- [GUIDE.md](./GUIDE_EN.md) - Detailed usage guide for skills
- [SYSTEM_PROMPT.md](./SYSTEM_PROMPT.md) - System prompt for Skill Creator Agent

## Structure

```
agent-skills/
├── SYSTEM_PROMPT.md              # System prompt for Skill Creator Agent
├── GUIDE.md                      # Usage guide for skills (Vietnamese)
├── GUIDE_EN.md                   # Usage guide for skills (English)
├── skills/                       # Created skills
│   ├── postgres-java-reactive-pro/
│   │   ├── SKILL.md
│   │   ├── SKILL_EN.md
│   │   ├── references/
│   │   └── scripts/
│   ├── git-pro/
│   │   ├── SKILL.md
│   │   ├── SKILL_EN.md
│   │   ├── references/
│   │   └── scripts/
│   └── workflow-agents/
│       ├── SKILL.md
│       ├── SKILL_EN.md
│       ├── references/
│       ├── scripts/
│       └── templates/
├── templates/
│   ├── SKILL.md            # Simple skill template
│   └── advanced-skill/     # Advanced skill template with refs & scripts
└── README.md
```

## Available Skills

| Skill                                                              | Description                                   | Command              |
| ------------------------------------------------------------------ | --------------------------------------------- | -------------------- |
| [postgres-java-reactive-pro](./skills/postgres-java-reactive-pro/) | High-performance PostgreSQL with R2DBC        | `/postgres-reactive` |
| [git-pro](./skills/git-pro/)                                       | Advanced Git with intelligent commit messages | `/git-pro`           |
| [workflow-agents](./skills/workflow-agents/)                       | Multi-agent workflow orchestration            | `/workflow-agents`   |
| [java-spring-reactive-expert](./skills/java-spring-reactive-expert/) | Expert guidance for reactive Java with Spring WebFlux | `/reactive-java`     |
| [message-queue-java-expert](./skills/message-queue-java-expert/)     | Expert guidance for Kafka, RabbitMQ, and NATS in Java | `/mq-java`           |

## Usage

### Create a Simple Skill

1. Copy `templates/SKILL.md` to `skills/`
2. Rename and fill in the content

### Create an Advanced Skill (with references and scripts)

1. Copy folder `templates/advanced-skill/` to `skills/`
2. Rename folder and update content:
   - `SKILL.md` - Main file
   - `references/` - Reference documentation
   - `scripts/` - Support scripts

### Using Skill Creator Agent

Load `SYSTEM_PROMPT.md` as a system prompt for Claude to use the AI assistant for creating skills.

## Skill Components

| Component     | Description                        | Required |
| ------------- | ---------------------------------- | -------- |
| `SKILL.md`    | Main file containing instructions  | Yes      |
| `references/` | API docs, examples, external links | No       |
| `scripts/`    | Setup, helpers, validators         | No       |

## Skill Format

```yaml
---
name: skill-name
description: Short description
triggers:
  - keyword
  - /command
tools:
  - Read
  - Write
references: # Optional
  - references/api-docs.md
scripts: # Optional
  - scripts/helper.py
---
```

## Supported Tools

| Tool      | Function         |
| --------- | ---------------- |
| Read      | Read file        |
| Write     | Create file      |
| Edit      | Edit file        |
| Glob      | Find files       |
| Grep      | Find content     |
| Bash      | Shell commands   |
| WebFetch  | Fetch web        |
| WebSearch | Web search       |
| Task      | Spawn sub-agents |

## Documentation

See [GUIDE_EN.md](./GUIDE_EN.md) for details on:

- How to use each skill
- Scripts and commands
- Quick reference and examples
- Anti-patterns to avoid
