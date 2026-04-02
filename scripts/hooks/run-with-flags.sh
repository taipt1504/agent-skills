#!/usr/bin/env bash
# =============================================================================
# run-with-flags.sh — Profile-based hook gating system (v3.2)
# =============================================================================
#
# Source this file at the top of any hook script to enable profile-based gating.
# If the current hook is not enabled for the active profile, the sourcing script
# exits cleanly with code 0.
#
# Usage (in hook scripts):
#   source "$(dirname "$0")/run-with-flags.sh" "hook-name" || exit 0
#
# Profile resolution (first match wins):
#   1. .claude/devco-config.json → hooks.profile
#   2. HOOK_PROFILE env var
#   3. default: "standard"
#
# Profiles (v3.2):
#   minimal:  session-init, session-save, subagent-init
#   standard: + skill-router, quality-gate, compact-advisor, git-guard,
#               pre-compact, post-compact, workflow-tracker,
#               verify-fix-loop, build-checkpoint, observability-trace
#   strict:   same as standard (all hooks active)
#
# Disable specific hooks: DISABLED_HOOKS="verify-fix-loop,observability-trace"
# =============================================================================

# Self-heal CLAUDE_PLUGIN_ROOT
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -n "$_SELF_DIR" ]; then
    export CLAUDE_PLUGIN_ROOT="$(cd "$_SELF_DIR/../.." 2>/dev/null && pwd)"
  fi
fi

_HOOK_NAME="${1:-}"

# Resolve profile: devco-config.json > HOOK_PROFILE env > "standard"
_HOOK_PROFILE=""
_DEVCO_CONFIG=".claude/devco-config.json"
if [ -z "$_HOOK_PROFILE" ] && [ -f "$_DEVCO_CONFIG" ]; then
  _HOOK_PROFILE=$(python3 -c "import json; print(json.load(open('$_DEVCO_CONFIG')).get('hooks',{}).get('profile',''))" 2>/dev/null) || true
fi
if [ -z "$_HOOK_PROFILE" ]; then
  _HOOK_PROFILE="${HOOK_PROFILE:-standard}"
fi

# Define which hooks are enabled per profile
case "$_HOOK_PROFILE" in
  minimal)
    _ENABLED_HOOKS="session-init session-save subagent-init"
    ;;
  standard)
    _ENABLED_HOOKS="session-init session-save skill-router quality-gate compact-advisor git-guard pre-compact post-compact workflow-tracker subagent-init verify-fix-loop build-checkpoint observability-trace"
    ;;
  strict)
    _ENABLED_HOOKS="session-init session-save skill-router quality-gate compact-advisor git-guard pre-compact post-compact workflow-tracker subagent-init verify-fix-loop build-checkpoint observability-trace"
    ;;
  *)
    _ENABLED_HOOKS="session-init session-save skill-router quality-gate compact-advisor git-guard pre-compact post-compact workflow-tracker subagent-init verify-fix-loop build-checkpoint observability-trace"
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
    return 1 2>/dev/null || exit 0
  fi

  # Granular disable: DISABLED_HOOKS="hook1,hook2" or devco-config.json → hooks.disabled[]
  _DISABLED="${DISABLED_HOOKS:-}"
  if [ -z "$_DISABLED" ] && [ -f "$_DEVCO_CONFIG" ]; then
    _DISABLED=$(python3 -c "import json; print(','.join(json.load(open('$_DEVCO_CONFIG')).get('hooks',{}).get('disabled',[])))" 2>/dev/null) || true
  fi
  if [ -n "$_DISABLED" ]; then
    if echo ",$_DISABLED," | grep -q ",$_HOOK_NAME,"; then
      return 1 2>/dev/null || exit 0
    fi
  fi
fi

return 0 2>/dev/null || true
