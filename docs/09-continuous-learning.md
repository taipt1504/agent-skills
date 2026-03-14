# Continuous Learning Patterns

> How ECC implements cross-session learning and memory persistence.

---

## Two Learning Systems

ECC implements two generations of learning:

| System | Version | Mechanism | Reliability |
|--------|---------|-----------|-------------|
| `continuous-learning` | v1 | Stop hook extracts patterns to skill files | ~50-80% |
| `continuous-learning-v2` | v2.1 | Hook-based instincts with confidence scoring | ~100% |

**v2 is preferred** because hooks fire deterministically (100% of the time), while skill-based triggers are probabilistic (50-80%).

---

## V1: Session Pattern Extraction

### How it Works

```
Stop hook (session-end.js)
  ↓
evaluate-session.js (async, after long enough sessions)
  ↓
Extract reusable patterns from transcript
  ↓
Save to ~/.claude/skills/learned/*.md
```

### Learned Skill Format

```markdown
---
name: learned-pattern-name
source: session-extraction
date: 2026-03-15
---

# Pattern Name

## Problem
What situation triggers this pattern.

## Solution
How to handle it.

## Example
Code or workflow example.

## When to Use
Trigger scenarios.
```

### Trigger: `/learn` Command

Manually triggers pattern extraction from the current session:

```markdown
/learn
→ Analyze current session transcript
→ Identify reusable patterns
→ Save as learned skills
→ Report what was learned
```

---

## V2: Instinct-Based Learning

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Observation Layer                        │
│  PreToolUse hooks (*) ──── observe.sh (async, 100%)       │
│  PostToolUse hooks (*) ─── observe.sh (async, 100%)       │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│                   Analysis Layer                          │
│  Background observer agent (Haiku, every ~5 min)          │
│  Analyzes observations, generates/updates instincts       │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│                   Storage Layer                           │
│                                                           │
│  Global instincts:                                        │
│    ~/.claude/homunculus/instincts/personal/                │
│    ~/.claude/homunculus/instincts/inherited/               │
│                                                           │
│  Project-scoped instincts:                                │
│    ~/.claude/homunculus/projects/{hash}/instincts/         │
└──────────────────────────────────────────────────────────┘
```

### Instinct Format

```yaml
---
id: inst_abc123
trigger: "When writing Kafka consumer configuration"
confidence: 0.7
domain: kafka
source: observation
scope: project
project_id: hash_of_git_remote_url
created: 2026-03-10
updated: 2026-03-15
observations: 5
---

## Action
Always configure `max.poll.records` and `max.poll.interval.ms` together.
Set `max.poll.interval.ms` to at least 5x the expected processing time.

## Evidence
- Session 2026-03-10: Consumer timeout due to high poll interval
- Session 2026-03-12: Same pattern, confirmed fix
- Session 2026-03-15: Applied proactively, prevented issue
```

### Confidence Scoring

| Score | Meaning | Behavior |
|-------|---------|----------|
| 0.3 | Low — newly observed | Suggest, don't auto-apply |
| 0.5 | Medium — seen multiple times | Suggest with higher priority |
| 0.7 | High — consistently observed | Auto-suggest in relevant contexts |
| 0.9 | Very high — well-established | Apply proactively |

**Confidence changes:**
- Repeated observation → +0.1 (cap at 0.9)
- User correction/rejection → -0.2
- Auto-promotion threshold: confidence >= 0.8 in 2+ projects

### Project Scoping

Project detection priority:
1. `CLAUDE_PROJECT_DIR` environment variable
2. `git remote get-url origin` → SHA-256 hash
3. `git rev-parse --show-toplevel`
4. Global fallback

**Why scoping matters:** A pattern learned in a Node.js project shouldn't auto-apply in a Java project. Project scoping prevents cross-contamination.

### Auto-Promotion

When same instinct appears in 2+ projects with avg confidence >= 0.8:
```
Project A: instinct X (confidence 0.8)
Project B: instinct X (confidence 0.9)
→ Average: 0.85, in 2+ projects
→ Promoted to: ~/.claude/homunculus/instincts/personal/
```

---

## Commands for Learning

| Command | Purpose |
|---------|---------|
| `/learn` | Extract patterns from current session |
| `/instinct-status` | Show all instincts with confidence scores |
| `/instinct-export` | Export instincts for sharing with team |
| `/instinct-import` | Import instincts from teammates |
| `/evolve` | Cluster instincts → promote to skills/commands/agents |
| `/promote` | Promote project instinct to global |

---

## Session Persistence

### Session File Format

Stored at `~/.claude/sessions/YYYY-MM-DD-{shortId}-session.tmp`:

```markdown
<!-- ECC:HEADER:START -->
## Session: 2026-03-15
Project: /Users/taiphan/Documents/Projects/lab/agent-skills
Branch: main
<!-- ECC:HEADER:END -->

<!-- ECC:SUMMARY:START -->
## Summary
- Tasks: Implemented Kafka consumer configuration
- Files modified: KafkaConfig.java, ConsumerService.java
- Tools used: 45 (Read: 12, Edit: 8, Bash: 15, Grep: 10)
- Duration: ~45 minutes

## Notes for Next Session
- Consumer group rebalancing needs testing
- DLT configuration still pending

## Context to Load
- Review KafkaConfig.java for consumer settings
- Check ConsumerService.java error handling
<!-- ECC:SUMMARY:END -->
```

### Session Lifecycle

```
SessionStart hook
  → Find most recent session file (within 7 days)
  → Read summary section
  → Output to stdout (injected into context)
  → "Welcome back! Last session: [summary]"

Stop hook (after each response)
  → session-end.js (async)
  → Parse current transcript
  → Extract tasks, files, tools, stats
  → Write/update session file
  → Use marker blocks for idempotent updates

PreCompact hook
  → Log compaction timestamp
  → Annotate session file with compaction marker
```

---

## Evolution Pipeline

```
Observations → Instincts → Clusters → Skills/Commands/Agents

/evolve command:
1. Read all instincts with confidence >= 0.7
2. Cluster by domain/trigger similarity
3. For each cluster:
   a. 3+ instincts with avg confidence >= 0.8 → Generate SKILL.md
   b. 2+ instincts that form a workflow → Generate command
   c. 5+ instincts that form a role → Generate agent
4. Present generated artifacts for user review
5. Save approved artifacts to skills/, commands/, agents/
```

---

## Applying to Our Plugin

### What We Already Have
- `continuous-learning-v2` skill
- `/learn`, `/instinct-status`, `/evolve` commands
- `evaluate-session` hook

### What We Could Improve
1. **Session persistence hooks** — load previous session context on SessionStart
2. **PreCompact hook** — save state before compaction
3. **Project scoping** — scope instincts by project, not just global
4. **Auto-promotion** — promote patterns seen in multiple projects
5. **Confidence-based behavior** — low confidence = suggest, high = auto-apply
6. **Instinct export/import** — team knowledge sharing

### Privacy Considerations
- Observations stay local (never transmitted)
- Only patterns (not raw observations) can be exported
- Project-scoped instincts don't leak to other projects
- User corrections immediately reduce confidence
