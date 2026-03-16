#!/usr/bin/env bash
# =============================================================================
# session-start.sh — Claude Code Session Start Hook
# =============================================================================
#
# Production-quality hook that runs when a new Claude Code session starts.
# Detects project type, loads context, integrates with claude-mem, and
# provides workflow reminders.
#
# Convention: ALL output goes to stderr (Claude Code hook standard).
# Safety:     ALWAYS exits 0 — never blocks session start.
#
# Cross-platform: macOS + Linux (bash 3.2+, no exotic deps)
# Dependencies:   git, find, grep, curl (optional, for claude-mem)
# =============================================================================

# NOTE: No set -euo pipefail — hooks must ALWAYS exit 0, so we handle errors
# explicitly at each call site (|| true). set -e would cause premature abort.

# Profile gate — exit if not enabled for current HOOK_PROFILE
source "$(dirname "$0")/run-with-flags.sh" "session-start" || exit 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# All output to stderr (Claude Code convention)
log() { echo "[SessionStart] $*" >&2; }

# Safe wrapper — catch any unexpected error so we never block session start
safe() {
  "$@" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Project root detection (works inside git worktrees)
# ---------------------------------------------------------------------------

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

PROJECT_NAME="$(basename "$(pwd)")"

log "Project: $PROJECT_NAME"
log "Root: $PROJECT_ROOT"

# ---------------------------------------------------------------------------
# 1. Detect project type
# ---------------------------------------------------------------------------

# --- Build tool ---
BUILD_TOOL="unknown"
if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  if [ -f "gradlew" ]; then
    BUILD_TOOL="Gradle Wrapper (./gradlew)"
  else
    BUILD_TOOL="Gradle"
  fi
elif [ -f "pom.xml" ]; then
  if [ -f "mvnw" ]; then
    BUILD_TOOL="Maven Wrapper (./mvnw)"
  else
    BUILD_TOOL="Maven"
  fi
fi

if [ "$BUILD_TOOL" != "unknown" ]; then
  log "Build tool: $BUILD_TOOL"
else
  log "Build tool: not detected"
fi

# --- Java version ---
if command -v java &>/dev/null; then
  JAVA_VERSION="$(java -version 2>&1 | head -1 | cut -d'"' -f2)"
  log "Java version: $JAVA_VERSION"
fi

# --- Spring framework type ---
# Check build.gradle, build.gradle.kts, and pom.xml for Spring starters
SPRING_TYPE=""
GRADLE_FILE=""
if [ -f "build.gradle" ]; then
  GRADLE_FILE="build.gradle"
elif [ -f "build.gradle.kts" ]; then
  GRADLE_FILE="build.gradle.kts"
fi

if [ -n "$GRADLE_FILE" ]; then
  if grep -q "spring-boot-starter-webflux" "$GRADLE_FILE" 2>/dev/null; then
    SPRING_TYPE="WebFlux (Reactive)"
  elif grep -q "spring-boot-starter-web" "$GRADLE_FILE" 2>/dev/null; then
    SPRING_TYPE="Spring MVC (Servlet)"
  fi
elif [ -f "pom.xml" ]; then
  if grep -q "spring-boot-starter-webflux" pom.xml 2>/dev/null; then
    SPRING_TYPE="WebFlux (Reactive)"
  elif grep -q "spring-boot-starter-web" pom.xml 2>/dev/null; then
    SPRING_TYPE="Spring MVC (Servlet)"
  fi
fi

if [ -n "$SPRING_TYPE" ]; then
  log "Spring type: $SPRING_TYPE"
fi

# --- Monorepo detection ---
# Check settings.gradle(.kts) for multiple include/includeBuild statements
SETTINGS_FILE=""
if [ -f "settings.gradle" ]; then
  SETTINGS_FILE="settings.gradle"
elif [ -f "settings.gradle.kts" ]; then
  SETTINGS_FILE="settings.gradle.kts"
fi

if [ -n "$SETTINGS_FILE" ]; then
  # Count include/includeBuild lines (Gradle multi-project)
  INCLUDE_COUNT="$(grep -cE "^\s*(include|includeBuild)\s" "$SETTINGS_FILE" 2>/dev/null || echo 0)"
  if [ "$INCLUDE_COUNT" -gt 1 ]; then
    log "Layout: Monorepo ($INCLUDE_COUNT modules in $SETTINGS_FILE)"
  fi
elif [ -f "pom.xml" ]; then
  # Maven multi-module: count <module> tags
  MODULE_COUNT="$(grep -c "<module>" pom.xml 2>/dev/null || echo 0)"
  if [ "$MODULE_COUNT" -gt 1 ]; then
    log "Layout: Monorepo ($MODULE_COUNT modules in pom.xml)"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Load project context
# ---------------------------------------------------------------------------

SESSIONS_DIR=".claude/sessions"
LEARNED_DIR=".claude/learned-skills"

# --- PROJECT_GUIDELINES.md ---
if [ -f "PROJECT_GUIDELINES.md" ]; then
  log "Project guidelines loaded"
fi

# --- Recent sessions (< 7 days) ---
if [ -d "$SESSIONS_DIR" ]; then
  # Look for both .tmp (active) and .md (completed) session files
  RECENT_SESSIONS="$(find "$SESSIONS_DIR" -maxdepth 1 \( -name "*-session.tmp" -o -name "*-session.md" \) -mtime -7 2>/dev/null | sort -r)"
  if [ -n "$RECENT_SESSIONS" ]; then
    SESSION_COUNT="$(echo "$RECENT_SESSIONS" | wc -l | tr -d ' ')"
    log "Recent sessions (< 7 days): $SESSION_COUNT"
    # List up to 5 most recent
    echo "$RECENT_SESSIONS" | head -5 | while IFS= read -r session_file; do
      log "  → $(basename "$session_file")"
    done

    # Load content from the most recent session file (for context continuity)
    LATEST_SESSION="$(echo "$RECENT_SESSIONS" | head -1)"
    if [ -n "$LATEST_SESSION" ] && [ -f "$LATEST_SESSION" ]; then
      log "--- Previous session context ($(basename "$LATEST_SESSION")) ---"
      # Limit to 80 lines to avoid flooding context
      head -80 "$LATEST_SESSION" | while IFS= read -r line; do
        echo "$line" >&2
      done
      TOTAL_LINES="$(wc -l < "$LATEST_SESSION" | tr -d ' ')"
      if [ "$TOTAL_LINES" -gt 80 ]; then
        log "... (truncated, $TOTAL_LINES total lines)"
      fi
      log "--- End previous session context ---"
    fi
  fi
fi

# --- Learned skills ---
if [ -d "$LEARNED_DIR" ]; then
  LEARNED_COUNT="$(find "$LEARNED_DIR" -maxdepth 2 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$LEARNED_COUNT" -gt 0 ]; then
    log "Learned skills: $LEARNED_COUNT available"
  fi
