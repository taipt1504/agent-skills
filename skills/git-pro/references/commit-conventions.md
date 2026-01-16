# Commit Message Conventions

## Conventional Commits

Standard format được sử dụng rộng rãi.

### Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

### Examples

```
feat(auth): add OAuth2 login support

Implement OAuth2 authentication flow with Google and GitHub providers.
- Add OAuth2 configuration
- Create callback handlers
- Update user model for provider linking

Closes #123
```

```
fix(api): handle null pointer in user service

The getUserById method was not checking for null before accessing
user properties, causing NullPointerException in production.

Fixes #456
```

```
refactor(database): migrate from MySQL to PostgreSQL

BREAKING CHANGE: Database connection configuration has changed.
Update your .env file with new PostgreSQL settings.

Refs #789
```

---

## Types

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat: add search functionality` |
| `fix` | Bug fix | `fix: resolve login timeout issue` |
| `docs` | Documentation only | `docs: update API documentation` |
| `style` | Code style (formatting, semicolons) | `style: fix indentation` |
| `refactor` | Code change without fix/feature | `refactor: extract helper function` |
| `perf` | Performance improvement | `perf: optimize database queries` |
| `test` | Adding/correcting tests | `test: add user service tests` |
| `build` | Build system/dependencies | `build: upgrade webpack to v5` |
| `ci` | CI configuration | `ci: add GitHub Actions workflow` |
| `chore` | Other changes | `chore: update gitignore` |
| `revert` | Revert previous commit | `revert: revert "feat: add login"` |

---

## Scope

Scope indicates the section of codebase affected.

### Common Scopes

```
feat(auth): ...       # Authentication module
feat(api): ...        # API layer
feat(ui): ...         # User interface
feat(db): ...         # Database
feat(core): ...       # Core functionality
feat(config): ...     # Configuration
feat(deps): ...       # Dependencies
```

### Project-specific Scopes

```
# By component
feat(header): ...
feat(sidebar): ...
feat(dashboard): ...

# By domain
feat(users): ...
feat(orders): ...
feat(payments): ...

# By layer
feat(controller): ...
feat(service): ...
feat(repository): ...
```

---

## Subject Line Rules

### DO:

1. Use imperative mood: "add" not "added" or "adds"
2. Don't capitalize first letter
3. No period at the end
4. Keep under 50 characters
5. Be specific and descriptive

### DON'T:

1. Don't use past tense
2. Don't be vague
3. Don't include ticket number in subject (use footer)

### Good Examples

```
feat(auth): add password reset functionality
fix(api): handle empty response from server
refactor(utils): extract date formatting logic
docs(readme): add installation instructions
test(user): add unit tests for validation
```

### Bad Examples

```
feat(auth): Added password reset functionality     # Past tense
fix: fix bug                                       # Too vague
refactor(utils): Extract date formatting logic.   # Capitalized, period
docs: Updated readme with installation stuff      # Past tense, vague
JIRA-123: add feature                             # Ticket in subject
```

---

## Body

When to include a body:
- Changes are complex and need explanation
- Breaking changes
- Non-obvious reasoning

### Format

```
<type>(<scope>): <subject>
<BLANK LINE>
<body>
```

### Rules

1. Wrap at 72 characters
2. Explain WHAT and WHY, not HOW
3. Use bullet points for multiple items
4. Reference issues at bottom

### Example

```
refactor(auth): replace JWT library

The previous JWT library (jsonwebtoken) had security vulnerabilities
and was no longer maintained. Switched to jose which is actively
maintained and has better TypeScript support.

Changes:
- Replace jsonwebtoken with jose
- Update token generation logic
- Update token verification middleware
- Add new configuration options

This change requires updating the JWT_SECRET format in production.
```

---

## Footer

### Breaking Changes

```
feat(api): change user endpoint response format

BREAKING CHANGE: The /api/users endpoint now returns a different
JSON structure. The 'name' field has been split into 'firstName'
and 'lastName'.

Before: { "name": "John Doe" }
After: { "firstName": "John", "lastName": "Doe" }
```

### Issue References

```
fix(checkout): resolve payment processing error

Fixes #123
Closes #456
Refs #789
```

| Keyword | Effect (GitHub) |
|---------|-----------------|
| `Fixes` | Closes issue when merged |
| `Closes` | Closes issue when merged |
| `Resolves` | Closes issue when merged |
| `Refs` | Links but doesn't close |
| `Related to` | Links but doesn't close |

### Co-authors

```
feat(ui): redesign dashboard layout

Co-authored-by: Jane Doe <jane@example.com>
Co-authored-by: Bob Smith <bob@example.com>
```

---

## Multi-line Commits in CLI

### Using Heredoc

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add two-factor authentication

Implement TOTP-based 2FA for enhanced security.

- Add QR code generation for authenticator apps
- Create backup codes functionality
- Update login flow for 2FA verification

Closes #123
EOF
)"
```

### Using -m Multiple Times

```bash
git commit \
  -m "feat(auth): add two-factor authentication" \
  -m "Implement TOTP-based 2FA for enhanced security." \
  -m "Closes #123"
```

### Using Editor

```bash
# Opens default editor
git commit

# Use specific editor
GIT_EDITOR=vim git commit
```

---

## Automated Validation

### commitlint

```json
// .commitlintrc.json
{
  "extends": ["@commitlint/config-conventional"],
  "rules": {
    "type-enum": [
      2,
      "always",
      ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"]
    ],
    "scope-case": [2, "always", "lower-case"],
    "subject-case": [2, "always", "lower-case"],
    "subject-max-length": [2, "always", 50],
    "body-max-line-length": [2, "always", 72]
  }
}
```

### Git Hook (commit-msg)

```bash
#!/bin/sh
# .git/hooks/commit-msg

commit_msg=$(cat "$1")
pattern="^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z]+\))?: .{1,50}$"

if ! echo "$commit_msg" | head -1 | grep -qE "$pattern"; then
    echo "Invalid commit message format"
    echo "Expected: <type>(<scope>): <subject>"
    exit 1
fi
```

---

## Templates

### Git Commit Template

```bash
# Create template file
cat > ~/.gitmessage << 'EOF'
# <type>(<scope>): <subject>
#
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
#
# Body (optional): Explain WHAT and WHY
#
# Footer (optional):
# - BREAKING CHANGE: description
# - Closes #issue
EOF

# Configure
git config --global commit.template ~/.gitmessage
```

---

## Quick Reference

```
┌──────────────────────────────────────────────────┐
│ <type>(<scope>): <subject>                       │
│                                                  │
│ [body]                                           │
│                                                  │
│ [footer]                                         │
└──────────────────────────────────────────────────┘

Types:
  feat     - New feature
  fix      - Bug fix
  docs     - Documentation
  style    - Formatting
  refactor - Code restructure
  perf     - Performance
  test     - Tests
  build    - Build system
  ci       - CI/CD
  chore    - Other

Subject rules:
  ✓ Imperative mood (add, fix, change)
  ✓ Lowercase
  ✓ No period
  ✓ Max 50 chars

Footer keywords:
  Fixes #123      - Closes issue
  Closes #456     - Closes issue
  BREAKING CHANGE - Breaking change
  Co-authored-by  - Credit co-author
```
