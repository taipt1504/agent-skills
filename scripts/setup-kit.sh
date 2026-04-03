#!/usr/bin/env bash
# =============================================================================
# setup-kit.sh — devco-agent-skills Team Kit: 1-command full install
# =============================================================================
#
# Installs everything needed for a team to use devco-agent-skills:
#   1. Core setup (CLAUDE.md, rules, memory)
#   2. Plugin config (devco-config.json from defaults)
#   3. Project detection (project-profile.json)
#   4. Hook registration (.claude/settings.json)
#   5. MCP server suggestions
#   6. Installation validation
#
# Usage:
#   bash scripts/setup-kit.sh                    # Interactive setup
#   bash scripts/setup-kit.sh --mode standard    # Non-interactive with defaults
#   bash scripts/setup-kit.sh --mode yolo        # Yolo mode preset
#   bash scripts/setup-kit.sh --mode strict      # Strict mode preset
#   bash scripts/setup-kit.sh --team             # Enable team features
#   bash scripts/setup-kit.sh --validate         # Validate existing installation
#
# Safe to re-run: idempotent. Will not overwrite user customizations.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CLAUDE_DIR="$PROJECT_ROOT/.claude"
TOTAL_STEPS=6

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

MODE=""
TEAM_ENABLED=false
VALIDATE_ONLY=false
NON_INTERACTIVE=false

show_help() {
  echo "devco-agent-skills Team Kit Installer"
  echo ""
  echo "Usage: bash scripts/setup-kit.sh [options]"
  echo ""
  echo "Options:"
  echo "  --mode MODE    Set mode: yolo, standard, strict (non-interactive)"
  echo "  --team         Enable team/multi-agent features"
  echo "  --validate     Validate existing installation only"
  echo "  --help         Show this help"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode) MODE="$2"; NON_INTERACTIVE=true; shift 2 ;;
    --team) TEAM_ENABLED=true; shift ;;
    --validate) VALIDATE_ONLY=true; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

step() {
  echo ""
  echo -e "${BLUE}[Step $1/$TOTAL_STEPS]${NC} ${BOLD}$2${NC}"
}

pass() {
  echo -e "  ${GREEN}✓${NC} $1"
}

warn() {
  echo -e "  ${YELLOW}!${NC} $1"
}

fail() {
  echo -e "  ${RED}✗${NC} $1"
}

banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}devco-agent-skills Team Kit Installer v3.2${NC}  ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
}

# ---------------------------------------------------------------------------
# JSON helper — uses python3 with sed fallback
# ---------------------------------------------------------------------------

