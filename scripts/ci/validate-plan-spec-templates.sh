#!/usr/bin/env bash
# validate-plan-spec-templates.sh — enforce template conformance for plans + specs.
# v2.0: supports BOTH single-file shape AND split (index + slices/) shape per
# threshold rule (≤2 slices = single-file, 3+ = split).
#
# Usage:
#   ./validate-plan-spec-templates.sh --plan <path>     # single-file plan OR plan index dir
#   ./validate-plan-spec-templates.sh --spec <path>     # single-file spec OR spec index dir
#   ./validate-plan-spec-templates.sh --plan <p> --spec <s>
#   ./validate-plan-spec-templates.sh --all             # scan all .claude/docs/plans/ + specs/
#
# Shape detection:
#   - path is *.md file → single-file shape (validate against PLAN_TEMPLATE.md / SPEC_TEMPLATE.md)
#   - path is directory containing index.md + slices/ → split shape (validate index + each slice + cross-refs)
#
# Exit codes:
#   0 = all artifacts conform
#   1 = at least one artifact missing required section / cross-reference
#   2 = bad invocation

set -euo pipefail

# Single-file PLAN required sections (legacy / small-feature shape)
PLAN_SINGLE_SECTIONS=(
  "^## 1\. Scope"
  "^## 2\. Affected files"
  "^## 3\. Slices"
  "^## 4\. Dependency graph"
  "^## 5\. Risk register"
  "^## 6\. Out of scope"
  "^## 7\. Execution order"
)

# Single-file SPEC required sections
SPEC_SINGLE_SECTIONS=(
  "^## 1\. Inputs"
  "^## 2\. Outputs / Side Effects"
  "^## 3\. Contracts / Invariants"
  "^## 4\. Error Cases"
  "^## 5\. Scenarios"
  "^## 6\. SDD"
  "^## 10\. Logging"
  "^## 11\. Out of scope"
  "^## 12\. References"
)

# Split-shape PLAN INDEX required sections
PLAN_INDEX_SECTIONS=(
  "^## 1\. Scope"
  "^## 2\. Affected files"
  "^## 3\. Slice index"
  "^## 4\. Dependency graph"
  "^## 5\. Risk register"
  "^## 6\. Out of scope"
  "^## 7\. Execution order"
)

# Split-shape PLAN SLICE required sections
PLAN_SLICE_SECTIONS=(
  "^## 1\. Description"
  "^## 2\. Files touched"
  "^## 3\. Skills required"
  "^## 4\. Rules required"
  "^## 5\. Rationale"
  "^## 6\. Estimated effort"
)

# Split-shape SPEC INDEX required sections
SPEC_INDEX_SECTIONS=(
  "^## 1\. Cross-cutting"
  "^### 1\.1 Inputs"
  "^### 1\.4 Logging"
  "^### 1\.5 Error envelope"
  "^## 2\. Slice index"
  "^## 3\. Out of scope"
  "^## 4\. References"
)

# Split-shape SPEC SLICE required sections
SPEC_SLICE_SECTIONS=(
  "^## 0\. Cross-cutting reference"
  "^## 1\. Inputs"
  "^## 2\. Outputs / Side Effects"
  "^## 3\. Contracts / Invariants"
  "^## 4\. Error Cases"
  "^## 5\. Scenarios"
  "^## 6\. SDD"
)

# Frontmatter keys per shape
PLAN_SINGLE_FM=("^status:" "^feature:" "^service:" "^lane:" "^created:" "^phase:")
SPEC_SINGLE_FM=("^status:" "^feature:" "^service:" "^lane:" "^plan:" "^created:" "^phase:")
PLAN_INDEX_FM=("^status:" "^feature:" "^service:" "^lane:" "^slice_count:" "^slice_decomposition:" "^created:" "^phase:")
PLAN_SLICE_FM=("^slice_id:" "^slice_title:" "^parent_plan:" "^status:" "^risk:" "^complexity:")
SPEC_INDEX_FM=("^status:" "^feature:" "^service:" "^lane:" "^slice_count:" "^slice_decomposition:" "^plan:" "^created:" "^phase:")
SPEC_SLICE_FM=("^slice_id:" "^slice_title:" "^parent_spec:" "^parent_plan_slice:" "^status:" "^scenario_count:")

errors=0

extract_frontmatter() {
  /usr/bin/awk '/^---$/{if (++c == 1) next; if (c == 2) exit; print}' "$1"
}

