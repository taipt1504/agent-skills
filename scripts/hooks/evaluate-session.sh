#!/usr/bin/env bash
#
# Continuous Learning - Session Evaluator
# Cross-platform (macOS, Linux)
#
# Runs on Stop hook to extract reusable patterns from Claude Code sessions
#
# Why Stop hook instead of UserPromptSubmit:
# - Stop runs once at session end (lightweight)
# - UserPromptSubmit runs every message (heavy, adds latency)
#

# Profile gate
source "$(dirname "$0")/run-with-flags.sh" "evaluate-session" || exit 0

# Resolve project root (works in worktrees too)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# Configuration (relative to project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="skills/continuous-learning-v2/config.json"
LEARNED_DIR=".claude/learned-skills"
MIN_SESSION_LENGTH=10

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
    if command -v jq &> /dev/null; then
        MIN_SESSION_LENGTH=$(jq -r '.min_session_length // 10' "$CONFIG_FILE" 2>/dev/null || echo 10)
        CUSTOM_PATH=$(jq -r '.learned_skills_path // empty' "$CONFIG_FILE" 2>/dev/null)
        if [ -n "$CUSTOM_PATH" ]; then
            LEARNED_DIR="${CUSTOM_PATH/#\~/$HOME}"
        fi
    fi
fi

# Ensure directory exists
mkdir -p "$LEARNED_DIR"

# Check transcript path
TRANSCRIPT_PATH="${CLAUDE_TRANSCRIPT_PATH:-}"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Count user messages in session
MESSAGE_COUNT=$(grep -c '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)

# Skip short sessions
if [ "$MESSAGE_COUNT" -lt "$MIN_SESSION_LENGTH" ]; then
    echo "[ContinuousLearning] Session too short ($MESSAGE_COUNT messages), skipping" >&2
    exit 0
fi

# Signal to Claude that session should be evaluated
echo "[ContinuousLearning] Session has $MESSAGE_COUNT messages - evaluate for extractable patterns" >&2
echo "[ContinuousLearning] Save learned skills to: $LEARNED_DIR" >&2

exit 0
