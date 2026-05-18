#!/usr/bin/env bash
# preflight-discovery.sh — enumerate available skills + rules from filesystem
#
# Output: markdown injected into agent context at PreToolUse for workflow commands.
# Does NOT decide APPLY/SKIP — that is the agent's job per doc 07.
#
# Reads filesystem, not memory. Forces fresh enumeration every gate.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

cat <<'HEADER'
## Available skills (filesystem walk — enumerate ALL, score each, justify SKIP)
HEADER

if [[ -d "$PLUGIN_ROOT/skills" ]]; then
  find "$PLUGIN_ROOT/skills" -name "SKILL.md" -type f 2>/dev/null | sort | while read -r f; do
    name=$(basename "$(dirname "$f")")
    desc=$(awk '/^description:/{flag=1; sub(/^description:[[:space:]]*/, ""); print; flag=0; exit} flag && /^[[:space:]]/{sub(/^[[:space:]]+/, " "); printf "%s", $0; if (/[.]$/) {print ""; exit}}' "$f" 2>/dev/null | head -c 200)
    echo "- **${name}**: ${desc:-<no description>}"
  done
else
  echo "_(no skills/ directory)_"
fi

# Auto-evolved skills from Tier 3 (global)
if [[ -d "$HOME/.claude/skills/auto-evolved" ]]; then
  echo ""
  echo "### Auto-evolved (Tier 3)"
  find "$HOME/.claude/skills/auto-evolved" -name "SKILL.md" -type f 2>/dev/null | sort | while read -r f; do
    name=$(basename "$(dirname "$f")")
    desc=$(awk '/^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$f" 2>/dev/null | head -c 200)
    echo "- **${name}**: ${desc:-<auto-evolved>}"
  done
fi

cat <<'HEADER'

## Available rules (enumerate ALL, score each, justify SKIP)
HEADER

# Detect Summer project — conditional load of rules/summer/
WORKSPACE="${CLAUDE_PROJECT_DIR:-$(/usr/bin/git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
PROFILE_FILE="$WORKSPACE/.claude/project-profile.json"
SUMMER_DETECTED=false
if [[ -f "$PROFILE_FILE" ]]; then
  SUMMER_VAL=$(grep -o '"summer"[[:space:]]*:[[:space:]]*[a-z]*' "$PROFILE_FILE" | head -1 | sed 's/.*: *//')
  [[ "$SUMMER_VAL" = "true" ]] && SUMMER_DETECTED=true
else
  # Fallback: scan build file
  for BUILD_FILE in build.gradle build.gradle.kts pom.xml; do
    if [[ -f "$WORKSPACE/$BUILD_FILE" ]] && grep -q "io.f8a.summer" "$WORKSPACE/$BUILD_FILE" 2>/dev/null; then
      SUMMER_DETECTED=true
      break
    fi
  done
fi

if [[ -d "$PLUGIN_ROOT/rules" ]]; then
  find "$PLUGIN_ROOT/rules" -name "*.md" -type f 2>/dev/null | sort | while read -r f; do
    rel="${f#$PLUGIN_ROOT/}"
    # Conditional: skip rules/summer/ unless Summer detected
    if [[ "$rel" == rules/summer/* ]] && [[ "$SUMMER_DETECTED" != "true" ]]; then
      continue
    fi
    first_heading=$(grep -m1 "^# " "$f" | sed 's/^#[[:space:]]*//' | head -c 120)
    echo "- **${rel}** — ${first_heading:-<no heading>}"
  done
  if [[ "$SUMMER_DETECTED" != "true" ]]; then
    echo ""
    echo "_(rules/summer/ NOT enumerated — project does not use io.f8a.summer)_"
  else
    echo ""
    echo "_(rules/summer/ enumerated — Summer detected in project profile)_"
  fi
else
  echo "_(no rules/ directory)_"
fi

# Active instincts (Tier 3)
echo ""
echo "## Active instincts (confidence ≥ 0.6)"
INSTINCTS_FILE="$HOME/.claude/instincts.jsonl"
if [[ -f "$INSTINCTS_FILE" ]]; then
  awk -F'"' '/"confidence":/{
    for(i=1;i<=NF;i++) if($i ~ /confidence/) {
      gsub(/[^0-9.]/,"",$(i+1))
      if($(i+1) >= 0.6) print
    }
  }' "$INSTINCTS_FILE" 2>/dev/null | head -20 | while read -r line; do
    echo "- $line"
  done
else
  echo "_(no instincts file)_"
fi

cat <<'FOOTER'

---
> **1% rule:** dù 1% relevance cũng phải enumerate. Score each item 0–100%. Justify every SKIP with concrete evidence (file path, missing dep, grep result). Write artifact to `.claude/memory/preflight/<gate>-<timestamp>.md` before proceeding.
FOOTER
