#!/usr/bin/env bash
#
# Stop Hook: Check for debug statements in modified Java files
# Cross-platform (macOS, Linux)
#
# This hook runs after each response and checks if any modified
# Java files contain debug statements (System.out.println, e.printStackTrace).
# It provides warnings to help developers remember to remove
# debug statements before committing.
#

# Read stdin (if any)
DATA=$(cat)

# Check if we're in a git repository
if ! git rev-parse --git-dir &> /dev/null; then
    echo "$DATA"
    exit 0
fi

# Get list of modified Java files
FILES=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(java)$' || true)

HAS_DEBUG=false

# Check each file for debug statements
for FILE in $FILES; do
    if [ -f "$FILE" ]; then
        # Check for System.out.println
        if grep -q 'System\.out\.println\|System\.err\.println' "$FILE" 2>/dev/null; then
            echo "[Hook] WARNING: System.out.println found in $FILE" >&2
            HAS_DEBUG=true
        fi
        
        # Check for e.printStackTrace()
        if grep -q '\.printStackTrace()' "$FILE" 2>/dev/null; then
            echo "[Hook] WARNING: e.printStackTrace() found in $FILE" >&2
            HAS_DEBUG=true
        fi
        
        # Check for @Disabled tests (might be intentional but worth warning)
        if grep -q '@Disabled' "$FILE" 2>/dev/null; then
            echo "[Hook] INFO: @Disabled test found in $FILE" >&2
        fi
    fi
done

if [ "$HAS_DEBUG" = true ]; then
    echo "[Hook] Remove debug statements before committing. Use proper logging (SLF4J/Logback) instead." >&2
fi

# Output original data
echo "$DATA"
