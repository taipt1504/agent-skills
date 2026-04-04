#!/usr/bin/env bash
# =============================================================================
# test_helper.bash — Shared test utilities for bats hook tests
# =============================================================================

# Setup: create temp directory, set environment
setup() {
  export TEST_DIR="$(mktemp -d)"
  export HOOK_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")"/../../scripts/hooks && pwd)"
  export PROJECT_ROOT="$TEST_DIR/project"
  mkdir -p "$PROJECT_ROOT/.claude"
  cd "$PROJECT_ROOT"

  # Default env vars
  export HOOK_PROFILE="standard"
  export DISABLED_HOOKS=""
  export STRICT_MODE="false"
}

# Teardown: clean temp directory
teardown() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Helper: create a minimal devco-config.json
create_devco_config() {
  local profile="${1:-standard}"
  cat > "$PROJECT_ROOT/.claude/devco-config.json" << EOF
{
  "hooks": { "profile": "$profile" },
  "traces": { "retentionDays": 7 }
}
EOF
}

# Helper: create a minimal Java file
create_java_file() {
  local path="$1"
  local content="${2:-public class Test {}}"
  mkdir -p "$(dirname "$path")"
  echo "$content" > "$path"
}

# Helper: create a minimal build.gradle
create_build_gradle() {
  cat > "$PROJECT_ROOT/build.gradle" << 'EOF'
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.2.0'
}
EOF
}

# Helper: pipe JSON tool input to a hook script
run_hook_with_input() {
  local hook="$1"
  local input="$2"
  echo "$input" | bash "$HOOK_DIR/$hook"
}

# Helper: create tool input JSON
tool_input_json() {
  local file_path="${1:-}"
  local tool_name="${2:-Edit}"
  cat << EOF
{"tool_name":"$tool_name","file_path":"$file_path"}
EOF
}
