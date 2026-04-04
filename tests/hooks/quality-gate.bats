#!/usr/bin/env bats
# =============================================================================
# Tests for quality-gate.sh — PostToolUse code quality enforcement
# =============================================================================

load test_helper

@test "passes through non-Java files" {
  export HOOK_PROFILE="standard"
  local input='{"tool_name":"Edit","file_path":"src/main/resources/application.yml"}'
  create_java_file "$PROJECT_ROOT/src/main/resources/application.yml" "server.port: 8080"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"application.yml"* ]]
}

@test "detects System.out.println as HIGH violation" {
  export HOOK_PROFILE="standard"
  local file="$PROJECT_ROOT/src/main/java/Test.java"
  create_java_file "$file" 'public class Test { void run() { System.out.println("debug"); } }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"System.out.println"* ]]
  [[ "$output" == *"SLF4J"* ]]
}

@test "detects printStackTrace as HIGH violation" {
  export HOOK_PROFILE="standard"
  local file="$PROJECT_ROOT/src/main/java/Test.java"
  create_java_file "$file" 'public class Test { void run() { try {} catch(Exception e) { e.printStackTrace(); } } }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"printStackTrace"* ]]
}

@test "detects .block() in non-test file as CRITICAL" {
  export HOOK_PROFILE="standard"
  local file="$PROJECT_ROOT/src/main/java/Service.java"
  create_java_file "$file" 'public class Service { String run() { return Mono.just("x").block(); } }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 2 ]
  [[ "$output" == *"block"* ]]
  [[ "$output" == *"CRITICAL"* ]]
}

@test "allows .block() in test file" {
  export HOOK_PROFILE="standard"
  local file="$PROJECT_ROOT/src/test/java/ServiceTest.java"
  create_java_file "$file" 'public class ServiceTest { void test() { Mono.just("x").block(); } }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  # Should not be CRITICAL for test files
  [[ "$output" != *"CRITICAL"* ]]
}

@test "detects SELECT * as HIGH violation" {
  export HOOK_PROFILE="standard"
  local file="$PROJECT_ROOT/src/main/java/Repo.java"
  create_java_file "$file" 'public class Repo { String q = "SELECT * FROM orders"; }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SELECT *"* ]]
}

@test "detects hardcoded AWS key as CRITICAL" {
  export HOOK_PROFILE="standard"
  local file="$PROJECT_ROOT/src/main/java/Config.java"
  create_java_file "$file" 'public class Config { String key = "AKIAIOSFODNN7EXAMPLE"; }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 2 ]
  [[ "$output" == *"AWS"* ]]
}

@test "strict mode blocks HIGH violations" {
  export HOOK_PROFILE="strict"
  export STRICT_MODE="true"
  local file="$PROJECT_ROOT/src/main/java/Test.java"
  create_java_file "$file" 'public class Test { void run() { System.out.println("debug"); } }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 2 ]
  [[ "$output" == *"block"* ]]
}

@test "standard mode warns on HIGH violations (no block)" {
  export HOOK_PROFILE="standard"
  export STRICT_MODE="false"
  local file="$PROJECT_ROOT/src/main/java/Test.java"
  create_java_file "$file" 'public class Test { void run() { System.out.println("debug"); } }'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QualityGate"* ]]
}

@test "clean Java file passes without violations" {
  export HOOK_PROFILE="standard"
  local file="$PROJECT_ROOT/src/main/java/Clean.java"
  create_java_file "$file" 'import lombok.RequiredArgsConstructor;
@RequiredArgsConstructor
public class Clean {
    private final String name;
    public String getName() { return name; }
}'
  local input="{\"tool_name\":\"Edit\",\"file_path\":\"$file\"}"
  run run_hook_with_input "quality-gate.sh" "$input"
  [ "$status" -eq 0 ]
  [[ "$output" != *"CRITICAL"* ]]
  [[ "$output" != *"HIGH"* ]]
}
