#!/usr/bin/env python3
"""
Agent Configuration Validator

Validates agent definitions for correctness and best practices.

Usage:
    python validate-agents.py                    # Validate .claude/agents/
    python validate-agents.py --path /custom/path
    python validate-agents.py --strict           # Fail on warnings
    python validate-agents.py --json             # JSON output

Examples:
    python validate-agents.py
    python validate-agents.py --path ./my-project/.claude/agents
    python validate-agents.py --strict --json
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional


class Severity(Enum):
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"


@dataclass
class ValidationIssue:
    severity: Severity
    message: str
    file: str
    line: Optional[int] = None
    suggestion: Optional[str] = None


@dataclass
class ValidationResult:
    file: str
    valid: bool
    issues: list[ValidationIssue] = field(default_factory=list)
    agent_name: Optional[str] = None
    description: Optional[str] = None
    tools: list[str] = field(default_factory=list)
    model: Optional[str] = None


VALID_TOOLS = {
    "Read", "Write", "Edit", "Bash", "Glob", "Grep",
    "Task", "WebFetch", "WebSearch", "TodoWrite",
    "NotebookEdit", "AskUserQuestion"
}

VALID_MODELS = {"haiku", "sonnet", "opus"}

READ_ONLY_TOOLS = {"Read", "Glob", "Grep"}

DANGEROUS_TOOLS = {"Bash", "Write", "Edit"}


def parse_frontmatter(content: str) -> tuple[dict, str]:
    """Parse YAML frontmatter from markdown content."""
    if not content.startswith("---"):
        return {}, content

    lines = content.split("\n")
    end_idx = None

    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end_idx = i
            break

    if end_idx is None:
        return {}, content

    frontmatter_lines = lines[1:end_idx]
    body = "\n".join(lines[end_idx + 1:])

    # Simple YAML parsing
    frontmatter = {}
    current_key = None
    current_list = None

    for line in frontmatter_lines:
        if not line.strip() or line.strip().startswith("#"):
            continue

        # List item
        if line.strip().startswith("- "):
            if current_list is not None:
                current_list.append(line.strip()[2:].strip())
            continue

        # Key-value or key with list
        match = re.match(r"^(\w+):\s*(.*)$", line)
        if match:
            key, value = match.groups()
            current_key = key

            if value:
                # Check if it's a comma-separated list
                if "," in value:
                    frontmatter[key] = [v.strip() for v in value.split(",")]
                    current_list = None
                else:
                    frontmatter[key] = value
                    current_list = None
            else:
                # Start of a list
                frontmatter[key] = []
                current_list = frontmatter[key]

    return frontmatter, body


def validate_agent_file(file_path: Path) -> ValidationResult:
    """Validate a single agent definition file."""
    result = ValidationResult(file=str(file_path), valid=True)

    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception as e:
        result.valid = False
        result.issues.append(ValidationIssue(
            severity=Severity.ERROR,
            message=f"Cannot read file: {e}",
            file=str(file_path)
        ))
        return result

    # Parse frontmatter
    frontmatter, body = parse_frontmatter(content)

    # Check required fields
    if "name" not in frontmatter:
        result.valid = False
        result.issues.append(ValidationIssue(
            severity=Severity.ERROR,
            message="Missing required field: name",
            file=str(file_path),
            suggestion="Add 'name: your-agent-name' to frontmatter"
        ))
    else:
        result.agent_name = frontmatter["name"]

    if "description" not in frontmatter:
        result.valid = False
        result.issues.append(ValidationIssue(
            severity=Severity.ERROR,
            message="Missing required field: description",
            file=str(file_path),
            suggestion="Add 'description: ...' to frontmatter"
        ))
    else:
        result.description = frontmatter["description"]

        # Check description quality
        if len(frontmatter["description"]) < 20:
            result.issues.append(ValidationIssue(
                severity=Severity.WARNING,
                message="Description is too short",
                file=str(file_path),
                suggestion="Provide a more detailed description for better agent selection"
            ))

        if "use" not in frontmatter["description"].lower():
            result.issues.append(ValidationIssue(
                severity=Severity.INFO,
                message="Description doesn't indicate when to use the agent",
                file=str(file_path),
                suggestion="Include 'Use when...' or 'Use for...' in description"
            ))

    # Validate tools
    if "tools" in frontmatter:
        tools = frontmatter["tools"]
        if isinstance(tools, str):
            tools = [t.strip() for t in tools.split(",")]

        result.tools = tools

        for tool in tools:
            if tool not in VALID_TOOLS:
                result.valid = False
                result.issues.append(ValidationIssue(
                    severity=Severity.ERROR,
                    message=f"Invalid tool: {tool}",
                    file=str(file_path),
                    suggestion=f"Valid tools: {', '.join(sorted(VALID_TOOLS))}"
                ))

        # Security warnings
        has_dangerous = any(t in DANGEROUS_TOOLS for t in tools)
        is_reviewer = "review" in result.agent_name.lower() if result.agent_name else False

        if is_reviewer and has_dangerous:
            result.issues.append(ValidationIssue(
                severity=Severity.WARNING,
                message="Reviewer agent has dangerous tools (Write/Edit/Bash)",
                file=str(file_path),
                suggestion="Reviewers should typically be read-only"
            ))

        # Check for Task tool without other tools
        if "Task" in tools and len(tools) == 1:
            result.issues.append(ValidationIssue(
                severity=Severity.WARNING,
                message="Agent only has Task tool - might be too limited",
                file=str(file_path),
                suggestion="Consider adding Read, Glob, Grep for context gathering"
            ))

    else:
        result.issues.append(ValidationIssue(
            severity=Severity.WARNING,
            message="No tools specified - agent will inherit all tools",
            file=str(file_path),
            suggestion="Explicitly specify tools for least privilege"
        ))

    # Validate model
    if "model" in frontmatter:
        model = frontmatter["model"].lower()
        result.model = model

        if model not in VALID_MODELS:
            result.valid = False
            result.issues.append(ValidationIssue(
                severity=Severity.ERROR,
                message=f"Invalid model: {model}",
                file=str(file_path),
                suggestion=f"Valid models: {', '.join(sorted(VALID_MODELS))}"
            ))

        # Model recommendations
        if model == "opus" and result.tools:
            if set(result.tools).issubset(READ_ONLY_TOOLS):
                result.issues.append(ValidationIssue(
                    severity=Severity.INFO,
                    message="Using Opus for read-only tasks might be overkill",
                    file=str(file_path),
                    suggestion="Consider using Haiku or Sonnet for simpler tasks"
                ))

        if model == "haiku" and "architect" in (result.agent_name or "").lower():
            result.issues.append(ValidationIssue(
                severity=Severity.WARNING,
                message="Haiku might be too limited for architecture tasks",
                file=str(file_path),
                suggestion="Consider using Sonnet or Opus for complex reasoning"
            ))

    # Validate body content
    if len(body.strip()) < 50:
        result.issues.append(ValidationIssue(
            severity=Severity.WARNING,
            message="Agent prompt is very short",
            file=str(file_path),
            suggestion="Provide detailed instructions for the agent"
        ))

    # Check for common patterns
    body_lower = body.lower()

    if "checklist" not in body_lower and "step" not in body_lower:
        result.issues.append(ValidationIssue(
            severity=Severity.INFO,
            message="No checklist or steps found in prompt",
            file=str(file_path),
            suggestion="Consider adding a checklist or step-by-step process"
        ))

    if "output" not in body_lower and "format" not in body_lower:
        result.issues.append(ValidationIssue(
            severity=Severity.INFO,
            message="No output format specified",
            file=str(file_path),
            suggestion="Define expected output format for consistency"
        ))

    return result


def validate_directory(path: Path) -> list[ValidationResult]:
    """Validate all agent files in a directory."""
    results = []

    if not path.exists():
        results.append(ValidationResult(
            file=str(path),
            valid=False,
            issues=[ValidationIssue(
                severity=Severity.ERROR,
                message=f"Directory not found: {path}",
                file=str(path)
            )]
        ))
        return results

    # Find all markdown files
    agent_files = list(path.glob("*.md"))

    if not agent_files:
        results.append(ValidationResult(
            file=str(path),
            valid=True,
            issues=[ValidationIssue(
                severity=Severity.WARNING,
                message="No agent files found",
                file=str(path),
                suggestion="Create agent files in .claude/agents/"
            )]
        ))
        return results

    for file_path in agent_files:
        result = validate_agent_file(file_path)
        results.append(result)

    return results


def print_results(results: list[ValidationResult], json_output: bool = False):
    """Print validation results."""
    if json_output:
        output = {
            "valid": all(r.valid for r in results),
            "results": [
                {
                    "file": r.file,
                    "valid": r.valid,
                    "agent_name": r.agent_name,
                    "description": r.description,
                    "tools": r.tools,
                    "model": r.model,
                    "issues": [
                        {
                            "severity": i.severity.value,
                            "message": i.message,
                            "suggestion": i.suggestion
                        }
                        for i in r.issues
                    ]
                }
                for r in results
            ]
        }
        print(json.dumps(output, indent=2))
        return

    # Text output
    total_errors = 0
    total_warnings = 0
    total_info = 0

    for result in results:
        print(f"\n{'=' * 60}")
        print(f"File: {result.file}")
        print(f"Valid: {'✓' if result.valid else '✗'}")

        if result.agent_name:
            print(f"Agent: {result.agent_name}")
        if result.tools:
            print(f"Tools: {', '.join(result.tools)}")
        if result.model:
            print(f"Model: {result.model}")

        if result.issues:
            print(f"\nIssues ({len(result.issues)}):")
            for issue in result.issues:
                if issue.severity == Severity.ERROR:
                    prefix = "❌ ERROR"
                    total_errors += 1
                elif issue.severity == Severity.WARNING:
                    prefix = "⚠️  WARN"
                    total_warnings += 1
                else:
                    prefix = "ℹ️  INFO"
                    total_info += 1

                print(f"  {prefix}: {issue.message}")
                if issue.suggestion:
                    print(f"          → {issue.suggestion}")

    # Summary
    print(f"\n{'=' * 60}")
    print("Summary")
    print(f"{'=' * 60}")
    print(f"Files validated: {len(results)}")
    print(f"Errors: {total_errors}")
    print(f"Warnings: {total_warnings}")
    print(f"Info: {total_info}")

    if total_errors > 0:
        print(f"\n❌ Validation failed with {total_errors} errors")
    elif total_warnings > 0:
        print(f"\n⚠️  Validation passed with {total_warnings} warnings")
    else:
        print("\n✓ All validations passed")


def main():
    parser = argparse.ArgumentParser(description="Validate agent configurations")
    parser.add_argument(
        "--path",
        default=".claude/agents",
        help="Path to agents directory (default: .claude/agents)"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as errors"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    args = parser.parse_args()

    path = Path(args.path)
    results = validate_directory(path)

    print_results(results, json_output=args.json)

    # Exit code
    has_errors = any(not r.valid for r in results)
    has_warnings = any(
        i.severity == Severity.WARNING
        for r in results
        for i in r.issues
    )

    if has_errors:
        sys.exit(1)
    elif args.strict and has_warnings:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