json_set() {
  local file="$1"
  local key="$2"
  local value="$3"
  local value_type="${4:-string}"  # string, bool, number, null

  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open('$file', 'r') as f:
    data = json.load(f)
keys = '$key'.split('.')
obj = data
for k in keys[:-1]:
    obj = obj.setdefault(k, {})
v = '$value'
vtype = '$value_type'
if vtype == 'bool':
    obj[keys[-1]] = v.lower() == 'true'
elif vtype == 'number':
    obj[keys[-1]] = int(v) if '.' not in v else float(v)
elif vtype == 'null':
    obj[keys[-1]] = None
else:
    obj[keys[-1]] = v
with open('$file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  else
    # Fallback: simple sed for flat keys (best-effort)
    if [ "$value_type" = "string" ]; then
      sed -i.bak "s|\"${key##*.}\": *\"[^\"]*\"|\"${key##*.}\": \"$value\"|" "$file"
    elif [ "$value_type" = "bool" ]; then
      sed -i.bak "s|\"${key##*.}\": *[a-z]*|\"${key##*.}\": $value|" "$file"
    fi
    rm -f "${file}.bak"
  fi
}

json_merge_hooks() {
  local source="$1"
  local target="$2"

  if command -v python3 &>/dev/null; then
    python3 -c "
import json

with open('$source', 'r') as f:
    src = json.load(f)
with open('$target', 'r') as f:
    tgt = json.load(f)

src_hooks = src.get('hooks', {})
tgt_hooks = tgt.setdefault('hooks', {})

added = 0
for event, entries in src_hooks.items():
    if event not in tgt_hooks:
        tgt_hooks[event] = entries
        added += len(entries)
    else:
        # Check each entry — add only if command not already present
        existing_cmds = set()
        for entry_group in tgt_hooks[event]:
            for hook in entry_group.get('hooks', []):
                existing_cmds.add(hook.get('command', ''))
        for entry in entries:
            for hook in entry.get('hooks', []):
                if hook.get('command', '') not in existing_cmds:
                    tgt_hooks[event].append(entry)
                    added += 1
                    break

with open('$target', 'w') as f:
    json.dump(tgt, f, indent=2)
    f.write('\n')

print(added)
"
  else
    echo "0"
  fi
}

# ---------------------------------------------------------------------------
# Dependency detection helpers
# ---------------------------------------------------------------------------

has_dependency() {
  local dep="$1"
  local found=false

  # Check build.gradle / build.gradle.kts
  for gf in "$PROJECT_ROOT/build.gradle" "$PROJECT_ROOT/build.gradle.kts"; do
    if [ -f "$gf" ] && grep -qi "$dep" "$gf" 2>/dev/null; then
      found=true
    fi
  done

  # Check pom.xml
  if [ -f "$PROJECT_ROOT/pom.xml" ] && grep -qi "$dep" "$PROJECT_ROOT/pom.xml" 2>/dev/null; then
    found=true
  fi

  $found
}

detect_build_tool() {
  if [ -f "$PROJECT_ROOT/gradlew" ]; then
    echo "gradle-wrapper"
  elif command -v gradle &>/dev/null && [ -f "$PROJECT_ROOT/build.gradle" -o -f "$PROJECT_ROOT/build.gradle.kts" ]; then
    echo "gradle"
  elif [ -f "$PROJECT_ROOT/mvnw" ]; then
    echo "maven-wrapper"
  elif command -v mvn &>/dev/null && [ -f "$PROJECT_ROOT/pom.xml" ]; then
    echo "maven"
  else
    echo "unknown"
  fi
}

detect_build_tool_display() {
  case "$1" in
    gradle-wrapper) echo "Gradle Wrapper (./gradlew)" ;;
    gradle) echo "Gradle" ;;
    maven-wrapper) echo "Maven Wrapper (./mvnw)" ;;
    maven) echo "Maven" ;;
    *) echo "Unknown" ;;
  esac
}

detect_spring_type() {
  if has_dependency "spring-boot-starter-webflux"; then
    echo "webflux"
  elif has_dependency "spring-boot-starter-web"; then
    echo "mvc"
  else
    echo "unknown"
  fi
}

detect_java_version() {
  if command -v java &>/dev/null; then
    java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/'
  else
    echo "not found"
  fi
}

detect_project_java_version() {
  local ver=""
  for gf in "$PROJECT_ROOT/build.gradle" "$PROJECT_ROOT/build.gradle.kts"; do
    if [ -f "$gf" ]; then
      ver=$(grep -oE "sourceCompatibility\s*=\s*['\"]?[0-9]+" "$gf" 2>/dev/null | grep -oE "[0-9]+" | head -1)
      [ -z "$ver" ] && ver=$(grep -oE "JavaVersion\.VERSION_([0-9]+)" "$gf" 2>/dev/null | grep -oE "[0-9]+" | head -1)
      [ -z "$ver" ] && ver=$(grep -oE "jvmTarget\s*=\s*['\"]?[0-9]+" "$gf" 2>/dev/null | grep -oE "[0-9]+" | head -1)
      [ -n "$ver" ] && echo "$ver" && return
    fi
  done
  if [ -z "$ver" ] && [ -f "$PROJECT_ROOT/gradle.properties" ]; then
    ver=$(grep -oE "sourceCompatibility\s*=\s*[0-9]+" "$PROJECT_ROOT/gradle.properties" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    [ -n "$ver" ] && echo "$ver" && return
  fi
  if [ -z "$ver" ] && [ -f "$PROJECT_ROOT/pom.xml" ]; then
    ver=$(grep -oE "<maven\.compiler\.source>[0-9]+" "$PROJECT_ROOT/pom.xml" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    [ -z "$ver" ] && ver=$(grep -oE "<java\.version>[0-9]+" "$PROJECT_ROOT/pom.xml" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    [ -n "$ver" ] && echo "$ver" && return
  fi
  echo ""
}

detect_summer_framework() {
  if has_dependency "io.f8a.summer" || has_dependency "summer-platform" || has_dependency "summer-framework"; then
    echo "true"
  else
    echo "false"
  fi
}

# =============================================================================
# VALIDATE-ONLY MODE
# =============================================================================

if [ "$VALIDATE_ONLY" = true ]; then
  banner
  echo ""
  echo -e "${BOLD}Validation Mode — checking existing installation${NC}"

  VPASS=0
  VFAIL=0

  check_file() {
    if [ -e "$1" ]; then
      pass "$2"
      VPASS=$((VPASS + 1))
    else
      fail "$2 — MISSING"
      VFAIL=$((VFAIL + 1))
    fi
  }

  echo ""
  echo "Core files:"
  check_file "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
  check_file "$CLAUDE_DIR/rules" "rules/"
  check_file "$CLAUDE_DIR/memory" "memory/"

  echo ""
  echo "Plugin config:"
  check_file "$CLAUDE_DIR/devco-config.json" "devco-config.json"
  check_file "$CLAUDE_DIR/project-profile.json" "project-profile.json"

  echo ""
  echo "Settings:"
  check_file "$CLAUDE_DIR/settings.json" "settings.json"
  if [ -f "$CLAUDE_DIR/settings.json" ] && grep -q '"hooks"' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
    pass "Hooks registered in settings.json"
    VPASS=$((VPASS + 1))
  else
    warn "No hooks found in settings.json (may use plugin system instead)"
  fi

  echo ""
  echo "CI Validation:"
  if bash "$PLUGIN_DIR/scripts/ci/run-all.sh" >/dev/null 2>&1; then
    pass "CI validation: all passed"
    VPASS=$((VPASS + 1))
  else
    fail "CI validation: some checks failed"
    VFAIL=$((VFAIL + 1))
  fi

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
  if [ "$VFAIL" -eq 0 ]; then
    echo -e "${CYAN}║${NC}  ${GREEN}Validation: $VPASS/$VPASS checks passed${NC}            ${CYAN}║${NC}"
  else
    echo -e "${CYAN}║${NC}  ${YELLOW}Validation: $VPASS passed, $VFAIL failed${NC}             ${CYAN}║${NC}"
  fi
  echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  [ "$VFAIL" -eq 0 ] && exit 0 || exit 1
fi

# =============================================================================
# FULL INSTALLATION
# =============================================================================

banner

# Ensure .claude directory exists
mkdir -p "$CLAUDE_DIR"

# ---------------------------------------------------------------------------
# Step 1: Core Setup
# ---------------------------------------------------------------------------

step 1 "Core Setup"

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  pass "CLAUDE.md already installed"
else
  if bash "$PLUGIN_DIR/scripts/setup.sh" >/dev/null 2>&1; then
    pass "CLAUDE.md installed"
  else
    fail "Core setup failed — run 'bash scripts/setup.sh' manually"
    exit 1
  fi
fi

# Verify core artifacts (setup.sh may have been run previously)
if [ -d "$CLAUDE_DIR/rules" ]; then
  rule_count=$(find "$CLAUDE_DIR/rules" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  pass "Rules copied ($rule_count files)"
else
  # Run setup.sh if rules are missing
  bash "$PLUGIN_DIR/scripts/setup.sh" >/dev/null 2>&1
  rule_count=$(find "$CLAUDE_DIR/rules" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  pass "Rules installed ($rule_count files)"
fi

if [ -d "$CLAUDE_DIR/memory" ]; then
  pass "Memory initialized"
else
  mkdir -p "$CLAUDE_DIR/memory"
  pass "Memory directory created"
fi

# ---------------------------------------------------------------------------
# Step 2: Plugin Configuration
# ---------------------------------------------------------------------------

step 2 "Plugin Configuration"

CONFIG_FILE="$CLAUDE_DIR/devco-config.json"

if [ -f "$CONFIG_FILE" ]; then
  pass "devco-config.json already exists"
else
  cp "$PLUGIN_DIR/config/defaults.json" "$CONFIG_FILE"
  pass "devco-config.json created from defaults"
fi

# ---------------------------------------------------------------------------
# Mode selection (interactive or from --mode flag)
# ---------------------------------------------------------------------------

apply_mode_presets() {
  local mode="$1"
  json_set "$CONFIG_FILE" "mode" "$mode" "string"

  case "$mode" in
    yolo)
      json_set "$CONFIG_FILE" "workflow.skipPlanConfirm" "true" "bool"
      json_set "$CONFIG_FILE" "workflow.skipSpecConfirm" "true" "bool"
      json_set "$CONFIG_FILE" "hooks.profile" "minimal" "string"
      pass "Mode: yolo — skip confirmations, minimal hooks"
      ;;
    standard)
      json_set "$CONFIG_FILE" "workflow.skipPlanConfirm" "false" "bool"
      json_set "$CONFIG_FILE" "workflow.skipSpecConfirm" "false" "bool"
      json_set "$CONFIG_FILE" "workflow.autoVerify" "true" "bool"
      json_set "$CONFIG_FILE" "workflow.autoReview" "true" "bool"
      json_set "$CONFIG_FILE" "hooks.profile" "standard" "string"
      pass "Mode: standard — balanced workflow with auto-verify"
      ;;
    strict)
      json_set "$CONFIG_FILE" "workflow.skipPlanConfirm" "false" "bool"
      json_set "$CONFIG_FILE" "workflow.skipSpecConfirm" "false" "bool"
      json_set "$CONFIG_FILE" "workflow.autoReview" "true" "bool"
      json_set "$CONFIG_FILE" "workflow.autoVerify" "true" "bool"
      json_set "$CONFIG_FILE" "hooks.profile" "strict" "string"
      pass "Mode: strict — all gates enforced, all hooks active"
      ;;
  esac
}

EFFECTIVE_MODE="standard"

if [ -n "$MODE" ]; then
  # Non-interactive: apply the specified mode
  case "$MODE" in
    yolo|standard|strict)
      apply_mode_presets "$MODE"
      EFFECTIVE_MODE="$MODE"
      ;;
    *)
      warn "Unknown mode '$MODE' — using standard"
      apply_mode_presets "standard"
      ;;
  esac
elif [ "$NON_INTERACTIVE" = false ]; then
  # Interactive: ask user to choose mode
  echo ""
  echo -e "  ${BOLD}Choose development mode:${NC}"
  echo ""
  echo -e "    ${GREEN}1. standard${NC} (recommended)"
  echo -e "       PLAN→SPEC→BUILD→VERIFY→REVIEW workflow"
  echo -e "       Auto-verify after build, auto-review after verify"
  echo -e "       Standard hooks (skill-router, quality-gate, verify-fix-loop)"
  echo ""
  echo -e "    ${YELLOW}2. yolo${NC}"
  echo -e "       Skip plan/spec confirmations for faster iteration"
  echo -e "       Minimal hooks (session-init, session-save only)"
  echo -e "       Best for experienced devs who want speed"
  echo ""
  echo -e "    ${RED}3. strict${NC}"
  echo -e "       All confirmations required, all hooks active"
  echo -e "       Git-guard, pre/post-compact, subagent-init"
  echo -e "       Best for production codebases and teams"
  echo ""
  echo -n "  Select mode [1/2/3] (default: 1): "
  read -r mode_choice

  case "$mode_choice" in
    2|yolo)
      apply_mode_presets "yolo"
      EFFECTIVE_MODE="yolo"
      ;;
    3|strict)
      apply_mode_presets "strict"
      EFFECTIVE_MODE="strict"
      ;;
    *)
      apply_mode_presets "standard"
      EFFECTIVE_MODE="standard"
      ;;
  esac

  # --- Workflow options ---
  echo ""
  echo -e "  ${BOLD}Workflow options:${NC}"
  echo ""

  echo -n "  Auto-run /verify after BUILD? [Y/n]: "
  read -r auto_verify
  case "$auto_verify" in
    n|N|no) json_set "$CONFIG_FILE" "workflow.autoVerify" "false" "bool" ;;
    *)      json_set "$CONFIG_FILE" "workflow.autoVerify" "true" "bool" ;;
  esac

  echo -n "  Auto-run /dc-review after VERIFY? [Y/n]: "
  read -r auto_review
  case "$auto_review" in
    n|N|no) json_set "$CONFIG_FILE" "workflow.autoReview" "false" "bool" ;;
    *)      json_set "$CONFIG_FILE" "workflow.autoReview" "true" "bool" ;;
  esac

  echo -n "  Max verify retries before escalating to user [3]: "
  read -r max_retries
  if [[ "$max_retries" =~ ^[0-9]+$ ]] && [ "$max_retries" -ge 1 ] && [ "$max_retries" -le 10 ]; then
    json_set "$CONFIG_FILE" "workflow.maxRetryOnFail" "$max_retries" "number"
  else
    json_set "$CONFIG_FILE" "workflow.maxRetryOnFail" "3" "number"
  fi

  pass "Workflow options configured"

  # --- Team features ---
  echo ""
  echo -n "  Enable multi-agent team features? [y/N]: "
  read -r team_choice
  case "$team_choice" in
    y|Y|yes)
      TEAM_ENABLED=true
      json_set "$CONFIG_FILE" "team.enabled" "true" "bool"
      pass "Team features enabled"
      ;;
    *)
      json_set "$CONFIG_FILE" "team.enabled" "false" "bool"
      pass "Team features disabled"
      ;;
  esac