fi

# ---------------------------------------------------------------------------
# 3. claude-mem integration (graceful — works without it)
# ---------------------------------------------------------------------------

CLAUDE_MEM_PORT=37777
CLAUDE_MEM_URL="http://localhost:${CLAUDE_MEM_PORT}"

if command -v curl &>/dev/null; then
  # Quick connectivity check with short timeout
  if curl -sf --max-time 2 "${CLAUDE_MEM_URL}/api/health" >/dev/null 2>&1; then
    # Worker is running — query for recent project context
    MEM_RESPONSE="$(curl -sf --max-time 5 \
      "${CLAUDE_MEM_URL}/api/search?project=${PROJECT_NAME}&limit=5" 2>/dev/null || echo "")"

    if [ -n "$MEM_RESPONSE" ]; then
      # Try to extract count from JSON response.
      # Works with jq if available, falls back to grep.
      if command -v jq &>/dev/null; then
        OBS_COUNT="$(echo "$MEM_RESPONSE" | jq -r '.results | length' 2>/dev/null || echo "0")"
      else
        # Rough count: number of "id" fields in the response
        OBS_COUNT="$(echo "$MEM_RESPONSE" | grep -co '"id"' 2>/dev/null || echo "0")"
      fi
      log "claude-mem: $OBS_COUNT recent observations loaded"
    else
      log "claude-mem: connected but no observations for '$PROJECT_NAME'"
    fi
  else
    log "claude-mem: not running (standalone mode)"
  fi
else
  log "claude-mem: curl not available (standalone mode)"
fi

# ---------------------------------------------------------------------------
# 4. Git context
# ---------------------------------------------------------------------------

if git rev-parse --is-inside-work-tree &>/dev/null; then
  # Current branch
  BRANCH="$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")"
  log "Git branch: $BRANCH"

  # Uncommitted changes (staged + unstaged + untracked)
  STAGED="$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')"
  UNSTAGED="$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')"
  UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
  TOTAL_CHANGES=$(( STAGED + UNSTAGED + UNTRACKED ))

  if [ "$TOTAL_CHANGES" -gt 0 ]; then
    log "Uncommitted changes: $TOTAL_CHANGES (staged: $STAGED, unstaged: $UNSTAGED, untracked: $UNTRACKED)"
  else
    log "Working tree: clean"
  fi

  # Last commit message (short, single line)
  LAST_COMMIT="$(git log -1 --pretty=format:'%h %s' 2>/dev/null || echo "no commits")"
  log "Last commit: $LAST_COMMIT"
fi

# ---------------------------------------------------------------------------
# 5. TODO / Blockers
# ---------------------------------------------------------------------------

# Check for TODO files in common locations
TODO_FILE=""
if [ -f "TODO.md" ]; then
  TODO_FILE="TODO.md"
elif [ -f ".claude/todo.md" ]; then
  TODO_FILE=".claude/todo.md"
fi

