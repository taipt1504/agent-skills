# Summer Versioning Workflow

How to keep `agent-skills` Summer documentation in sync with `common-libs/CHANGELOG.md`.

## Layout recap

```
skills/
├── summer-core/
│   ├── SKILL.md                        ← LATEST stable (canon)
│   └── references/
│       ├── version-matrix.md           ← single source of feature × version table
│       ├── versioning-workflow.md      ← this file
│       ├── migrations/                 ← cross-cutting <from>-to-<to> guides
│       │   ├── 0.2.x-to-0.3.0.md
│       │   ├── 0.3.0-to-0.3.1.md
│       │   ├── 0.3.1-to-0.3.2.md
│       │   └── 0.3.2-to-0.3.3.md
│       └── versions/                   ← per-version notes for cross-cutting changes
│           ├── 0.2.1.md
│           ├── 0.2.5.md
│           ├── 0.2.6.md
│           ├── 0.2.8.md
│           └── _template.md
└── summer-{security,data,rest,ratelimit,test}/
    ├── SKILL.md                        ← LATEST stable for this skill
    └── references/
        ├── ...                         ← skill-specific topical refs (unchanged)
        └── versions/
            └── X.Y.Z.md                ← only when this skill changed in X.Y.Z
```

`SKILL.md` always tracks the latest stable schema — agents reading it get current guidance
without legacy noise. Older versions live in `versions/<X.Y.Z>.md` overlays.

## When `common-libs/CHANGELOG.md` adds a new release

Walk through these steps in order:

1. **Read the CHANGELOG entry for the new version.** Identify the affected modules: outbox,
   audit, security, rest, ratelimit, kafka-consumer, payment-sdk, etc.
2. **Update `summer-core/references/version-matrix.md`:**
   - Add the new version as a column in the Module × Version table.
   - Add a "Headline changes" section at the top (chronological — newest first).
   - If the version exposes a new detectable artifact / class / property, add an entry to the
     Pattern Detection table.
3. **For each affected skill, write `skills/<skill>/references/versions/X.Y.Z.md`.** Use
   `summer-core/references/versions/_template.md` as a starting point. Sections expected:
   - Features (per-feature paragraph).
   - Breaking changes (with before/after diff).
   - Deprecations (with replacement and removal version).
   - Config schema delta (only when YAML keys changed).
   - Migration from previous version (concrete steps).
   - Verification (how to confirm the upgrade landed).
4. **If the new version contains breaking changes**, write
   `skills/summer-core/references/migrations/<previous>-to-<X.Y.Z>.md`. Pull the per-skill
   diffs together into a single end-to-end checklist.
5. **If `X.Y.Z` becomes the new stable**, edit each affected skill's `SKILL.md` so that the
   canon section reflects the new schema/API. Move what was canonical into the previous
   version's overlay if needed (e.g. when a config block is replaced).
6. **Run the coverage check** to verify everything is wired up:

   ```bash
   ./scripts/ci/check-summer-version-coverage.sh
   ```

   In strict mode (CI-enforced):

   ```bash
   ./scripts/ci/check-summer-version-coverage.sh --strict
   ```

7. **Smoke-load the skill in a real session.** Pick a project on the new version, ask the
   agent something that exercises the changed area, confirm it produces config matching the
   new schema. Update the SKILL.md if anything reads stale.

## Guidelines

### Per-version files

- One file per version, only when this skill changed. Versions that didn't touch the skill get
  no file.
- Keep them short — 100-200 lines max. The full CHANGELOG entry lives upstream; this file is
  for skill-specific guidance the agent needs.
- Always name files `X.Y.Z.md` (no shortening). The coverage script keys off this pattern.
- Aggregate older minor lines (`0.2.x.md`) only when individual patch files would be
  near-empty — not the convention here, but reserved for legacy lines after they EOL.

### Migration guides

- One per BREAKING transition. Skip if a release is purely additive — note in version-matrix
  headline that the migration step is "no required changes".
- Always include a verification checklist at the end.
- Cross-link the per-skill `versions/X.Y.Z.md` files for full detail.

### `SKILL.md` canon

- Document **what to write today**, not history. History lives in `versions/`.
- Inline version notes as a "Version Notes" section at the bottom — 1-2 lines per affected
  release plus a link to the overlay.
- When the agent needs old-version guidance, the harness loads
  `versions/<detected-version>.md` alongside the canon.

### Detection signals

- Add to the Pattern Detection table in `version-matrix.md` only when:
  - The signal is unambiguous (specific class name, config property, or artifact id).
  - The signal is **introduced** in the listed version (not also present earlier).
- Prefer artifact names and config-property names over class signatures — they survive
  refactors better.

## Source-of-truth contract

`common-libs/CHANGELOG.md` is the only authoritative changelog. This repo's per-skill files
are derived. Never document a Summer feature here that isn't in the upstream CHANGELOG —
either the CHANGELOG is wrong (push a fix there) or the feature isn't real.

The CI script enforces the version side of this contract:

> Every `## Summer X.Y.Z` heading in the upstream CHANGELOG must appear in
> `version-matrix.md`. Strict mode also requires every matrix version to have at least one
> per-skill overlay.

If you intentionally skip a release in `version-matrix.md` (e.g. an internal-only patch), pin
it to a `<!-- skipped -->` line so the script can be taught to ignore it (currently it
doesn't — extend if needed).
