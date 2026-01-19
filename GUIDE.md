# Agent Skills Guide

Comprehensive guide for using skills within the system.

---

## Table of Contents

1. [Overview](#overview)
2. [How to Use Skills](#how-to-use-skills)
3. [List of Skills](#list-of-skills)
   - [postgres-java-reactive-pro](#postgres-java-reactive-pro)
   - [git-pro](#git-pro)
   - [workflow-agents](#workflow-agents)
4. [Creating New Skills](#creating-new-skills)

---

## Overview

Skills are specialized knowledge modules that enable the AI agent to perform specific tasks efficiently. Each skill consists of:

| Component     | Description                                           |
| ------------- | ----------------------------------------------------- |
| `SKILL.md`    | Main file containing instructions and best practices  |
| `references/` | Reference documentation, API docs, and examples       |
| `scripts/`    | Support scripts (setup, validation, benchmark)        |

## How to Use Skills

### 1. Activation via Triggers

Each skill has trigger keywords. When a user mentions these keywords, the agent automatically applies the corresponding skill.

```
User: "Help me optimize r2dbc postgresql query"
Agent: [Applies skill postgres-java-reactive-pro]
```

### 2. Activation via Slash Command

Some skills support slash commands for direct activation:

```
User: "/postgres-reactive"
Agent: [Applies skill postgres-java-reactive-pro]
```

### 3. Using Scripts

Scripts within a skill can be executed independently:

```bash
# Run analysis script
python skills/postgres-java-reactive-pro/scripts/analyze-queries.py --help

# Run benchmark
./skills/postgres-java-reactive-pro/scripts/benchmark.sh --help
```

---

## List of Skills

---

### postgres-java-reactive-pro

**Expert guidance for high-performance PostgreSQL with Java Reactive using R2DBC**

#### Information

| Field         | Value                                      |
| ------------- | ------------------------------------------ |
| Name          | `postgres-java-reactive-pro`               |
| Slash Command | `/postgres-reactive`                       |
| Stack         | PostgreSQL, Java, R2DBC, Spring Data R2DBC |

#### Triggers

The skill is activated when the user mentions:

- `r2dbc postgresql`
- `reactive postgres java`
- `spring data r2dbc`
- `high performance reactive database`

#### Use Cases

| Scenario                  | How the Skill Helps                                           |
| ------------------------- | ------------------------------------------------------------- |
| Repository layer design   | Guidance on patterns for ReactiveCrudRepository, custom queries |
| Connection pool optim     | Configuring pool size, timeouts, validation                   |
| Batch operations          | Patterns for bulk insert, upsert, batch update                |
| Query optimization        | Keyset pagination, covering indexes, avoiding N+1             |
| Streaming large data      | Backpressure handling, limitRate, buffer                      |
| Transaction management    | Reactive transactions, savepoints                             |

#### References

| File                               | Content                                                             |
| ---------------------------------- | ------------------------------------------------------------------- |
| `references/r2dbc-config.md`       | Dependencies, connection config, pool settings, SSL, converters     |
| `references/query-patterns.md`     | Repository patterns, pagination, batch ops, joins, locking          |
| `references/performance-tuning.md` | PostgreSQL config, index strategies, query optimization, monitoring |

#### Scripts

##### analyze-queries.py

Analyzes slow queries from PostgreSQL logs or `pg_stat_statements`.

```bash
# Analyze log file
python scripts/analyze-queries.py --log /var/log/postgresql/postgresql.log

# With custom threshold (default 100ms)
python scripts/analyze-queries.py --log postgresql.log --threshold 50

# Get stats from pg_stat_statements
python scripts/analyze-queries.py --stats --host localhost --database mydb --user postgres

# View top 30 slow queries
python scripts/analyze-queries.py --log postgresql.log --top 30
```

**Output example:**

```
Found 156 slow queries
+--------+----------+----------+------------+--------------------------------------------------+
|  Count |  Avg(ms) |  Max(ms) |  Total(ms) | Query                                            |
+--------+----------+----------+------------+--------------------------------------------------+
|     45 |   250.3  |   892.1  |   11263.5  | SELECT * FROM orders WHERE user_id = ?...        |
|     32 |   180.2  |   445.6  |    5766.4  | SELECT * FROM users WHERE id = ANY(?)...         |
+--------+----------+----------+------------+--------------------------------------------------+

Recommendations:
- Query: SELECT * FROM orders WHERE user_id = ?
  - Consider selecting only needed columns instead of SELECT *
  - Check EXPLAIN ANALYZE for this query
```

##### benchmark.sh

Benchmarks connection pool with different pool sizes.

```bash
# Run with defaults
./scripts/benchmark.sh

# Custom configuration
./scripts/benchmark.sh \
  --url "r2dbc:postgresql://localhost:5432/mydb" \
  --user postgres \
  --password secret \
  --iterations 5000 \
  --concurrency 100 \
  --pool-sizes "10 25 50 75 100"
```

**Output example:**

```
==========================================
R2DBC Connection Pool Benchmark
==========================================

Testing pool size: 10
  Throughput: 2340 queries/sec

Testing pool size: 25
  Throughput: 4521 queries/sec

Testing pool size: 50
  Throughput: 5892 queries/sec

==========================================
Summary
==========================================

Pool Size    Total (ms)      Avg (ms)        RPS
------------------------------------------------------------
10           427.35          0.427           2340
25           221.12          0.221           4521
50           169.73          0.170           5892

Recommendation: Choose pool size with best RPS that doesn't exhaust database connections.
```

#### Quick Reference

##### Connection Pool Config

```java
ConnectionPoolConfiguration.builder()
    .connectionFactory(connectionFactory)
    .initialSize(10)
    .maxSize(50)
    .maxIdleTime(Duration.ofMinutes(30))
    .maxAcquireTime(Duration.ofSeconds(5))
    .validationQuery("SELECT 1")
    .build();
```

##### Keyset Pagination

```java
public Flux<User> getUsersAfter(Long lastId, int size) {
    return databaseClient.sql(
        "SELECT * FROM users WHERE id > :lastId ORDER BY id LIMIT :size")
        .bind("lastId", lastId)
        .bind("size", size)
        .map(this::mapToUser)
        .all();
}
```

##### Batch Insert

```java
public Mono<Void> batchInsert(List<User> users) {
    return Flux.fromIterable(users)
        .buffer(1000)
        .flatMap(this::insertBatch, 4)
        .then();
}
```

##### Backpressure Handling

```java
public Flux<User> streamUsers() {
    return userRepository.findAll()
        .limitRate(100);
}
```

#### Anti-patterns to Avoid

| Anti-pattern                    | Problem                | Solution                   |
| ------------------------------- | ---------------------- | -------------------------- |
| `.block()` in reactive chain    | Blocks event loop      | Keep chain fully reactive  |
| `SELECT *`                      | Over-fetching          | Select only needed columns |
| Offset pagination               | Slow with large offsets| Use keyset pagination      |
| N+1 queries                     | Multiple round trips   | Use JOINs or batch fetch   |
| Unbounded queries               | Memory exhaustion      | Always use LIMIT           |

#### Production Checklist

```
[ ] Connection pool sized correctly
[ ] Prepared statement cache enabled
[ ] All queries have proper indexes
[ ] No N+1 queries
[ ] Large result sets use streaming/pagination
[ ] Transactions have proper timeouts
[ ] Metrics and logging configured
[ ] Slow query threshold set
[ ] Health check endpoint for database
[ ] Graceful shutdown handling
```

---

### git-pro

**Advanced Git source control with intelligent commit message generation**

#### Information

| Field         | Value              |
| ------------- | ------------------ |
| Name          | `git-pro`          |
| Slash Command | `/git-pro`         |
| Stack         | Git, Shell, Python |

#### Triggers

The skill is activated when the user mentions:

- `git advanced`
- `git workflow`
- `commit message`
- `source control`
- `git analyze`

#### Use Cases

| Scenario                | How the Skill Helps                                        |
| ----------------------- | ---------------------------------------------------------- |
| Repo status analysis    | Comprehensive analysis of working tree, branches, remotes  |
| Generate commit message | Automatically generate messages following Conventional Commits |
| Branch management       | Patterns for branching, merging, rebasing                  |
| History analysis        | Search commits, blame, bisect                              |
| Conflict resolution     | Strategies and commands for merge conflicts                |
| Repository cleanup      | Prune, gc, stale branches                                  |

#### References

| File                               | Content                                       |
| ---------------------------------- | --------------------------------------------- |
| `references/commands.md`           | Full Git command reference with examples      |
| `references/workflows.md`          | GitFlow, GitHub Flow, Trunk-Based Development |
| `references/commit-conventions.md` | Conventional Commits specification            |

#### Scripts

##### analyze-repo.sh

Comprehensive repository status analysis.

```bash
# Full analysis
./scripts/analyze-repo.sh

# Status only
./scripts/analyze-repo.sh --status

# Staged changes analysis
./scripts/analyze-repo.sh --staged

# Branch analysis
./scripts/analyze-repo.sh --branches

# History analysis
./scripts/analyze-repo.sh --history

# JSON output
./scripts/analyze-repo.sh --json
```

**Output example:**

```
════════════════════════════════════════════════════════════
  REPOSITORY STATUS
════════════════════════════════════════════════════════════

Repository:  my-project
Branch:      feature/user-auth
Upstream:    origin/feature/user-auth
Ahead:       2 commits
Behind:      0 commits

── Working Tree ──
Staged:      3 files
Unstaged:    1 files
Untracked:   2 files

── Staged Files ──
  [+] src/auth/login.ts
  [~] src/api/users.ts
  [~] package.json

── Detected Change Type ──
  ✓ New files added (possible feat)
  ? Small change (possible fix or refactor)
```

##### generate-commit-msg.py

Generates optimal commit messages from staged changes.

```bash
# Generate message
python scripts/generate-commit-msg.py

# Analyze only (do not generate)
python scripts/generate-commit-msg.py --analyze

# Force specific type
python scripts/generate-commit-msg.py --type feat

# Force specific scope
python scripts/generate-commit-msg.py --scope auth

# Interactive mode
python scripts/generate-commit-msg.py --interactive

# Subject only (no body)
python scripts/generate-commit-msg.py --no-body
```

**Output example:**

```
════════════════════════════════════════════════════════════
STAGED CHANGES ANALYSIS
════════════════════════════════════════════════════════════

Files Added:    1
Files Modified: 2
Files Deleted:  0
Files Renamed:  0

Insertions: +45
Deletions:  -12

File Types:
  .ts: 2
  .json: 1

Directories: src/auth, src/api

Detected Type: feat
Detected Scope: auth

════════════════════════════════════════════════════════════
GENERATED COMMIT MESSAGE
════════════════════════════════════════════════════════════

feat(auth): add login functionality

Added:
- src/auth/login.ts

Modified:
- src/api/users.ts
- package.json

════════════════════════════════════════════════════════════

To use this message:
  git commit -m "feat(auth): add login functionality"
```

#### Quick Reference

##### Commit Message Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

##### Commit Types

| Type       | Description      |
| ---------- | ---------------- |
| `feat`     | New feature      |
| `fix`      | Bug fix          |
| `docs`     | Documentation    |
| `style`    | Formatting       |
| `refactor` | Code restructure |
| `perf`     | Performance      |
| `test`     | Tests            |
| `chore`    | Other            |

##### Useful Commands

```bash
# Status with branch info
git status -sb

# Log with graph
git log --oneline --graph -20

# Stash with message
git stash push -m "WIP: feature"

# Interactive rebase
git rebase -i HEAD~5

# Cherry-pick
git cherry-pick abc123

# Reset soft (keep staged)
git reset --soft HEAD~1
```

##### History Search

```bash
# Find commits by message
git log --grep="keyword" --oneline

# Find commits by code
git log -S "function_name" --oneline

# Blame specific lines
git blame -L 10,20 file.ts
```

#### Anti-patterns to Avoid

| Anti-pattern              | Problem                    | Solution                    |
| ------------------------- | -------------------------- | --------------------------- |
| Commit directly to main   | Risk, no review            | Use feature branches        |
| Force push shared branch  | Overwrites others' work    | Use `--force-with-lease`    |
| Vague commit messages     | Hard to understand history | Follow Conventional Commits |
| Large commits             | Hard to review, revert     | Atomic commits              |
| Commit secrets            | Security risk              | Use .gitignore, git-secrets |

#### Pre-Commit Checklist

```
[ ] Review all changes (git diff --cached)
[ ] No unnecessary files
[ ] No sensitive data
[ ] Commit message follows conventions
[ ] Tests pass
[ ] Code formatted
```

#### Pre-Push Checklist

```
[ ] Pull/rebase latest changes
[ ] Resolve conflicts
[ ] Run tests locally
[ ] Review commit history
[ ] Correct branch
```

---

### workflow-agents

**Design and orchestrate multi-agent workflows for building products with Claude Agent SDK**

#### Information

| Field         | Value                                |
| ------------- | ------------------------------------ |
| Name          | `workflow-agents`                    |
| Slash Command | `/workflow-agents`                   |
| Stack         | Claude Agent SDK, Python, TypeScript |

#### Triggers

The skill is activated when the user mentions:

- `workflow agent`
- `multi-agent`
- `agent orchestration`
- `agent hierarchy`
- `claude agent sdk`

#### Use Cases

| Scenario                | How the Skill Helps                                                   |
| ----------------------- | --------------------------------------------------------------------- |
| Design agent hierarchy  | Patterns for agent specialization, tool restrictions, model selection |
| Orchestration patterns  | Sequential, Parallel, Conditional, Iterative, Supervisor patterns     |
| Agent definitions       | Templates for code-reviewer, bug-fixer, architect, test-runner        |
| SDK integration         | Python/TypeScript SDK usage, programmatic control                     |
| Permission management   | Tool restrictions, permission modes, security best practices          |
| Workflow automation     | Event-driven pipelines, saga patterns, map-reduce                     |

#### References

| File                                | Content                                                     |
| ----------------------------------- | ----------------------------------------------------------- |
| `references/sdk-guide.md`           | Claude Agent SDK overview, query function, options          |
| `references/orchestration-patterns.md` | 8 orchestration patterns with implementation examples    |
| `references/agent-definitions.md`   | Example agents with complete definitions                    |

#### Scripts

##### scaffold-project.sh

Scaffolds a new agent-based project with structure and templates.

```bash
# Python project (default)
./scripts/scaffold-project.sh my-agent-product --python

# TypeScript project
./scripts/scaffold-project.sh my-agent-product --typescript

# Minimal setup
./scripts/scaffold-project.sh my-agent-product --minimal

# Help
./scripts/scaffold-project.sh --help
```

**Output structure:**

```
my-agent-product/
├── .claude/
│   ├── agents/           # Agent definitions
│   │   ├── code-reviewer.md
│   │   ├── bug-fixer.md
│   │   └── test-runner.md
│   ├── CLAUDE.md         # Project context
│   └── settings.json     # Permissions
├── src/
│   ├── agents/           # Agent code
│   │   ├── definitions.py/ts
│   │   └── orchestrator.py/ts
│   └── main.py/ts
├── tests/
├── requirements.txt / package.json
└── README.md
```

##### validate-agents.py

Validates agent configurations for correctness and best practices.

```bash
# Validate .claude/agents/ directory
python scripts/validate-agents.py

# Custom path
python scripts/validate-agents.py --path /custom/path

# Strict mode (fail on warnings)
python scripts/validate-agents.py --strict

# JSON output
python scripts/validate-agents.py --json
```

**Output example:**

```
============================================================
File: .claude/agents/code-reviewer.md
Valid: ✓
Agent: code-reviewer
Tools: Read, Glob, Grep
Model: sonnet

Issues (2):
  ℹ️  INFO: Description doesn't indicate when to use the agent
          → Include 'Use when...' or 'Use for...' in description
  ℹ️  INFO: No checklist or steps found in prompt
          → Consider adding a checklist or step-by-step process

============================================================
Summary
============================================================
Files validated: 3
Errors: 0
Warnings: 0
Info: 4

✓ All validations passed
```

#### Quick Reference

##### Agent Definition Format

```markdown
---
name: agent-name
description: When to use this agent. Use for specific tasks.
tools: Read, Glob, Grep
model: sonnet
---

You are an expert in [domain].

## Process
1. First step
2. Second step
3. Third step

## Output Format
[Define expected output structure]
```

##### Model Selection Guide

| Model  | Use For                              | Cost    |
| ------ | ------------------------------------ | ------- |
| Haiku  | Simple tasks, test running, linting  | Lowest  |
| Sonnet | Most development tasks, code review  | Medium  |
| Opus   | Architecture, complex reasoning      | Highest |

##### Tool Restriction Patterns

```markdown
# Read-only agent (reviewers, analyzers)
tools: Read, Glob, Grep

# Development agent (builders, fixers)
tools: Read, Write, Edit, Bash, Glob, Grep

# Orchestrator agent (coordinators)
tools: Read, Glob, Grep, Task
```

##### Permission Modes

| Mode              | Description                          |
| ----------------- | ------------------------------------ |
| `default`         | Prompt for each tool use             |
| `acceptEdits`     | Auto-accept file edits               |
| `bypassPermissions` | Skip all permission prompts        |
| `plan`            | Planning mode only                   |

##### Basic Orchestration

```python
from claude_agent_sdk import query, ClaudeAgentOptions

async def run_workflow():
    options = ClaudeAgentOptions(
        allowed_tools=["Read", "Write", "Task"],
        permission_mode="acceptEdits",
        agents=AGENTS,
        model="sonnet"
    )

    async for message in query(prompt="...", options=options):
        if hasattr(message, 'result'):
            print(message.result)
```

#### Orchestration Patterns

| Pattern               | Use Case                              |
| --------------------- | ------------------------------------- |
| Sequential Pipeline   | Step-by-step processes                |
| Parallel Fan-out      | Independent parallel tasks            |
| Conditional Branching | Decision-based routing                |
| Iterative Refinement  | Quality improvement loops             |
| Supervisor            | Complex coordination                  |
| Event-Driven          | Reactive automation                   |
| Map-Reduce            | Batch processing                      |
| Saga                  | Reversible operations                 |

#### Anti-patterns to Avoid

| Anti-pattern                   | Problem                  | Solution                         |
| ------------------------------ | ------------------------ | -------------------------------- |
| Write tools for reviewers      | Security risk            | Use read-only tools              |
| Opus for simple tasks          | Waste of resources       | Match model to task complexity   |
| No tool restrictions           | Agents do too much       | Least privilege principle        |
| Vague agent descriptions       | Wrong agent selection    | Clear "Use when..." guidance     |
| Missing output format          | Inconsistent results     | Define expected structure        |
| Single monolithic agent        | Hard to maintain         | Specialize by responsibility     |

#### Agent Definition Checklist

```
[ ] Name is descriptive and unique
[ ] Description includes "Use when..." guidance
[ ] Tools follow least privilege principle
[ ] Model matches task complexity
[ ] Prompt includes clear process/checklist
[ ] Output format defined
[ ] Anti-patterns documented
```

#### Workflow Design Checklist

```
[ ] Agents have clear responsibilities
[ ] Tool permissions properly restricted
[ ] Orchestration pattern matches use case
[ ] Error handling planned
[ ] Session management considered
[ ] Testing strategy defined
[ ] Permissions configured in settings.json
```

---

### java-spring-reactive-expert

**Expert guidance for high-performance reactive Java with Spring WebFlux, Project Reactor, and reactive data access patterns**

#### Information

| Field         | Value                                                                 |
| ------------- | --------------------------------------------------------------------- |
| Name          | `java-spring-reactive-expert`                                         |
| Slash Command | `/reactive-java`                                                      |
| Stack         | Java, Spring WebFlux, Project Reactor, R2DBC, MongoDB Reactive, Redis |

#### Triggers

The skill is activated when the user mentions:

- `spring webflux`
- `java reactive`
- `reactor`
- `mono flux`
- `reactive spring`

#### Use Cases

| Scenario                | How the Skill Helps                                          |
| ----------------------- | ------------------------------------------------------------ |
| REST API implementation | Patterns for Annotated Controllers and Functional Endpoints  |
| Non-blocking I/O        | Optimizing throughput for high-concurrency applications      |
| Reactive Data Access    | R2DBC, Reactive MongoDB, and Redis implementation patterns   |
| Reactive Security       | JWT, OAuth2, and method-level security in WebFlux            |
| Performance Integration | Backpressure handling, connection pooling, and optimizing GC |

#### References

| File                                 | Content                                                   |
| ------------------------------------ | --------------------------------------------------------- |
| `references/webflux-patterns.md`     | Controller patterns, WebClient, SSE, WebSocket, Error handling |
| `references/reactive-data-access.md` | R2DBC, MongoDB, Redis configuration and patterns          |
| `references/reactive-security.md`    | Security context, JWT, OAuth2, Method security            |
| `references/performance-optimization.md`| Memory management, scheduler tuning, pooling, metrics    |

#### Scripts

##### analyze-blocking-calls.py

Detects blocking calls in reactive code paths.

##### benchmark-reactive.sh

Benchmarks reactive endpoints to measure throughput and latency under load.

---

### message-queue-java-expert

**Expert guidance for implementing message queue systems in Java (Kafka, RabbitMQ, NATS)**

#### Information

| Field         | Value                                                   |
| ------------- | ------------------------------------------------------- |
| Name          | `message-queue-java-expert`                             |
| Slash Command | `/mq-java`                                              |
| Stack         | Java, Kafka, RabbitMQ, NATS, Spring Cloud Stream        |

#### Triggers

The skill is activated when the user mentions:

- `kafka java`
- `rabbitmq java`
- `nats java`
- `message queue`
- `event streaming`

#### Use Cases

| Scenario                  | How the Skill Helps                                              |
| ------------------------- | ---------------------------------------------------------------- |
| Event-Driven Architecture | Designing reliable event streams and messaging patterns          |
| Reliable Delivery         | Implementing At-Least-Once, Exactly-Once, and transaction patterns |
| High Throughput           | Tuning batch sizes, compression, and parallelism for performance |
| Consumer Scaling          | Configuring consumer groups, partitions, and concurrency         |
| Error Handling            | Dead Letter Queues (DLQ), retry strategies, and circuit breakers |

#### References

| File                            | Content                                                     |
| ------------------------------- | ----------------------------------------------------------- |
| `references/kafka-patterns.md`  | Producer/Consumer patterns, transactions, tuning for Kafka  |
| `references/rabbitmq-patterns.md`| Exchanges, queues, reliability, and RPC patterns for RabbitMQ |
| `references/nats-patterns.md`   | Core NATS and JetStream patterns for high-performance messaging |

#### Scripts

##### analyze-consumer-lag.py

Monitors and analyzes consumer lag for Kafka/RabbitMQ.

##### benchmark-throughput.sh

Measures message throughput and latency for different broker configurations.

---

## Creating New Skills

### Using Templates

```bash
# Simple skill
cp templates/SKILL.md skills/SKILL.md

# Complex skill
cp -r templates/advanced-skill skills/my-new-skill
```

### Skill Structure

```
skills/my-new-skill/
├── SKILL.md              # Required
├── references/           # Optional
│   ├── api-docs.md
│   └── examples.md
└── scripts/              # Optional
    ├── setup.sh
    └── helper.py
```

### Frontmatter Format

```yaml
---
name: my-new-skill
description: Short description of the skill
triggers:
