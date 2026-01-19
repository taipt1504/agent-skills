#!/usr/bin/env python3
"""
Blocking Call Analyzer for Reactive Java Code

This script scans Java source files for common blocking patterns that should
be avoided in reactive code. It reports violations with file names, line numbers,
and provides suggestions for reactive alternatives.

Usage:
    python analyze-blocking-calls.py [directory] [--strict] [--exclude-tests]

Examples:
    python analyze-blocking-calls.py ./src/main/java
    python analyze-blocking-calls.py . --strict --exclude-tests
"""

import os
import re
import sys
import argparse
from dataclasses import dataclass
from typing import List, Dict, Optional
from pathlib import Path
from enum import Enum


class Severity(Enum):
    ERROR = "ERROR"
    WARNING = "WARNING"
    INFO = "INFO"


@dataclass
class BlockingPattern:
    """Represents a blocking pattern to detect."""
    name: str
    pattern: str
    severity: Severity
    description: str
    suggestion: str


@dataclass
class Violation:
    """Represents a detected blocking call violation."""
    file_path: str
    line_number: int
    line_content: str
    pattern_name: str
    severity: Severity
    description: str
    suggestion: str


# Define blocking patterns to detect
BLOCKING_PATTERNS: List[BlockingPattern] = [
    # Direct blocking calls
    BlockingPattern(
        name="block()",
        pattern=r"\.block\s*\(",
        severity=Severity.ERROR,
        description="Direct .block() call blocks the event loop",
        suggestion="Use flatMap, then, or subscribe instead of block()"
    ),
    BlockingPattern(
        name="blockFirst()",
        pattern=r"\.blockFirst\s*\(",
        severity=Severity.ERROR,
        description=".blockFirst() blocks waiting for first element",
        suggestion="Use next() or take(1) with proper subscription"
    ),
    BlockingPattern(
        name="blockLast()",
        pattern=r"\.blockLast\s*\(",
        severity=Severity.ERROR,
        description=".blockLast() blocks waiting for last element",
        suggestion="Use last() or takeLast(1) with proper subscription"
    ),
    BlockingPattern(
        name="blockOptional()",
        pattern=r"\.blockOptional\s*\(",
        severity=Severity.ERROR,
        description=".blockOptional() blocks the thread",
        suggestion="Use Mono operations instead of blocking"
    ),

    # Thread blocking
    BlockingPattern(
        name="Thread.sleep()",
        pattern=r"Thread\.sleep\s*\(",
        severity=Severity.ERROR,
        description="Thread.sleep() blocks the current thread",
        suggestion="Use Mono.delay() or delayElement() for reactive delays"
    ),
    BlockingPattern(
        name="wait()",
        pattern=r"\.wait\s*\(\s*\)",
        severity=Severity.ERROR,
        description="Object.wait() blocks the thread",
        suggestion="Use reactive signaling with Sinks or Mono.create()"
    ),
    BlockingPattern(
        name="join()",
        pattern=r"\.join\s*\(\s*\)",
        severity=Severity.WARNING,
        description="Thread.join() blocks waiting for thread completion",
        suggestion="Use Mono.fromFuture() or reactive task coordination"
    ),

    # Synchronous I/O
    BlockingPattern(
        name="InputStream",
        pattern=r"new\s+(?:File)?InputStream\s*\(",
        severity=Severity.WARNING,
        description="Blocking InputStream creation",
        suggestion="Use DataBufferUtils.read() or reactive file APIs"
    ),
    BlockingPattern(
        name="OutputStream",
        pattern=r"new\s+(?:File)?OutputStream\s*\(",
        severity=Severity.WARNING,
        description="Blocking OutputStream creation",
        suggestion="Use DataBufferUtils.write() or reactive file APIs"
    ),
    BlockingPattern(
        name="BufferedReader",
        pattern=r"new\s+BufferedReader\s*\(",
        severity=Severity.WARNING,
        description="Blocking BufferedReader",
        suggestion="Use Flux.using() with async read operations"
    ),
    BlockingPattern(
        name="Files.readAllBytes",
        pattern=r"Files\.readAllBytes\s*\(",
        severity=Severity.WARNING,
        description="Blocking file read",
        suggestion="Use DataBufferUtils.read() with Path"
    ),
    BlockingPattern(
        name="Files.write",
        pattern=r"Files\.write\s*\(",
        severity=Severity.WARNING,
        description="Blocking file write",
        suggestion="Use DataBufferUtils.write() for reactive writes"
    ),
    BlockingPattern(
        name="Files.readAllLines",
        pattern=r"Files\.readAllLines\s*\(",
        severity=Severity.WARNING,
        description="Blocking file read into memory",
        suggestion="Use Flux.using() with Files.lines() wrapped properly"
    ),

    # JDBC/Blocking database calls
    BlockingPattern(
        name="JDBC Connection",
        pattern=r"DriverManager\.getConnection\s*\(",
        severity=Severity.ERROR,
        description="JDBC connection is blocking",
        suggestion="Use R2DBC for reactive database access"
    ),
    BlockingPattern(
        name="JDBC Statement execute",
        pattern=r"(?:Statement|PreparedStatement).*\.execute(?:Query|Update)?\s*\(",
        severity=Severity.ERROR,
        description="JDBC statement execution is blocking",
        suggestion="Use R2DBC DatabaseClient or Repository"
    ),
    BlockingPattern(
        name="ResultSet processing",
        pattern=r"ResultSet.*\.(?:next|getString|getInt|getLong)\s*\(",
        severity=Severity.ERROR,
        description="JDBC ResultSet iteration is blocking",
        suggestion="Use R2DBC row mapping with Flux"
    ),
    BlockingPattern(
        name="JPA/Hibernate EntityManager",
        pattern=r"EntityManager.*\.(?:find|persist|merge|createQuery)\s*\(",
        severity=Severity.ERROR,
        description="JPA EntityManager operations are blocking",
        suggestion="Use R2DBC or Spring Data R2DBC repositories"
    ),

    # Blocking HTTP clients
    BlockingPattern(
        name="RestTemplate",
        pattern=r"RestTemplate.*\.(?:getForObject|postForObject|exchange)\s*\(",
        severity=Severity.ERROR,
        description="RestTemplate is blocking",
        suggestion="Use WebClient for non-blocking HTTP calls"
    ),
    BlockingPattern(
        name="HttpURLConnection",
        pattern=r"HttpURLConnection.*\.(?:connect|getInputStream|getOutputStream)\s*\(",
        severity=Severity.ERROR,
        description="HttpURLConnection is blocking",
        suggestion="Use WebClient for reactive HTTP"
    ),
    BlockingPattern(
        name="Apache HttpClient",
        pattern=r"HttpClient.*\.execute\s*\(",
        severity=Severity.WARNING,
        description="Apache HttpClient is typically blocking",
        suggestion="Use WebClient or Reactor Netty HttpClient"
    ),
    BlockingPattern(
        name="OkHttp synchronous call",
        pattern=r"\.execute\s*\(\s*\)\s*;",
        severity=Severity.WARNING,
        description="OkHttp synchronous execute() is blocking",
        suggestion="Use WebClient or OkHttp async with enqueue()"
    ),

    # Synchronization primitives
    BlockingPattern(
        name="synchronized block",
        pattern=r"\bsynchronized\s*\(",
        severity=Severity.WARNING,
        description="synchronized blocks can cause thread contention",
        suggestion="Use reactive patterns or atomic operations instead"
    ),
    BlockingPattern(
        name="ReentrantLock",
        pattern=r"ReentrantLock.*\.lock\s*\(",
        severity=Severity.WARNING,
        description="Explicit locking can block threads",
        suggestion="Use Sinks or reactive coordination patterns"
    ),
    BlockingPattern(
        name="Semaphore acquire",
        pattern=r"Semaphore.*\.acquire\s*\(",
        severity=Severity.WARNING,
        description="Semaphore.acquire() blocks the thread",
        suggestion="Use rate limiting operators or reactive semaphores"
    ),
    BlockingPattern(
        name="CountDownLatch await",
        pattern=r"CountDownLatch.*\.await\s*\(",
        severity=Severity.WARNING,
        description="CountDownLatch.await() blocks the thread",
        suggestion="Use Mono.zip() or reactive coordination"
    ),
    BlockingPattern(
        name="CyclicBarrier await",
        pattern=r"CyclicBarrier.*\.await\s*\(",
        severity=Severity.WARNING,
        description="CyclicBarrier.await() blocks the thread",
        suggestion="Use reactive coordination patterns"
    ),

    # Future blocking
    BlockingPattern(
        name="Future.get()",
        pattern=r"Future.*\.get\s*\(",
        severity=Severity.ERROR,
        description="Future.get() blocks waiting for result",
        suggestion="Use Mono.fromFuture() for non-blocking Future handling"
    ),
    BlockingPattern(
        name="CompletableFuture.join()",
        pattern=r"CompletableFuture.*\.join\s*\(",
        severity=Severity.ERROR,
        description="CompletableFuture.join() blocks the thread",
        suggestion="Use Mono.fromFuture() and chain with flatMap"
    ),

    # Console I/O
    BlockingPattern(
        name="System.in",
        pattern=r"System\.in\.read",
        severity=Severity.WARNING,
        description="Console input is blocking",
        suggestion="Avoid in reactive services; use async input if needed"
    ),
    BlockingPattern(
        name="Scanner",
        pattern=r"new\s+Scanner\s*\(\s*System\.in",
        severity=Severity.WARNING,
        description="Scanner with System.in is blocking",
        suggestion="Avoid in reactive services"
    ),

    # Other blocking operations
    BlockingPattern(
        name="toList() on stream",
        pattern=r"\.stream\(\).*\.collect\(Collectors\.toList\(\)\)",
        severity=Severity.INFO,
        description="Collecting stream in reactive context may be blocking",
        suggestion="Consider if this is inside a reactive chain"
    ),
    BlockingPattern(
        name="toIterable()",
        pattern=r"\.toIterable\s*\(",
        severity=Severity.WARNING,
        description="toIterable() converts reactive stream to blocking iterator",
        suggestion="Keep data in reactive pipeline; avoid iteration"
    ),
    BlockingPattern(
        name="toStream()",
        pattern=r"\.toStream\s*\(",
        severity=Severity.WARNING,
        description="toStream() converts Flux to blocking Java Stream",
        suggestion="Use Flux operators instead of Stream operations"
    ),
]


