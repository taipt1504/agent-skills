#!/usr/bin/env bats
# =============================================================================
# Tests for git-guard.sh — PreToolUse git operation blocking
# =============================================================================

load test_helper

@test "blocks git commit" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Bash","command":"git commit -m test"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 2 ]
  [[ "$output" == *"decision"*"block"* ]]
  [[ "$output" == *"GitGuard"* ]]
}

@test "blocks git push" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Bash","command":"git push origin main"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 2 ]
  [[ "$output" == *"decision"*"block"* ]]
}

@test "blocks git rebase" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Bash","command":"git rebase main"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 2 ]
  [[ "$output" == *"decision"*"block"* ]]
}

@test "blocks git reset --hard" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Bash","command":"git reset --hard HEAD"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 2 ]
  [[ "$output" == *"decision"*"block"* ]]
}

@test "allows git status" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Bash","command":"git status"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" != *"block"* ]]
}

@test "allows git diff" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Bash","command":"git diff HEAD"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" != *"block"* ]]
}

@test "allows git log" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Bash","command":"git log --oneline"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" != *"block"* ]]
}

@test "passes through non-Bash tools" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Edit","file_path":"src/Main.java"}'
  run run_hook_with_input "git-guard.sh" "$input"
  [ "$status" -eq 0 ]
}