else
  # NON_INTERACTIVE but no MODE specified — read existing
  if command -v python3 &>/dev/null; then
    EFFECTIVE_MODE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('mode','standard'))" 2>/dev/null || echo "standard")
  fi
  pass "Using existing mode: $EFFECTIVE_MODE"
fi

# Apply team setting from flag (overrides interactive choice)
if [ "$TEAM_ENABLED" = true ]; then
  json_set "$CONFIG_FILE" "team.enabled" "true" "bool"
fi

# ---------------------------------------------------------------------------
# Step 3: Project Detection
# ---------------------------------------------------------------------------

step 3 "Project Detection"

BUILD_TOOL=$(detect_build_tool)
BUILD_TOOL_DISPLAY=$(detect_build_tool_display "$BUILD_TOOL")
pass "Build tool: $BUILD_TOOL_DISPLAY"

SPRING_TYPE=$(detect_spring_type)
pass "Spring type: $(echo "$SPRING_TYPE" | sed 's/webflux/WebFlux/;s/mvc/MVC/;s/unknown/not detected/')"

SUMMER=$(detect_summer_framework)
if [ "$SUMMER" = "true" ]; then
  pass "Summer Framework: detected"
else
  pass "Summer Framework: not detected"
fi

JAVA_VERSION=$(detect_java_version)
pass "Java version (OS): $JAVA_VERSION"

JAVA_PROJECT_VERSION=$(detect_project_java_version)
if [ -n "$JAVA_PROJECT_VERSION" ]; then
  pass "Java version (project config): $JAVA_PROJECT_VERSION"
else
  pass "Java version (project config): not detected"
fi

