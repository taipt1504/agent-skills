#!/bin/bash
# Compatible with macOS bash 3.2 — no mapfile, no associative arrays.
# Verify every Summer release in the source CHANGELOG is mentioned in the version-matrix.
#
# Source of truth: $SUMMER_CHANGELOG (default points at common-libs locally — override in CI).
# Target:          skills/summer-core/references/version-matrix.md
#
# Exits non-zero when:
#   - the matrix is missing a version that appears in CHANGELOG
#   - a new version appears in matrix but no per-skill `versions/<v>.md` overlay exists
#     (warning only — exit 0 unless --strict)
#
# Usage:  scripts/ci/check-summer-version-coverage.sh [--strict] [--changelog PATH]

set -euo pipefail

SUMMER_CHANGELOG="${SUMMER_CHANGELOG:-}"
STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --changelog) SUMMER_CHANGELOG="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$SUMMER_CHANGELOG" ]]; then
  # Sensible local default — same checkout pattern most devs have.
  for candidate in \
    "$HOME/Coding/F8a/common-libs/java-common-ms/CHANGELOG.md" \
    "../common-libs/java-common-ms/CHANGELOG.md" \
    "../../common-libs/java-common-ms/CHANGELOG.md"; do
    if [[ -f "$candidate" ]]; then SUMMER_CHANGELOG="$candidate"; break; fi
  done
fi

if [[ ! -f "$SUMMER_CHANGELOG" ]]; then
  echo "ERROR: Summer CHANGELOG not found. Set SUMMER_CHANGELOG or pass --changelog PATH." >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MATRIX="$REPO_ROOT/skills/summer-core/references/version-matrix.md"

if [[ ! -f "$MATRIX" ]]; then
  echo "ERROR: $MATRIX not found." >&2; exit 2
fi

RELEASED_LIST=$(grep -E '^## Summer [0-9]+\.[0-9]+\.[0-9]+( \(Unreleased\))?$' "$SUMMER_CHANGELOG" \
  | sed -E 's/^## Summer ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
IN_MATRIX_LIST=$(grep -oE '0\.[0-9]+\.[0-9]+' "$MATRIX" | sort -u)

missing=""
for v in $RELEASED_LIST; do
  if ! printf '%s\n' "$IN_MATRIX_LIST" | grep -qx "$v"; then
    missing="$missing $v"
  fi
done

if [[ -n "$missing" ]]; then
  echo "FAIL: version-matrix.md is missing versions:$missing" >&2
  echo "Update $MATRIX (Module x version table + Headline changes section)." >&2
  exit 1
fi

# Soft check: every version in matrix should have a per-skill overlay somewhere.
overlay_warn=""
for v in $IN_MATRIX_LIST; do
  if [[ -z "$(find "$REPO_ROOT/skills" -path "*/references/versions/${v}.md" -print -quit 2>/dev/null)" ]]; then
    # Allow 0.2.x.md aggregate placeholder.
    if [[ -z "$(find "$REPO_ROOT/skills" -path "*/references/versions/0.2.x.md" -print -quit 2>/dev/null)" ]]; then
      overlay_warn="$overlay_warn $v"
    fi
  fi
done

if [[ -n "$overlay_warn" ]]; then
  echo "WARN: matrix lists these versions but no skill has a versions/<v>.md overlay:$overlay_warn" >&2
  if [[ "$STRICT" == "1" ]]; then exit 1; fi
fi

released_count=$(echo "$RELEASED_LIST" | wc -l | tr -d ' ')
warn_count=$(echo "$overlay_warn" | wc -w | tr -d ' ')
echo "OK: matrix covers ${released_count} CHANGELOG versions; ${warn_count} versions without per-skill overlay."
