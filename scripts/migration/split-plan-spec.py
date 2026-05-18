#!/usr/bin/env python3
"""Migration: convert single-file plan/spec into split (index + slices/) shape.

Triggers on user request only — not automatic. Existing artifacts opt-in.

Usage:
    python3 scripts/migration/split-plan-spec.py --plan <path-to-plan.md>
    python3 scripts/migration/split-plan-spec.py --spec <path-to-spec.md>
    python3 scripts/migration/split-plan-spec.py --feature <feature-slug>   # both

Output:
    Single-file plan `.claude/docs/plans/<feature>.md`
    →
    Split plan `.claude/docs/plans/<feature>/index.md` + `slices/<NN>-<slug>.md`

The original single-file is renamed to `<feature>.md.pre-split-backup` for safety.
User MUST review the generated split shape — auto-extraction is best-effort.
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

SLICE_HEADING_RE = re.compile(r"^###\s+Slice\s+(\d+)[:\s—-]+(.+?)$", re.MULTILINE)


def slugify(title: str) -> str:
    """Convert slice title to kebab-case slug."""
    s = title.lower()
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"\s+", "-", s.strip())
    s = re.sub(r"-+", "-", s)
    return s[:50]  # cap length


def extract_frontmatter(text: str) -> tuple[str, str]:
    """Return (frontmatter_body_without_fences, rest_of_doc)."""
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
    if not m:
        return "", text
    return m.group(1), m.group(2)


def split_plan(plan_path: Path) -> None:
    text = plan_path.read_text(encoding="utf-8")
    fm, body = extract_frontmatter(text)

    # Locate § 3. Slices section
    slices_section_match = re.search(
        r"^##\s+3\.\s+Slices?\s*$", body, re.MULTILINE)
    if not slices_section_match:
        print(f"ERR: {plan_path} has no §3. Slices section", file=sys.stderr)
        sys.exit(1)

    # Locate § 4 onwards (everything after slices)
    next_section_match = re.search(
        r"^##\s+4\.\s+", body[slices_section_match.end():], re.MULTILINE)
    if not next_section_match:
        print(f"ERR: {plan_path} has no §4. Dependency graph", file=sys.stderr)
        sys.exit(1)

    slices_text = body[slices_section_match.end():
                       slices_section_match.end() + next_section_match.start()]
    rest_of_doc = body[slices_section_match.end() + next_section_match.start():]

    # Extract each slice
    slice_matches = list(SLICE_HEADING_RE.finditer(slices_text))
    if len(slice_matches) < 3:
        print(f"NOTE: {plan_path} has only {len(slice_matches)} slices — threshold is 3+. "
              "Keeping single-file shape. No migration needed.", file=sys.stderr)
        return

    feature_slug = plan_path.stem  # filename without .md
    parent_dir = plan_path.parent
    new_dir = parent_dir / feature_slug
    slices_dir = new_dir / "slices"

    if new_dir.exists():
        print(f"ERR: target dir {new_dir} already exists. Aborting.", file=sys.stderr)
        sys.exit(1)

    slices_dir.mkdir(parents=True, exist_ok=True)

    slice_info: list[dict] = []
    for i, sm in enumerate(slice_matches):
        slice_id_str = sm.group(1).zfill(2)
        title = sm.group(2).strip()
        slug = slugify(title)

        start = sm.end()
        end = slice_matches[i + 1].start() if i + 1 < len(slice_matches) else len(slices_text)
        slice_body = slices_text[start:end].strip()

        slice_file = slices_dir / f"{slice_id_str}-{slug}.md"
        slice_content = f"""---
slice_id: {slice_id_str}
slice_title: {title}
parent_plan: ../index.md
status: DRAFT
risk: TODO (migration — review needed)
complexity: TODO (migration — review needed)
depends_on: []
blocks: []
service: TODO
---

# Slice {slice_id_str} — {title}

> **Auto-migrated from single-file plan {plan_path.name}. Review required.**

## 1. Description

TODO — extract from migrated body below.

## 2. Files touched

TODO — extract from migrated body.

## 3. Skills required

TODO — list from pre-flight 2 APPLY.

## 4. Rules required

TODO — list from pre-flight 2 APPLY.

## 5. Rationale

TODO — extract from migrated body.

## 6. Estimated effort

TODO

---

## Migrated body (review + redistribute into sections above)

{slice_body}
"""
        slice_file.write_text(slice_content)
        slice_info.append({
            "id": slice_id_str,
            "title": title,
            "slug": slug,
            "file": f"slices/{slice_id_str}-{slug}.md",
        })

    # Build index.md
    slice_index_rows = "\n".join(
        f"| {s['id']} | [{s['file']}]({s['file']}) | {s['title']} | TODO | TODO | DRAFT |"
        for s in slice_info
    )

    index_content = f"""---
{fm}
slice_count: {len(slice_info)}
slice_decomposition: split
---

# Plan — {plan_path.stem.replace('-', ' ').title()} (MIGRATED)

> **Auto-migrated from {plan_path.name}. Review required.**
> **Original preserved:** `{plan_path.name}.pre-split-backup`

---

## 1. Scope

TODO — copy from original §1.

## 2. Affected files (aggregate)

TODO — aggregate from per-slice files.

## 3. Slice index

| # | Slice file | Title | Risk | Complexity | Status |
|---|---|---|---|---|---|
{slice_index_rows}

## 4. Dependency graph

TODO — extract from original.

