# Git Workflows Reference

## 1. GitHub Flow

Simple workflow cho continuous deployment.

### Structure

```
main ─────●─────●─────●─────●─────●─────●
           \         /       \         /
feature     ●───●───●         ●───●───●
```

### Rules

1. `main` luôn deployable
2. Tạo branch từ `main` cho mỗi feature/fix
3. Commit thường xuyên vào feature branch
4. Open Pull Request để review
5. Merge vào `main` sau khi approved
6. Deploy ngay sau merge

### Commands

```bash
# Start feature
git checkout main
git pull origin main
git checkout -b feature/user-auth

# Work on feature
git add .
git commit -m "feat(auth): add login form"

# Push và tạo PR
git push -u origin feature/user-auth

# After merge, cleanup
git checkout main
git pull origin main
git branch -d feature/user-auth
```

---

## 2. GitFlow

Workflow phức tạp hơn cho scheduled releases.

### Structure

```
main     ─────●───────────────────●─────────────●
              │                   │             │
hotfix        │           ●───●──●             │
              │          /                      │
release       │    ●───●───●                   │
              │   /         \                   │
develop  ─────●───●───●───●──●───●───●───●───●──●
               \     /           \         /
feature         ●───●             ●───●───●
```

### Branches

| Branch | Purpose | Merge to |
|--------|---------|----------|
| `main` | Production code | - |
| `develop` | Development | `main` |
| `feature/*` | New features | `develop` |
| `release/*` | Release prep | `main`, `develop` |
| `hotfix/*` | Production fixes | `main`, `develop` |

### Commands

```bash
# Feature
git checkout develop
git checkout -b feature/xyz
# ... work ...
git checkout develop
git merge --no-ff feature/xyz
git branch -d feature/xyz

# Release
git checkout develop
git checkout -b release/1.2.0
# ... version bump, testing ...
git checkout main
git merge --no-ff release/1.2.0
git tag -a v1.2.0 -m "Release 1.2.0"
git checkout develop
git merge --no-ff release/1.2.0
git branch -d release/1.2.0

# Hotfix
git checkout main
git checkout -b hotfix/1.2.1
# ... fix ...
git checkout main
git merge --no-ff hotfix/1.2.1
git tag -a v1.2.1 -m "Hotfix 1.2.1"
git checkout develop
git merge --no-ff hotfix/1.2.1
git branch -d hotfix/1.2.1
```

---

## 3. Trunk-Based Development

Continuous integration với short-lived branches.

### Structure

```
main  ───●───●───●───●───●───●───●───●───●───●
          \   /   \   /       \       /
           ●─●     ●─●         ●─────●
          (1-2 days max)
```

### Rules

1. Single `main` branch
2. Feature branches live < 2 days
3. Frequent integration (multiple times/day)
4. Feature flags cho incomplete features
5. Automated testing required

### Commands

```bash
# Start small change
git checkout main
git pull origin main
git checkout -b short-feature

# Quick work (max 1-2 days)
git add .
git commit -m "feat: small change"

# Integrate quickly
git checkout main
git pull origin main
git merge short-feature
git push origin main
git branch -d short-feature
```

---

## 4. Forking Workflow

Cho open source projects.

### Structure

```
upstream/main ────●─────●─────●─────●
                  │     ↑     │
                  │     │     │
origin/main ──────●─────●─────●
                   \         /
feature             ●───●───●
```

### Setup

```bash
# Clone your fork
git clone git@github.com:your-username/repo.git

# Add upstream
git remote add upstream git@github.com:original/repo.git

# Verify
git remote -v
```

### Commands

```bash
# Sync with upstream
git fetch upstream
git checkout main
git merge upstream/main

# Create feature
git checkout -b feature/xyz

# Work and push to your fork
git push origin feature/xyz

# Create PR to upstream (via GitHub UI)

# After merge, sync again
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
git branch -d feature/xyz
```

---

## 5. Release Branches

Cho projects với multiple supported versions.

### Structure

```
main      ────●───●───●───●───●───●───●
               \           \
release/1.x     ●───●───●───●───●
                         \
release/2.x               ●───●───●───●
```

### Commands

```bash
# Create release branch
git checkout main
git checkout -b release/2.0

# Backport fix to older release
git checkout release/1.x
git cherry-pick <commit-hash>

# Tag releases
git checkout release/2.0
git tag -a v2.0.1 -m "Release 2.0.1"
git push origin v2.0.1
```

---

## Comparison

| Workflow | Best For | Complexity | Release Cadence |
|----------|----------|------------|-----------------|
| GitHub Flow | Web apps, CD | Low | Continuous |
| GitFlow | Scheduled releases | High | Periodic |
| Trunk-Based | Large teams, CD | Medium | Continuous |
| Forking | Open source | Medium | Varies |
| Release Branches | Multiple versions | High | Per version |

---

## Merge Strategies

### Merge Commit (--no-ff)

```bash
git merge --no-ff feature
```

```
main    ─────●─────────────●
              \           /
feature        ●───●───●─
```

Pros: Full history, clear feature boundaries
Cons: More commits, messier log

### Squash Merge

```bash
git merge --squash feature
git commit -m "feat: complete feature"
```

```
main    ─────●─────────────●
              \           /
feature        ●───●───●
```

Pros: Clean linear history
Cons: Loses individual commits

### Rebase + Fast-forward

```bash
git checkout feature
git rebase main
git checkout main
git merge feature  # fast-forward
```

```
main    ─────●─────●───●───●
```

Pros: Linear history
Cons: Rewrites history, can cause issues with shared branches

---

## Branch Naming Conventions

```
feature/ABC-123-user-authentication
bugfix/ABC-456-fix-login-error
hotfix/ABC-789-security-patch
release/1.2.0
docs/update-readme
refactor/cleanup-auth-module
test/add-user-tests
```

Pattern: `<type>/<ticket>-<short-description>`
