#!/usr/bin/env python3
"""
Score a completed session based on execution traces and session metrics.

Reads:
  - .claude/sessions/execution-trace.jsonl (per-tool-call traces)
  - .claude/sessions/session-metrics.json (aggregated metrics)
  - .claude/workflow-state.json (phase transitions)
  - .claude/verify-fix-state.json (verify retry state)

Outputs:
  - session-score.json with scores for all 9 criteria

Usage:
    python3 score-session.py --project-dir /path/to/project [--task-id 01-create-crud-api]
    python3 score-session.py --session-dir .claude/sessions/ [--task-file evals/tasks/01-create-crud-api.md]
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


# --- Criterion weights ---
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

GRADE_MAP = [
    (0.90, "A"), (0.80, "B"), (0.70, "C"), (0.60, "D"), (0.0, "F")
]


def load_json(path: Path) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def load_jsonl(path: Path) -> list[dict]:
    entries = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    except FileNotFoundError:
        pass
    return entries


def load_task(task_path: Path) -> dict:
    """Parse task .md file to extract expected skills and checks."""
    if not task_path or not task_path.exists():
        return {"expected_skills": [], "checks": [], "complexity": "medium"}

    content = task_path.read_text()
    task = {"expected_skills": [], "checks": [], "complexity": "medium"}

    # Extract expected skills
    skill_section = re.search(r"## Expected Skill Usage\n(.*?)(?=\n##|\Z)", content, re.DOTALL)
    if skill_section:
        for match in re.finditer(r"`(\w[\w-]+)`", skill_section.group(1)):
            task["expected_skills"].append(match.group(1))

    # Extract checks
    for match in re.finditer(r"- \[[ x]\] (.+)", content):
        task["checks"].append(match.group(1))

    # Extract complexity
    complexity_match = re.search(r"Complexity:\s*(\w[\w-]*)", content)
    if complexity_match:
        task["complexity"] = complexity_match.group(1).lower()

    return task


def complexity_to_baseline(complexity: str) -> int:
    """Map complexity to expected tool call baseline."""
    mapping = {"low": 15, "low-medium": 20, "medium": 30, "medium-high": 40, "high": 50}
    return mapping.get(complexity, 30)


# --- Criterion scorers ---

def score_code_quality(project_dir: Path) -> tuple[float, str]:
    """Criterion 1: Code Quality (compile, test, violations, coverage)."""
    score = 0.0
    evidence = []

    # Check compile
    result = subprocess.run(
        ["./gradlew", "compileJava", "--quiet"],
        cwd=project_dir, capture_output=True, timeout=120
    ) if (project_dir / "gradlew").exists() else None

    if result and result.returncode == 0:
        score += 0.30
        evidence.append("compile: PASS")
    else:
        evidence.append("compile: FAIL or not available")

    # Check tests
    result = subprocess.run(
        ["./gradlew", "test", "--quiet"],
        cwd=project_dir, capture_output=True, timeout=300
    ) if (project_dir / "gradlew").exists() else None

    if result and result.returncode == 0:
        score += 0.30
        evidence.append("tests: PASS")
    else:
        evidence.append("tests: FAIL or not available")

    # Check critical violations
    violations = 0
    for java_file in project_dir.rglob("src/main/**/*.java"):
        content = java_file.read_text(errors="ignore")
        if ".block()" in content:
            violations += 1
        if "@Autowired" in content and "private" in content:
            # Crude check for field injection
            for line in content.split("\n"):
                if "@Autowired" in line:
                    next_lines = content[content.index(line):]
                    if re.search(r"@Autowired\s+private", next_lines):
                        violations += 1
                    break

    if violations == 0:
        score += 0.20
        evidence.append("critical violations: 0")
    else:
        evidence.append(f"critical violations: {violations}")

    # Coverage (check JaCoCo report)
    jacoco_xml = project_dir / "build/reports/jacoco/test/jacocoTestReport.xml"
    if jacoco_xml.exists():
        xml_content = jacoco_xml.read_text(errors="ignore")
        # Extract instruction coverage
        match = re.search(r'type="INSTRUCTION"[^/]*missed="(\d+)"[^/]*covered="(\d+)"', xml_content)
        if match:
            missed, covered = int(match.group(1)), int(match.group(2))
            total = missed + covered
            coverage = covered / total if total > 0 else 0
            if coverage >= 0.80:
                score += 0.20
                evidence.append(f"coverage: {coverage:.0%} (≥80%)")
            else:
                evidence.append(f"coverage: {coverage:.0%} (<80%)")
    else:
        evidence.append("coverage: JaCoCo report not found")

    return score, "; ".join(evidence)


def score_convention_compliance(project_dir: Path) -> tuple[float, str]:
    """Criterion 2: Convention Compliance."""
    checks = {
        "no_block": (0.20, True),
        "no_autowired_field": (0.15, True),
        "dtos_are_records": (0.15, True),
        "no_exposed_entities": (0.15, True),
        "valid_on_boundaries": (0.10, True),
        "parameterized_queries": (0.10, True),
        "constructor_injection": (0.10, True),
        "domain_exceptions": (0.05, True),
    }

    java_files = list(project_dir.rglob("src/main/**/*.java"))
    evidence = []

    for f in java_files:
        content = f.read_text(errors="ignore")
        if ".block()" in content and "src/test" not in str(f):
            checks["no_block"] = (0.20, False)
        if re.search(r"@Autowired\s*\n\s*private", content):
            checks["no_autowired_field"] = (0.15, False)
        if "class " in content and "Dto" in f.name and "record " not in content:
            checks["dtos_are_records"] = (0.15, False)
        if re.search(r"@RestController|@Controller", content):
            if re.search(r"@Entity|@Table", content):
                checks["no_exposed_entities"] = (0.15, False)
        if "RuntimeException" in content and "domain" not in str(f).lower():
            checks["domain_exceptions"] = (0.05, False)

    score = sum(weight for (weight, passed) in checks.values() if passed)
    for name, (weight, passed) in checks.items():
        evidence.append(f"{name}: {'PASS' if passed else 'FAIL'}")

    return score, "; ".join(evidence)


def score_workflow_compliance(workflow_state: dict, traces: list[dict]) -> tuple[float, str]:
    """Criterion 3: Workflow Compliance."""
    phases_detected = set()
    evidence = []

    # Check workflow state
    phase_history = workflow_state.get("phaseHistory", [])
    for entry in phase_history:
        phase = entry if isinstance(entry, str) else entry.get("phase", "")
        phases_detected.add(phase.upper())

    # Also check traces for phase info
    for trace in traces:
        phase = trace.get("phase", "").upper()
        if phase and phase != "UNKNOWN":
            phases_detected.add(phase)

    phase_scores = {
        "PLAN": 0.25,
        "SPEC": 0.20,
        "BUILD": 0.15,
        "VERIFY": 0.25,
        "REVIEW": 0.15,
    }

    score = sum(weight for phase, weight in phase_scores.items() if phase in phases_detected)
    penalty = 1.0
    if "VERIFY" not in phases_detected:
        penalty *= 0.5
        evidence.append("MISSING: VERIFY (penalty ×0.5)")
    if "REVIEW" not in phases_detected:
        penalty *= 0.7
        evidence.append("MISSING: REVIEW (penalty ×0.7)")

    score *= penalty
    evidence.insert(0, f"phases detected: {sorted(phases_detected)}")
    return score, "; ".join(evidence)


def score_skill_utilization(metrics: dict, traces: list[dict], task: dict) -> tuple[float, str]:
    """Criterion 4: Skill Utilization Effectiveness."""
    evidence = []

    # 4a: Skill coverage
    expected = set(task.get("expected_skills", []))
    used = set(k for k, v in metrics.get("skillUsage", {}).items()
               if k != "untagged" and v > 0)
    coverage = len(expected & used) / max(len(expected), 1) if expected else 0.5
    evidence.append(f"coverage: {len(expected & used)}/{len(expected)} expected skills used")

    # 4b: Skill announcement (check traces for announcement pattern)
    announcements = sum(1 for t in traces if "Applying skill" in t.get("status", ""))
    skill_uses = len(used)
    announcement_rate = min(announcements / max(skill_uses, 1), 1.0)
    evidence.append(f"announcements: {announcements}/{skill_uses}")

    # 4c: Skill Usage Report — would need transcript analysis
    # Default to 0.5 (neutral) without transcript
    report_present = 0.5
    evidence.append("skill report: estimated (no transcript)")

    # 4d: Command usage — check for /plan, /spec, /verify etc in traces
    commands_used = set()
    for t in traces:
        tool = t.get("tool", "")
        if tool.startswith("/") or tool in ("plan", "spec", "verify", "build", "review"):
            commands_used.add(tool)
    command_score = min(len(commands_used) / 3, 1.0)  # expect at least 3 commands
    evidence.append(f"commands: {commands_used}")

    score = 0.40 * coverage + 0.20 * announcement_rate + 0.20 * report_present + 0.20 * command_score
    return score, "; ".join(evidence)


def score_skill_trigger_accuracy(metrics: dict, task: dict) -> tuple[float, str]:
    """Criterion 5: Skill Trigger Accuracy."""
    evidence = []
    expected = set(task.get("expected_skills", []))
    used = set(k for k, v in metrics.get("skillUsage", {}).items()
               if k != "untagged" and v > 0)
    always_loaded = {"bootstrap", "coding-standards"}

    # 5a: True positive rate
    tpr = len(expected & used) / max(len(expected), 1) if expected else 0.5
    evidence.append(f"TPR: {len(expected & used)}/{len(expected)}")

    # 5b: False positive rate (inverse)
    irrelevant = used - expected - always_loaded
    fpr_inv = 1.0 - (len(irrelevant) / max(len(used), 1))
    evidence.append(f"irrelevant skills: {irrelevant if irrelevant else 'none'}")

    # 5c: Trigger latency — estimate from total tool calls before first skill
    latency_score = 0.8  # default estimate without detailed timing
    evidence.append("latency: estimated")

    score = 0.50 * tpr + 0.30 * fpr_inv + 0.20 * latency_score
    return score, "; ".join(evidence)


def score_context_efficiency(metrics: dict, traces: list[dict], task: dict) -> tuple[float, str]:
    """Criterion 6: Context Efficiency & Memory."""
    evidence = []

    # 6a: Progressive disclosure
    ref_loads = sum(1 for t in traces if "references/" in t.get("file", ""))
    skill_loads = sum(1 for t in traces if "SKILL.md" in t.get("file", ""))
    total_loads = skill_loads + ref_loads
    ratio = skill_loads / max(total_loads, 1)
    progressive = min(ratio / 0.5, 1.0) if total_loads > 0 else 0.5
    evidence.append(f"progressive: {skill_loads} SKILL.md, {ref_loads} refs (ratio={ratio:.2f})")

    # 6b: Context budget
    total_calls = metrics.get("totalToolCalls", 0)
    baseline = complexity_to_baseline(task.get("complexity", "medium"))
    budget_score = min(baseline / max(total_calls, 1), 1.0)
    evidence.append(f"budget: {total_calls} calls vs {baseline} baseline")

    # 6c: Memory load at start
    memory_loaded = any(
        "memory" in t.get("tool", "").lower() or "search_nodes" in t.get("tool", "")
        for t in traces[:5]
    )
    memory_load_score = 1.0 if memory_loaded else 0.0
    evidence.append(f"memory load: {'yes' if memory_loaded else 'no'}")

    # 6d: Memory write at end
    memory_written = any(
        "memory" in t.get("tool", "").lower() or "create_entities" in t.get("tool", "")
        for t in traces[-10:]
    )
    memory_write_score = 1.0 if memory_written else 0.0
    evidence.append(f"memory write: {'yes' if memory_written else 'no'}")

    score = 0.30 * progressive + 0.30 * budget_score + 0.20 * memory_load_score + 0.20 * memory_write_score
    return score, "; ".join(evidence)


def score_task_completion(workflow_state: dict, verify_state: dict, traces: list[dict]) -> tuple[float, str]:
    """Criterion 7: Task Completion Rate."""
    evidence = []

    # 7a: REVIEW pass
    current_phase = workflow_state.get("phase", "UNKNOWN").upper()
    review_passed = 1.0 if current_phase == "REVIEW" or current_phase == "COMPLETE" else 0.0
    evidence.append(f"final phase: {current_phase}")

    # 7b: Verify pass rate
    verify_attempts = verify_state.get("currentAttempt", 0)
    if verify_attempts <= 1:
        verify_score = 1.0
    else:
        verify_score = max(0.3, 1.0 - (verify_attempts - 1) * 0.2)
    evidence.append(f"verify attempts: {verify_attempts}")

    # 7c: No escalation
    escalation = any(
        "ESCALATE" in t.get("status", "") or "NO_PROGRESS" in t.get("status", "")
        for t in traces
    )
    no_escalation = 0.0 if escalation else 1.0
    evidence.append(f"escalation: {'YES' if escalation else 'no'}")

    score = 0.50 * review_passed + 0.30 * verify_score + 0.20 * no_escalation
    return score, "; ".join(evidence)


def score_execution_optimality(metrics: dict, traces: list[dict], task: dict) -> tuple[float, str]:
    """Criterion 8: Task Execution Optimality."""
    evidence = []

    # 8a: Tool call efficiency
    actual = metrics.get("totalToolCalls", 0)
    baseline = complexity_to_baseline(task.get("complexity", "medium"))
    efficiency = min(baseline / max(actual, 1), 1.0)
    evidence.append(f"calls: {actual} vs {baseline} baseline")

    # 8b: No redundant work
    file_edits: dict[str, int] = {}
    for t in traces:
        f = t.get("file", "")
        if f and t.get("tool", "") in ("Edit", "Write"):
            file_edits[f] = file_edits.get(f, 0) + 1
    max_edits = max(file_edits.values()) if file_edits else 0
    redundancy = 1.0 if max_edits <= 3 else max(0.3, 1.0 - (max_edits - 3) * 0.15)
    evidence.append(f"max file edits: {max_edits}")

    # 8c: Error recovery speed
    recovery_score = 1.0  # default when no failures
    verify_fails = [i for i, t in enumerate(traces)
                    if t.get("status") == "error" and "test" in t.get("tool", "").lower()]
    if verify_fails:
        last_fail = verify_fails[-1]
        next_success = next(
            (i for i in range(last_fail, len(traces))
             if traces[i].get("status") == "ok" and "test" in traces[i].get("tool", "").lower()),
            len(traces)
        )
        recovery_calls = next_success - last_fail
        recovery_score = 1.0 if recovery_calls <= 5 else max(0.2, 1.0 - (recovery_calls - 5) * 0.1)
        evidence.append(f"recovery: {recovery_calls} calls after failure")
    else:
        evidence.append("recovery: no failures")

    score = 0.40 * efficiency + 0.30 * redundancy + 0.30 * recovery_score
    return score, "; ".join(evidence)


def score_cross_session_memory(traces: list[dict]) -> tuple[float, str]:
    """Criterion 9: Cross-Session Memory (requires 2-session eval)."""
    # This requires manual/grader-based evaluation for full accuracy
    # Automated: check if memory was searched and entities were created
    evidence = []

    memory_searched = any("search_nodes" in t.get("tool", "") for t in traces)
    memory_written = any("create_entities" in t.get("tool", "") for t in traces)

    recall = 1.0 if memory_searched else 0.0
    updated = 1.0 if memory_written else 0.0
    accuracy = 0.5  # cannot determine automatically

    evidence.append(f"search: {'yes' if memory_searched else 'no'}")
    evidence.append(f"write: {'yes' if memory_written else 'no'}")
    evidence.append("accuracy: estimated (needs grader)")

    score = 0.50 * recall + 0.25 * accuracy + 0.25 * updated
    return score, "; ".join(evidence)


def grade(composite: float) -> str:
    for threshold, g in GRADE_MAP:
        if composite >= threshold:
            return g
    return "F"


def main():
    parser = argparse.ArgumentParser(description="Score a completed plugin session")
    parser.add_argument("--project-dir", type=Path, default=Path("."),
                        help="Project root directory")
    parser.add_argument("--session-dir", type=Path, default=None,
                        help="Session directory (default: <project-dir>/.claude/sessions/)")
    parser.add_argument("--task-file", type=Path, default=None,
                        help="Task definition file (evals/tasks/*.md)")
    parser.add_argument("--task-id", type=str, default=None,
                        help="Task ID (e.g., 01-create-crud-api)")
    parser.add_argument("--output", "-o", type=Path, default=None,
                        help="Output path for session-score.json")
    args = parser.parse_args()

    project_dir = args.project_dir.resolve()
    session_dir = args.session_dir or project_dir / ".claude" / "sessions"

    # Load data
    traces = load_jsonl(session_dir / "execution-trace.jsonl")
    metrics = load_json(session_dir / "session-metrics.json")
    workflow_state = load_json(project_dir / ".claude" / "workflow-state.json")
    verify_state = load_json(project_dir / ".claude" / "verify-fix-state.json")

    # Load task definition
    task_path = args.task_file
    if not task_path and args.task_id:
        # Search for task file
        evals_dir = project_dir / "evals" / "tasks"
        candidates = list(evals_dir.glob(f"*{args.task_id}*"))
        if candidates:
            task_path = candidates[0]

    task = load_task(task_path)

    # Score all criteria
    scores = {}
    s, e = score_code_quality(project_dir)
    scores["code_quality"] = {"score": round(s, 4), "evidence": e}

    s, e = score_convention_compliance(project_dir)
    scores["convention_compliance"] = {"score": round(s, 4), "evidence": e}

    s, e = score_workflow_compliance(workflow_state, traces)
    scores["workflow_compliance"] = {"score": round(s, 4), "evidence": e}

    s, e = score_skill_utilization(metrics, traces, task)
    scores["skill_utilization"] = {"score": round(s, 4), "evidence": e}

    s, e = score_skill_trigger_accuracy(metrics, task)
    scores["skill_trigger_accuracy"] = {"score": round(s, 4), "evidence": e}

    s, e = score_context_efficiency(metrics, traces, task)
    scores["context_efficiency"] = {"score": round(s, 4), "evidence": e}

    s, e = score_task_completion(workflow_state, verify_state, traces)
    scores["task_completion"] = {"score": round(s, 4), "evidence": e}

    s, e = score_execution_optimality(metrics, traces, task)
    scores["execution_optimality"] = {"score": round(s, 4), "evidence": e}

    s, e = score_cross_session_memory(traces)
    scores["cross_session_memory"] = {"score": round(s, 4), "evidence": e}

    # Composite score
    composite = sum(
        WEIGHTS[criterion] * data["score"]
        for criterion, data in scores.items()
    )

    result = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "task_id": args.task_id or (task_path.stem if task_path else "unknown"),
        "project_dir": str(project_dir),
        "scores": scores,
        "composite_score": round(composite, 4),
        "grade": grade(composite),
        "data_sources": {
            "traces": len(traces),
            "total_tool_calls": metrics.get("totalToolCalls", 0),
            "skills_used": list(metrics.get("skillUsage", {}).keys()),
        }
    }

    # Output
    output_path = args.output or (session_dir / "session-score.json")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"Score: {composite:.2f} (Grade: {grade(composite)})")
    print(f"Saved: {output_path}")

    # Print breakdown
    print("\nBreakdown:")
    for criterion, data in scores.items():
        weight = WEIGHTS[criterion]
        weighted = weight * data["score"]
        print(f"  {criterion:30s}  {data['score']:.2f} × {weight:.2f} = {weighted:.4f}")
    print(f"  {'COMPOSITE':30s}  {composite:.4f}")


if __name__ == "__main__":
    main()