{rest_of_doc}
"""
    (new_dir / "index.md").write_text(index_content)

    # Backup original
    backup = plan_path.with_suffix(plan_path.suffix + ".pre-split-backup")
    shutil.move(str(plan_path), str(backup))

    print(f"OK: split {plan_path} → {new_dir}/", file=sys.stderr)
    print(f"   slices: {len(slice_info)}", file=sys.stderr)
    print(f"   backup: {backup}", file=sys.stderr)
    print(f"   REVIEW REQUIRED: every slice file has TODO markers to fill in.", file=sys.stderr)


def split_spec(spec_path: Path) -> None:
    text = spec_path.read_text(encoding="utf-8")
    fm, body = extract_frontmatter(text)

    # Look for "## Slice N" or "### Slice N" patterns in spec scenarios
    slice_matches = list(re.finditer(
        r"^#{2,3}\s+Slice\s+(\d+)[:\s—-]+(.+?)$", body, re.MULTILINE))

    if len(slice_matches) < 3:
        print(f"NOTE: {spec_path} has only {len(slice_matches)} slice sections. "
              "Threshold is 3+. Keeping single-file.", file=sys.stderr)
        return

    feature_slug = spec_path.stem
    parent_dir = spec_path.parent
    new_dir = parent_dir / feature_slug
    slices_dir = new_dir / "slices"

    if new_dir.exists():
        print(f"ERR: target dir {new_dir} already exists. Aborting.", file=sys.stderr)
        sys.exit(1)

    slices_dir.mkdir(parents=True, exist_ok=True)

    # Build slice files
    slice_info: list[dict] = []
    for i, sm in enumerate(slice_matches):
        slice_id_str = sm.group(1).zfill(2)
        title = sm.group(2).strip()
        slug = slugify(title)
        start = sm.end()
        end = slice_matches[i + 1].start() if i + 1 < len(slice_matches) else len(body)
        slice_body = body[start:end].strip()

        slice_file = slices_dir / f"{slice_id_str}-{slug}.md"
        slice_content = f"""---
slice_id: {slice_id_str}
slice_title: {title}
parent_spec: ../index.md
parent_plan_slice: ../../plans/{feature_slug}/slices/{slice_id_str}-{slug}.md
status: DRAFT
scenario_count: TODO
service: TODO
---

# Spec Slice {slice_id_str} — {title}

> **Auto-migrated from single-file spec {spec_path.name}. Review required.**

## 0. Cross-cutting reference

Cross-cutting concerns inherited from `../index.md §1`. Override forbidden w/o ADR.

## 1. Inputs (slice-specific)

TODO — extract from migrated body.

## 2. Outputs / Side Effects (slice-specific)

TODO

## 3. Contracts / Invariants (slice-specific)

TODO

## 4. Error Cases (slice-specific)

TODO

## 5. Scenarios

TODO — extract from migrated body.

## 6. SDD ↔ TDD mapping

TODO

---

## Migrated body (review + redistribute)

{slice_body}
"""
        slice_file.write_text(slice_content)
        slice_info.append({
            "id": slice_id_str,
            "title": title,
            "slug": slug,
            "file": f"slices/{slice_id_str}-{slug}.md",
        })

    slice_index_rows = "\n".join(
        f"| {s['id']} | [{s['file']}]({s['file']}) | {s['title']} | TODO | DRAFT |"
        for s in slice_info
    )

    index_content = f"""---
{fm}
slice_count: {len(slice_info)}
slice_decomposition: split
---

# Spec — {spec_path.stem.replace('-', ' ').title()} (MIGRATED)

> **Auto-migrated from {spec_path.name}. Review required.**
> **Original preserved:** `{spec_path.name}.pre-split-backup`

---

## 1. Cross-cutting (applies to ALL slices)

### 1.1 Inputs (common)
TODO

### 1.2 Auth
TODO

### 1.3 Idempotency
TODO

### 1.4 Logging (MDC mandatory)
TODO

### 1.5 Error envelope (RFC 7807)
TODO

### 1.6 Performance budget
TODO

## 2. Slice index

| # | Slice spec file | Title | Scenarios | Status |
|---|---|---|---|---|
{slice_index_rows}

## 3. Out of scope (aggregate)
TODO

## 4. References
TODO
"""
    (new_dir / "index.md").write_text(index_content)
    backup = spec_path.with_suffix(spec_path.suffix + ".pre-split-backup")
    shutil.move(str(spec_path), str(backup))

    print(f"OK: split {spec_path} → {new_dir}/", file=sys.stderr)
    print(f"   slices: {len(slice_info)}", file=sys.stderr)
    print(f"   backup: {backup}", file=sys.stderr)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--plan", type=Path, help="Path to single-file plan.md")
    p.add_argument("--spec", type=Path, help="Path to single-file spec.md")
    p.add_argument("--feature", type=str,
                   help="Feature slug — splits both plan + spec in .claude/docs/")
    args = p.parse_args()

    if not (args.plan or args.spec or args.feature):
        p.print_help()
        return 2

    if args.feature:
        workspace = Path.cwd()
        plan_path = workspace / ".claude/docs/plans" / f"{args.feature}.md"
        spec_path = workspace / ".claude/docs/specs" / f"{args.feature}.md"
        if plan_path.exists():
            split_plan(plan_path)
        if spec_path.exists():
            split_spec(spec_path)
        return 0

    if args.plan:
        split_plan(args.plan)
    if args.spec:
        split_spec(args.spec)

    return 0


if __name__ == "__main__":
    sys.exit(main())
