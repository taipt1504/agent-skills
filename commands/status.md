---
name: status
description: >
  Show full plugin state: detected project type, Summer Framework status, loaded skills,
  loaded rules, context usage estimate, hook profile, installation status, and git info.
---

# /status -- Plugin State & Health Check (v3.0)

Run the diagnostic script below using the Bash tool. Then format the raw output into a
clean, readable report for the user. Do NOT add commentary beyond the data.

```bash
echo ""
echo "======================================================"
echo "     @devco/agent-skills v3.0.1 -- Plugin Status       "
echo "======================================================"
echo ""

PASS="[OK]"
FAIL="[MISSING]"
WARN="[WARN]"
ALL_OK=true

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# =====================================================================
# 1. DETECTED PROJECT TYPE
# =====================================================================
echo "--- Project Type ---"

# Java version
JAVA_VER="$(java -version 2>&1 | head -1 | grep -oE '"[^"]+"' | tr -d '"' 2>/dev/null || echo "not found")"
echo "  Java version:   $JAVA_VER"

# Build tool
BUILD_TOOL="none"
if [ -f "build.gradle.kts" ]; then
  BUILD_TOOL="Gradle (Kotlin DSL)"
  BUILD_FILE="build.gradle.kts"
elif [ -f "build.gradle" ]; then
  BUILD_TOOL="Gradle (Groovy)"
  BUILD_FILE="build.gradle"
elif [ -f "pom.xml" ]; then
  BUILD_TOOL="Maven"
  BUILD_FILE="pom.xml"
fi
[ -f "gradlew" ] && BUILD_TOOL="$BUILD_TOOL + wrapper (./gradlew)"
[ -f "mvnw" ] && BUILD_TOOL="$BUILD_TOOL + wrapper (./mvnw)"
echo "  Build tool:     $BUILD_TOOL"

# Spring type
SPRING_TYPE="none"
if [ -n "${BUILD_FILE:-}" ] && [ -f "$BUILD_FILE" ]; then
  if grep -q "spring-boot-starter-webflux" "$BUILD_FILE" 2>/dev/null; then
    SPRING_TYPE="WebFlux (Reactive)"
  elif grep -q "spring-boot-starter-web" "$BUILD_FILE" 2>/dev/null; then
    SPRING_TYPE="Spring MVC (Servlet)"
  fi
fi
echo "  Spring type:    $SPRING_TYPE"
echo ""

# =====================================================================
# 2. SUMMER FRAMEWORK
# =====================================================================
echo "--- Summer Framework ---"
SUMMER_DETECTED="no"
SUMMER_VERSION="n/a"
if [ -n "${BUILD_FILE:-}" ] && [ -f "$BUILD_FILE" ]; then
  if grep -q "io.f8a.summer" "$BUILD_FILE" 2>/dev/null; then
    SUMMER_DETECTED="yes"
    if [ -f "gradle.properties" ]; then
      SUMMER_VERSION="$(grep -oE 'summerVersion\s*=\s*[0-9][0-9.]*' gradle.properties 2>/dev/null | grep -oE '[0-9][0-9.]*' || echo "unknown")"
      [ -z "$SUMMER_VERSION" ] && SUMMER_VERSION="unknown"
    fi
  fi
fi
echo "  Detected:       $SUMMER_DETECTED"
[ "$SUMMER_DETECTED" = "yes" ] && echo "  Version:        $SUMMER_VERSION"
echo ""

# =====================================================================
# 3. LOADED SKILLS (from bootstrap registry)
# =====================================================================
echo "--- Loaded Skills ---"
SKILL_COUNT=0

# Resolve plugin root
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  # Try common locations
  for candidate in \
    "$HOME/.claude/plugins/cache/devco-agent-skills" \
    "$HOME/.claude/plugins/cache/@devco/agent-skills" \
    "$(dirname "$0")/.."; do
    [ -d "$candidate/skills" ] && PLUGIN_ROOT="$candidate" && break
  done
fi

echo "  Core:"
if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/skills/bootstrap/SKILL.md" ]; then
  echo "    $PASS bootstrap (enforcement engine)"
  SKILL_COUNT=$((SKILL_COUNT + 1))
else
  echo "    $FAIL bootstrap -- NOT FOUND"
fi

echo "  Generic (Java/Spring):"
if [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_ROOT/skills" ]; then
  for skill_dir in "$PLUGIN_ROOT/skills"/*/; do
    [ -f "${skill_dir}SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    # Skip summer skills and bootstrap (handled separately)
    [[ "$skill_name" == summer-* ]] && continue
    [[ "$skill_name" == "bootstrap" ]] && continue
    echo "    $PASS $skill_name"
    SKILL_COUNT=$((SKILL_COUNT + 1))
  done
fi

echo "  Summer:"
if [ "$SUMMER_DETECTED" = "yes" ]; then
  for skill_dir in "$PLUGIN_ROOT/skills"/summer-*/; do
    [ -f "${skill_dir}SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    echo "    $PASS $skill_name"
    SKILL_COUNT=$((SKILL_COUNT + 1))
  done
else
  echo "    -- skipped (summer not detected)"
fi
echo "  Total skills:   $SKILL_COUNT"
echo ""

# =====================================================================
# 4. LOADED RULES
# =====================================================================
echo "--- Loaded Rules ---"
RULE_COUNT=0
if [ -d ".claude/rules" ]; then
  for rule in .claude/rules/*.md; do
    [ -f "$rule" ] || continue
    rule_name="$(basename "$rule")"
    echo "    $PASS $rule_name"
    RULE_COUNT=$((RULE_COUNT + 1))
  done
  echo "  Total rules:    $RULE_COUNT"
else
  echo "    $FAIL .claude/rules/ directory not found"
  echo "  Total rules:    0"
fi
echo ""

# =====================================================================
# 5. CONTEXT USAGE (estimated)
# =====================================================================
echo "--- Context Usage (estimated) ---"
CLAUDE_MD_TOKENS=0
[ -f "CLAUDE.md" ] && CLAUDE_MD_TOKENS=400
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD_TOKENS=400

SKILL_TOKENS=$((SKILL_COUNT * 800))
RULE_TOKENS=$((RULE_COUNT * 500))
BOOTSTRAP_TOKENS=1500
TOTAL_TOKENS=$((CLAUDE_MD_TOKENS + BOOTSTRAP_TOKENS + RULE_TOKENS + SKILL_TOKENS))

echo "  CLAUDE.md:         ~${CLAUDE_MD_TOKENS} tokens"
echo "  Bootstrap skill:   ~${BOOTSTRAP_TOKENS} tokens"
echo "  Skills ($SKILL_COUNT x ~800): ~${SKILL_TOKENS} tokens"
echo "  Rules  ($RULE_COUNT x ~500): ~${RULE_TOKENS} tokens"
echo "  ────────────────────────────"
echo "  Estimated total:   ~${TOTAL_TOKENS} tokens"
if [ "$TOTAL_TOKENS" -le 5000 ]; then
  echo "  Budget status:     $PASS within 5K auto-load budget"
elif [ "$TOTAL_TOKENS" -le 15000 ]; then
  echo "  Budget status:     $WARN within 15K max budget (lazy-loaded)"
else
  echo "  Budget status:     $FAIL exceeds 15K max budget"
fi
echo ""

# =====================================================================
# 6. HOOK PROFILE
# =====================================================================
echo "--- Hook Profile ---"
PROFILE="${HOOK_PROFILE:-strict}"
echo "  Active profile: $PROFILE"
case "$PROFILE" in
  minimal)
    echo "  Active hooks:   session-init, session-save"
    echo "  Disabled:       skill-router, quality-gate, compact-advisor, pre-compact"
    ;;
  standard)
    echo "  Active hooks:   session-init, session-save, skill-router, quality-gate, compact-advisor"
    echo "  Disabled:       pre-compact"
    ;;
  strict)
    echo "  Active hooks:   session-init, session-save, skill-router, quality-gate, compact-advisor, pre-compact"
    echo "  Disabled:       (none)"
    ;;
  *)
    echo "  $WARN Unknown profile -- falling back to standard"
    ;;
esac
echo ""

# =====================================================================
# 7. INSTALLATION STATUS
# =====================================================================
echo "--- Installation Status ---"
# CLAUDE.md
if [ -f "CLAUDE.md" ] || [ -f ".claude/CLAUDE.md" ]; then
  echo "  $PASS CLAUDE.md present"
else
  echo "  $FAIL CLAUDE.md not found"
  ALL_OK=false
fi

# Rules
if [ -d ".claude/rules" ] && [ "$RULE_COUNT" -gt 0 ]; then
  echo "  $PASS Rules installed ($RULE_COUNT files)"
else
  echo "  $FAIL Rules not installed"
  ALL_OK=false
fi

# Memory
if [ -d ".claude/memory" ]; then
  if [ -f ".claude/memory/sessions/index.json" ]; then
    SESSION_CT=$(python3 -c "import json; print(len(json.load(open('.claude/memory/sessions/index.json')).get('sessions',[])))" 2>/dev/null || echo "0")
    echo "  $PASS Memory initialized ($SESSION_CT sessions)"
  else
    echo "  $PASS Memory directory exists (no sessions yet)"
  fi
else
  echo "  $WARN Memory not initialized (auto-creates on first session)"
fi

# Hooks wired
if [ -f ".claude/settings.json" ] && grep -q "session-init" ".claude/settings.json" 2>/dev/null; then
  echo "  $PASS Hooks wired in .claude/settings.json"
elif [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/hooks/hooks.json" ]; then
  echo "  $PASS Hooks wired via plugin hooks.json"
else
  echo "  $FAIL Hooks not wired"
  ALL_OK=false
fi
echo ""

# =====================================================================
# 8. GIT INFO
# =====================================================================
echo "--- Git ---"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  BRANCH="$(git branch --show-current 2>/dev/null || echo "detached")"
  UNCOMMITTED="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  echo "  Branch:            $BRANCH"
  echo "  Uncommitted files: $UNCOMMITTED"
else
  echo "  $WARN Not a git repository"
fi
echo ""

# =====================================================================
# SUMMARY
# =====================================================================
echo "======================================================"
if [ "$ALL_OK" = false ]; then
  echo "  Some components missing. Run /setup to install."
else
  echo "  All components installed. Plugin is fully operational."
fi
echo "======================================================"
echo ""
```
