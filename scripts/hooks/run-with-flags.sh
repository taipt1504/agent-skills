#!/usr/bin/env bash
# =============================================================================
# run-with-flags.sh — Profile-based hook gating system
# =============================================================================
#
# Source this file at the top of any hook script to enable profile-based gating.
# If the current hook is not enabled for the active profile, the sourcing script
# exits cleanly with code 0.
#
# Usage (in hook scripts):
#   source "$(dirname "$0")/run-with-flags.sh" "hook-name" || exit 0
#
# Environment:
#   HOOK_PROFILE  — minimal | standard (default) | strict
#
# Profiles:
#   minimal:  session-start, session-end, cost-tracker
#   standard: + suggest-compact, java-compile-check, check-debug-statements
#   strict:   + java-format, evaluate-session, pre-compact
# =============================================================================

# ---------------------------------------------------------------------------
# Self-heal CLAUDE_PLUGIN_ROOT (bug #27145: not set for SessionStart/SessionEnd)
# Derive from this script's own location: scripts/hooks/run-with-flags.sh → plugin root
# ---------------------------------------------------------------------------
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "$_SELF_DIR" ]; then
    export CLAUDE_PLUGIN_ROOT="$(cd "$_SELF_DIR/../.." 2>/dev/null && pwd)"
  fi
fi

_HOOK_NAME="${1:-}"
_HOOK_PROFILE="${HOOK_PROFILE:-standard}"

# Define which hooks are enabled per profile
case "$_HOOK_PROFILE" in
  minimal)
    _ENABLED_HOOKS="session-start session-end cost-tracker"
    ;;
  standard)
    _ENABLED_HOOKS="session-start session-end cost-tracker suggest-compact java-compile-check check-debug-statements observe"
    ;;
  strict)
    _ENABLED_HOOKS="session-start session-end cost-tracker suggest-compact java-compile-check check-debug-statements observe java-format evaluate-session pre-compact"
    ;;
  *)
    # Unknown profile — default to standard
    _ENABLED_HOOKS="session-start session-end cost-tracker suggest-compact java-compile-check check-debug-statements"
    ;;
esac

# Check if this hook is enabled
if [ -n "$_HOOK_NAME" ]; then
  _FOUND=false
  for _h in $_ENABLED_HOOKS; do
    if [ "$_h" = "$_HOOK_NAME" ]; then
      _FOUND=true
      break
    fi
  done

  if [ "$_FOUND" = false ]; then
    # Hook not enabled for this profile — exit silently
    return 1 2>/dev/null || exit 0
  fi
fi

# Hook is enabled — continue execution
return 0 2>/dev/null || true
