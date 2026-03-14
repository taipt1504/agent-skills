# Instinct Command

Manage learned instincts — view status, export for sharing, or import from teammates.

## Usage

```
/instinct                    → defaults to "status"
/instinct status             → show all instincts with confidence scores
/instinct export             → export instincts to shareable YAML
/instinct import <file>      → import instincts from file or URL
```

---

## Subcommand: `status`

Show all learned instincts grouped by domain with confidence bars.

### Flags

- `--domain <name>` — filter by domain (code-style, testing, git, etc.)
- `--low-confidence` — show only instincts with confidence < 0.5
- `--high-confidence` — show only instincts with confidence >= 0.7
- `--json` — output as JSON

### What to Do

1. Read instinct files from `~/.claude/homunculus/instincts/personal/`
2. Read inherited instincts from `~/.claude/homunculus/instincts/inherited/`
3. Display grouped by domain with confidence bars

### Output

```
Instinct Status
===============

## Code Style (4 instincts)

  prefer-functional-style
  Trigger: when writing new functions → Use functional patterns
  Confidence: ████████░░ 80%  |  Source: session-observation

## Testing (2 instincts)

  test-first-workflow
  Trigger: when adding new functionality → Write test first
  Confidence: █████████░ 90%  |  Source: session-observation

---
Total: 9 instincts (4 personal, 5 inherited)
```

---

## Subcommand: `export`

Export instincts to a shareable YAML format.

### Flags

- `--domain <name>` — export only specified domain
- `--min-confidence <n>` — minimum confidence threshold (default: 0.3)
- `--output <file>` — output path (default: `instincts-export-YYYYMMDD.yaml`)
- `--format <yaml|json|md>` — output format (default: yaml)

### What to Do

1. Read instincts from `~/.claude/homunculus/instincts/personal/`
2. Filter based on flags
3. Strip sensitive information (session IDs, absolute file paths, old timestamps)
4. Generate export file

### Privacy

Exports include: trigger patterns, actions, confidence scores, domains, observation counts.
Exports do NOT include: code snippets, file paths, session transcripts, personal identifiers.

### Output Format

```yaml
version: "2.0"
exported_by: "continuous-learning-v2"
export_date: "2025-01-22T10:30:00Z"
instincts:
  - id: prefer-functional-style
    trigger: "when writing new functions"
    action: "Use functional patterns over classes"
    confidence: 0.8
    domain: code-style
    observations: 8
```

---

## Subcommand: `import`

Import instincts from teammates, Skill Creator, or community collections.

### Flags

- `--dry-run` — preview without importing
- `--force` — import even if conflicts exist
- `--merge-strategy <higher|local|import>` — how to handle duplicates
- `--from-skill-creator <owner/repo>` — import from Skill Creator analysis
- `--min-confidence <n>` — only import instincts above threshold

### What to Do

1. Fetch the instinct file (local path or URL)
2. Parse and validate format
3. Check for duplicates with existing instincts
4. Merge or add new instincts
5. Save to `~/.claude/homunculus/instincts/inherited/`

### Merge Strategy

- **Duplicates**: higher confidence wins, merge observation counts
- **Conflicts**: skip by default, flag for manual resolution
- Imported instincts marked with `source: "inherited"` and import metadata

### Output

```
Import complete!
Added: 8 instincts | Updated: 1 | Skipped: 3 (2 duplicates, 1 conflict)
Saved to: ~/.claude/homunculus/instincts/inherited/
Run /instinct status to see all instincts.
```
