#!/usr/bin/env bash
# Initialize structured memory directory for a project (v3.0)
# 3-tier: L1 (session), L2 (project), L3 (knowledge/optional)
set -euo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MEMORY_DIR="$PROJECT_ROOT/.claude/memory"

# L1: Session storage (last 5, auto-prune)
mkdir -p "$MEMORY_DIR/sessions"

# L2: Project-level persistent knowledge
mkdir -p "$MEMORY_DIR/knowledge"
mkdir -p "$MEMORY_DIR/context"

# Initialize index if not exists
if [ ! -f "$MEMORY_DIR/sessions/index.json" ]; then
  echo '{"sessions":[]}' > "$MEMORY_DIR/sessions/index.json"
fi

# Initialize knowledge files if not exists
for f in decisions.json patterns.json blockers.json; do
  if [ ! -f "$MEMORY_DIR/knowledge/$f" ]; then
    echo '{"entries":[]}' > "$MEMORY_DIR/knowledge/$f"
  fi
done

# Debug knowledge base (v3.0) — resolved debug patterns
if [ ! -f "$MEMORY_DIR/debug-knowledge.md" ]; then
  cat > "$MEMORY_DIR/debug-knowledge.md" <<'EOF'
# Debug Knowledge Base

Resolved debug patterns from past sessions. Check here before investigating from scratch.

<!-- Format: ## Error Pattern → Resolution (date) -->
EOF
fi

# Initialize context files
if [ ! -f "$MEMORY_DIR/context/project-state.json" ]; then
  cat > "$MEMORY_DIR/context/project-state.json" <<EOF
{
  "project": "$(basename "$PROJECT_ROOT")",
  "initialized_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "tech_stack": [],
  "active_branch": ""
}
EOF
fi

if [ ! -f "$MEMORY_DIR/context/active-work.json" ]; then
  echo '{"current_task":"","started_at":"","notes":[]}' > "$MEMORY_DIR/context/active-work.json"
fi

# Config (v3.0)
if [ ! -f "$MEMORY_DIR/config.json" ]; then
  cat > "$MEMORY_DIR/config.json" <<'EOF'
{
  "version": "3.0",
  "max_sessions_retained": 5,
  "session_retention_days": 30,
  "token_budget": {
    "tier0_index": 50,
    "tier1_context": 200,
    "tier2_full": 500,
    "max_total": 750
  },
  "auto_prune": true
}
EOF
fi

# Auto-prune: keep only last 5 session JSON files (sorted by name = date order)
if [ -d "$MEMORY_DIR/sessions" ]; then
  PRUNE_FILES=$(find "$MEMORY_DIR/sessions" -name "*.json" -not -name "index.json" -not -name "config.json" 2>/dev/null | sort -r | tail -n +6)
  if [ -n "$PRUNE_FILES" ]; then
    echo "$PRUNE_FILES" | while IFS= read -r f; do
      [ -n "$f" ] && rm -f "$f" 2>/dev/null || true
    done
  fi
fi

echo "Memory directory initialized: $MEMORY_DIR"