# Detect databases and messaging
HAS_POSTGRES=false
HAS_MYSQL=false
HAS_REDIS=false
HAS_KAFKA=false
HAS_RABBITMQ=false
HAS_DOCKER=false

{ has_dependency "postgresql" || has_dependency "r2dbc-postgresql"; } && HAS_POSTGRES=true || true
{ has_dependency "mysql" || has_dependency "r2dbc-mysql"; } && HAS_MYSQL=true || true
{ has_dependency "redis" || has_dependency "lettuce"; } && HAS_REDIS=true || true
has_dependency "kafka" && HAS_KAFKA=true || true
{ has_dependency "rabbitmq" || has_dependency "amqp"; } && HAS_RABBITMQ=true || true
{ has_dependency "testcontainers" || has_dependency "docker"; } && HAS_DOCKER=true || true

# Check for GitHub remote
HAS_GITHUB=false
if git remote -v 2>/dev/null | grep -q "github.com"; then
  HAS_GITHUB=true
fi

PROFILE_FILE="$CLAUDE_DIR/project-profile.json"

if command -v python3 &>/dev/null; then
  python3 -c "
import json

profile = {
    'version': '3.2.0',
    'buildTool': '$BUILD_TOOL',
    'springType': '$SPRING_TYPE',
    'summerFramework': $( [ \"$SUMMER\" = \"true\" ] && echo True || echo False ),
    'javaVersion': '$JAVA_VERSION',
    'javaProjectVersion': '$JAVA_PROJECT_VERSION' if '$JAVA_PROJECT_VERSION' else None,
    'dependencies': {
        'postgresql': $( $HAS_POSTGRES && echo True || echo False ),
        'mysql': $( $HAS_MYSQL && echo True || echo False ),
        'redis': $( $HAS_REDIS && echo True || echo False ),
        'kafka': $( $HAS_KAFKA && echo True || echo False ),
        'rabbitmq': $( $HAS_RABBITMQ && echo True || echo False ),
        'docker': $( $HAS_DOCKER && echo True || echo False )
    },
    'github': $( $HAS_GITHUB && echo True || echo False )
}

with open('$PROFILE_FILE', 'w') as f:
    json.dump(profile, f, indent=2)
    f.write('\n')
"
else
  cat > "$PROFILE_FILE" <<PROFILEJSON
{
  "version": "3.1.0",
  "buildTool": "$BUILD_TOOL",
  "springType": "$SPRING_TYPE",
  "summerFramework": $( [ "$SUMMER" = "true" ] && echo true || echo false ),
  "javaVersion": "$JAVA_VERSION",
  "javaProjectVersion": $([ -n "$JAVA_PROJECT_VERSION" ] && echo "\"$JAVA_PROJECT_VERSION\"" || echo "null"),
  "dependencies": {
    "postgresql": $( $HAS_POSTGRES && echo true || echo false ),
    "mysql": $( $HAS_MYSQL && echo true || echo false ),
    "redis": $( $HAS_REDIS && echo true || echo false ),
    "kafka": $( $HAS_KAFKA && echo true || echo false ),
    "rabbitmq": $( $HAS_RABBITMQ && echo true || echo false ),
    "docker": $( $HAS_DOCKER && echo true || echo false )
  },
  "github": $( $HAS_GITHUB && echo true || echo false )
}
PROFILEJSON
fi

pass "project-profile.json written"

# --- Sync detected values into devco-config.json project section ---
if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
  python3 -c "
import json

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

# Map detected spring type to config project.type
spring_map = {'webflux': 'spring-webflux', 'mvc': 'spring-mvc', 'unknown': None}
config.setdefault('project', {})
config['project']['type'] = spring_map.get('$SPRING_TYPE', None)
config['project']['useSummer'] = $( [ \"$SUMMER\" = \"true\" ] && echo True || echo False )
config['project']['stack'] = {
    'buildTool': '$BUILD_TOOL',
    'javaVersion': '$JAVA_VERSION',
    'javaProjectVersion': '$JAVA_PROJECT_VERSION' if '$JAVA_PROJECT_VERSION' else None,
    'postgresql': $( $HAS_POSTGRES && echo True || echo False ),
    'mysql': $( $HAS_MYSQL && echo True || echo False ),
    'redis': $( $HAS_REDIS && echo True || echo False ),
    'kafka': $( $HAS_KAFKA && echo True || echo False ),
    'rabbitmq': $( $HAS_RABBITMQ && echo True || echo False ),
    'docker': $( $HAS_DOCKER && echo True || echo False )
}

with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
"
  pass "devco-config.json project section synced with detected stack"
fi

# ---------------------------------------------------------------------------
# Step 4: Plugin Registration
# ---------------------------------------------------------------------------

step 4 "Plugin Registration"

SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# Ensure settings.json exists with minimal structure
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Hooks are auto-registered by Claude Code plugin system from hooks/hooks.json.
# We do NOT copy hooks into settings.json — that would cause double-registration.
# Instead, we ensure the plugin is enabled and env vars are set.

if command -v python3 &>/dev/null; then
  python3 -c "
import json

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

# Ensure enabledPlugins contains our plugin
enabled = settings.setdefault('enabledPlugins', {})
if 'devco-agent-skills@devco-agent-skills' not in enabled:
    enabled['devco-agent-skills@devco-agent-skills'] = True

# Ensure env vars for agent teams
env = settings.setdefault('env', {})
if 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' not in env:
    env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1'

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
  pass "Plugin enabled in settings.json"
  pass "Hooks auto-registered via plugin system (hooks/hooks.json)"
  pass "Agent teams env var set"
else
  # Fallback: minimal JSON manipulation
  if ! grep -q "enabledPlugins" "$SETTINGS_FILE" 2>/dev/null; then
    warn "python3 not available — manually add enabledPlugins to settings.json"
  else
    pass "Plugin already registered in settings.json"
  fi
fi

# ---------------------------------------------------------------------------
# Step 5: MCP Suggestions
# ---------------------------------------------------------------------------

step 5 "MCP Suggestions"

MCP_DIR="$PLUGIN_DIR/mcp-configs"

# Core MCPs (always recommended)
CORE_MCPS=("context7" "sequential-thinking")

# Stack-detected MCPs
SUGGESTED_MCPS=()

$HAS_POSTGRES && SUGGESTED_MCPS+=("postgres")
$HAS_REDIS && SUGGESTED_MCPS+=("redis")
$HAS_KAFKA && SUGGESTED_MCPS+=("kafka")
$HAS_DOCKER && SUGGESTED_MCPS+=("docker")
$HAS_GITHUB && SUGGESTED_MCPS+=("github")

install_mcp() {
  local name="$1"
  local config_file=""

  # Find the MCP config file
  for dir in core optional productivity; do
    if [ -f "$MCP_DIR/$dir/$name.json" ]; then
      config_file="$MCP_DIR/$dir/$name.json"
      break
    fi
  done

  if [ -z "$config_file" ]; then
    warn "$name — config not found"
    return 1
  fi

  # Extract install command from _install field
  local install_cmd
  install_cmd=$(python3 -c "
import json
with open('$config_file') as f:
    d = json.load(f)
print(d.get('_install', ''))
" 2>/dev/null || echo "")

  if [ -n "$install_cmd" ]; then
    if eval "$install_cmd" >/dev/null 2>&1; then
      pass "$name — installed"
    else
      warn "$name — install command failed (run manually: $install_cmd)"
    fi
  else
    warn "$name — no install command found in config"
  fi
}

# Install core MCPs
for mcp in "${CORE_MCPS[@]}"; do
  install_mcp "$mcp"
done

# Handle suggested MCPs
if [ ${#SUGGESTED_MCPS[@]} -gt 0 ]; then
  if [ "$NON_INTERACTIVE" = true ]; then
    # Non-interactive: just suggest, don't install
    for mcp in "${SUGGESTED_MCPS[@]}"; do
      # Find the config path for display
      for dir in core optional productivity; do
        if [ -f "$MCP_DIR/$dir/$mcp.json" ]; then
          dep_label=$(echo "$mcp" | sed 's/postgres/PostgreSQL/;s/redis/Redis/;s/kafka/Kafka/;s/docker/Docker/;s/github/GitHub/')
          warn "$dep_label detected — suggest: mcp-configs/$dir/$mcp.json"
          break
        fi
      done
    done
  else
    # Interactive: ask user
    echo ""
    echo -e "  ${BOLD}Detected stack dependencies — install MCPs?${NC}"
    for i in "${!SUGGESTED_MCPS[@]}"; do
      mcp="${SUGGESTED_MCPS[$i]}"
      dep_label=$(echo "$mcp" | sed 's/postgres/PostgreSQL/;s/redis/Redis/;s/kafka/Kafka/;s/docker/Docker/;s/github/GitHub/')
      echo -e "    $((i+1)). $dep_label ($mcp)"
    done
    echo ""
    echo -n "  Install which? (a=all, n=none, or comma-separated numbers): "
    read -r mcp_choice

    case "$mcp_choice" in
      a|A|all)
        for mcp in "${SUGGESTED_MCPS[@]}"; do
          install_mcp "$mcp"
        done
        ;;
      n|N|none|"")
        warn "Skipped optional MCPs"
        ;;
      *)
        IFS=',' read -ra selected <<< "$mcp_choice"
        for idx in "${selected[@]}"; do
          idx=$(echo "$idx" | tr -d ' ')
          if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le ${#SUGGESTED_MCPS[@]} ]; then
            install_mcp "${SUGGESTED_MCPS[$((idx-1))]}"
          fi
        done
        ;;
    esac
  fi
else
  pass "No additional MCPs suggested for detected stack"
fi

# ---------------------------------------------------------------------------
# Step 6: Validation
# ---------------------------------------------------------------------------

step 6 "Validation"

# Run CI validation
CI_OUTPUT=""
if CI_OUTPUT=$(bash "$PLUGIN_DIR/scripts/ci/run-all.sh" 2>&1); then
  # Extract pass/fail counts from output
  ci_summary=$(echo "$CI_OUTPUT" | grep "Total:" | head -1 || echo "")
  if [ -n "$ci_summary" ]; then
    pass "CI validation: $ci_summary"
  else
    pass "CI validation: all passed"
  fi
else
  warn "CI validation: some checks failed (non-blocking)"
fi

# Check all critical files
CRITICAL_PASS=0
CRITICAL_TOTAL=0

check_critical() {
  CRITICAL_TOTAL=$((CRITICAL_TOTAL + 1))
  if [ -e "$1" ]; then
    CRITICAL_PASS=$((CRITICAL_PASS + 1))
  else
    fail "Missing: $2"
  fi
}

check_critical "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
check_critical "$CLAUDE_DIR/rules" "rules/"
check_critical "$CLAUDE_DIR/memory" "memory/"
check_critical "$CLAUDE_DIR/devco-config.json" "devco-config.json"
check_critical "$CLAUDE_DIR/project-profile.json" "project-profile.json"
check_critical "$CLAUDE_DIR/settings.json" "settings.json"

if [ "$CRITICAL_PASS" -eq "$CRITICAL_TOTAL" ]; then
  pass "All critical files present ($CRITICAL_PASS/$CRITICAL_TOTAL)"
else
  warn "Some critical files missing ($CRITICAL_PASS/$CRITICAL_TOTAL)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

TEAM_LABEL="disabled"
$TEAM_ENABLED && TEAM_LABEL="enabled"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}Installation Complete!${NC}                       ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Mode: ${BOLD}$EFFECTIVE_MODE${NC} | Team: ${BOLD}$TEAM_LABEL${NC}              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Next: Run \`claude\` and try \`/dc-status\`      ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
