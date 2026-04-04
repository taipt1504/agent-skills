#!/usr/bin/env bats
# =============================================================================
# Tests for run-with-flags.sh — profile gating system
# =============================================================================

load test_helper

@test "standard profile enables quality-gate" {
  create_devco_config "standard"
  export HOOK_PROFILE="standard"
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "quality-gate" && echo "enabled"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"enabled"* ]]
}

@test "minimal profile disables quality-gate" {
  create_devco_config "minimal"
  export HOOK_PROFILE="minimal"
  # run-with-flags.sh returns 1 (or exit 0) when hook is not enabled
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "quality-gate" || echo "disabled"'
  [[ "$output" == *"disabled"* ]]
}

@test "off profile disables all hooks" {
  create_devco_config "off"
  export HOOK_PROFILE="off"
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "session-init" || echo "disabled"'
  [[ "$output" == *"disabled"* ]]
}

@test "strict profile exports STRICT_MODE=true" {
  create_devco_config "strict"
  export HOOK_PROFILE="strict"
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "quality-gate" && echo "STRICT=$STRICT_MODE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STRICT=true"* ]]
}

@test "standard profile does not set STRICT_MODE" {
  create_devco_config "standard"
  export HOOK_PROFILE="standard"
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "quality-gate" && echo "STRICT=$STRICT_MODE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STRICT=false"* ]]
}

@test "DISABLED_HOOKS disables specific hook" {
  export HOOK_PROFILE="standard"
  export DISABLED_HOOKS="quality-gate,observability-trace"
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "quality-gate" || echo "disabled"'
  [[ "$output" == *"disabled"* ]]
}

@test "minimal profile enables session-init" {
  export HOOK_PROFILE="minimal"
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "session-init" && echo "enabled"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"enabled"* ]]
}

@test "unknown profile falls back to standard" {
  export HOOK_PROFILE="nonexistent"
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "quality-gate" && echo "enabled"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"enabled"* ]]
}

@test "_json_get reads nested JSON value with python3" {
  create_devco_config "standard"
  run bash -c '
    source "$HOOK_DIR/run-with-flags.sh" "session-init"
    echo "$(_json_get "$PROJECT_ROOT/.claude/devco-config.json" "hooks" "profile")"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"standard"* ]]
}

@test "dependency detection exports _HAS_PYTHON3" {
  run bash -c 'source "$HOOK_DIR/run-with-flags.sh" "session-init" && echo "PY=$_HAS_PYTHON3"'
  [ "$status" -eq 0 ]
  # Should be true or false, not empty
  [[ "$output" =~ PY=(true|false) ]]
}
