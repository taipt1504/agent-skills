#!/usr/bin/env python3
"""Migration v4.0 → v4.1: flat memory → lifecycle hierarchy.

Reorganizes existing flat .claude/memory/ into per-feature dirs under active/.
Generates pointers.json + index.json. Backs up original to v4.0-backup/.

Usage:
    python3 scripts/migration/reorganize-memory.py [--workspace .] [--dry-run]

Idempotent. Safe re-run.
"""
import argparse
import json
import re
import shutil
from datetime import datetime
from pathlib import Path


def extract_feature_slug(filename: str) -> str:
    """Heuristic feature slug from artifact filename.

    Examples:
        plan-1747391500.md → unknown-1747391500
        2026-05-15-pagination.md → 2026-05-pagination
        execute-1747391100.md → unknown-1747391100
    """
    stem = Path(filename).stem
    m = re.match(r"^(\d{4}-\d{2})-?\d{0,2}-?(.+)$", stem)
    if m:
        return f"{m.group(1)}-{m.group(2)}"
    return f"unknown-{stem}"


def migrate(workspace: Path, dry_run: bool = False) -> int:
    memory = workspace / ".claude" / "memory"
    if not memory.is_dir():
        print(f"ERR: no .claude/memory/ at {workspace}")
        return 1

    backup = workspace / ".claude" / "memory" / "v4.0-backup"
    active = memory / "active"
    shared = memory / "shared"

    # Sources to migrate
    preflight_dir = memory / "preflight"
    align_dir = memory / "align-artifacts"
    brainstorm_dir = memory / "brainstorm-artifacts"
    state_dir = memory / "state"

    features: dict[str, dict] = {}

    # Group preflight artifacts by inferred feature slug
    if preflight_dir.is_dir():
        for f in preflight_dir.glob("*.md"):
            slug = extract_feature_slug(f.name)
            features.setdefault(slug, {"preflight": [], "align": [], "brainstorm": [], "state": []})
            features[slug]["preflight"].append(f)

    if align_dir.is_dir():
        for f in align_dir.glob("*.md"):
            slug = extract_feature_slug(f.name)
            features.setdefault(slug, {"preflight": [], "align": [], "brainstorm": [], "state": []})
            features[slug]["align"].append(f)

    if brainstorm_dir.is_dir():
        for f in brainstorm_dir.glob("*.md"):
            slug = extract_feature_slug(f.name)
            features.setdefault(slug, {"preflight": [], "align": [], "brainstorm": [], "state": []})
            features[slug]["brainstorm"].append(f)

    if not features:
        print("No legacy flat artifacts found — nothing to migrate")
        return 0

    print(f"Found {len(features)} feature(s) to reorganize:")
    for slug in sorted(features.keys()):
        print(f"  - {slug}")

    if dry_run:
        print("\nDry-run mode — no changes made")
        return 0

    # Backup
    if not backup.exists():
        backup.mkdir(parents=True)
    for src in [preflight_dir, align_dir, brainstorm_dir]:
        if src.is_dir():
            dest = backup / src.name
            if not dest.exists():
                shutil.copytree(src, dest)

    # Migrate per-feature
    for slug, sources in features.items():
        feature_dir = active / slug
        feature_dir.mkdir(parents=True, exist_ok=True)
        (feature_dir / "preflight").mkdir(exist_ok=True)

        # Move preflight artifacts
        for f in sources["preflight"]:
            shutil.move(str(f), str(feature_dir / "preflight" / f.name))

        # Move align (take latest if multiple)
        if sources["align"]:
            latest = sorted(sources["align"], key=lambda p: p.stat().st_mtime)[-1]
            shutil.move(str(latest), str(feature_dir / "align.md"))
            for extra in sources["align"]:
                if extra.exists():
                    extra.unlink()

        # Move brainstorm (take latest)
        if sources["brainstorm"]:
            latest = sorted(sources["brainstorm"], key=lambda p: p.stat().st_mtime)[-1]
            shutil.move(str(latest), str(feature_dir / "brainstorm.md"))
            for extra in sources["brainstorm"]:
                if extra.exists():
                    extra.unlink()

        # Write meta.json
        meta = {
            "feature_id": slug,
            "status": "active",
            "lane": "unknown",
            "created": datetime.utcnow().isoformat() + "Z",
            "last_touched": datetime.utcnow().isoformat() + "Z",
            "migrated_from": "v4.0 flat",
        }
        (feature_dir / "meta.json").write_text(json.dumps(meta, indent=2))

    # Build pointers + index
    pointers = {
        "active_features": list(features.keys()),
        "primary": list(features.keys())[0] if features else None,
        "last_switched": datetime.utcnow().isoformat() + "Z",
    }
    (memory / "pointers.json").write_text(json.dumps(pointers, indent=2))

    index = {
        "version": 1,
        "features": {
            slug: {
                "title": slug.replace("-", " "),
                "lane": "unknown",
                "status": "active",
                "created": datetime.utcnow().isoformat() + "Z",
                "last_touched": datetime.utcnow().isoformat() + "Z",
                "path": f".claude/memory/active/{slug}",
            }
            for slug in features.keys()
        },
    }
    (memory / "index.json").write_text(json.dumps(index, indent=2))

    # Move global state files to shared/
    if state_dir.is_dir():
        for f in state_dir.glob("*.json"):
            if f.name in ("current-triage.json", "workflow-state.json"):
                # Move to primary feature
                primary = pointers["primary"]
                if primary:
                    primary_dir = active / primary
                    dest = primary_dir / f.name.replace("current-", "")
                    shutil.move(str(f), str(dest))
            else:
                shutil.move(str(f), str(shared / f.name))

    print(f"\nMigration complete:")
    print(f"  Features migrated: {len(features)}")
    print(f"  Primary feature: {pointers['primary']}")
    print(f"  Backup: {backup}")
    print(f"  Pointers: {memory}/pointers.json")
    print(f"  Index: {memory}/index.json")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--workspace", type=Path, default=Path.cwd())
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    return migrate(args.workspace, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
