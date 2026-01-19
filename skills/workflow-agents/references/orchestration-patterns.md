# Orchestration Patterns

## Pattern Catalog

### 1. Sequential Pipeline

Execute agents in order, passing results forward.

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│ Analyze │ -> │ Design  │ -> │  Build  │ -> │  Test   │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
```

**Implementation:**

```python
async def sequential_pipeline(orchestrator, agents):
    stages = [
        ("analyzer", "Analyze requirements and existing code"),
        ("designer", "Design solution based on analysis"),
        ("builder", "Implement the designed solution"),
        ("tester", "Test the implementation")
    ]

    results = []
    for agent_name, task in stages:
        context = "\n".join(results) if results else ""
        prompt = f"""
        Previous context: {context}

        Current task: {task}
        Use {agent_name} agent to complete this task.
        """

        async for msg in orchestrator.run(prompt, agents):
            if hasattr(msg, 'result'):
                results.append(f"{agent_name}: {msg.result}")
            yield msg
```

**Use Cases:**

- Code review pipelines
- Feature development workflows
- CI/CD automation

---

### 2. Parallel Fan-out

Execute multiple agents simultaneously, then aggregate.

```
              ┌─────────┐
          -> │ Agent A │ -
         /   └─────────┘   \
┌───────┐    ┌─────────┐    ┌───────────┐
│ Start │ -> │ Agent B │ -> │ Aggregate │
└───────┘    └─────────┘    └───────────┘
         \   ┌─────────┐   /
          -> │ Agent C │ -
              └─────────┘
```

**Implementation:**

```python
async def parallel_fanout(orchestrator, agents):
    prompt = """
    Execute research tasks in parallel:

    1. Use auth-explorer to analyze authentication
    2. Use db-explorer to analyze database layer
    3. Use api-explorer to analyze API endpoints

    Run these simultaneously, then combine findings.
    """

    # Claude will automatically parallelize Task tool calls
    async for msg in orchestrator.run(prompt, agents):
        yield msg
```

**Use Cases:**

- Multi-module analysis
- Comprehensive codebase exploration
- Parallel testing

---

### 3. Conditional Branching

Choose workflow path based on conditions.

```
              ┌─────────┐
             │ Path A  │
            / └─────────┘
┌─────────┐/   ┌─────────┐
│ Decide  │ -> │ Path B  │
└─────────┘\   └─────────┘
            \ ┌─────────┐
             │ Path C  │
              └─────────┘
```

**Implementation:**

```python
async def conditional_branch(orchestrator, agents, context):
    # Analyze first
    analysis_prompt = "Analyze the current state and identify issues"
    issues = []

    async for msg in orchestrator.run(analysis_prompt, agents):
        if hasattr(msg, 'issues'):
            issues = msg.issues

    # Branch based on analysis
    if any(i['severity'] == 'critical' for i in issues):
        prompt = "Critical issues found. Use bug-fixer for immediate fixes."
    elif any(i['type'] == 'security' for i in issues):
        prompt = "Security issues found. Use security-auditor for analysis."
    else:
        prompt = "Minor issues only. Use code-reviewer for suggestions."

    async for msg in orchestrator.run(prompt, agents):
        yield msg
```

**Use Cases:**

- Adaptive workflows
- Error handling paths
- Priority-based routing

---

### 4. Iterative Refinement

Loop until quality threshold met.

```
┌─────────┐    ┌──────────┐    ┌─────────┐
│ Execute │ -> │ Evaluate │ -> │  Done?  │
└─────────┘    └──────────┘    └─────────┘
     ^                              │ No
     └──────────────────────────────┘
```

**Implementation:**

```python
async def iterative_refinement(orchestrator, agents, max_iterations=5):
    for iteration in range(max_iterations):
        # Execute
        exec_prompt = f"Iteration {iteration + 1}: Implement/improve the solution"
        async for msg in orchestrator.run(exec_prompt, agents):
            yield msg

        # Evaluate
        eval_prompt = "Use code-reviewer to evaluate current solution quality"
        quality_score = 0

        async for msg in orchestrator.run(eval_prompt, agents):
            if hasattr(msg, 'quality_score'):
                quality_score = msg.quality_score

        # Check threshold
        if quality_score >= 8:  # Out of 10
            yield {"status": "complete", "iterations": iteration + 1}
            return

    yield {"status": "max_iterations_reached"}
```

**Use Cases:**

- Code quality improvement
- Test coverage optimization
- Performance tuning

---

### 5. Supervisor Pattern

One agent coordinates others.

```
              ┌────────────┐
              │ Supervisor │
              └────────────┘
                    │
         ┌─────────┼─────────┐
         │         │         │
    ┌────────┐ ┌────────┐ ┌────────┐
    │ Worker │ │ Worker │ │ Worker │
    └────────┘ └────────┘ └────────┘
