#!/usr/bin/env python3
"""
PostgreSQL Slow Query Analyzer for R2DBC Applications

Usage:
    python analyze-queries.py --log /var/log/postgresql/postgresql.log
    python analyze-queries.py --log postgresql.log --threshold 100
    python analyze-queries.py --stats  # Connect to pg_stat_statements

Requirements:
    pip install psycopg2-binary tabulate

Examples:
    # Analyze log file
    python analyze-queries.py --log /var/log/postgresql/postgresql.log --threshold 50

    # Get stats from pg_stat_statements
    python analyze-queries.py --stats --host localhost --database mydb --user postgres
"""

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

try:
    from tabulate import tabulate
    HAS_TABULATE = True
except ImportError:
    HAS_TABULATE = False


@dataclass
class SlowQuery:
    timestamp: datetime
    duration_ms: float
    query: str
    database: str = ""
    user: str = ""


def parse_log_line(line: str) -> Optional[SlowQuery]:
    """Parse PostgreSQL log line for slow query information."""
    # Pattern for: 2024-01-15 10:30:00.123 UTC [12345] LOG:  duration: 150.234 ms  statement: SELECT ...
    pattern = r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+).*duration: ([\d.]+) ms\s+(?:statement|execute.*?):\s*(.+)'

    match = re.search(pattern, line, re.IGNORECASE)
    if match:
        timestamp_str, duration_str, query = match.groups()
        try:
            timestamp = datetime.strptime(timestamp_str[:23], '%Y-%m-%d %H:%M:%S.%f')
            duration = float(duration_str)
            return SlowQuery(timestamp=timestamp, duration_ms=duration, query=query.strip())
        except ValueError:
            pass

    return None


def analyze_log_file(log_path: str, threshold_ms: float = 100) -> list[SlowQuery]:
    """Analyze PostgreSQL log file for slow queries."""
    slow_queries = []
    path = Path(log_path)

    if not path.exists():
        print(f"Error: Log file not found: {log_path}")
        sys.exit(1)

    print(f"Analyzing {log_path}...")
    print(f"Threshold: {threshold_ms}ms")
    print()

    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            query = parse_log_line(line)
            if query and query.duration_ms >= threshold_ms:
                slow_queries.append(query)

    return slow_queries


def normalize_query(query: str) -> str:
    """Normalize query by replacing literals with placeholders."""
    # Replace numbers
    normalized = re.sub(r'\b\d+\b', '?', query)
    # Replace quoted strings
    normalized = re.sub(r"'[^']*'", "'?'", normalized)
    # Remove extra whitespace
    normalized = ' '.join(normalized.split())
    return normalized


def group_queries(queries: list[SlowQuery]) -> dict:
    """Group queries by normalized form."""
    groups = defaultdict(lambda: {'count': 0, 'total_ms': 0, 'max_ms': 0, 'queries': []})

    for q in queries:
        key = normalize_query(q.query)
        groups[key]['count'] += 1
        groups[key]['total_ms'] += q.duration_ms
        groups[key]['max_ms'] = max(groups[key]['max_ms'], q.duration_ms)
        groups[key]['queries'].append(q)

    return groups


def print_report(queries: list[SlowQuery], top_n: int = 20):
    """Print analysis report."""
    if not queries:
        print("No slow queries found.")
        return

    print(f"Found {len(queries)} slow queries")
    print("=" * 80)

    # Group by normalized query
    groups = group_queries(queries)

    # Sort by total time
    sorted_groups = sorted(
        groups.items(),
        key=lambda x: x[1]['total_ms'],
        reverse=True
    )[:top_n]

    if HAS_TABULATE:
        table_data = []
        for normalized, stats in sorted_groups:
            avg_ms = stats['total_ms'] / stats['count']
            table_data.append([
                stats['count'],
                f"{avg_ms:.1f}",
                f"{stats['max_ms']:.1f}",
                f"{stats['total_ms']:.1f}",
                normalized[:80] + ('...' if len(normalized) > 80 else '')
            ])

        print(tabulate(
            table_data,
            headers=['Count', 'Avg(ms)', 'Max(ms)', 'Total(ms)', 'Query'],
            tablefmt='grid'
        ))
    else:
        print(f"{'Count':>8} {'Avg(ms)':>10} {'Max(ms)':>10} {'Total(ms)':>12} Query")
        print("-" * 100)
        for normalized, stats in sorted_groups:
            avg_ms = stats['total_ms'] / stats['count']
            query_preview = normalized[:60] + ('...' if len(normalized) > 60 else '')
            print(f"{stats['count']:>8} {avg_ms:>10.1f} {stats['max_ms']:>10.1f} {stats['total_ms']:>12.1f} {query_preview}")

    print()
    print("Recommendations:")
    print("-" * 80)

    # Analyze patterns
    for normalized, stats in sorted_groups[:5]:
        print(f"\nQuery (called {stats['count']}x, avg {stats['total_ms']/stats['count']:.1f}ms):")
        print(f"  {normalized[:100]}...")

        # Suggestions based on query pattern
        suggestions = []

        if 'SELECT *' in normalized.upper():
            suggestions.append("- Consider selecting only needed columns instead of SELECT *")

        if 'OFFSET' in normalized.upper():
            suggestions.append("- Consider cursor-based pagination instead of OFFSET")

        if normalized.upper().count('SELECT') > 1:
            suggestions.append("- Subquery detected, consider using JOIN or CTE")

        if 'LIKE' in normalized.upper() and "'%?" in normalized:
            suggestions.append("- Leading wildcard LIKE prevents index usage")

        if 'ORDER BY' in normalized.upper() and 'LIMIT' not in normalized.upper():
            suggestions.append("- ORDER BY without LIMIT may be expensive")

        if not suggestions:
            suggestions.append("- Check EXPLAIN ANALYZE for this query")
            suggestions.append("- Verify appropriate indexes exist")

        for s in suggestions:
            print(f"  {s}")