def is_inside_comment(line: str, match_pos: int) -> bool:
    """Check if the match position is inside a comment."""
    # Check for line comment
    comment_start = line.find("//")
    if comment_start != -1 and match_pos > comment_start:
        return True

    # Check for block comment (simple heuristic)
    block_start = line.find("/*")
    block_end = line.find("*/")
    if block_start != -1 and block_start < match_pos:
        if block_end == -1 or block_end > match_pos:
            return True

    return False


def is_inside_string(line: str, match_pos: int) -> bool:
    """Check if the match position is inside a string literal."""
    in_string = False
    escape_next = False
    quote_char = None

    for i, char in enumerate(line):
        if i == match_pos:
            return in_string

        if escape_next:
            escape_next = False
            continue

        if char == '\\':
            escape_next = True
            continue

        if char in ('"', "'"):
            if not in_string:
                in_string = True
                quote_char = char
            elif char == quote_char:
                in_string = False
                quote_char = None

    return in_string


def is_test_file(file_path: str) -> bool:
    """Check if the file is a test file."""
    path_lower = file_path.lower()
    return (
        "/test/" in path_lower or
        "/tests/" in path_lower or
        "test.java" in path_lower or
        "tests.java" in path_lower or
        "spec.java" in path_lower or
        "/it/" in path_lower  # integration tests
    )


