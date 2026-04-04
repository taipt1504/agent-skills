#!/usr/bin/env python3
"""
Aggregate session scores across multiple runs and generate trends.

Reads session-score.json files from results directory and produces:
- Per-criterion statistics (mean, stddev, min, max)
- Trend analysis over time
- With-plugin vs without-plugin comparison (if both present)

Usage:
    python3 aggregate-scores.py --results-dir evals/results/
    python3 aggregate-scores.py --results-dir evals/results/ --output report.json
"""

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path


WEIGHTS = {
    "code_quality": 0.15,
    "convention_compliance": 0.10,
    "workflow_compliance": 0.10,
    "skill_utilization": 0.15,
    "skill_trigger_accuracy": 0.10,
    "context_efficiency": 0.10,
    "task_completion": 0.15,
    "execution_optimality": 0.10,
    "cross_session_memory": 0.05,
}


def stats(values: list[float]) -> dict:
    if not values:
        return {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0, "n": 0}
    n = len(values)
    mean = sum(values) / n
    variance = sum((x - mean) ** 2 for x in values) / max(n - 1, 1)
    return {
        "mean": round(mean, 4),
        "stddev": round(math.sqrt(variance), 4),
        "min": round(min(values), 4),
        "max": round(max(values), 4),
        "n": n,
    }


