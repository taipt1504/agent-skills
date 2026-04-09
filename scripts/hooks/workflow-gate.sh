#!/usr/bin/env bash
# =============================================================================
# workflow-gate.sh — PreToolUse Workflow Entry Guard (v3.3)
# =============================================================================
# Blocks production code writes (src/main/) when workflow phase is not BUILD
# or IDLE. Prevents agents from writing code before PLAN and SPEC are approved.
# Fires on: PreToolUse (Edit|Write|MultiEdit) — sync, must complete in <5s
#
# Phase rules:
#   IDLE           → allow (first-time edit before workflow starts)
#   PLAN, SPEC     → BLOCK src/main/ (spec not approved yet)
#   BUILD          → allow (correct phase for implementation)
#   VERIFY_PENDING → BLOCK src/main/ (build done, awaiting verify)
#   REVIEW_PENDING → BLOCK src/main/ (verify done, awaiting review)
#   VERIFY, REVIEW → BLOCK src/main/ (not in implementation phase)
#   COMPLETE       → allow (post-completion fixes)
#
# Skip conditions:
#   - skipCondition: true in workflow-state.json (trivial ≤5-line fixes)
#   - File is in src/test/ (always allowed)
#   - File is not a Java source file
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "workflow-gate" || exit 0

trap 'exit 0' ERR

# Read tool input from stdin
DATA=$(cat)

# Extract file path
FILE_PATH=$(echo "$DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

# Pass through if no file path
[ -z "$FILE_PATH" ] && { printf '%s' "$DATA"; exit 0; }

# Only guard Java files in src/main/ — skip everything else immediately
if [[ ! "$FILE_PATH" =~ src/main/ ]] || [[ ! "$FILE_PATH" =~ \.java$ ]]; then
  printf '%s' "$DATA"
  exit 0
fi

# Locate workflow-state.json in the target project
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
WORKFLOW_FILE="$PROJECT_ROOT/.claude/workflow-state.json"

# No workflow file → IDLE state, allow edit
if [ ! -f "$WORKFLOW_FILE" ]; then
  printf '%s' "$DATA"
  exit 0
fi

# Read current phase
CURRENT_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WORKFLOW_FILE" | head -1 | sed 's/.*: *"//' | sed 's/".*//')

# Allowed phases for src/main/ writes
case "$CURRENT_PHASE" in
  IDLE|BUILD|COMPLETE|"")
    # Explicitly allowed — pass through
    printf '%s' "$DATA"
    exit 0
    ;;
esac

# Check skipCondition — trivial fixes bypass the gate
SKIP_CONDITION=$(grep -o '"skipCondition"[[:space:]]*:[[:space:]]*[a-z]*' "$WORKFLOW_FILE" | head -1 | sed 's/.*: *//')
if [ "$SKIP_CONDITION" = "true" ]; then
  printf '%s' "$DATA"
  exit 0
fi

# Block: phase is PLAN, SPEC, VERIFY_PENDING, REVIEW_PENDING, VERIFY, or REVIEW
FILENAME="$(basename "$FILE_PATH")"
BLOCK_REASON="[WorkflowGate] BLOCKED: Cannot write production code to $FILENAME while workflow phase is '$CURRENT_PHASE'. "

case "$CURRENT_PHASE" in
  PLAN|PLAN_APPROVED)
    BLOCK_REASON="${BLOCK_REASON}PLAN phase is active — approve the plan and run /spec first."
    ;;
  SPEC|SPEC_APPROVED)
    BLOCK_REASON="${BLOCK_REASON}SPEC phase is active — approve the spec and run /build first."
    ;;
  VERIFY_PENDING)
    BLOCK_REASON="${BLOCK_REASON}BUILD is complete but VERIFY has not run. Run /verify full NOW before making more changes."
    ;;
  REVIEW_PENDING)
    BLOCK_REASON="${BLOCK_REASON}VERIFY passed but REVIEW has not run. Run /dc-review NOW before making more changes."
    ;;
  VERIFY)
    BLOCK_REASON="${BLOCK_REASON}VERIFY phase is active — complete verification before making more changes."
    ;;
  REVIEW)
    BLOCK_REASON="${BLOCK_REASON}REVIEW phase is active — complete code review before making more changes."
    ;;
  *)
    BLOCK_REASON="${BLOCK_REASON}Run /build to enter the BUILD phase before writing production code."
    ;;
esac

REASON_ESCAPED=$(printf '%s' "$BLOCK_REASON" | sed 's/"/\\"/g')
printf '{"decision":"block","reason":"%s"}' "$REASON_ESCAPED"
exit 2