def scan_file(file_path: str, patterns: List[BlockingPattern]) -> List[Violation]:
    """Scan a single file for blocking patterns."""
    violations = []

    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Warning: Could not read file {file_path}: {e}", file=sys.stderr)
        return violations

    in_block_comment = False

    for line_num, line in enumerate(lines, 1):
        # Track block comments
        if "/*" in line and "*/" not in line:
            in_block_comment = True
            continue
        if "*/" in line:
            in_block_comment = False
            continue
        if in_block_comment:
            continue

        for pattern in patterns:
            for match in re.finditer(pattern.pattern, line):
                match_pos = match.start()

                # Skip if inside comment or string
                if is_inside_comment(line, match_pos):
                    continue
                if is_inside_string(line, match_pos):
                    continue

                violations.append(Violation(
                    file_path=file_path,
                    line_number=line_num,
                    line_content=line.strip(),
                    pattern_name=pattern.name,
                    severity=pattern.severity,
                    description=pattern.description,
                    suggestion=pattern.suggestion
                ))

    return violations


def scan_directory(
    directory: str,
    patterns: List[BlockingPattern],
    exclude_tests: bool = False
) -> List[Violation]:
    """Scan all Java files in a directory."""
    all_violations = []

    for root, dirs, files in os.walk(directory):
        # Skip common non-source directories
        dirs[:] = [d for d in dirs if d not in {
            '.git', '.idea', '.gradle', 'build', 'target', 'node_modules',
            '.mvn', 'out', 'bin', '.settings'
        }]

        for file in files:
            if not file.endswith('.java'):
                continue

            file_path = os.path.join(root, file)

            if exclude_tests and is_test_file(file_path):
                continue

            violations = scan_file(file_path, patterns)
            all_violations.extend(violations)

    return all_violations


