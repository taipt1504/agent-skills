# Summer X.Y.Z

Released: YYYY-MM-DD

> Per-version reference for skill `<skill-name>`. Concise diff vs the previous version. Use this
> file when the project's `summer-platform` version is `X.Y.Z` and a feature/breaking change in
> this skill's domain originated here. The canonical, "what to write today" guide lives in
> `../SKILL.md` (always tracks LATEST stable).

## Features

- Feature 1 — short description, code sample only when behaviour is non-obvious.
- Feature 2 — `ClassName` introduced in module `summer-foo`.

## Breaking changes

- **Title.** What changed, why, and concrete migration:
  ```yaml
  # Before (X.Y.{Z-1})
  ...
  # After (X.Y.Z)
  ...
  ```

## Deprecations

- `OldApi.foo()` — replaced by `NewApi.bar()`. Removed in N.M.K.

## Config schema delta

Diff vs previous version. Empty sections may be removed.

```yaml
# Before
old:
  shape: ...
# After
new:
  shape: ...
```

## Migration from X.Y.{Z-1}

1. Step 1 — copy/paste-able snippet.
2. Step 2.
3. Verification — what to check after upgrade (logs, beans present, tests pass).
