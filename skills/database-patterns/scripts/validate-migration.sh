#!/usr/bin/env bash
# =============================================================================
# validate-migration.sh — Validate Flyway/Liquibase migration files
# =============================================================================
# Checks: naming convention, no destructive DDL, no data manipulation in schema
# migrations, no SELECT *, proper index naming, and checksums.
# Usage: bash validate-migration.sh [migration-dir]
# Default dir: src/main/resources/db/migration
# =============================================================================
set -euo pipefail

MIGRATION_DIR="${1:-src/main/resources/db/migration}"
ERRORS=0
WARNINGS=0

if [ ! -d "$MIGRATION_DIR" ]; then
  echo "ERROR: Migration directory not found: $MIGRATION_DIR" >&2
  exit 1
fi

echo "=== Migration Validation ==="
echo "Directory: $MIGRATION_DIR"
echo ""

# --- 1. Naming Convention ---
echo "--- Naming Convention ---"
for f in "$MIGRATION_DIR"/*.sql; do
  [ -f "$f" ] || continue
  BASE=$(basename "$f")

  # Flyway: V{version}__{description}.sql or R__{description}.sql
  if ! echo "$BASE" | grep -qE '^(V[0-9]+(\.[0-9]+)*__[A-Za-z0-9_]+\.sql|R__[A-Za-z0-9_]+\.sql)$'; then
    echo "  WARN: Non-standard name: $BASE (expected V{n}__{desc}.sql)"
    ((WARNINGS++)) || true
  fi
done
echo "  Checked naming conventions"

# --- 2. Destructive DDL Detection ---
echo ""
echo "--- Destructive DDL Check ---"
for f in "$MIGRATION_DIR"/*.sql; do
  [ -f "$f" ] || continue
  BASE=$(basename "$f")

  # Skip repeatable migrations (R__) — they can have DROP
  echo "$BASE" | grep -q '^R__' && continue

  if grep -inE '^\s*(DROP\s+TABLE|DROP\s+COLUMN|TRUNCATE|DROP\s+INDEX)' "$f" 2>/dev/null; then
    echo "  ERROR: Destructive DDL in $BASE — use separate migration with backup strategy"
    ((ERRORS++)) || true
  fi

  if grep -inE '^\s*ALTER\s+TABLE\s+\w+\s+DROP\s+COLUMN' "$f" 2>/dev/null; then
    echo "  ERROR: DROP COLUMN in $BASE — requires two-phase migration (deprecate then drop)"
    ((ERRORS++)) || true
  fi

  if grep -inE '^\s*(DELETE\s+FROM|UPDATE\s+)' "$f" 2>/dev/null; then
    echo "  WARN: DML in schema migration $BASE — consider separate data migration"
    ((WARNINGS++)) || true
  fi
done
echo "  Checked destructive DDL"

# --- 3. SELECT * Detection ---
echo ""
echo "--- SELECT * Check ---"
for f in "$MIGRATION_DIR"/*.sql; do
  [ -f "$f" ] || continue
  if grep -inE 'SELECT\s+\*\s+FROM' "$f" 2>/dev/null; then
    echo "  WARN: SELECT * in $(basename "$f") — use explicit column list"
    ((WARNINGS++)) || true
  fi
done
echo "  Checked SELECT *"

# --- 4. Index Naming Convention ---
echo ""
echo "--- Index Naming ---"
for f in "$MIGRATION_DIR"/*.sql; do
  [ -f "$f" ] || continue
  # Check for CREATE INDEX without idx_ prefix
  while IFS= read -r line; do
    IDX_NAME=$(echo "$line" | grep -oE 'CREATE\s+(UNIQUE\s+)?INDEX\s+(IF NOT EXISTS\s+)?(\w+)' | awk '{print $NF}')
    if [ -n "$IDX_NAME" ] && ! echo "$IDX_NAME" | grep -qE '^(idx_|uq_|pk_)'; then
      echo "  WARN: Index '$IDX_NAME' in $(basename "$f") — prefer idx_/uq_/pk_ prefix"
      ((WARNINGS++)) || true
    fi
  done < <(grep -iE 'CREATE\s+(UNIQUE\s+)?INDEX' "$f" 2>/dev/null || true)
done
echo "  Checked index naming"

# --- 5. NOT NULL without DEFAULT on existing tables ---
echo ""
echo "--- NOT NULL Safety ---"
for f in "$MIGRATION_DIR"/*.sql; do
  [ -f "$f" ] || continue
  if grep -inE 'ADD\s+COLUMN\s+\w+\s+\w+.*NOT\s+NULL' "$f" 2>/dev/null | grep -ivE 'DEFAULT' > /dev/null 2>&1; then
    echo "  ERROR: ADD COLUMN NOT NULL without DEFAULT in $(basename "$f") — will fail on existing rows"
    ((ERRORS++)) || true
  fi
done
echo "  Checked NOT NULL safety"

# --- 6. Version Ordering ---
echo ""
echo "--- Version Ordering ---"
PREV_VERSION=""
for f in $(ls "$MIGRATION_DIR"/V*.sql 2>/dev/null | sort); do
  VERSION=$(basename "$f" | grep -oE '^V[0-9]+(\.[0-9]+)*' | sed 's/^V//')
  if [ -n "$PREV_VERSION" ] && [ -n "$VERSION" ]; then
    # Simple numeric comparison for single-number versions
    V_NUM=$(echo "$VERSION" | tr -d '.')
    P_NUM=$(echo "$PREV_VERSION" | tr -d '.')
    if [ "$V_NUM" -le "$P_NUM" ] 2>/dev/null; then
      echo "  ERROR: Version $VERSION is not greater than $PREV_VERSION"
      ((ERRORS++)) || true
    fi
  fi
  PREV_VERSION="$VERSION"
done
echo "  Checked version ordering"

# --- 7. File checksum report ---
echo ""
echo "--- Checksums ---"
TOTAL_FILES=0
for f in "$MIGRATION_DIR"/*.sql; do
  [ -f "$f" ] || continue
  ((TOTAL_FILES++)) || true
  MD5=$(md5sum "$f" 2>/dev/null | awk '{print $1}' || shasum "$f" | awk '{print $1}')
  printf "  %-50s %s\n" "$(basename "$f")" "$MD5"
done

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "Files scanned: $TOTAL_FILES"
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  echo "RESULT: FAIL"
  exit 1
else
  echo "RESULT: PASS"
  exit 0
fi