def format_violation(violation: Violation, base_dir: str) -> str:
    """Format a violation for display."""
    relative_path = os.path.relpath(violation.file_path, base_dir)
    severity_icon = {
        Severity.ERROR: "[ERROR]",
        Severity.WARNING: "[WARN] ",
        Severity.INFO: "[INFO] "
    }[violation.severity]

    return (
        f"\n{severity_icon} {violation.pattern_name}\n"
        f"  File: {relative_path}:{violation.line_number}\n"
        f"  Line: {violation.line_content[:100]}{'...' if len(violation.line_content) > 100 else ''}\n"
        f"  Problem: {violation.description}\n"
        f"  Fix: {violation.suggestion}"
    )


def print_summary(violations: List[Violation], base_dir: str) -> None:
    """Print a summary of all violations."""
    if not violations:
        print("\nNo blocking call violations found!")
        return

    # Group by severity
    by_severity: Dict[Severity, List[Violation]] = {
        Severity.ERROR: [],
        Severity.WARNING: [],
        Severity.INFO: []
    }

    for v in violations:
        by_severity[v.severity].append(v)

    # Group by file
    by_file: Dict[str, List[Violation]] = {}
    for v in violations:
        relative_path = os.path.relpath(v.file_path, base_dir)
        if relative_path not in by_file:
            by_file[relative_path] = []
        by_file[relative_path].append(v)

    print("\n" + "=" * 80)
    print("BLOCKING CALL ANALYSIS REPORT")
    print("=" * 80)

    print(f"\nTotal violations: {len(violations)}")
    print(f"  - Errors:   {len(by_severity[Severity.ERROR])}")
    print(f"  - Warnings: {len(by_severity[Severity.WARNING])}")
    print(f"  - Info:     {len(by_severity[Severity.INFO])}")
    print(f"\nFiles with violations: {len(by_file)}")

    # Print violations grouped by severity
    for severity in [Severity.ERROR, Severity.WARNING, Severity.INFO]:
        if by_severity[severity]:
            print(f"\n{'-' * 40}")
            print(f"{severity.value}S ({len(by_severity[severity])})")
            print("-" * 40)

            for violation in by_severity[severity]:
                print(format_violation(violation, base_dir))

    print("\n" + "=" * 80)

    # Print per-file summary
    print("\nViolations by file:")
    for file_path, file_violations in sorted(by_file.items()):
        errors = sum(1 for v in file_violations if v.severity == Severity.ERROR)
        warnings = sum(1 for v in file_violations if v.severity == Severity.WARNING)
        infos = sum(1 for v in file_violations if v.severity == Severity.INFO)
        print(f"  {file_path}: {errors}E/{warnings}W/{infos}I")


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Analyze Java code for blocking calls in reactive context"
    )
    parser.add_argument(
        "directory",
        nargs="?",
        default=".",
        help="Directory to scan (default: current directory)"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Include INFO level violations"
    )
    parser.add_argument(
        "--exclude-tests",
        action="store_true",
        help="Exclude test files from analysis"
    )
    parser.add_argument(
        "--errors-only",
        action="store_true",
        help="Only report ERROR level violations"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Error: '{args.directory}' is not a directory", file=sys.stderr)
        return 1

    # Filter patterns based on flags
    patterns = BLOCKING_PATTERNS
    if args.errors_only:
        patterns = [p for p in patterns if p.severity == Severity.ERROR]
    elif not args.strict:
        patterns = [p for p in patterns if p.severity != Severity.INFO]

    # Scan directory
    violations = scan_directory(args.directory, patterns, args.exclude_tests)

    if args.json:
        import json
        output = [
            {
                "file": v.file_path,
                "line": v.line_number,
                "content": v.line_content,
                "pattern": v.pattern_name,
                "severity": v.severity.value,
                "description": v.description,
                "suggestion": v.suggestion
            }
            for v in violations
        ]
        print(json.dumps(output, indent=2))
    else:
        print_summary(violations, args.directory)

    # Return exit code based on violations
    error_count = sum(1 for v in violations if v.severity == Severity.ERROR)
    return 1 if error_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
