# Agent Design Guide

> Best practices for creating effective agents, extracted from ECC's 18 agents.

---

## Agent File Format

Agents are single Markdown files with YAML frontmatter in the `agents/` directory.

```
agents/
├── planner.md
├── code-reviewer.md
├── architect.md
├── tdd-guide.md
├── security-reviewer.md
├── build-error-resolver.md
└── ...
```

## YAML Frontmatter

### Required Fields

```yaml
---
name: agent-name           # lowercase, hyphenated
description: >-            # CRITICAL: determines auto-invocation
  Use PROACTIVELY when planning complex features.
  Analyzes requirements and produces phased implementation plans.
tools: ["Read", "Grep", "Glob"]  # Only what's needed
model: sonnet              # haiku | sonnet | opus
---
```

### Optional Fields

```yaml
color: orange              # UI display color
```

## Model Selection Guide

| Model | When to Use | Example Agents |
|-------|-------------|----------------|
| `haiku` | Simple, fast, background tasks | Formatting, simple checks |
| `sonnet` | Coding, review, most agents | code-reviewer, tdd-guide, build-error-resolver |
| `opus` | Complex reasoning, architecture | architect, planner, chief-of-staff |

**Key principle:** Start with `sonnet`. Upgrade to `opus` only for agents that need deep reasoning without writing code. Use `haiku` for background/async tasks.

## Tool Scoping

**Only list tools the agent actually needs:**

| Agent Type | Tools | Rationale |
|------------|-------|-----------|
| Read-only analysts | `["Read", "Grep", "Glob"]` | Cannot modify code, only analyze |
| Code modifiers | `["Read", "Write", "Edit", "Bash", "Grep", "Glob"]` | Full write access |
| Build fixers | `["Read", "Edit", "Bash", "Grep", "Glob"]` | Edit existing, don't create new |
| Test runners | `["Read", "Bash", "Grep", "Glob"]` | Run tests, read results |

**Read-only agents (architect, planner) use only `Read, Grep, Glob`** — they cannot accidentally modify code during analysis.

## Agent Content Structure

### 1. Role Statement

```markdown
You are a **code review specialist** focused on code quality, maintainability, and security.
```

### 2. Your Role Section

```markdown
## Your Role

**What you DO:**
- Review code changes for quality, correctness, and security
- Classify findings by severity (CRITICAL / HIGH / MEDIUM / LOW)
- Suggest specific fixes with code examples

**What you DO NOT do:**
- Make architectural decisions (delegate to `architect` agent)
- Write new features (delegate to user/developer)
- Auto-fix issues without review
```

**Critical:** Explicitly stating "What you DO NOT do" prevents scope creep.

### 3. Workflow

```markdown
## Workflow

1. **Understand** — Read the changed files, understand the context
2. **Analyze** — Check against coding standards, security rules, test coverage
3. **Classify** — Rate each finding by severity
4. **Report** — Present findings in structured format
5. **Suggest** — Provide specific fix recommendations
```

### 4. Domain-Specific Content

Tables, checklists, or decision trees relevant to the agent's domain:

```markdown
## Severity Classification

| Severity | Criteria | Action |
|----------|----------|--------|
| CRITICAL | Security vulnerability, data loss risk | Block merge |
| HIGH | Bug, performance issue, missing validation | Must fix before merge |
| MEDIUM | Code smell, missing test, suboptimal pattern | Should fix |
| LOW | Style, naming, minor improvement | Nice to have |
```

### 5. Output Format

```markdown
## Output Format

Present findings as:

### Summary
| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 2 |

### Findings

#### [HIGH] Missing input validation in UserController
**File:** `src/main/.../UserController.java:45`
**Issue:** Request body not validated
**Fix:**
```java
public Mono<ResponseEntity<UserResponse>> createUser(
    @Valid @RequestBody CreateUserRequest request) {
```
```

### 6. Cross-References

```markdown
## Related

- For detailed security patterns, see skill: `security-review`
- For TDD guidance, see skill: `tdd-workflow`
- Invoke via command: `/code-review`
```

### 7. Boundaries (When NOT to Use)

```markdown
## When NOT to Use

- For build/compile errors → use `build-error-resolver` agent
- For architectural decisions → use `architect` agent
- For test writing → use `tdd-guide` agent
```

## Description Field: The Trigger Mechanism

The `description` field is **the most important field** — it determines when Claude auto-invokes the agent.

### Pattern: Use "PROACTIVELY" for Auto-Invocation

```yaml
# Auto-invokes when relevant context detected
description: >-
  Use PROACTIVELY after writing code that handles user input,
  authentication, or external API calls to check for security vulnerabilities.

# Only invoked when explicitly requested
description: >-
  Analyzes build and compile errors, providing minimal-diff fixes.
  Use when Gradle build or Java compilation fails.
```

### Description Best Practices

```yaml
# BAD: Too vague
description: Reviews code

# GOOD: Specific trigger + domain
description: >-
  Reviews uncommitted code changes for quality, security, and maintainability.
  Classifies findings by severity (CRITICAL/HIGH/MEDIUM/LOW).
  Use after implementation, before commit.

# BAD: No trigger context
description: Handles database issues

# GOOD: Specific scenarios
description: >-
  Reviews PostgreSQL/MySQL schema design, query performance, JPA mappings,
  and migration safety. Use when modifying database schemas, writing complex
  queries, or adding new JPA entities.
```

## ECC Agent Examples (Annotated)

### Planner (Opus, Read-Only)
- Model: `opus` (complex reasoning for planning)
- Tools: `["Read", "Grep", "Glob"]` (read-only, no modifications)
- Content: Phased breakdown format, risk assessment, worked examples
- Length: ~150 lines

### Build Error Resolver (Sonnet, Minimal Write)
- Model: `sonnet` (coding-level, not reasoning-heavy)
- Tools: `["Read", "Edit", "Bash", "Grep", "Glob"]` (Edit, not Write — fix existing, don't create)
- Content: Priority levels, explicit DO/DON'T table, "When NOT to Use"
- Length: ~80 lines
- Key constraint: "Fixes build/type errors only with minimal diffs, no architectural edits"

### Code Reviewer (Sonnet, with Bash)
- Model: `sonnet`
- Tools: includes `Bash` (to run linters, tests)
- Content: Confidence-based filtering, severity classification, summary table format
- Length: ~120 lines

## Agent Size Guidelines

| Metric | Guideline |
|--------|-----------|
| Total lines | 50-200 (keep concise) |
| Workflow steps | 3-7 |
| Checklist items | 5-15 |
| Code examples | 1-3 (reference skills for more) |
| DO/DON'T items | 3-5 each |

**Key principle:** Agents should be action-oriented coordinators, not encyclopedias. Reference skills for detailed knowledge.
