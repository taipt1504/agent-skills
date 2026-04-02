# Instinct Pipeline — Technical Reference

## Overview

The instinct pipeline implements principle H7 (Compound Every Cycle) from the harness engineering framework. Every session produces learnings that accumulate into skills. Instincts are the atomic unit of this compounding — micro-patterns extracted from developer sessions that grow in confidence through repeated application, cluster into related groups, and eventually evolve into full skills or agent behaviors.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Session    │────>│   Extract    │────>│  Instincts  │
│  (patterns)  │     │  (meta learn)│     │  (personal/) │
└─────────────┘     └──────────────┘     └──────┬──────┘
                                                 │
                    ┌──────────────┐              │
                    │   Evolve     │<─────────────┘
                    │  (cluster)   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              v            v            v
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │  Skill   │ │  Agent   │ │ Promoted │
        │ (learned)│ │(suggested)│ │ (global) │
        └──────────┘ └──────────┘ └──────────┘
```

## Directory Structure

```
.claude/instincts/
├── personal/              # Project-scope instincts
│   ├── error-handling-001.md
│   ├── api-validation-002.md
│   ├── .session-meta-*.json  # Session metadata (written by hook)
│   └── ...
├── archived/              # Pruned instincts (--archive)
└── promoted -> ~/.claude/instincts/promoted/  # Symlink to global

~/.claude/instincts/
└── promoted/              # Cross-project instincts
    ├── always-use-records-for-dtos.md
    └── ...

.claude/skills/learned/    # Skills generated from instinct clusters
└── error-handling-patterns/
    └── SKILL.md
```

## Instinct File Format

Each instinct is a standalone Markdown file with YAML frontmatter:

```yaml
---
trigger: "normalized trigger phrase"
action: "what to do when triggered"
confidence: 0.5
source: "session"
createdAt: "2026-04-01T10:00:00Z"
lastApplied: null
applyCount: 0
project: "my-service"
---

Detailed explanation of the pattern, when to apply it, and why.
Include specific examples from the originating session.
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `trigger` | string | Normalized phrase that activates this instinct |
| `action` | string | Concise description of what to do |
| `confidence` | float | 0.0-1.0, starts at 0.5 for new instincts |
| `source` | enum | `session`, `user`, `promoted` |
| `createdAt` | ISO 8601 | When the instinct was first extracted |
| `lastApplied` | ISO 8601 or null | Last time this instinct was used |
| `applyCount` | int | Number of times this instinct was applied |
| `project` | string | Project name where the instinct was created |

## Extraction Rules

### What to Extract

- **User corrections**: "no, do X instead of Y" — these are the highest-signal patterns
- **Confirmed approaches**: "yes, that's correct" or accepted without pushback
- **Repeated patterns**: Same type of change done 3+ times in a session
- **Failed approaches that were replaced**: Anti-patterns specific to the project

### What NOT to Extract

- Trivial or obvious patterns (e.g., "use semicolons in Java")
- One-time fixes specific to a single bug instance
- Patterns already captured in existing skills or CLAUDE.md
- Generic programming knowledge not specific to the project context

### Trigger Normalization

Triggers are normalized to enable clustering and deduplication:

1. Lowercase all text
2. Remove articles (a, an, the)
3. Stem verbs (creating -> create, handling -> handle)
4. Remove project-specific names (service names, class names)
5. Remove filler words (just, also, basically)

**Example**: "When creating a new REST endpoint in OrderService" -> "create rest endpoint"

## Confidence Scoring

Confidence is a 0.0-1.0 score that tracks how reliable an instinct is.

### Score Changes

| Event | Change | Rationale |
|-------|--------|-----------|
| User confirms pattern | +0.1 | Explicit validation |
| Pattern applied successfully | +0.05 | Implicit validation through use |
| User corrects/rejects | -0.2 | Strong negative signal |
| Not applied for 14 days | -0.05 | Decay from disuse |
| Not applied for 30 days | Mark stale | Candidate for pruning |

### Confidence Boundaries

- **0.0**: Completely unreliable, should be pruned
- **0.3**: Fading threshold — below this is pruning candidate
- **0.5**: Default starting confidence for new instincts
- **0.8**: High confidence — candidate for skill evolution
- **0.9**: Established — single instinct can stand alone
- **1.0**: Maximum confidence cap

## Clustering Algorithm

### Similarity Metric

Instincts are clustered using Jaccard similarity on normalized trigger tokens:

