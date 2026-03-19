---
name: meta
description: Meta-learning commands -- extract patterns, evolve instincts into skills, get quick guidance, and create new skills from patterns.
---

# /meta -- Meta-Learning & Self-Improvement

Unified command for pattern extraction, instinct management, skill evolution, and skill creation.

## Usage

```
/meta learn              -> extract patterns from current session
/meta evolve             -> cluster instincts into skills/commands
/meta instinct           -> show instinct status (default)
/meta instinct export    -> export instincts to shareable YAML
/meta instinct import    -> import instincts from file
/meta create-skill       -> create new skill from repo patterns
```

---

## Subcommand: /meta learn

Extract reusable patterns from the current session and save them as skills.

### What to Extract

1. **Error Resolution Patterns** - What error occurred, root cause, what fixed it
2. **Debugging Techniques** - Non-obvious debugging steps, tool combinations
3. **Workarounds** - Library quirks, API limitations, version-specific fixes
4. **Project-Specific Patterns** - Codebase conventions, architecture decisions

### Process

1. Review the session for extractable patterns
2. Identify the most valuable/reusable insight
3. Draft the skill file
4. Ask user to confirm before saving
5. Save to `~/.claude/skills/learned/`

### Output Format

Create a skill file at `~/.claude/skills/learned/[pattern-name].md`:

```markdown
# [Descriptive Pattern Name]

**Extracted:** [Date]
**Context:** [Brief description of when this applies]

## Problem
[What problem this solves]

## Solution
[The pattern/technique/workaround]

## Example
[Code example if applicable]

## When to Use
[Trigger conditions]
```

### Guidelines

- Don't extract trivial fixes (typos, simple syntax errors)
- Don't extract one-time issues (specific API outages)
- Focus on patterns that will save time in future sessions
- Keep skills focused -- one pattern per skill

---

## Subcommand: /meta evolve

Analyze instincts and cluster related ones into higher-level structures (commands, skills, or agents).

### Evolution Rules

**-> Command** (user-invoked actions):
When instincts describe actions a user would explicitly request with a repeatable sequence.

**-> Skill** (auto-triggered behaviors):
When instincts describe behaviors that should happen automatically -- pattern-matching triggers, error handling, code style enforcement.

**-> Agent** (needs depth/isolation):
When instincts describe complex, multi-step processes that benefit from isolation -- debugging workflows, refactoring sequences, research tasks.

### Process

1. Read all instincts from `~/.claude/homunculus/instincts/`
2. Group instincts by domain similarity, trigger pattern overlap, action sequence
3. For each cluster of 3+ related instincts, determine evolution type
4. Generate the appropriate file
5. Save to `~/.claude/homunculus/evolved/{commands,skills,agents}/`

### Flags

- `--execute` - Actually create the evolved structures (default is preview)
- `--dry-run` - Preview without creating
- `--domain <name>` - Only evolve instincts in specified domain
- `--threshold <n>` - Minimum instincts to form cluster (default: 3)
- `--type <command|skill|agent>` - Only create specified type

### Output

```
Evolve Analysis
===============

Found 3 clusters ready for evolution:

Cluster 1: Database Migration Workflow
  Instincts: new-table-migration, update-schema, regenerate-types
  Type: Command
  Confidence: 85%

Cluster 2: Functional Code Style
  Instincts: prefer-functional, use-immutable, avoid-classes
  Type: Skill
  Confidence: 78%

Run `/meta evolve --execute` to create these files.
```

---

## Subcommand: /meta instinct

Manage learned instincts -- view status, export for sharing, or import from teammates.

### /meta instinct (status)

Show all learned instincts grouped by domain with confidence scores.

**Flags:**
- `--domain <name>` - Filter by domain
- `--low-confidence` - Show only confidence < 0.5
- `--high-confidence` - Show only confidence >= 0.7

**Process:**
1. Read instinct files from `~/.claude/homunculus/instincts/personal/`
2. Read inherited instincts from `~/.claude/homunculus/instincts/inherited/`
3. Display grouped by domain

**Output:**
```
Instinct Status
===============

Code Style (4 instincts)
  prefer-functional-style
  Trigger: when writing new functions -> Use functional patterns
  Confidence: 80%  |  Source: session-observation

Testing (2 instincts)
  test-first-workflow
  Trigger: when adding new functionality -> Write test first
  Confidence: 90%  |  Source: session-observation

Total: 9 instincts (4 personal, 5 inherited)
```

### /meta instinct export

Export instincts to a shareable YAML format.

**Flags:**
- `--domain <name>` - Export only specified domain
- `--min-confidence <n>` - Minimum confidence threshold (default: 0.3)
- `--output <file>` - Output path
- `--format <yaml|json|md>` - Output format (default: yaml)

**Privacy:** Exports include trigger patterns, actions, confidence scores. Exports do NOT include code snippets, file paths, session transcripts, or personal identifiers.

### /meta instinct import

Import instincts from teammates, Skill Creator, or community collections.

**Flags:**
- `--dry-run` - Preview without importing
- `--force` - Import even if conflicts exist
- `--merge-strategy <higher|local|import>` - How to handle duplicates
- `--min-confidence <n>` - Only import above threshold

**Merge Strategy:**
- Duplicates: higher confidence wins, merge observation counts
- Conflicts: skip by default, flag for manual resolution
- Imported instincts marked with `source: "inherited"`

---

## Subcommand: /meta create-skill

Analyze the repository's git history to extract coding patterns and generate SKILL.md files.

### Usage

```
/meta create-skill                    # Analyze current repo
/meta create-skill --commits 100      # Analyze last 100 commits
/meta create-skill --output ./skills  # Custom output directory
/meta create-skill --instincts        # Also generate instincts
```

### Analysis Steps

1. **Gather Git Data**
   ```bash
   git log --oneline -n 200 --name-only --pretty=format:"%H|%s|%ad" --date=short
   git log --oneline -n 200 --name-only | sort | uniq -c | sort -rn | head -20
   ```

2. **Detect Patterns**

   | Pattern                | Detection Method                               |
   |------------------------|------------------------------------------------|
   | Commit conventions     | Regex on commit messages (feat:, fix:, chore:) |
   | File co-changes        | Files that always change together               |
   | Workflow sequences     | Repeated file change patterns                   |
   | Architecture           | Folder structure and naming conventions          |
   | Testing patterns       | Test file locations, naming, coverage            |

3. **Generate SKILL.md**

   ```markdown
   ---
   name: {repo-name}-patterns
   description: Coding patterns extracted from {repo-name}
   version: 1.0.0
   source: local-git-analysis
   analyzed_commits: {count}
   ---

   # {Repo Name} Patterns

   ## Commit Conventions
   ## Code Architecture
   ## Workflows
   ## Testing Patterns
   ```

4. **Generate Instincts** (if --instincts flag)

   Creates instinct YAML files for the continuous-learning system.

### GitHub App Integration

For advanced features (10k+ commits, team sharing, auto-PRs), use the Skill Creator GitHub App:
- Install: github.com/apps/skill-creator
- Comment `/skill-creator analyze` on any issue
