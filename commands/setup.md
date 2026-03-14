---
name: setup
description: >
  Install devco-agent-skills into the current project — copies CLAUDE.md,
  WORKING_WORKFLOW.md, and rules/ into the project root so they auto-load
  every session. Run once per project after cloning or after plugin updates.
---

# /setup — Install Plugin into Current Project

Copies three things from the plugin into your project:

| File/Dir | Where | Auto-loaded by Claude |
|----------|-------|----------------------|
| `CLAUDE.md` | Project root | ✅ Every session for this project |
| `WORKING_WORKFLOW.md` | Project root | When Claude reads it from CLAUDE.md |
| `.claude/rules/` | Project `.claude/rules/` | ✅ Every session for this project |

## Run setup now

Use the Bash tool to execute the setup script. First, locate the plugin:

```bash
# Find the installed plugin directory
PLUGIN_DIR="$(find "$HOME/.claude/plugins" -maxdepth 4 -name "setup.sh" \
  -path "*/devco-agent-skills/*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {})"

if [ -z "$PLUGIN_DIR" ]; then
  echo "❌ Plugin not found in ~/.claude/plugins"
  echo "   Install it first: claude plugin add devco-agent-skills@devco-agent-skills"
  exit 1
fi

echo "Plugin found at: $PLUGIN_DIR"
```

Then run setup from the **target project's root directory**:

```bash
bash "$PLUGIN_DIR/scripts/setup.sh"
```

## Commit to version control

Share the setup with your team by committing the generated files:

```bash
git add CLAUDE.md WORKING_WORKFLOW.md .claude/rules/
git commit -m "chore: add Claude Code project context"
```

Once committed, every teammate who clones the repo gets the rules automatically —
no manual setup required.

## Optional: also install globally

To load plugin rules in **every** project on this machine (not just this one):

```bash
bash "$PLUGIN_DIR/scripts/setup.sh" --global
```

## Refresh after plugin update

Re-run to pull in updated rules after a plugin upgrade — safe to run multiple times:

```bash
bash "$PLUGIN_DIR/scripts/setup.sh" --update
```

## Verify it worked

```bash
test -f CLAUDE.md           && echo "✅ CLAUDE.md present"
test -f WORKING_WORKFLOW.md && echo "✅ WORKING_WORKFLOW.md present"
ls .claude/rules/ 2>/dev/null && echo "✅ Rules installed" || echo "❌ Rules missing"
```

## What gets loaded

```
PROJECT_ROOT/
├── CLAUDE.md                ← loaded every session for this project
├── WORKING_WORKFLOW.md      ← 7-phase workflow reference (read by CLAUDE.md)
└── .claude/
    └── rules/               ← loaded every session for this project
        ├── common/
        │   ├── coding-style.md
        │   └── security.md
        ├── java/
        │   ├── reactive.md
        │   └── testing.md
        └── ...
```
