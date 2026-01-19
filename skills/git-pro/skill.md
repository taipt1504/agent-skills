---
name: git-pro
description: Advanced Git source control with intelligent commit message generation
triggers:
  - git advanced
  - git workflow
  - commit message
  - source control
  - git analyze
  - /git-pro
tools:
  - Read
  - Bash
  - Glob
  - Grep
references:
  - references/commands.md
  - references/workflows.md
  - references/commit-conventions.md
scripts:
  - scripts/analyze-repo.sh
  - scripts/generate-commit-msg.py
---

# Git Pro

Advanced Git source control skill with source analysis capabilities and optimal commit message generation.

## Purpose

This skill helps the agent:

- Comprehensively analyze repository status
- Use optimal Git commands for each situation
- Generate commit messages following standard conventions
- Efficiently manage branches, merges, and history
- Intelligently detect and resolve conflicts

## When to Use

- Analyzing repo status and changes
- Creating commits with quality messages
- Managing branches and merging
- Reviewing history and searching commits
- Resolving conflicts and rebasing
- Cleanup and repository optimization

## When NOT to Use

- Simple `git add . && git commit` without analysis
- User already has a commit message
- Non-git version control systems (SVN, Mercurial)

---

## Core Workflow

### 1. Analyze Repository Status

Before performing any operation, ALWAYS analyze repo status:

```bash
# Full status analysis
git status --short --branch

# View staged changes
git diff --cached --stat

# View unstaged changes
git diff --stat

# View untracked files
git ls-files --others --exclude-standard
```

### 2. Understand the Changes

```bash
# Detailed diff of staged changes
git diff --cached

# Diff with context
git diff --cached -U5

# View only changed file names
git diff --cached --name-only

# View changes by file
git diff --cached -- path/to/file
```

### 3. Generate Optimal Commit Message

Based on analysis, generate message in format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

---

## Commit Message Generation

### Step 1: Analyze Changes

```bash
# List changed files
git diff --cached --name-only

# Get stats
git diff --cached --stat

# Get detailed changes
git diff --cached
```

### Step 2: Determine Commit Type

| Type       | When to use                             |
| ---------- | --------------------------------------- |
| `feat`     | Adding a new feature                    |
| `fix`      | Fixing a bug                            |
| `refactor` | Code refactoring (no behavior change)   |
| `docs`     | Documentation changes only              |
| `style`    | Formatting, missing semicolons, etc.    |
| `test`     | Adding or fixing tests                  |
| `chore`    | Build, CI, dependencies                 |
| `perf`     | Performance improvements                |

### Step 3: Identify Scope

Scope is the affected module/component:

```bash
# Find common directory of changed files
git diff --cached --name-only | xargs -I {} dirname {} | sort -u

# Example output:
# src/auth          -> scope: auth
# src/api/users     -> scope: api
# tests/            -> scope: tests
```

### Step 4: Write Subject Line

Rules:

- Imperative mood: "add" not "added"
- No capitalization of first letter
- No trailing period
- Max 50 characters

```
Good: feat(auth): add JWT refresh token support
Bad:  feat(auth): Added JWT refresh token support.
```

### Step 5: Write Body (if needed)

```
When body is needed:
- Complex changes requiring explanation
- Breaking changes
- Related to issue/ticket

Format:
- Wrap at 72 characters
- Explain WHAT and WHY, not HOW
- Bullet points for multiple changes
```

### Step 6: Add Footer (if needed)

```
# Breaking changes
BREAKING CHANGE: description

# Issue references
Closes #123
Fixes #456
Refs #789
```

---

## Advanced Git Commands

### Branch Management

```bash
# Create branch from specific commit
git checkout -b feature/xyz abc123

# Create branch and track remote
git checkout -b feature/xyz origin/feature/xyz

# Rename branch
git branch -m old-name new-name

# Delete branch (safe)
git branch -d feature/xyz

# Delete branch (force)
git branch -D feature/xyz

# Delete remote branch
git push origin --delete feature/xyz

# Cleanup stale remote branches
git fetch --prune
git remote prune origin
```

### History Analysis

```bash
# Log with graph
git log --oneline --graph --all -20

# Log of specific file
git log --oneline --follow -- path/to/file

# Search commits by message
git log --grep="keyword" --oneline

# Search commits by code change
git log -S "function_name" --oneline

# Commits by author
git log --author="name" --oneline

# Commits in date range
git log --after="2024-01-01" --before="2024-02-01" --oneline

# Show what changed in each commit
git log --stat --oneline -10
```

### Stash Operations

```bash
# Stash with message
git stash push -m "WIP: feature xyz"

# Stash including untracked
git stash push -u -m "WIP: feature xyz"

# List stashes
git stash list

# Apply and keep stash
git stash apply stash@{0}

# Apply and remove stash
git stash pop stash@{0}

# Show stash contents
git stash show -p stash@{0}

# Create branch from stash
git stash branch feature/xyz stash@{0}
```