def load_scores(results_dir: Path) -> list[dict]:
    """Load all session-score.json files recursively."""
    scores = []
    for f in sorted(results_dir.rglob("session-score.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
                data["_source"] = str(f)
                scores.append(data)
        except (json.JSONDecodeError, OSError) as e:
            print(f"Warning: skipping {f}: {e}", file=sys.stderr)
    return scores


def aggregate(scores: list[dict]) -> dict:
    """Aggregate scores into statistics per criterion."""
    criteria_values: dict[str, list[float]] = {c: [] for c in WEIGHTS}
    composites = []
    per_task: dict[str, list[float]] = {}

    for score in scores:
        composites.append(score.get("composite_score", 0))
        task_id = score.get("task_id", "unknown")
        per_task.setdefault(task_id, []).append(score.get("composite_score", 0))

        for criterion, data in score.get("scores", {}).items():
            if criterion in criteria_values:
                criteria_values[criterion].append(data.get("score", 0))

    return {
        "total_sessions": len(scores),
        "composite": stats(composites),
        "per_criterion": {c: stats(v) for c, v in criteria_values.items()},
        "per_task": {t: stats(v) for t, v in sorted(per_task.items())},
    }


def compare_configs(with_plugin: list[dict], without_plugin: list[dict]) -> dict:
    """Compare with-plugin vs without-plugin scores."""
    agg_with = aggregate(with_plugin)
    agg_without = aggregate(without_plugin)

    delta = {}
    for criterion in WEIGHTS:
        w = agg_with["per_criterion"].get(criterion, {}).get("mean", 0)
        wo = agg_without["per_criterion"].get(criterion, {}).get("mean", 0)
        delta[criterion] = {
            "with_plugin": round(w, 4),
            "without_plugin": round(wo, 4),
            "delta": round(w - wo, 4),
            "improvement": f"{(w - wo) * 100:+.1f}%",
        }

    composite_delta = (
        agg_with["composite"]["mean"] - agg_without["composite"]["mean"]
    )

    return {
        "with_plugin": agg_with,
        "without_plugin": agg_without,
        "delta": delta,
        "composite_delta": round(composite_delta, 4),
        "composite_improvement": f"{composite_delta * 100:+.1f}%",
    }


def generate_markdown(report: dict) -> str:
    """Generate human-readable markdown report."""
    lines = ["# Plugin Benchmark Report", ""]

    ts = report.get("timestamp", "")
    lines.append(f"**Generated:** {ts}")
    lines.append(f"**Total Sessions:** {report.get('total_sessions', 0)}")
    lines.append("")

    # Composite summary
    if "comparison" in report:
        comp = report["comparison"]
        lines.append("## With-Plugin vs Without-Plugin")
        lines.append("")
        lines.append("| Criterion | With Plugin | Without Plugin | Delta |")
        lines.append("|-----------|-------------|----------------|-------|")
        for c, d in comp["delta"].items():
            label = c.replace("_", " ").title()
            lines.append(f"| {label} | {d['with_plugin']:.2f} | {d['without_plugin']:.2f} | {d['improvement']} |")
        lines.append(f"| **COMPOSITE** | **{comp['with_plugin']['composite']['mean']:.2f}** | "
                      f"**{comp['without_plugin']['composite']['mean']:.2f}** | "
                      f"**{comp['composite_improvement']}** |")
        lines.append("")

    # Per-criterion breakdown
    agg = report.get("aggregate", report.get("comparison", {}).get("with_plugin", {}))
    if agg.get("per_criterion"):
        lines.append("## Per-Criterion Statistics")
        lines.append("")
        lines.append("| Criterion | Mean | StdDev | Min | Max | Weight |")
        lines.append("|-----------|------|--------|-----|-----|--------|")
        for c, s in agg["per_criterion"].items():
            label = c.replace("_", " ").title()
            w = WEIGHTS.get(c, 0)
            lines.append(f"| {label} | {s['mean']:.2f} | {s['stddev']:.2f} | "
                          f"{s['min']:.2f} | {s['max']:.2f} | {w:.0%} |")
        lines.append("")

    # Per-task breakdown
    per_task = agg.get("per_task", {})
    if per_task:
        lines.append("## Per-Task Scores")
        lines.append("")
        lines.append("| Task | Mean | StdDev | Runs |")
        lines.append("|------|------|--------|------|")
        for task, s in per_task.items():
            lines.append(f"| {task} | {s['mean']:.2f} | {s['stddev']:.2f} | {s['n']} |")
        lines.append("")

    # Weakest criteria
    if agg.get("per_criterion"):
        sorted_criteria = sorted(agg["per_criterion"].items(), key=lambda x: x[1]["mean"])
        lines.append("## Areas for Improvement")
        lines.append("")
        for c, s in sorted_criteria[:3]:
            label = c.replace("_", " ").title()
            lines.append(f"- **{label}**: {s['mean']:.2f} (lowest)")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Aggregate plugin benchmark scores")
    parser.add_argument("--results-dir", type=Path, required=True,
                        help="Directory containing session-score.json files")
    parser.add_argument("--output", "-o", type=Path, default=None,
                        help="Output path for aggregate report")
    args = parser.parse_args()

    all_scores = load_scores(args.results_dir)
    if not all_scores:
        print("No session-score.json files found.", file=sys.stderr)
        sys.exit(1)

    # Split by config if present
    with_plugin = [s for s in all_scores if "without" not in s.get("_source", "")]
    without_plugin = [s for s in all_scores if "without" in s.get("_source", "")]

    report = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "total_sessions": len(all_scores),
    }

    if without_plugin:
        report["comparison"] = compare_configs(with_plugin, without_plugin)
        report["aggregate"] = report["comparison"]["with_plugin"]
    else:
        report["aggregate"] = aggregate(all_scores)

    # Output
    output_json = args.output or (args.results_dir / "benchmark-report.json")
    output_md = output_json.with_suffix(".md")

    with open(output_json, "w") as f:
        json.dump(report, f, indent=2)
    print(f"Generated: {output_json}")

    markdown = generate_markdown(report)
    with open(output_md, "w") as f:
        f.write(markdown)
    print(f"Generated: {output_md}")

    # Print summary
    agg = report.get("aggregate", {})
    comp = agg.get("composite", {})
    print(f"\nComposite: {comp.get('mean', 0):.2f} ± {comp.get('stddev', 0):.2f} "
          f"(n={comp.get('n', 0)})")

    if "comparison" in report:
        print(f"Plugin improvement: {report['comparison']['composite_improvement']}")


if __name__ == "__main__":
    main()