```
similarity(A, B) = |tokens(A) ∩ tokens(B)| / |tokens(A) ∪ tokens(B)|
```

- **Threshold**: 0.6 (tokens overlap >= 60%)
- Instincts above the threshold are grouped into the same cluster

### Promotion Rules

| Condition | Action | Output Location |
|-----------|--------|-----------------|
| 2+ instincts, avg confidence >= 0.8 | Suggest skill | `.claude/skills/learned/` |
| 3+ instincts, avg confidence >= 0.75 | Suggest agent | Report only (manual creation) |
| 1 instinct, confidence >= 0.9 | Mark established | In-place update |
| Any, confidence < 0.3 | Mark fading | Prune candidate |
| In >= 2 projects, avg confidence >= 0.8 | Auto-promote | `~/.claude/instincts/promoted/` |

### Generated Skill Format

When `/meta evolve --generate` creates a skill from a cluster:

```yaml
---
name: "{cluster-trigger-kebab-case}"
description: >
  Auto-generated skill from {N} instincts with avg confidence {X}.
  Covers: {list of instinct triggers}
triggers:
  natural: ["{cluster trigger variations}"]
  code: ["{code patterns from instincts}"]
source: instinct-evolution
generatedAt: "ISO date"
sourceInstincts: ["{instinct file names}"]
---

# {Skill Name}

{Merged content from all instincts in the cluster}
```

## Pruning Rules

| Rule | Condition | Action |
|------|-----------|--------|
| TTL expired | `lastApplied` > 30 days ago | Remove or archive |
| Fading | `confidence` < 0.3 | Remove or archive |
| Unused | `applyCount` = 0 AND age > 14 days | Remove or archive |
| Contradicted | Newer instinct directly contradicts | Remove older |

### Archive vs Delete

- `--archive` flag moves files to `.claude/instincts/archived/` with a timestamp suffix
- Default behavior permanently deletes the instinct file
- `--dry-run` flag shows what would be affected without making changes

## Session Integration

### Session-Save Hook (session-save.sh)

The session-save hook writes metadata that `/meta learn extract` uses later:

1. Check if `.claude/instincts/personal/` directory exists
2. If present, record session metadata as `.session-meta-{timestamp}.json`:
   - `sessionEnd`: ISO timestamp of session completion
   - `branch`: Current git branch
   - `toolCalls`: Approximate count of tool invocations in session
   - `uncommittedFiles`: Count of uncommitted files at session end
   - `project`: Project directory name
3. The metadata files are consumed by `/meta learn extract` to identify sessions with high pattern density

### SubagentStart Integration

Promoted instincts from `~/.claude/instincts/promoted/` are injected into subagent context:

1. SubagentStart hook checks for promoted instinct files
2. High-confidence instincts (>= 0.8) are included as additional context rules
3. This enables cross-project pattern sharing without manual configuration

## Pipeline Commands Reference

| Command | Phase | Input | Output |
|---------|-------|-------|--------|
| `/meta learn extract` | Extract | Session conversation | Instinct files in `personal/` |
| `/meta learn status` | Monitor | Instinct files | Dashboard with counts and states |
| `/meta learn report` | Monitor | Instinct files + history | Trends and recommendations |
| `/meta evolve` | Evolve | Instinct files | Evolution report with suggestions |
| `/meta evolve --generate` | Evolve | Cluster suggestions | Skill files in `learned/` |
| `/meta evolve --promote` | Evolve | High-confidence instincts | Promoted files in global scope |
| `/meta prune` | Prune | Instinct files | Cleaned instinct directory |
| `/meta prune --dry-run` | Prune | Instinct files | Preview report (no changes) |
| `/meta prune --archive` | Prune | Stale instincts | Archived instinct files |

## Design Principles

1. **Zero-config start**: Instincts begin accumulating from the first session with no setup required beyond directory creation via `/dc-setup` or `/meta`
2. **Gradual confidence**: New instincts start neutral (0.5) and must prove themselves through repeated successful application before evolving
3. **Automatic decay**: Unused instincts fade naturally, preventing stale pattern accumulation
4. **Composability**: Individual instincts cluster into skills, which can further compose into agent behaviors
5. **Cross-project sharing**: High-confidence patterns automatically promote to global scope, benefiting all projects
6. **Reversibility**: Pruned instincts can be archived rather than deleted, and evolved skills trace back to their source instincts