### Interactive Rebase

```bash
# Rebase last N commits
git rebase -i HEAD~5

# Rebase onto specific branch
git rebase -i main

# Commands in interactive mode:
# pick   - keep commit
# reword - change message
# edit   - stop to amend
# squash - combine with previous commit
# fixup  - combine, discard message
# drop   - remove commit
```

### Cherry-pick

```bash
# Pick single commit
git cherry-pick abc123

# Pick multiple commits
git cherry-pick abc123 def456

# Pick without commit (stage only)
git cherry-pick -n abc123

# Pick range
git cherry-pick abc123..def456
```

### Reset and Revert

```bash
# Soft reset (keep changes staged)
git reset --soft HEAD~1

# Mixed reset (keep changes unstaged)
git reset HEAD~1

# Hard reset (discard changes)
git reset --hard HEAD~1

# Reset single file
git checkout HEAD -- path/to/file

# Revert commit (create new commit)
git revert abc123

# Revert without commit
git revert -n abc123
```

---

## Source Analysis Patterns

### Detect Change Type

```bash
# Check if only docs changed
git diff --cached --name-only | grep -E '\.(md|txt|rst)$'

# Check if only tests changed
git diff --cached --name-only | grep -E '(test|spec)\.'

# Check if config changed
git diff --cached --name-only | grep -E '\.(json|ya?ml|toml|ini)$'

# Check for new files
git diff --cached --name-status | grep '^A'

# Check for deleted files
git diff --cached --name-status | grep '^D'

# Check for renamed files
git diff --cached --name-status | grep '^R'
```

### Analyze Code Impact

```bash
# Count lines added/removed
git diff --cached --shortstat

# Breakdown by file
git diff --cached --numstat

# Detect function changes (for supported languages)
git diff --cached -p | grep -E '^\+.*function|^\+.*def |^\+.*class '
```

### Detect Breaking Changes

Patterns to look for:

- Renamed public APIs
- Changed function signatures
- Removed exports
- Changed config schemas

```bash
# Check for removed exports
git diff --cached | grep -E '^\-.*export'

# Check for changed interfaces
git diff --cached | grep -E '^\-.*interface|^\+.*interface'
```

---

## Conflict Resolution

### Analyze Conflicts

```bash
# List conflicted files
git diff --name-only --diff-filter=U

# Show conflict markers
git diff --check

# Show both versions
git show :1:file  # common ancestor
git show :2:file  # ours
git show :3:file  # theirs
```

### Resolution Strategies

```bash
# Accept ours
git checkout --ours path/to/file
git add path/to/file

# Accept theirs
git checkout --theirs path/to/file
git add path/to/file

# Manual merge tool
git mergetool

# Abort merge
git merge --abort

# Abort rebase
git rebase --abort
```

---

## Best Practices

### DO:

- Commit frequently with atomic changes
- Write meaningful commit messages
- Use branches for features/fixes
- Pull/rebase before pushing
- Review changes before committing

### DON'T:

- Commit directly to main/master
- Force push shared branches
- Commit sensitive data (passwords, keys)
- Mix multiple changes in one commit
- Leave merge commits messy

---

## Git Configuration

### Recommended Settings

```bash
# User info
git config --global user.name "Your Name"
git config --global user.email "your@email.com"

# Default branch
git config --global init.defaultBranch main

# Auto-correct typos
git config --global help.autocorrect 10

# Better diff
git config --global diff.algorithm histogram

# Rebase by default on pull
git config --global pull.rebase true

# Auto-prune on fetch
git config --global fetch.prune true

# Better merge conflict markers
git config --global merge.conflictstyle diff3

# Sign commits (if using GPG)
git config --global commit.gpgsign true
```

### Useful Aliases

```bash
git config --global alias.st "status --short --branch"
git config --global alias.co "checkout"
git config --global alias.br "branch"
git config --global alias.ci "commit"
git config --global alias.lg "log --oneline --graph --all -20"
git config --global alias.last "log -1 HEAD --stat"
git config --global alias.unstage "reset HEAD --"
git config --global alias.amend "commit --amend --no-edit"
```

---

## Pre-Commit Checklist

```
[ ] Reviewed all changes (git diff --cached)
[ ] No unnecessary files
[ ] No sensitive data
[ ] Commit message follows conventions
[ ] Tests pass (if any)
[ ] Code formatted correctly
```

## Pre-Push Checklist

```
[ ] Pull/rebase latest changes
[ ] Resolved conflicts (if any)
[ ] Run tests locally
[ ] Review commit history
[ ] Correct branch
```

---

## References

- `references/commands.md` - Full Git command reference
- `references/workflows.md` - Git workflows (GitFlow, GitHub Flow, etc.)
- `references/commit-conventions.md` - Commit message conventions

## Scripts

- `scripts/analyze-repo.sh` - Analyze repository status
- `scripts/generate-commit-msg.py` - Generate commit message from changes