check_frontmatter() {
  local file="$1"
  local label="$2"
  shift 2
  local keys=("$@")
  local fm
  fm=$(extract_frontmatter "$file")
  if [[ -z "$fm" ]]; then
    echo "FAIL ${label} ${file} — no frontmatter" >&2
    errors=$((errors + 1))
    return
  fi
  for key in "${keys[@]}"; do
    if ! echo "$fm" | /usr/bin/grep -qE "$key"; then
      echo "FAIL ${label} ${file} — missing frontmatter key: ${key}" >&2
      errors=$((errors + 1))
    fi
  done
}

check_sections() {
  local file="$1"
  local label="$2"
  shift 2
  local sections=("$@")
  for section in "${sections[@]}"; do
    if ! /usr/bin/grep -qE "$section" "$file"; then
      echo "FAIL ${label} ${file} — missing section: ${section}" >&2
      errors=$((errors + 1))
    fi
  done
}

validate_single_file_plan() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL plan-single ${file} — file not found" >&2
    errors=$((errors + 1))
    return
  fi
  check_frontmatter "$file" "plan-single" "${PLAN_SINGLE_FM[@]}"
  check_sections "$file" "plan-single" "${PLAN_SINGLE_SECTIONS[@]}"
  [[ $errors -eq 0 ]] && echo "OK   plan-single ${file}" >&2
}

validate_single_file_spec() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL spec-single ${file} — file not found" >&2
    errors=$((errors + 1))
    return
  fi
  check_frontmatter "$file" "spec-single" "${SPEC_SINGLE_FM[@]}"
  check_sections "$file" "spec-single" "${SPEC_SINGLE_SECTIONS[@]}"
  [[ $errors -eq 0 ]] && echo "OK   spec-single ${file}" >&2
}

validate_plan_index() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL plan-index ${file} — file not found" >&2
    errors=$((errors + 1))
    return
  fi
  check_frontmatter "$file" "plan-index" "${PLAN_INDEX_FM[@]}"
  check_sections "$file" "plan-index" "${PLAN_INDEX_SECTIONS[@]}"
}

validate_plan_slice() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL plan-slice ${file} — file not found" >&2
    errors=$((errors + 1))
    return
  fi
  check_frontmatter "$file" "plan-slice" "${PLAN_SLICE_FM[@]}"
  check_sections "$file" "plan-slice" "${PLAN_SLICE_SECTIONS[@]}"
}

validate_spec_index() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL spec-index ${file} — file not found" >&2
    errors=$((errors + 1))
    return
  fi
  check_frontmatter "$file" "spec-index" "${SPEC_INDEX_FM[@]}"
  check_sections "$file" "spec-index" "${SPEC_INDEX_SECTIONS[@]}"
}

validate_spec_slice() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL spec-slice ${file} — file not found" >&2
    errors=$((errors + 1))
    return
  fi
  check_frontmatter "$file" "spec-slice" "${SPEC_SLICE_FM[@]}"
  check_sections "$file" "spec-slice" "${SPEC_SLICE_SECTIONS[@]}"
  # Cross-cutting override check: if "Cross-cutting override" section present, must reference an ADR
  if /usr/bin/grep -qE "^### Cross-cutting override" "$file"; then
    if ! /usr/bin/grep -qE "ADR-[0-9]+" "$file"; then
      echo "FAIL spec-slice ${file} — Cross-cutting override present but no ADR reference (ADR-NNNN)" >&2
      errors=$((errors + 1))
    fi
  fi
}

# Cross-reference check: every slice file listed in index AND every file in slices/ listed in index
validate_split_cross_refs() {
  local index="$1"
  local slices_dir="$2"
  local label="$3"

  if [[ ! -d "$slices_dir" ]]; then
    echo "FAIL ${label} ${index} — slices/ directory missing" >&2
    errors=$((errors + 1))
    return
  fi

  # Slice files listed in index — extract links matching slices/NN-*.md
  local indexed
  indexed=$(/usr/bin/grep -oE "slices/[0-9]+-[a-z0-9-]+\.md" "$index" 2>/dev/null | /usr/bin/sort -u || true)

  # Actual files on disk
  local actual
  actual=$(/usr/bin/find "$slices_dir" -name "*.md" -type f -maxdepth 1 2>/dev/null | /usr/bin/sed "s|.*/slices/|slices/|" | /usr/bin/sort -u)

  # Files on disk NOT in index
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if ! echo "$indexed" | /usr/bin/grep -qF "$file"; then
      echo "FAIL ${label} ${index} — file ${file} exists but not listed in index" >&2
      errors=$((errors + 1))
    fi
  done <<<"$actual"

  # Files in index NOT on disk
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if ! echo "$actual" | /usr/bin/grep -qF "$file"; then
      echo "FAIL ${label} ${index} — index references ${file} but file missing" >&2
      errors=$((errors + 1))
    fi
  done <<<"$indexed"
}

