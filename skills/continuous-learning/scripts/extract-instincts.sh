#!/usr/bin/env bash
# =============================================================================
# extract-instincts.sh — Extract learning patterns from session metrics
# =============================================================================
# Reads session-metrics.json and workflow-state.json to identify:
# - Frequently used skills (instinct candidates)
# - Common error patterns (learning opportunities)
# - Workflow deviations (process improvements)
# Usage: bash extract-instincts.sh [project-dir]
# =============================================================================
set -euo pipefail

PROJECT_DIR="${1:-.}"
METRICS_FILE="$PROJECT_DIR/.claude/session-metrics.json"
WORKFLOW_FILE="$PROJECT_DIR/.claude/workflow-state.json"
INSTINCTS_FILE="$PROJECT_DIR/.claude/instincts.json"

echo "=== Instinct Extraction ==="
echo ""

# --- 1. Skill Usage Analysis ---
echo "--- Skill Usage Frequency ---"
if [ -f "$METRICS_FILE" ]; then
  # Extract skill usage counts from metrics
  if command -v python3 &>/dev/null; then
    python3 << 'PYEOF'
import json, sys, os
from collections import Counter

metrics_file = os.environ.get('METRICS_FILE', '.claude/session-metrics.json')
try:
    with open(metrics_file) as f:
        data = json.load(f)

    skills = Counter()
    errors = Counter()
    phases = Counter()

    # Count skill activations
    for session in data.get('sessions', [data]):
        for event in session.get('events', []):
            if event.get('type') == 'skill_activated':
                skills[event.get('skill', 'unknown')] += 1
            if event.get('type') == 'error':
                errors[event.get('category', 'unknown')] += 1
            if event.get('type') == 'phase_transition':
                phases[event.get('phase', 'unknown')] += 1

    if skills:
        print("  Top skills (instinct candidates):")
        for skill, count in skills.most_common(10):
            marker = " ★ INSTINCT" if count >= 5 else ""
            print(f"    {skill}: {count} uses{marker}")
    else:
        print("  No skill usage data found")

    if errors:
        print("\n  Common errors (learning opportunities):")
        for error, count in errors.most_common(5):
            print(f"    {error}: {count} occurrences")

    if phases:
        print("\n  Phase distribution:")
        for phase, count in phases.most_common():
            print(f"    {phase}: {count} transitions")

except FileNotFoundError:
    print("  No metrics file found")
except json.JSONDecodeError:
    print("  Invalid metrics file format")
PYEOF
  else
    echo "  python3 not available — showing raw metrics"
    cat "$METRICS_FILE" 2>/dev/null | head -50 || echo "  No metrics file"
  fi
else
  echo "  No session-metrics.json found at $METRICS_FILE"
fi

# --- 2. Workflow Pattern Analysis ---
echo ""
echo "--- Workflow Patterns ---"
if [ -f "$WORKFLOW_FILE" ]; then
  if command -v python3 &>/dev/null; then
    python3 << 'PYEOF'
import json, os

workflow_file = os.environ.get('WORKFLOW_FILE', '.claude/workflow-state.json')
try:
    with open(workflow_file) as f:
        data = json.load(f)

    skips = data.get('phase_skips', [])
    retries = data.get('verify_retries', 0)
    failures = data.get('verify_failures', [])

    if skips:
        print("  Phase skips detected:")
        for skip in skips[-10:]:
            print(f"    Skipped {skip.get('phase')} — reason: {skip.get('reason', 'none')}")

    print(f"  Verify/fix retries: {retries}")

    if failures:
        print("  Recent verification failures:")
        for fail in failures[-5:]:
            print(f"    {fail.get('type', 'unknown')}: {fail.get('message', '')[:80]}")

except (FileNotFoundError, json.JSONDecodeError):
    print("  No workflow state available")
PYEOF
  else
    echo "  python3 not available"
  fi
else
  echo "  No workflow-state.json found"
fi

# --- 3. Git Pattern Analysis ---
echo ""
echo "--- Code Pattern Frequency (git history) ---"
if command -v git &>/dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  echo "  Most modified file types (last 100 commits):"
  git log --oneline -100 --diff-filter=M --name-only 2>/dev/null | \
    grep -oE '\.[a-zA-Z]+$' | sort | uniq -c | sort -rn | head -5 | \
    while read count ext; do
      echo "    $ext: $count modifications"
    done

  echo ""
  echo "  Most modified packages (last 100 commits):"
  git log --oneline -100 --diff-filter=M --name-only 2>/dev/null | \
    grep '\.java$' | sed 's|/[^/]*\.java$||' | sort | uniq -c | sort -rn | head -5 | \
    while read count pkg; do
      echo "    $pkg: $count changes"
    done
else
  echo "  Not a git repository or git not available"
fi

# --- 4. Generate Instincts Summary ---
echo ""
echo "--- Instinct Summary ---"
echo "  Instincts are skills used ≥5 times → consider auto-loading"
echo "  Learning opportunities are errors occurring ≥3 times → consider new rules"
echo "  Workflow deviations indicate process friction → consider harness adjustments"
echo ""
echo "=== Extraction Complete ==="
