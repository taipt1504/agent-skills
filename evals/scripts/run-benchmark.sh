#!/usr/bin/env bash
# =============================================================================
# run-benchmark.sh — Run full benchmark suite for devco-agent-skills plugin
# =============================================================================
# Runs eval tasks with and without plugin, scores each session, aggregates results.
#
# Usage:
#   bash evals/scripts/run-benchmark.sh [options]
#
# Options:
#   --tasks "01 02 03"    Run specific tasks (space-separated IDs, default: all)
#   --runs N              Runs per task per config (default: 1)
#   --with-only           Only run with-plugin config
#   --without-only        Only run without-plugin config
#   --model MODEL         Model to use (default: user's configured model)
#   --timeout N           Timeout per task in seconds (default: 600)
#   --project-dir DIR     Target project to run tasks against
#   --output-dir DIR      Output directory (default: evals/results/YYYY-MM-DD/)
#
# Prerequisites:
#   - claude CLI installed and authenticated
#   - Target project with build.gradle/pom.xml
# =============================================================================
set -euo pipefail

# Defaults
TASKS=""
RUNS=1
CONFIG="both"  # both, with, without
MODEL=""
TIMEOUT=600
PROJECT_DIR=""
OUTPUT_DIR=""
PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVALS_DIR="$PLUGIN_DIR/evals"
SCRIPTS_DIR="$EVALS_DIR/scripts"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --tasks) TASKS="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --with-only) CONFIG="with"; shift ;;
    --without-only) CONFIG="without"; shift ;;
    --model) MODEL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate
if [ -z "$PROJECT_DIR" ]; then
  echo "ERROR: --project-dir is required (path to target Spring Boot project)" >&2
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' CLI not found. Install Claude Code first." >&2
  exit 1
fi

# Setup output directory
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
OUTPUT_DIR="${OUTPUT_DIR:-$EVALS_DIR/results/$TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

echo "============================================"
echo "  devco-agent-skills Benchmark Runner"
echo "============================================"
echo "Plugin:     $PLUGIN_DIR"
echo "Project:    $PROJECT_DIR"
echo "Output:     $OUTPUT_DIR"
echo "Config:     $CONFIG"
echo "Runs/task:  $RUNS"
echo "Timeout:    ${TIMEOUT}s"
echo ""

# Discover tasks
TASK_FILES=()
if [ -n "$TASKS" ]; then
  for id in $TASKS; do
    found=$(find "$EVALS_DIR/tasks" -name "*${id}*" -type f | head -1)
    if [ -n "$found" ]; then
      TASK_FILES+=("$found")
    else
      echo "WARN: Task '$id' not found, skipping"
    fi
  done
else
  while IFS= read -r f; do
    TASK_FILES+=("$f")
  done < <(find "$EVALS_DIR/tasks" -name "*.md" -type f | sort)
fi

echo "Tasks: ${#TASK_FILES[@]}"
echo ""

# Extract prompt from task file (macOS + Linux compatible)
extract_prompt() {
  local task_file="$1"
  python3 -c "
import re, sys
content = open(sys.argv[1]).read()
match = re.search(r'## Prompt\s*\n+\s*\`\`\`\s*\n(.*?)\n\s*\`\`\`', content, re.DOTALL)
if match:
    print(match.group(1).strip())
else:
    # Fallback: extract everything between ## Prompt and next ##
    match = re.search(r'## Prompt\s*\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
    if match:
        text = match.group(1).strip()
        text = re.sub(r'^\`\`\`.*\n?', '', text)
        text = re.sub(r'\n?\`\`\`\s*$', '', text)
        print(text)
" "$task_file"
}

# Run a single eval
run_eval() {
  local task_file="$1"
  local config="$2"  # with_plugin or without_plugin
  local run_num="$3"
  local task_id=$(basename "$task_file" .md)

  local run_dir="$OUTPUT_DIR/$task_id/$config/run-$run_num"
  mkdir -p "$run_dir"

  local prompt
  prompt=$(extract_prompt "$task_file")

  echo "  [$config] Run $run_num: $task_id"

  local cmd=("claude" "-p" "$prompt" "--output-format" "json" "--verbose")

  if [ "$config" = "without_plugin" ]; then
    # Run without plugin by not including plugin path
    cmd+=("--no-user-config")
  fi

  if [ -n "$MODEL" ]; then
    cmd+=("--model" "$MODEL")
  fi

  # Remove CLAUDECODE env to allow nesting
  local start_time
  start_time=$(date +%s)

  # macOS: use gtimeout (brew install coreutils) or fallback to no timeout
  local timeout_cmd=""
  if command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout $TIMEOUT"
  elif command -v timeout &>/dev/null; then
    timeout_cmd="timeout $TIMEOUT"
  fi

  env -u CLAUDECODE $timeout_cmd "${cmd[@]}" \
    > "$run_dir/output.json" 2> "$run_dir/stderr.log" || true

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Save timing
  cat > "$run_dir/timing.json" << TJSON
{
  "total_duration_seconds": $duration,
  "task_id": "$task_id",
  "config": "$config",
  "run": $run_num,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
TJSON

  # Score the session
  if [ -f "$SCRIPTS_DIR/score-session.py" ]; then
    python3 "$SCRIPTS_DIR/score-session.py" \
      --project-dir "$PROJECT_DIR" \
      --task-file "$task_file" \
      --task-id "$task_id" \
      --output "$run_dir/session-score.json" \
      2>/dev/null || echo "  WARN: scoring failed for $task_id/$config/run-$run_num"
  fi

  echo "    Done (${duration}s)"
}

# Main benchmark loop
TOTAL_RUNS=0
COMPLETED=0

for task_file in "${TASK_FILES[@]}"; do
  task_id=$(basename "$task_file" .md)
  echo "--- $task_id ---"

  for run_num in $(seq 1 "$RUNS"); do
    if [ "$CONFIG" = "both" ] || [ "$CONFIG" = "with" ]; then
      run_eval "$task_file" "with_plugin" "$run_num"
      ((TOTAL_RUNS++))
    fi
    if [ "$CONFIG" = "both" ] || [ "$CONFIG" = "without" ]; then
      run_eval "$task_file" "without_plugin" "$run_num"
      ((TOTAL_RUNS++))
    fi
  done
  echo ""
done

# Aggregate results
echo "============================================"
echo "  Aggregating Results"
echo "============================================"

if [ -f "$SCRIPTS_DIR/aggregate-scores.py" ]; then
  python3 "$SCRIPTS_DIR/aggregate-scores.py" \
    --results-dir "$OUTPUT_DIR" \
    --output "$OUTPUT_DIR/benchmark-report.json" || true
fi

echo ""
echo "============================================"
echo "  Benchmark Complete"
echo "============================================"
echo "Total runs: $TOTAL_RUNS"
echo "Results:    $OUTPUT_DIR"

if [ -f "$OUTPUT_DIR/benchmark-report.md" ]; then
  echo ""
  cat "$OUTPUT_DIR/benchmark-report.md"
fi
