#!/usr/bin/env bats
# =============================================================================
# skill-triggers.bats — Verify all skills have required frontmatter fields
# =============================================================================

SKILLS_DIR=""

setup() {
  SKILLS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../skills" && pwd)"
}

@test "all skills have SKILL.md" {
  local missing=0
  for dir in "$SKILLS_DIR"/*/; do
    local name="$(basename "$dir")"
    [ "$name" = "_shared" ] && continue
    if [ ! -f "$dir/SKILL.md" ]; then
      echo "Missing SKILL.md: $name"
      ((missing++))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "all skills have name in frontmatter" {
  local missing=0
  for skill in "$SKILLS_DIR"/*/SKILL.md; do
    if ! head -20 "$skill" | grep -q '^name:'; then
      echo "Missing name: $skill"
      ((missing++))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "all skills have description in frontmatter" {
  local missing=0
  for skill in "$SKILLS_DIR"/*/SKILL.md; do
    if ! head -20 "$skill" | grep -q '^description:'; then
      echo "Missing description: $skill"
      ((missing++))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "all non-bootstrap skills have triggers" {
  local missing=0
  for skill in "$SKILLS_DIR"/*/SKILL.md; do
    local name="$(basename "$(dirname "$skill")")"
    [ "$name" = "bootstrap" ] && continue
    [ "$name" = "continuous-learning" ] && continue
    if ! head -20 "$skill" | grep -q '^triggers:'; then
      echo "Missing triggers: $name"
      ((missing++))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "summer skills have requires field" {
  local missing=0
  for skill in "$SKILLS_DIR"/summer-*/SKILL.md; do
    local name="$(basename "$(dirname "$skill")")"
    if ! head -20 "$skill" | grep -q '^requires:'; then
      echo "Missing requires: $name"
      ((missing++))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "summer sub-skills require summer-core" {
  local missing=0
  for skill in "$SKILLS_DIR"/summer-*/SKILL.md; do
    local name="$(basename "$(dirname "$skill")")"
    [ "$name" = "summer-core" ] && continue
    if ! head -20 "$skill" | grep -q 'summer-core'; then
      echo "Missing summer-core dependency: $name"
      ((missing++))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "no duplicate skill names" {
  local names=""
  local dupes=0
  for skill in "$SKILLS_DIR"/*/SKILL.md; do
    local name=$(head -20 "$skill" | grep '^name:' | sed 's/name: *//')
    if echo "$names" | grep -q "^${name}$"; then
      echo "Duplicate: $name"
      ((dupes++))
    fi
    names="$names
$name"
  done
  [ "$dupes" -eq 0 ]
}

@test "skill trigger keywords are non-empty" {
  local empty=0
  for skill in "$SKILLS_DIR"/*/SKILL.md; do
    local name="$(basename "$(dirname "$skill")")"
    [ "$name" = "bootstrap" ] && continue
    [ "$name" = "continuous-learning" ] && continue
    # Check that triggers.natural has at least one entry
    if head -20 "$skill" | grep -q 'natural: \[\]'; then
      echo "Empty natural triggers: $name"
      ((empty++))
    fi
  done
  [ "$empty" -eq 0 ]
}

@test "deployment-patterns skill exists" {
  [ -f "$SKILLS_DIR/deployment-patterns/SKILL.md" ]
}

@test "grpc-patterns skill exists" {
  [ -f "$SKILLS_DIR/grpc-patterns/SKILL.md" ]
}
