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
# Profile resolution (first match wins):
#   1. .claude/devco-config.json → hooks.profile
#   2. HOOK_PROFILE env var
#   3. default: "standard"
#
# Profiles:
#   off:      No hooks enabled (fully disabled)
#   minimal:  session-init, session-save, subagent-init
#   standard: + skill-router, quality-gate, compact-advisor, git-guard,
#               pre-compact, post-compact, workflow-tracker,
#               verify-fix-loop, build-checkpoint, observability-trace,
#               workflow-gate, workflow-phase-lock
#   strict:   all standard hooks + STRICT_MODE flag (quality-gate blocks
#             on HIGH violations, not just CRITICAL; mandatory spec compliance)
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

# --- Dependency detection (shared across all hooks) ---
# Export _HAS_PYTHON3 and _HAS_JQ so downstream hooks can branch on availability
export _HAS_PYTHON3=false
export _HAS_JQ=false
command -v python3 &>/dev/null && export _HAS_PYTHON3=true
command -v jq &>/dev/null && export _HAS_JQ=true

# Helper: parse JSON field — tries python3 first, then jq, then grep fallback
# Usage: _json_get "file.json" "hooks" "profile"
_json_get() {
  local file="$1" key1="${2:-}" key2="${3:-}"
  if [ ! -f "$file" ]; then echo ""; return; fi
  if [ "$_HAS_PYTHON3" = true ]; then
    if [ -n "$key2" ]; then
      python3 -c "import json; print(json.load(open('$file')).get('$key1',{}).get('$key2',''))" 2>/dev/null || echo ""
    else
      python3 -c "import json; print(json.load(open('$file')).get('$key1',''))" 2>/dev/null || echo ""
    fi
  elif [ "$_HAS_JQ" = true ]; then
    if [ -n "$key2" ]; then
      jq -r ".$key1.$key2 // empty" "$file" 2>/dev/null || echo ""
    else
      jq -r ".$key1 // empty" "$file" 2>/dev/null || echo ""
    fi
  else
    # Fallback: basic grep (only works for simple top-level string values)
    grep -o "\"${key2:-$key1}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -1 | sed 's/.*: *"//' | sed 's/"$//' || echo ""
  fi
}

# Resolve profile: devco-config.json > HOOK_PROFILE env > "standard"
_HOOK_PROFILE=""
_DEVCO_CONFIG=".claude/devco-config.json"
if [ -z "$_HOOK_PROFILE" ] && [ -f "$_DEVCO_CONFIG" ]; then
  _HOOK_PROFILE=$(_json_get "$_DEVCO_CONFIG" "hooks" "profile")
fi
if [ -z "$_HOOK_PROFILE" ]; then
  _HOOK_PROFILE="${HOOK_PROFILE:-standard}"
fi

# Define which hooks are enabled per profile
# Export STRICT_MODE so downstream hooks (quality-gate.sh) can read it
export STRICT_MODE=false

case "$_HOOK_PROFILE" in
  off)
    _ENABLED_HOOKS=""
    ;;
  minimal)
    _ENABLED_HOOKS="session-init session-save subagent-init preflight-gate preflight-discovery workflow-gate"
    ;;
  standard)
    _ENABLED_HOOKS="session-init session-save skill-router quality-gate compact-advisor git-guard pre-compact post-compact workflow-tracker subagent-init verify-fix-loop build-checkpoint workflow-gate workflow-phase-lock preflight-gate preflight-discovery auto-adr evolution-check docs-index"
    ;;
  strict)
    _ENABLED_HOOKS="session-init session-save skill-router quality-gate compact-advisor git-guard pre-compact post-compact workflow-tracker subagent-init verify-fix-loop build-checkpoint workflow-gate workflow-phase-lock preflight-gate preflight-discovery auto-adr evolution-check docs-index"
    export STRICT_MODE=true
    ;;
  *)
    _ENABLED_HOOKS="session-init session-save skill-router quality-gate compact-advisor git-guard pre-compact post-compact workflow-tracker subagent-init verify-fix-loop build-checkpoint workflow-gate workflow-phase-lock preflight-gate preflight-discovery auto-adr evolution-check docs-index"
    ;;
esac

# --- Output cap helper (v4.1 — DEVCO_*_MAX_CHARS) ---
#
# Cap additionalContext payload size per hook. Default caps:
#   session-init:        DEVCO_SESSION_START_MAX_CHARS=8000
#   subagent-init:       DEVCO_SUBAGENT_INIT_MAX_CHARS=6000
#   preflight-gate:      DEVCO_PREFLIGHT_MAX_CHARS=4000
#   preflight-discovery: DEVCO_PREFLIGHT_MAX_CHARS=4000
#   post-compact:        DEVCO_POST_COMPACT_MAX_CHARS=3000
#
# Usage in hook:
#   CTX=$(cap_context "$CTX" "$DEFAULT_CAP" "DEVCO_<NAME>_MAX_CHARS")
#
# Env var DEVCO_HOOK_PROFILE=off disables all output (overrides _HOOK_PROFILE for caps).
cap_context() {
  local text="$1"
  local default_cap="${2:-8000}"
  local env_var="${3:-}"
  local cap="$default_cap"

  if [ -n "$env_var" ] && [ -n "${!env_var:-}" ]; then
    cap="${!env_var}"
  fi

  # Profile minimal halves the cap
  if [ "$_HOOK_PROFILE" = "minimal" ]; then
    cap=$(( cap / 2 ))
  fi

  # Strict profile allows 1.5x
  if [ "$_HOOK_PROFILE" = "strict" ]; then
    cap=$(( cap * 3 / 2 ))
  fi

  local len=${#text}
  if [ "$len" -le "$cap" ]; then
    printf '%s' "$text"
    return 0
  fi

  # Truncate with marker
  printf '%s\n\n[truncated: %d chars > cap %d. Override via %s env var.]' \
    "${text:0:$cap}" "$len" "$cap" "$env_var"
}
export -f cap_context 2>/dev/null || true

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
    if [ "$_HAS_PYTHON3" = true ]; then
      _DISABLED=$(python3 -c "import json; print(','.join(json.load(open('$_DEVCO_CONFIG')).get('hooks',{}).get('disabled',[])))" 2>/dev/null) || true
    elif [ "$_HAS_JQ" = true ]; then
      _DISABLED=$(jq -r '(.hooks.disabled // []) | join(",")' "$_DEVCO_CONFIG" 2>/dev/null) || true
    fi
  fi
  if [ -n "$_DISABLED" ]; then
    if echo ",$_DISABLED," | grep -q ",$_HOOK_NAME,"; then
      return 1 2>/dev/null || exit 0
    fi
  fi
fi

return 0 2>/dev/null || true