```

**Implementation:**

```python
async def supervisor_pattern(orchestrator, agents):
    supervisor_prompt = """
    You are the supervisor coordinating this project.

    Available workers:
    - code-reviewer: For quality checks
    - bug-fixer: For fixing issues
    - test-runner: For running tests
    - architect: For design decisions

    Analyze the project state and delegate tasks to appropriate workers.
    Coordinate their outputs and ensure quality standards are met.

    Continue until all acceptance criteria are satisfied.
    """

    async for msg in orchestrator.run(supervisor_prompt, agents):
        yield msg
```

**Use Cases:**

- Complex project management
- Multi-stage development
- Quality assurance workflows

---

### 6. Event-Driven Pipeline

React to events and trigger appropriate agents.

```
┌─────────┐    ┌───────────┐    ┌─────────┐
│  Event  │ -> │  Router   │ -> │  Agent  │
└─────────┘    └───────────┘    └─────────┘
```

**Implementation:**

```python
EVENT_HANDLERS = {
    'file_changed': 'code-reviewer',
    'test_failed': 'bug-fixer',
    'pr_opened': 'code-reviewer',
    'security_alert': 'security-auditor',
    'performance_issue': 'optimizer'
}

async def event_driven(orchestrator, agents, event):
    event_type = event.get('type')
    handler = EVENT_HANDLERS.get(event_type)

    if not handler:
        yield {"error": f"No handler for event: {event_type}"}
        return

    prompt = f"""
    Event: {event_type}
    Details: {event.get('details', 'None')}

    Use {handler} to handle this event appropriately.
    """

    async for msg in orchestrator.run(prompt, agents):
        yield msg
```

**Use Cases:**

- CI/CD integration
- Automated responses
- Monitoring and alerting

---

### 7. Map-Reduce

Process items in parallel, then combine results.

```
         ┌────────┐
        │ Map A  │
       / └────────┘ \
┌─────┐  ┌────────┐  ┌────────┐
│Split│->│ Map B  │->│ Reduce │
└─────┘  └────────┘  └────────┘
       \ ┌────────┐ /
        │ Map C  │
         └────────┘
```

**Implementation:**

```python
async def map_reduce(orchestrator, agents, items):
    # Map phase
    map_prompt = f"""
    Process these items in parallel:
    {items}

    For each item, use the appropriate agent to analyze it.
    Return individual results for each item.
    """

    map_results = []
    async for msg in orchestrator.run(map_prompt, agents):
        if hasattr(msg, 'item_result'):
            map_results.append(msg.item_result)
        yield msg

    # Reduce phase
    reduce_prompt = f"""
    Combine these results into a unified report:
    {map_results}

    Identify common patterns, aggregate statistics, and provide summary.
    """

    async for msg in orchestrator.run(reduce_prompt, agents):
        yield msg
```

**Use Cases:**

- Multi-file analysis
- Batch processing
- Aggregated reporting

---

### 8. Saga Pattern

Long-running workflow with compensation on failure.

```
┌────┐    ┌────┐    ┌────┐
│ T1 │ -> │ T2 │ -> │ T3 │ -> Success
└────┘    └────┘    └────┘
  │         │         │
  v         v         v
┌────┐    ┌────┐    ┌────┐
│ C1 │ <- │ C2 │ <- │ C3 │ <- Failure
└────┘    └────┘    └────┘
```

**Implementation:**

```python
async def saga_pattern(orchestrator, agents, transactions):
    completed = []

    for tx in transactions:
        try:
            prompt = f"Execute transaction: {tx['action']}"
            async for msg in orchestrator.run(prompt, agents):
                yield msg

            completed.append(tx)

        except Exception as e:
            yield {"error": str(e), "compensating": True}

            # Compensate in reverse order
            for completed_tx in reversed(completed):
                compensate_prompt = f"Compensate: {completed_tx['compensate']}"
                async for msg in orchestrator.run(compensate_prompt, agents):
                    yield msg

            return

    yield {"status": "all_transactions_complete"}
```

**Use Cases:**

- Database migrations
- Multi-service operations
- Reversible workflows

---

## Choosing the Right Pattern

| Scenario | Recommended Pattern |
|----------|---------------------|
| Step-by-step process | Sequential Pipeline |
| Independent parallel tasks | Parallel Fan-out |
| Decision-based routing | Conditional Branching |
| Quality improvement loop | Iterative Refinement |
| Complex coordination | Supervisor Pattern |
| Reactive automation | Event-Driven |
| Batch processing | Map-Reduce |
| Reversible operations | Saga Pattern |

---

## Combining Patterns

Patterns can be composed for complex workflows:

```python
async def complex_workflow(orchestrator, agents):
    # 1. Parallel analysis (Fan-out)
    analysis_prompt = "Analyze all modules in parallel"
    async for msg in orchestrator.run(analysis_prompt, agents):
        yield msg

    # 2. Conditional routing based on analysis
    if needs_refactoring:
        # 3. Iterative refinement
        async for msg in iterative_refinement(orchestrator, agents):
            yield msg
    else:
        # 4. Sequential enhancement
        async for msg in sequential_pipeline(orchestrator, agents):
            yield msg

    # 5. Final supervisor review
    async for msg in supervisor_pattern(orchestrator, agents):
        yield msg
```