def get_pg_stat_statements(host: str, port: int, database: str, user: str, password: str, top_n: int = 20):
    """Get slow query stats from pg_stat_statements."""
    try:
        import psycopg2
    except ImportError:
        print("Error: psycopg2 not installed. Run: pip install psycopg2-binary")
        sys.exit(1)

    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            database=database,
            user=user,
            password=password
        )

        cur = conn.cursor()

        # Check if pg_stat_statements is available
        cur.execute("""
            SELECT EXISTS (
                SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
            )
        """)

        if not cur.fetchone()[0]:
            print("Error: pg_stat_statements extension not installed.")
            print("Run: CREATE EXTENSION pg_stat_statements;")
            sys.exit(1)

        # Get top slow queries
        cur.execute(f"""
            SELECT
                calls,
                mean_exec_time,
                max_exec_time,
                total_exec_time,
                rows,
                query
            FROM pg_stat_statements
            WHERE calls > 0
            ORDER BY mean_exec_time DESC
            LIMIT {top_n}
        """)

        rows = cur.fetchall()

        if HAS_TABULATE:
            table_data = [
                [
                    row[0],  # calls
                    f"{row[1]:.2f}",  # mean
                    f"{row[2]:.2f}",  # max
                    f"{row[3]:.2f}",  # total
                    row[4],  # rows
                    row[5][:60] + ('...' if len(row[5]) > 60 else '')
                ]
                for row in rows
            ]
            print(tabulate(
                table_data,
                headers=['Calls', 'Avg(ms)', 'Max(ms)', 'Total(ms)', 'Rows', 'Query'],
                tablefmt='grid'
            ))
        else:
            print(f"{'Calls':>10} {'Avg(ms)':>10} {'Max(ms)':>10} {'Total(ms)':>12} {'Rows':>10} Query")
            print("-" * 120)
            for row in rows:
                query_preview = row[5][:50] + ('...' if len(row[5]) > 50 else '')
                print(f"{row[0]:>10} {row[1]:>10.2f} {row[2]:>10.2f} {row[3]:>12.2f} {row[4]:>10} {query_preview}")

        cur.close()
        conn.close()

    except psycopg2.Error as e:
        print(f"Database error: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Analyze PostgreSQL slow queries for R2DBC optimization'
    )

    parser.add_argument('--log', help='Path to PostgreSQL log file')
    parser.add_argument('--threshold', type=float, default=100,
                        help='Slow query threshold in milliseconds (default: 100)')
    parser.add_argument('--top', type=int, default=20,
                        help='Number of top queries to show (default: 20)')

    # pg_stat_statements options
    parser.add_argument('--stats', action='store_true',
                        help='Use pg_stat_statements instead of log file')
    parser.add_argument('--host', default='localhost',
                        help='PostgreSQL host (default: localhost)')
    parser.add_argument('--port', type=int, default=5432,
                        help='PostgreSQL port (default: 5432)')
    parser.add_argument('--database', default='postgres',
                        help='Database name (default: postgres)')
    parser.add_argument('--user', default='postgres',
                        help='Database user (default: postgres)')
    parser.add_argument('--password', default='',
                        help='Database password')

    args = parser.parse_args()

    if args.stats:
        print("Fetching stats from pg_stat_statements...")
        print()
        get_pg_stat_statements(
            args.host, args.port, args.database,
            args.user, args.password, args.top
        )
    elif args.log:
        queries = analyze_log_file(args.log, args.threshold)
        print_report(queries, args.top)
    else:
        parser.print_help()
        print("\nError: Either --log or --stats is required")
        sys.exit(1)


if __name__ == '__main__':
    main()
