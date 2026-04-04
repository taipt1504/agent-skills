# Plugin Evaluation & Benchmark Framework

## Overview

This framework measures the effectiveness of `devco-agent-skills` plugin when used by Claude Code agents in real-world tasks.

## 9 Evaluation Criteria

| # | Criterion | Weight | Category |
|---|-----------|--------|----------|
| 1 | Code Quality | 15% | Output |
| 2 | Convention Compliance | 10% | Output |
| 3 | Workflow Compliance | 10% | Process |
| 4 | Skill Utilization Effectiveness | 15% | Agent Behavior |
| 5 | Skill Trigger Accuracy | 10% | Routing |
| 6 | Context Efficiency & Memory | 10% | Resource |
| 7 | Task Completion Rate | 15% | Outcome |
| 8 | Task Execution Optimality | 10% | Efficiency |
| 9 | Cross-Session Memory | 5% | Continuity |

## Directory Structure

```
evals/
├── README.md                   # This file
├── tasks/                      # 15 eval tasks (input prompts)
│   ├── category-task.md        # Task description + expected behavior
│   └── ...
├── rubrics/                    # Scoring criteria definitions
│   ├── scoring-criteria.md     # All 9 criteria with measurement methods
│   └── grader-prompt.md        # Prompt for grader agent
├── scripts/
│   ├── run-benchmark.sh        # Run full benchmark suite
│   ├── score-session.py        # Score a single session from traces
│   ├── aggregate-scores.py     # Aggregate scores across sessions
│   └── generate-report.py      # Generate HTML/markdown report
├── baselines/
│   ├── with-plugin/            # Outputs when plugin is active
│   └── without-plugin/         # Outputs with vanilla Claude Code
└── results/                    # Benchmark results (gitignored)
    └── YYYY-MM-DD/
        ├── benchmark.json
        └── benchmark.md
```

## Quick Start

```bash
# Score a completed session
python3 evals/scripts/score-session.py --session-dir .claude/sessions/

# Run full benchmark (requires claude CLI)
bash evals/scripts/run-benchmark.sh

# Aggregate historical scores
python3 evals/scripts/aggregate-scores.py --results-dir evals/results/
```
