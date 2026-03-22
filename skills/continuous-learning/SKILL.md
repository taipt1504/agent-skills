---
name: continuous-learning
description: Instinct-based learning system that observes sessions via hooks, creates atomic instincts with confidence scoring, and evolves them into skills/commands/agents.
version: 2.0.0
triggers:
  - /meta learn
  - /meta evolve
  - /meta instinct
  - pattern extraction
---

> **Status: EXPERIMENTAL** — The observation hook (`observe.sh`) is not yet automated in hooks.json. This skill requires manual setup. The instinct pipeline is functional but not triggered automatically.

# Continuous Learning — Instinct-Based Architecture

Turns Claude Code sessions into reusable knowledge through atomic "instincts" — small learned behaviors with confidence scoring.

## The Instinct Model

An instinct is a small learned behavior:

```yaml
---
id: prefer-functional-style
trigger: "when writing new functions"
confidence: 0.7
domain: "code-style"
source: "session-observation"
---
# Prefer Functional Style
## Action
Use functional patterns over classes when appropriate.
## Evidence
- Observed 5 instances of functional pattern preference
- User corrected class-based approach to functional on 2025-01-15
```

**Properties:** Atomic (one trigger, one action), confidence-weighted (0.3-0.9), domain-tagged, evidence-backed.

## How It Works

```
Session Activity → Hooks capture prompts + tool use (100% reliable)
      ↓
observations.jsonl → Observer agent (background, Haiku)
      ↓
PATTERN DETECTION (user corrections, error resolutions, repeated workflows)
      ↓
instincts/personal/ (confidence-scored .md files)
      ↓
/meta evolve clusters → evolved/ (commands, skills, agents)
```

## Commands

| Command                   | Description                                    |
|---------------------------|------------------------------------------------|
| `/meta instinct status`        | Show all learned instincts with confidence     |
| `/meta evolve`                 | Cluster related instincts into skills/commands |
| `/meta instinct export`        | Export instincts for sharing                   |
| `/meta instinct import <file>` | Import instincts from others                   |

## Confidence Scoring

| Score | Meaning      | Behavior                      |
|-------|--------------|-------------------------------|
| 0.3   | Tentative    | Suggested but not enforced    |
| 0.5   | Moderate     | Applied when relevant         |
| 0.7   | Strong       | Auto-approved for application |
| 0.9   | Near-certain | Core behavior                 |

**Increases:** repeated observation, user doesn't correct, corroborating sources.
**Decreases:** user corrects, pattern not seen for extended periods, contradicting evidence.

## Setup

1. Add PreToolUse/PostToolUse hooks to `~/.claude/settings.json` pointing to `hooks/observe.sh`.
2. Initialize: `mkdir -p ~/.claude/homunculus/{instincts/{personal,inherited},evolved/{agents,skills,commands}}`
3. Optional: run background observer via `agents/start-observer.sh`.

Configure via `config.json` (observation store, confidence thresholds, observer model, evolution settings).

## File Structure

```
~/.claude/homunculus/
├── observations.jsonl      # Session observations
├── instincts/
│   ├── personal/           # Auto-learned instincts
│   └── inherited/          # Imported from others
└── evolved/                # Generated agents, skills, commands
```

Observations stay local. Only instincts (patterns) can be exported — no code or conversation content is shared.