if [ -n "$TODO_FILE" ]; then
  # Count non-empty, non-comment lines that look like active items
  # Matches: - [ ] item, * [ ] item, - item, * item, or numbered lists
  ACTIVE_ITEMS="$(grep -cE '^\s*[-*]\s+\[[ ]\]|^\s*[-*]\s+[^[]|^\s*[0-9]+\.\s+' "$TODO_FILE" 2>/dev/null || echo "0")"
  # Also count completed for context
  DONE_ITEMS="$(grep -cE '^\s*[-*]\s+\[x\]' "$TODO_FILE" 2>/dev/null || echo "0")"
  log "TODO ($TODO_FILE): $ACTIVE_ITEMS active, $DONE_ITEMS done"
fi

# Check for blockers
if [ -f "BLOCKERS.md" ]; then
  BLOCKER_COUNT="$(grep -cE '^\s*[-*]\s+' BLOCKERS.md 2>/dev/null || echo "0")"
  if [ "$BLOCKER_COUNT" -gt 0 ]; then
    log "⚠️  BLOCKERS.md: $BLOCKER_COUNT blocker(s) — review before starting!"
    # Print first 3 blockers for immediate visibility
    grep -E '^\s*[-*]\s+' BLOCKERS.md 2>/dev/null | head -3 | while IFS= read -r blocker; do
      log "  $blocker"
    done
  fi
fi

# ---------------------------------------------------------------------------
# 6. Context injection — tiered retrieval + workflow reminder
# ---------------------------------------------------------------------------

# Build context string for injection
CONTEXT=""

# --- Structured memory context (tiered retrieval, ~750 tokens max) ---
READ_CONTEXT="$(dirname "$0")/../memory/read-context.sh"
if [ -x "$READ_CONTEXT" ]; then
  MEMORY_CONTEXT="$(bash "$READ_CONTEXT" 2>/dev/null || true)"
  if [ -n "$MEMORY_CONTEXT" ]; then
    CONTEXT="## Memory Context\n\n${MEMORY_CONTEXT}\n\n"
  fi
fi

# --- Stack context ---
if [ -n "$SPRING_TYPE" ]; then
  CONTEXT="${CONTEXT}**Stack**: Java ${JAVA_VERSION:-17+} · Spring Boot 3.x · $SPRING_TYPE\n\n"
fi

# --- Project guidelines ---
if [ -f "PROJECT_GUIDELINES.md" ]; then
  CONTEXT="${CONTEXT}**Project guidelines**: \`PROJECT_GUIDELINES.md\` present — read it before starting work.\n\n"
fi

# --- Workflow reminder (compact) ---
CONTEXT="${CONTEXT}## Workflow\n\n"
CONTEXT="${CONTEXT}**Trivial** (≤5 lines, 1 file, no new behavior) → BUILD directly\n"
CONTEXT="${CONTEXT}**Non-trivial** → \`/plan\` → confirm → \`/spec\` → approve → BUILD (TDD: RED→GREEN→REFACTOR)\n\n"
CONTEXT="${CONTEXT}**Hard blocks**: No code without /plan+/spec approval · Tests first · No .block() in src/main/ · No git commit\n\n"
CONTEXT="${CONTEXT}**Commands**: /plan → /spec → /verify → /code-review → /build-fix → /checkpoint → /compact\n\n"

# --- Knowledge graph hint ---
GRAPH_FILE=".claude/memory/knowledge-graph.jsonl"
if [ -f "$GRAPH_FILE" ]; then
  GRAPH_LINES="$(wc -l < "$GRAPH_FILE" 2>/dev/null | tr -d ' ')"
  if [ "$GRAPH_LINES" -gt 0 ]; then
    CONTEXT="${CONTEXT}**Knowledge graph**: ${GRAPH_LINES} entries — use \`mcp__memory__search_nodes\` to query.\n\n"
  fi
fi

# --- Setup warning ---
if [ ! -f ".claude/CLAUDE.md" ] && ! grep -q "devco-agent-skills:start" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  CONTEXT="${CONTEXT}> ⚠️  Plugin rules not installed: Run \`/setup\` to initialize project context.\n"
fi

# --- Fallback: legacy session context (if structured memory not available) ---
if [ ! -x "$READ_CONTEXT" ] && [ -d ".claude/sessions" ]; then
  LATEST="$(find ".claude/sessions" -maxdepth 1 -name "*-session.md" -mtime -7 2>/dev/null | sort -r | head -1)"
  if [ -n "$LATEST" ] && [ -f "$LATEST" ]; then
    LEGACY_CTX="$(head -20 "$LATEST" 2>/dev/null || true)"
    CONTEXT="${CONTEXT}## Previous Session\n\n${LEGACY_CTX}\n"
  fi
fi

# Output: plain text to stdout (Claude reads as context)
# Use printf %b to expand \n sequences in CONTEXT
# Safe: all user-facing data (PROJECT_NAME, BRANCH) goes through log() to stderr, not CONTEXT
printf '%b' "$CONTEXT" 2>/dev/null || true

# Verbose diagnostics on stderr (terminal only)
log "Workflow: PLAN → BUILD (TDD) → VERIFY → REVIEW → DELIVER"
log "Run /plan before writing code"

# ---------------------------------------------------------------------------
# Done — always exit 0
# ---------------------------------------------------------------------------

log "Session started ✓"
exit 0