validate_plan_path() {
  local path="$1"
  if [[ -f "$path" ]]; then
    # Single-file shape
    validate_single_file_plan "$path"
  elif [[ -d "$path" ]]; then
    # Split shape — expect index.md + slices/
    local index="$path/index.md"
    local slices="$path/slices"
    validate_plan_index "$index"
    validate_split_cross_refs "$index" "$slices" "plan-index"
    if [[ -d "$slices" ]]; then
      while IFS= read -r slice_file; do
        validate_plan_slice "$slice_file"
      done < <(/usr/bin/find "$slices" -name "*.md" -type f -maxdepth 1 2>/dev/null)
    fi
    [[ $errors -eq 0 ]] && echo "OK   plan-split ${path}" >&2
  else
    echo "FAIL plan ${path} — not file or directory" >&2
    errors=$((errors + 1))
  fi
}

validate_spec_path() {
  local path="$1"
  if [[ -f "$path" ]]; then
    validate_single_file_spec "$path"
  elif [[ -d "$path" ]]; then
    local index="$path/index.md"
    local slices="$path/slices"
    validate_spec_index "$index"
    validate_split_cross_refs "$index" "$slices" "spec-index"
    if [[ -d "$slices" ]]; then
      while IFS= read -r slice_file; do
        validate_spec_slice "$slice_file"
      done < <(/usr/bin/find "$slices" -name "*.md" -type f -maxdepth 1 2>/dev/null)
    fi
    [[ $errors -eq 0 ]] && echo "OK   spec-split ${path}" >&2
  else
    echo "FAIL spec ${path} — not file or directory" >&2
    errors=$((errors + 1))
  fi
}

main() {
  local plan_path="" spec_path="" scan_all=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan) plan_path="$2"; shift 2 ;;
      --spec) spec_path="$2"; shift 2 ;;
      --all) scan_all=true; shift ;;
      *) echo "Usage: $0 [--plan <path>] [--spec <path>] [--all]" >&2; exit 2 ;;
    esac
  done

  if [[ "$scan_all" = true ]]; then
    local workspace="${CLAUDE_PROJECT_DIR:-$(/usr/bin/git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    local plans_dir="$workspace/.claude/docs/plans"
    local specs_dir="$workspace/.claude/docs/specs"

    if [[ -d "$plans_dir" ]]; then
      # Top-level .md files = single-file plans
      while IFS= read -r f; do
        validate_single_file_plan "$f"
      done < <(/usr/bin/find "$plans_dir" -name "*.md" -type f -maxdepth 1 2>/dev/null)
      # Top-level dirs with index.md = split plans
      while IFS= read -r d; do
        [[ -f "$d/index.md" ]] && validate_plan_path "$d"
      done < <(/usr/bin/find "$plans_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    fi

    if [[ -d "$specs_dir" ]]; then
      while IFS= read -r f; do
        validate_single_file_spec "$f"
      done < <(/usr/bin/find "$specs_dir" -name "*.md" -type f -maxdepth 1 2>/dev/null)
      while IFS= read -r d; do
        [[ -f "$d/index.md" ]] && validate_spec_path "$d"
      done < <(/usr/bin/find "$specs_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    fi
  fi

  [[ -n "$plan_path" ]] && validate_plan_path "$plan_path"
  [[ -n "$spec_path" ]] && validate_spec_path "$spec_path"

  if [[ -z "$plan_path" && -z "$spec_path" && "$scan_all" != true ]]; then
    echo "Usage: $0 [--plan <path>] [--spec <path>] [--all]" >&2
    exit 2
  fi

  if [[ $errors -gt 0 ]]; then
    echo "" >&2
    echo "Template conformance FAILED: ${errors} error(s)" >&2
    echo "Templates: templates/{PLAN,SPEC}_TEMPLATE.md (single-file) OR templates/{PLAN,SPEC}_{INDEX,SLICE}_TEMPLATE.md (split)" >&2
    exit 1
  fi

  echo "Template conformance PASSED" >&2
  exit 0
}

main "$@"
