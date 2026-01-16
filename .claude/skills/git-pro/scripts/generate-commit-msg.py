#!/usr/bin/env python3
"""
Git Commit Message Generator

Analyzes staged changes and generates optimal commit messages
following Conventional Commits specification.

Usage:
    python generate-commit-msg.py              # Generate message
    python generate-commit-msg.py --analyze    # Analyze only, no message
    python generate-commit-msg.py --type feat  # Force specific type
    python generate-commit-msg.py --scope api  # Force specific scope
    python generate-commit-msg.py --interactive # Interactive mode

Requirements:
    - Git repository with staged changes
    - Python 3.8+

Examples:
    python generate-commit-msg.py
    python generate-commit-msg.py --analyze
    python generate-commit-msg.py --type fix --scope auth
"""

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class ChangeAnalysis:
    """Analysis of staged changes."""
    files_added: list[str]
    files_modified: list[str]
    files_deleted: list[str]
    files_renamed: list[tuple[str, str]]
    total_insertions: int
    total_deletions: int
    file_types: dict[str, int]
    directories: set[str]
    is_docs_only: bool
    is_tests_only: bool
    is_config_only: bool
    has_breaking_changes: bool
    detected_type: str
    detected_scope: Optional[str]


def run_git_command(args: list[str]) -> str:
    """Run a git command and return output."""
    try:
        result = subprocess.run(
            ['git'] + args,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        if e.returncode == 128:
            print("Error: Not a git repository", file=sys.stderr)
            sys.exit(1)
        return ""


def get_staged_files() -> list[tuple[str, str]]:
    """Get list of staged files with their status."""
    output = run_git_command(['diff', '--cached', '--name-status'])
    if not output:
        return []

    files = []
    for line in output.split('\n'):
        if line:
            parts = line.split('\t')
            status = parts[0]
            if status.startswith('R'):
                # Rename: R100\told\tnew
                files.append((status, f"{parts[1]} -> {parts[2]}"))
            else:
                files.append((status[0], parts[1]))
    return files


def get_diff_stats() -> tuple[int, int]:
    """Get total insertions and deletions."""
    output = run_git_command(['diff', '--cached', '--shortstat'])
    insertions = 0
    deletions = 0

    if output:
        match = re.search(r'(\d+) insertion', output)
        if match:
            insertions = int(match.group(1))
        match = re.search(r'(\d+) deletion', output)
        if match:
            deletions = int(match.group(1))

    return insertions, deletions


def get_diff_content() -> str:
    """Get full diff content for analysis."""
    return run_git_command(['diff', '--cached'])


def analyze_changes() -> ChangeAnalysis:
    """Analyze staged changes."""
    files = get_staged_files()
    insertions, deletions = get_diff_stats()
    diff_content = get_diff_content()

    files_added = []
    files_modified = []
    files_deleted = []
    files_renamed = []

    for status, filepath in files:
        if status == 'A':
            files_added.append(filepath)
        elif status == 'M':
            files_modified.append(filepath)
        elif status == 'D':
            files_deleted.append(filepath)
        elif status.startswith('R'):
            # Parse "old -> new"
            if ' -> ' in filepath:
                old, new = filepath.split(' -> ')
                files_renamed.append((old, new))

    # Analyze file types
    all_files = files_added + files_modified + [f[1] for f in files_renamed]
    file_types: dict[str, int] = {}
    directories: set[str] = set()

    for f in all_files:
        # File type
        ext = Path(f).suffix.lower() or 'no-extension'
        file_types[ext] = file_types.get(ext, 0) + 1

        # Directory
        parts = Path(f).parts
        if len(parts) > 1:
            directories.add(parts[0])
            if len(parts) > 2:
                directories.add(f"{parts[0]}/{parts[1]}")

    # Detect special cases
    doc_extensions = {'.md', '.txt', '.rst', '.doc', '.docx'}
    test_patterns = ['test', 'spec', '__tests__', 'tests']
    config_extensions = {'.json', '.yaml', '.yml', '.toml', '.ini', '.env'}

    is_docs_only = all(Path(f).suffix.lower() in doc_extensions for f in all_files) if all_files else False
    is_tests_only = all(any(p in f.lower() for p in test_patterns) for f in all_files) if all_files else False
    is_config_only = all(Path(f).suffix.lower() in config_extensions for f in all_files) if all_files else False

    # Detect breaking changes
    has_breaking_changes = False
    breaking_patterns = [
        r'BREAKING',
        r'removed.*export',
        r'renamed.*function',
        r'changed.*interface',
        r'removed.*parameter'
    ]
    for pattern in breaking_patterns:
        if re.search(pattern, diff_content, re.IGNORECASE):
            has_breaking_changes = True
            break

    # Detect type
    detected_type = detect_commit_type(
        files_added, files_modified, files_deleted, files_renamed,
        insertions, deletions, is_docs_only, is_tests_only, is_config_only
    )

    # Detect scope
    detected_scope = detect_scope(directories, all_files)

    return ChangeAnalysis(
        files_added=files_added,
        files_modified=files_modified,
        files_deleted=files_deleted,
        files_renamed=files_renamed,
        total_insertions=insertions,
        total_deletions=deletions,
        file_types=file_types,
        directories=directories,
        is_docs_only=is_docs_only,
        is_tests_only=is_tests_only,
        is_config_only=is_config_only,
        has_breaking_changes=has_breaking_changes,
        detected_type=detected_type,
        detected_scope=detected_scope
    )


def detect_commit_type(
    added: list, modified: list, deleted: list, renamed: list,
    insertions: int, deletions: int,
    is_docs: bool, is_tests: bool, is_config: bool
) -> str:
    """Detect the most appropriate commit type."""

    # Priority checks
    if is_docs:
        return 'docs'
    if is_tests:
        return 'test'
    if is_config:
        return 'chore'

    # New files = likely feat
    if added and not modified and not deleted:
        return 'feat'

    # Only deletions = might be refactor or chore
    if deleted and not added and not modified:
        return 'refactor'

    # Renames = refactor
    if renamed and not added:
        return 'refactor'

    # Small changes to existing files = likely fix
    if modified and not added:
        if insertions + deletions < 20:
            return 'fix'
        elif deletions > insertions:
            return 'refactor'

    # Mix of changes
    if added and modified:
        return 'feat'

    # Default
    return 'feat' if insertions > deletions else 'fix'


def detect_scope(directories: set[str], files: list[str]) -> Optional[str]:
    """Detect the most appropriate scope."""

    # Common scope mappings
    scope_mappings = {
        'src/auth': 'auth',
        'src/api': 'api',
        'src/ui': 'ui',
        'src/core': 'core',
        'src/utils': 'utils',
        'src/components': 'ui',
        'src/services': 'service',
        'lib': 'lib',
        'tests': 'test',
        'docs': 'docs',
        'config': 'config',
    }

    for dir_path, scope in scope_mappings.items():
        if any(f.startswith(dir_path) for f in files):
            return scope

    # Use first directory as scope
    if directories:
        first_dir = sorted(directories)[0]
        # Clean up scope
        scope = first_dir.replace('src/', '').replace('lib/', '')
        if len(scope) < 15:
            return scope

    return None


def generate_subject(analysis: ChangeAnalysis, commit_type: str, scope: Optional[str]) -> str:
    """Generate commit subject line."""

    # Build prefix
    if scope:
        prefix = f"{commit_type}({scope}): "
    else:
        prefix = f"{commit_type}: "

    # Generate description based on changes
    if analysis.files_added and not analysis.files_modified:
        if len(analysis.files_added) == 1:
            filename = Path(analysis.files_added[0]).stem
            return f"{prefix}add {filename}"
        return f"{prefix}add {len(analysis.files_added)} new files"

    if analysis.files_deleted and not analysis.files_added:
        if len(analysis.files_deleted) == 1:
            filename = Path(analysis.files_deleted[0]).stem
            return f"{prefix}remove {filename}"
        return f"{prefix}remove {len(analysis.files_deleted)} files"

    if analysis.files_renamed:
        old, new = analysis.files_renamed[0]
        return f"{prefix}rename {Path(old).name} to {Path(new).name}"

    if analysis.is_docs_only:
        return f"{prefix}update documentation"

    if analysis.is_tests_only:
        return f"{prefix}update tests"

    if analysis.is_config_only:
        return f"{prefix}update configuration"

    # Generic based on file count
    total_files = len(analysis.files_added) + len(analysis.files_modified)
    if total_files == 1:
        filename = (analysis.files_added + analysis.files_modified)[0]
        action = "add" if analysis.files_added else "update"
        return f"{prefix}{action} {Path(filename).stem}"

    return f"{prefix}update {total_files} files"


def generate_body(analysis: ChangeAnalysis) -> Optional[str]:
    """Generate commit body if needed."""

    # Only generate body for significant changes
    if analysis.total_insertions + analysis.total_deletions < 20:
        return None

    lines = []

    if analysis.files_added:
        lines.append("Added:")
        for f in analysis.files_added[:5]:
            lines.append(f"- {f}")
        if len(analysis.files_added) > 5:
            lines.append(f"- ... and {len(analysis.files_added) - 5} more")

    if analysis.files_modified:
        lines.append("\nModified:")
        for f in analysis.files_modified[:5]:
            lines.append(f"- {f}")
        if len(analysis.files_modified) > 5:
            lines.append(f"- ... and {len(analysis.files_modified) - 5} more")

    if analysis.files_deleted:
        lines.append("\nRemoved:")
        for f in analysis.files_deleted[:5]:
            lines.append(f"- {f}")

    return '\n'.join(lines) if lines else None


def generate_footer(analysis: ChangeAnalysis) -> Optional[str]:
    """Generate commit footer if needed."""
    if analysis.has_breaking_changes:
        return "BREAKING CHANGE: This commit contains breaking changes."
    return None


def format_commit_message(subject: str, body: Optional[str], footer: Optional[str]) -> str:
    """Format the full commit message."""
    parts = [subject]

    if body:
        parts.append("")
        parts.append(body)

    if footer:
        parts.append("")
        parts.append(footer)

    return '\n'.join(parts)


def print_analysis(analysis: ChangeAnalysis):
    """Print analysis results."""
    print("\n" + "=" * 60)
    print("STAGED CHANGES ANALYSIS")
    print("=" * 60)

    print(f"\nFiles Added:    {len(analysis.files_added)}")
    print(f"Files Modified: {len(analysis.files_modified)}")
    print(f"Files Deleted:  {len(analysis.files_deleted)}")
    print(f"Files Renamed:  {len(analysis.files_renamed)}")
    print(f"\nInsertions: +{analysis.total_insertions}")
    print(f"Deletions:  -{analysis.total_deletions}")

    print(f"\nFile Types:")
    for ext, count in sorted(analysis.file_types.items(), key=lambda x: -x[1]):
        print(f"  {ext}: {count}")

    print(f"\nDirectories: {', '.join(sorted(analysis.directories)) or 'root'}")

    print(f"\nDetected Type: {analysis.detected_type}")
    print(f"Detected Scope: {analysis.detected_scope or 'none'}")

    if analysis.is_docs_only:
        print("\n[!] Documentation only changes")
    if analysis.is_tests_only:
        print("\n[!] Test only changes")
    if analysis.is_config_only:
        print("\n[!] Configuration only changes")
    if analysis.has_breaking_changes:
        print("\n[!] Potential BREAKING CHANGES detected")


def main():
    parser = argparse.ArgumentParser(description='Generate optimal git commit messages')
    parser.add_argument('--analyze', action='store_true', help='Only analyze, do not generate message')
    parser.add_argument('--type', help='Force commit type (feat, fix, docs, etc.)')
    parser.add_argument('--scope', help='Force commit scope')
    parser.add_argument('--no-body', action='store_true', help='Generate subject only')
    parser.add_argument('--interactive', '-i', action='store_true', help='Interactive mode')

    args = parser.parse_args()

    # Check for staged changes
    staged = get_staged_files()
    if not staged:
        print("No staged changes. Use 'git add' to stage changes first.", file=sys.stderr)
        sys.exit(1)

    # Analyze
    analysis = analyze_changes()

    if args.analyze:
        print_analysis(analysis)
        sys.exit(0)

    # Determine type and scope
    commit_type = args.type or analysis.detected_type
    scope = args.scope or analysis.detected_scope

    # Interactive mode
    if args.interactive:
        print_analysis(analysis)
        print("\n" + "-" * 60)

        user_type = input(f"Commit type [{commit_type}]: ").strip()
        if user_type:
            commit_type = user_type

        user_scope = input(f"Scope [{scope or 'none'}]: ").strip()
        if user_scope:
            scope = user_scope if user_scope != 'none' else None

    # Generate message
    subject = generate_subject(analysis, commit_type, scope)

    body = None
    if not args.no_body:
        body = generate_body(analysis)

    footer = generate_footer(analysis)

    message = format_commit_message(subject, body, footer)

    print("\n" + "=" * 60)
    print("GENERATED COMMIT MESSAGE")
    print("=" * 60)
    print()
    print(message)
    print()
    print("=" * 60)

    # Option to copy or use
    print("\nTo use this message:")
    print(f'  git commit -m "{subject}"')

    if body or footer:
        print("\nOr for full message, use:")
        print("  git commit  # and paste the message above")


if __name__ == '__main__':
    main()
