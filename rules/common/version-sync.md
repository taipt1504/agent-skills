---
name: version-sync
description: Plugin version consistency rule — when bumping plugin version, sync all three sources of truth and verify no hardcoded version banners drift.
globs: "*.json,*.sh,*.md"
applicability:
  always: false
  triggers:
    files_match: ["**/.claude-plugin/plugin.json", "**/package.json", "**/.claude-plugin/marketplace.json", "**/setup-kit.sh", "**/scripts/**/*.sh"]
    task_keywords: ["version bump", "release", "publish", "tag", "ship"]
relevance_assessment: |
  HIGH 95%+: any task that bumps the plugin version (release / tag / publish).
  MEDIUM 50%: any edit to plugin metadata or setup script.
  ZERO: pure code task with no metadata change.
---

# Version Sync — Single Source of Truth

> Plugin version lives in three places. They MUST agree. Scripts MUST NOT hardcode version banners.

## Canonical source

**`.claude-plugin/plugin.json` `version` field** is the canonical source. Claude Code reads it. All other files mirror it.

## Required sync (every version bump)

When changing the plugin version, update all three in the same commit:

1. `.claude-plugin/plugin.json` — `version`
2. `package.json` — `version`
3. `.claude-plugin/marketplace.json` — `plugins[0].version`

## No hardcoded banners

Scripts MUST read the version dynamically. Never hardcode `vX.Y.Z` in a `banner()` or `echo` that's user-visible.

**Bad**
```bash
echo "devco-agent-skills Installer v3.2"
```

**Good**
```bash
PLUGIN_VERSION=$(python3 -c "import json; print(json.load(open('.claude-plugin/plugin.json'))['version'])")
echo "devco-agent-skills Installer v${PLUGIN_VERSION}"
```

## Per-script header comments

`# script.sh — purpose (v3.2)` headers in `scripts/hooks/*.sh` track per-script changes and may legitimately lag the plugin version. They are NOT user-visible and NOT subject to this rule. Leave alone unless rewriting the script.

## Validation

Run before declaring a release done:

```bash
bash scripts/ci/validate-version-sync.sh
```

This fails if:
- Any of the three version sources disagree.
- `setup-kit.sh` (or any future user-facing banner) contains a literal `Installer v<digits>` instead of `${PLUGIN_VERSION}`.

`scripts/ci/run-all.sh` runs this validator automatically.

## Marketplace description sync

`.claude-plugin/marketplace.json` `plugins[0].description` quotes plugin counts (skills, agents, commands, rules, hooks). When inventory changes meaningfully (Phase A/B refactor, new rule set), update the count here AND in `README.md` inventory tables.

Recheck via:

```bash
find skills -name SKILL.md | wc -l       # skills
find agents -name '*.md' | wc -l         # agents (including _shared-protocol)
find commands -name '*.md' | wc -l       # commands
find rules -name '*.md' | wc -l          # rules
find hooks -name 'hooks.json' -o -path '*hooks*.sh' | wc -l   # hooks
```

## Related

- `scripts/ci/validate-version-sync.sh` — CI enforcement
- `CLAUDE.md` Hard block #19 — release without sync = FORBIDDEN
- `rules/common/git-workflow.md` — commit + tag flow
