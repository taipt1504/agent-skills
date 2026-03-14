#!/usr/bin/env bash
#
# Java/Gradle Format Hook
# Runs Spotless (or Google Java Format) after Java file edits
#

# Read stdin
DATA=$(cat)

# Get file path from JSON input
FILE_PATH=$(echo "$DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    echo "$DATA"
    exit 0
fi

# Check if it's a Java file
if [[ ! "$FILE_PATH" =~ \.java$ ]]; then
    echo "$DATA"
    exit 0
fi

# Try to format with Spotless (Gradle)
if [ -f "gradlew" ]; then
    ./gradlew spotlessApply -q 2>/dev/null || true
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    gradle spotlessApply -q 2>/dev/null || true
fi

echo "$DATA"
