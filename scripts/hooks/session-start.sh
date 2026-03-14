#!/usr/bin/env bash
#
# SessionStart Hook - Load previous context on new session
# Cross-platform (macOS, Linux)
#
# Runs when a new Claude session starts. Checks for recent session
# files and notifies Claude of available context to load.
#

# Resolve project root (works in worktrees too)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# Get directories (relative to project root)
SESSIONS_DIR=".claude/sessions"
LEARNED_DIR=".claude/learned-skills"

# Ensure directories exist
mkdir -p "$SESSIONS_DIR" "$LEARNED_DIR"

# Check for recent session files (last 7 days)
RECENT_SESSIONS=$(find "$SESSIONS_DIR" -name "*-session.tmp" -mtime -7 2>/dev/null | sort -r | head -5)
SESSION_COUNT=$(echo "$RECENT_SESSIONS" | grep -c . || echo 0)

if [ "$SESSION_COUNT" -gt 0 ]; then
    LATEST=$(echo "$RECENT_SESSIONS" | head -1)
    echo "[SessionStart] Found $SESSION_COUNT recent session(s)" >&2
    echo "[SessionStart] Latest: $LATEST" >&2
fi

# Check for learned skills
LEARNED_COUNT=$(find "$LEARNED_DIR" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

if [ "$LEARNED_COUNT" -gt 0 ]; then
    echo "[SessionStart] $LEARNED_COUNT learned skill(s) available in $LEARNED_DIR" >&2
fi

# Detect build tool (Gradle for Java projects)
if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    if [ -f "gradlew" ]; then
        echo "[SessionStart] Build tool: Gradle Wrapper (./gradlew)" >&2
    else
        echo "[SessionStart] Build tool: Gradle" >&2
    fi
elif [ -f "pom.xml" ]; then
    if [ -f "mvnw" ]; then
        echo "[SessionStart] Build tool: Maven Wrapper (./mvnw)" >&2
    else
        echo "[SessionStart] Build tool: Maven" >&2
    fi
else
    echo "[SessionStart] No Java build tool detected (Gradle/Maven)" >&2
fi

# Check Java version
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    echo "[SessionStart] Java version: $JAVA_VERSION" >&2
fi

exit 0
