---
name: dc-setup
description: Install devco-agent-skills into the current project. Interactive wizard — always asks user preferences before configuring.
---

# /dc-setup — Interactive Project Setup

## CRITICAL RULE: Always Ask, Never Force Defaults

MUST ask user for preferences before configuring ANYTHING. Never auto-apply defaults. Never skip user choices. User decides everything.

## Setup Flow

### Phase 1: Ask User Preferences (MANDATORY — before any script runs)

Use **AskUserQuestion** tool to gather all preferences FIRST:

**Question 1 — Development Mode:**

```
Which development mode do you prefer?
- standard (Recommended): Full PLAN→SPEC→BUILD→VERIFY→REVIEW workflow, confirmations required
- yolo: Skip plan/spec confirmations, minimal hooks, fastest iteration
- strict: All gates enforced, all hooks active, best for production codebases
```

**Question 2 — Team Features:**

```
Enable multi-agent team features?
- Yes: Parallel BUILD with multiple agents, concurrent reviews
- No: Single agent mode (simpler, lower cost)
```

**Question 3 — MCP Servers:**
After project detection, present detected stack and ask:

```
Based on your project, these MCP servers are recommended:
[list detected MCPs based on build.gradle/pom.xml]
Which would you like to install? (select all that apply)
```

### Phase 2: Run Project Detection

Detect project stack FIRST (before config) to show user what was detected:

```bash
PLUGIN_DIR="$(find "$HOME/.claude/plugins" -maxdepth 4 -name "setup-kit.sh" \
  -path "*/devco-agent-skills/*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {})"

if [ -z "$PLUGIN_DIR" ]; then
  echo "Plugin not found. Install: claude plugin add devco-agent-skills@devco-agent-skills"
  exit 1
fi
echo "Plugin found at: $PLUGIN_DIR"
```

Detect stack (read-only, no writes yet):

```bash
# Detect build tool
if [ -f ./gradlew ]; then BUILD_TOOL="gradle-wrapper"
elif [ -f ./build.gradle ] || [ -f ./build.gradle.kts ]; then BUILD_TOOL="gradle"
elif [ -f ./mvnw ]; then BUILD_TOOL="maven-wrapper"
elif [ -f ./pom.xml ]; then BUILD_TOOL="maven"
else BUILD_TOOL="unknown"; fi

# Detect Spring type
SPRING_TYPE="unknown"
for bf in build.gradle build.gradle.kts pom.xml; do
  [ -f "$bf" ] || continue
  grep -q "spring-boot-starter-webflux" "$bf" 2>/dev/null && SPRING_TYPE="webflux"
  grep -q "spring-boot-starter-web" "$bf" 2>/dev/null && [ "$SPRING_TYPE" = "unknown" ] && SPRING_TYPE="mvc"
done

# Detect dependencies
for dep in postgresql mysql redis kafka rabbitmq testcontainers docker; do
  for bf in build.gradle build.gradle.kts pom.xml; do
    [ -f "$bf" ] && grep -qi "$dep" "$bf" 2>/dev/null && eval "HAS_$(echo $dep | tr 'a-z' 'A-Z')=true"
  done
done

echo "Build tool: $BUILD_TOOL"
echo "Spring type: $SPRING_TYPE"
```

**Present detection results to user** and ask if they want to adjust before proceeding.

### Phase 3: Run Setup with User's Choices

ONLY after ALL user preferences gathered, run setup-kit.sh with appropriate flags:

```bash
# Build the command based on user choices
CMD="bash $PLUGIN_DIR/scripts/setup-kit.sh --mode {user_chosen_mode}"
[ "{team_enabled}" = "yes" ] && CMD="$CMD --team"

# Run setup
eval "$CMD"
```

### Phase 4: MCP Server Installation

Based on user's MCP selections from Phase 1 Question 3:

- ONLY install MCPs user explicitly chose
- For each selected MCP, run `claude mcp add` with appropriate config
- Show user what was installed and ask to adjust

### Phase 5: Verify & Show Summary

Show user what was configured and ask if correct:

```
Setup Summary:
- Mode: {mode}
- Team: {enabled/disabled}
- Spring type: {detected}
- Dependencies: {list}
- MCPs installed: {list}
- Hooks: auto-registered via plugin system

Does this look correct? Any changes needed?
```

## Important Notes

- **Hooks are auto-registered** by Claude Code plugin system from `hooks/hooks.json`. Do NOT copy hooks into `.claude/settings.json`.
- **Config separation (v3.3+)**: Project detection results (build tool, Spring type, dependencies, Summer version, Java version) written exclusively to `project-profile.json`. Plugin behavior settings (mode, workflow, team) written exclusively to `devco-config.json`. Do NOT write project detection data into `devco-config.json`.
- **project-profile.json** is single source of truth for project context. All downstream hooks (quality-gate, skill-router, subagent-init, preflight-discovery) read from it.
- **Conditional rule loading (v4.0)**: `rules/summer/` enumerated by `preflight-discovery.sh` ONLY when `project-profile.json` shows `summer: true`. Same principle as `summer-*` skills — load only when project uses io.f8a.summer library.
- **Safe to re-run** — setup-kit.sh is idempotent, won't overwrite user customizations.
- **Optional rules symlink (v4.1)**: `/dc-setup --link-rules <profile>` symlinks plugin rule subset into project `.claude/rules/` for Claude Code native auto-load. Profiles:
  - `--link-rules common` — symlinks `rules/common/*.md` (lanes, spec-driven, skill-enforcement, etc.)
  - `--link-rules java-webflux` — common + `rules/java/{coding-style,reactive,api-design,security,testing,observability,migration}.md`
  - `--link-rules java-mvc` — common + java/* minus reactive
  - `--link-rules summer` — adds `rules/summer/*.md` to whichever java profile
  - Default OFF — preserves pre-flight discipline (rules loaded explicitly per gate by plugin agents)
  - Trade-off: symlinking → Claude Code auto-loads at every session (~5-10K tokens); no symlink → plugin agents read on-demand per pre-flight artifact

## Quick Re-run (after plugin update)

```bash
bash "$PLUGIN_DIR/scripts/setup-kit.sh" --validate
```
