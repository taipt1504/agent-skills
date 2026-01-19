---
name: workflow-agents
description: Design and orchestrate multi-agent workflows for building products
triggers:
  - workflow agent
  - multi-agent
  - agent orchestration
  - claude agent sdk
  - subagent
  - /workflow-agents
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
references:
  - references/sdk-guide.md
  - references/orchestration-patterns.md
  - references/agent-definitions.md
scripts:
  - scripts/scaffold-project.sh
  - scripts/validate-agents.py
---

# Workflow Agents

Expert skill for designing and orchestrating multi-agent workflows to build products with Claude Agent SDK.

## Mục đích

Skill này giúp agent:

- Thiết kế kiến trúc multi-agent cho products
- Tạo và configure agent definitions
- Orchestrate workflows với multiple specialized agents
- Apply best practices cho agent coordination
- Scaffold project structure cho agent-based products

## Khi nào sử dụng

- Thiết kế hệ thống multi-agent
- Tạo workflow automation với Claude agents
- Build products sử dụng Agent SDK
- Configure agent permissions và tools
- Orchestrate complex tasks với subagents

## Khi nào KHÔNG sử dụng

- Single-task operations không cần coordination
- Simple scripts không cần agent intelligence
- Tasks không liên quan đến Claude Agent SDK

---

## Core Concepts

### Agent Types

| Type | Model | Tools | Use Case |
|------|-------|-------|----------|
| **Explorer** | Haiku | Read-only | Fast codebase search |
| **Reviewer** | Sonnet | Read + Grep | Code review, analysis |
| **Builder** | Sonnet | All | Implementation tasks |
| **Architect** | Opus | Read + Write | Complex design decisions |
| **Runner** | Haiku | Bash | Test execution, CI tasks |

### Permission Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `default` | Ask before each operation | Interactive development |
| `acceptEdits` | Auto-accept file changes | Trusted automation |
| `bypassPermissions` | Skip all checks | Fully automated CI/CD |
| `plan` | Read-only exploration | Safe analysis phase |

### Model Selection Strategy

```
┌─────────────────────────────────────────────────────┐
│ Task Complexity                                      │
├─────────────────────────────────────────────────────┤
│ Simple (search, list, quick check)     → Haiku     │
│ Moderate (review, fix, implement)      → Sonnet    │
│ Complex (design, architecture)         → Opus      │
└─────────────────────────────────────────────────────┘
```

---

## Project Structure

### Standard Layout

```
my-agent-product/
├── .claude/
│   ├── agents/                    # Agent definitions (version controlled)
│   │   ├── code-reviewer.md
│   │   ├── bug-fixer.md
│   │   ├── architect.md
│   │   └── test-runner.md
│   ├── skills/                    # Custom skills
│   │   └── domain-specific.md
│   ├── settings.json              # Permissions, hooks, sandbox
│   └── CLAUDE.md                  # Project context for agents
├── src/
│   ├── agents/
│   │   ├── __init__.py
│   │   ├── definitions.py         # Programmatic agent configs
│   │   ├── orchestrator.py        # Multi-agent coordination
│   │   └── workflows.py           # Workflow definitions
│   ├── hooks/
│   │   └── validators.py          # Custom hook validators
│   └── main.py                    # Entry point
├── tests/
│   ├── test_agents.py
│   └── test_workflows.py
├── requirements.txt
└── README.md
```

---

## Agent Definition Patterns

### Pattern 1: File-based Agent (Recommended for Version Control)

Create `.claude/agents/<agent-name>.md`:

```markdown
---
name: code-reviewer
description: Expert code reviewer. Use proactively after code changes.
tools: Read, Glob, Grep
model: sonnet
---

You are a senior code reviewer ensuring high standards.

## When Invoked

1. Run `git diff` to see recent changes
2. Focus on modified files
3. Begin review immediately

## Review Checklist

- [ ] Code is clear and readable
- [ ] Functions well-named
- [ ] No duplicated code
- [ ] Proper error handling
- [ ] No exposed secrets
- [ ] Input validation
- [ ] Test coverage

## Output Format

Provide feedback by priority:
- **Critical** (must fix)
- **Warnings** (should fix)
- **Suggestions** (consider)
```

### Pattern 2: Programmatic Agent (For Dynamic Configuration)

```python
from claude_agent_sdk import AgentDefinition

def create_agents(config: dict) -> dict:
    """Factory for creating agents based on config"""

    return {
        "code-reviewer": AgentDefinition(
            description="Expert code reviewer for quality and security",
            prompt=f"""You are a code reviewer for {config['project_name']}.

Focus areas:
- {config.get('focus', 'general quality')}
- Security vulnerabilities
- Performance issues

Tech stack: {', '.join(config.get('tech_stack', []))}
""",
            tools=["Read", "Glob", "Grep"],
            model="sonnet"
        ),

        "bug-fixer": AgentDefinition(
            description="Debugging specialist for errors and test failures",
            prompt="""You are an expert debugger.

Process:
1. Capture error message and stack trace
2. Identify reproduction steps
3. Isolate failure location
4. Implement minimal fix
5. Verify solution
""",
            tools=["Read", "Edit", "Bash", "Grep", "Glob"],
            model="sonnet"
        ),

        "architect": AgentDefinition(
            description="System design expert for architecture decisions",
            prompt="""You are a solutions architect.

When analyzing:
1. Understand constraints and requirements
2. Identify patterns and improvements
3. Consider scalability and maintainability
4. Propose changes with trade-offs
5. Provide implementation roadmap
""",
            tools=["Read", "Glob", "Grep", "Write"],
            model="opus"
        ),

        "test-runner": AgentDefinition(
            description="Testing specialist for execution and coverage",
            prompt="""You are a testing expert.

Process:
1. Identify test suite location
2. Run appropriate test commands
3. Parse and analyze results
4. Report failures with context
5. Suggest coverage improvements
""",
            tools=["Bash", "Read", "Glob"],
            model="haiku"
        )
    }
```

---

## Orchestration Patterns

### Pattern 1: Sequential Pipeline

```python
async def sequential_pipeline(orchestrator, agents):
    """Execute agents in sequence, passing context"""

    prompt = """
    Execute development pipeline:

    1. Use architect agent to analyze requirements
    2. Use code-reviewer agent to review existing code
    3. Use bug-fixer agent to resolve any issues found
    4. Use test-runner agent to verify everything works

    Pass findings from each stage to the next.
    """

    async for message in orchestrator.run(prompt, agents):
        yield message
```

### Pattern 2: Parallel Research

```python
async def parallel_research(orchestrator, agents):
    """Execute multiple research tasks simultaneously"""

    prompt = """
    Research the codebase in parallel:

    - Use auth-explorer to analyze authentication module
    - Use db-explorer to analyze database layer
    - Use api-explorer to analyze API endpoints

    Then synthesize findings into a comprehensive report.
    """

    async for message in orchestrator.run(prompt, agents):
        yield message
```

### Pattern 3: Conditional Branching

```python
async def conditional_workflow(orchestrator, agents, context):
    """Branch workflow based on conditions"""

    if context.get('has_failing_tests'):
        prompt = """
        Tests are failing. Execute fix workflow:
        1. Use bug-fixer to diagnose failures
        2. Use test-runner to verify fixes
        """
    elif context.get('needs_review'):
        prompt = """
        Code needs review:
        1. Use code-reviewer for quality check
        2. Use architect for design review
        """
    else:
        prompt = """
        Standard workflow:
        1. Use test-runner to run tests
        2. Use code-reviewer for final check
        """

    async for message in orchestrator.run(prompt, agents):
        yield message
```

### Pattern 4: Iterative Refinement

```python
async def iterative_refinement(orchestrator, agents, max_iterations=3):
    """Iterate until quality threshold met"""

    for i in range(max_iterations):
        # Review
        review_prompt = f"Iteration {i+1}: Use code-reviewer to analyze code quality"
        issues = []
        async for msg in orchestrator.run(review_prompt, agents):
            if hasattr(msg, 'issues'):
                issues = msg.issues

        # Check if done
        if not issues or all(issue['severity'] == 'suggestion' for issue in issues):
            break

        # Fix
        fix_prompt = f"Fix these issues: {issues}"
        async for msg in orchestrator.run(fix_prompt, agents):
            yield msg
```

---

## Workflow Orchestrator Implementation

### Base Orchestrator

```python
import asyncio
from typing import AsyncIterator, Optional, Dict, Any
from claude_agent_sdk import query, ClaudeAgentOptions, Message

class WorkflowOrchestrator:
    """Coordinates multiple agents for complex workflows"""

    def __init__(
        self,
        cwd: str = None,
        model: str = "sonnet",
        permission_mode: str = "acceptEdits"
    ):
        self.cwd = cwd
        self.model = model
        self.permission_mode = permission_mode
        self.session_id: Optional[str] = None
        self.context: Dict[str, Any] = {}

    async def run(
        self,
        prompt: str,
        agents: dict,
        tools: list = None,
        preserve_session: bool = True
    ) -> AsyncIterator[Message]:
        """Execute a workflow with specified agents"""

        default_tools = [
            "Read", "Write", "Edit", "Bash",
            "Glob", "Grep", "Task"
        ]

        options = ClaudeAgentOptions(
            allowed_tools=tools or default_tools,
            permission_mode=self.permission_mode,
            agents=agents,
            cwd=self.cwd,
            model=self.model,
            resume=self.session_id if preserve_session else None
        )

        async for message in query(prompt=prompt, options=options):
            # Capture session ID for context preservation
            if hasattr(message, 'subtype') and message.subtype == 'init':
                self.session_id = message.session_id

            # Store results in context
            if hasattr(message, 'result'):
                self.context['last_result'] = message.result

            yield message

    async def run_workflow(
        self,
        workflow_type: str,
        agents: dict,
        **kwargs
    ) -> AsyncIterator[Message]:
        """Run a predefined workflow type"""

        workflows = {
            'code-review': self._code_review_workflow,
            'bug-fix': self._bug_fix_workflow,
            'feature-dev': self._feature_dev_workflow,
            'security-audit': self._security_audit_workflow,
        }

        if workflow_type not in workflows:
            raise ValueError(f"Unknown workflow: {workflow_type}")

        async for message in workflows[workflow_type](agents, **kwargs):
            yield message

    async def _code_review_workflow(
        self,
        agents: dict,
        **kwargs
    ) -> AsyncIterator[Message]:
        prompt = """
        Execute comprehensive code review:

        1. Use code-reviewer to analyze quality and security
        2. Use test-runner to verify tests pass
        3. Use architect to review design patterns

        Provide summary of findings and recommendations.
        """
        async for msg in self.run(prompt, agents):
            yield msg

    async def _bug_fix_workflow(
        self,
        agents: dict,
        bug_report: str = "",
        **kwargs
    ) -> AsyncIterator[Message]:
        prompt = f"""
        Fix the reported bug:

        Bug Report: {bug_report}

        1. Use bug-fixer to diagnose and fix
        2. Use test-runner to verify fix
        3. Use code-reviewer to ensure quality

        Return fixed code and explanation.
        """
        async for msg in self.run(prompt, agents):
            yield msg

    async def _feature_dev_workflow(
        self,
        agents: dict,
        requirements: str = "",
        **kwargs
    ) -> AsyncIterator[Message]:
        prompt = f"""
        Develop feature with requirements:

        {requirements}

        1. Use architect to design feature
        2. Implement with proper error handling
        3. Use test-runner to create tests
        4. Use code-reviewer for final review

        Deliverables: code, tests, documentation.
        """
        async for msg in self.run(prompt, agents):
            yield msg

    async def _security_audit_workflow(
        self,
        agents: dict,
        **kwargs
    ) -> AsyncIterator[Message]:
        prompt = """
        Perform security audit:

        1. Use code-reviewer to scan for vulnerabilities
        2. Use architect to review security architecture
        3. Check for OWASP Top 10 issues
        4. Review authentication and authorization

        Report findings with severity levels.
        """
        async for msg in self.run(prompt, agents):
            yield msg

    def reset_session(self):
        """Clear session and context"""
        self.session_id = None
        self.context = {}
```

---

## Configuration Files

### settings.json

```json
{
  "model": "sonnet",
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(python:*)",
      "Bash(pytest:*)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Bash(sudo:*)",
      "Bash(curl|wget:*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "./scripts/validate-command.sh"
          }
        ],
        "timeout": 30
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "./scripts/post-edit-hook.sh"
          }
        ]
      }
    ]
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "network": {
      "allowLocalBinding": false
    }
  }
}
```

### CLAUDE.md (Project Context)

```markdown
# Project Context

## Overview
This is an agent-based product using Claude Agent SDK.

## Architecture

### Agent Hierarchy
- **Orchestrator**: Coordinates all agents
- **Specialists**: Domain-specific agents
- **Utilities**: Helper agents for common tasks

### Workflow Types
1. Code Review → Tests → Architecture Check
2. Bug Fix → Verify → Review
3. Feature Dev → Design → Implement → Test → Review

## Conventions

### Commit Messages
Use Conventional Commits: `type(scope): description`

### Code Style
- Python: Black + isort + flake8
- TypeScript: ESLint + Prettier

### Testing
- Unit tests required for all new code
- Integration tests for workflows

## Agent Guidelines

### Code Reviewer
- Read-only access
- Focus on quality and security
- Use Sonnet model

### Bug Fixer
- Edit access granted
- Verify fixes with tests
- Document root cause

### Architect
- Use Opus for complex decisions
- Consider scalability
- Provide trade-off analysis
```

---

## Best Practices

### 1. Principle of Least Privilege

```python
# DON'T: Give all tools to all agents
agent = AgentDefinition(
    description="Reviewer",
    prompt="Review code",
    # No tools specified = inherits ALL
)

# DO: Explicitly limit tools
agent = AgentDefinition(
    description="Reviewer",
    prompt="Review code for quality",
    tools=["Read", "Glob", "Grep"],  # Read-only
    model="sonnet"
)
```

### 2. Clear Agent Descriptions

```python
# DON'T: Vague description
description="Helper agent"

# DO: Specific, actionable description
description="Code review specialist for TypeScript. Use proactively after any .ts/.tsx file changes. Focuses on type safety and React patterns."
```

### 3. Session Management

```python
# DO: Preserve context across related operations
orchestrator = WorkflowOrchestrator()

# First call establishes session
async for msg in orchestrator.run("Analyze auth module", agents):
    pass

# Second call continues with context
async for msg in orchestrator.run("Now find all callers", agents):
    pass  # Has context from first call

# Reset when starting new task
orchestrator.reset_session()
```

### 4. Error Handling

```python
from claude_agent_sdk import (
    CLINotFoundError,
    ProcessError,
    CLIJSONDecodeError
)

async def safe_run(orchestrator, prompt, agents):
    try:
        async for msg in orchestrator.run(prompt, agents):
            yield msg
    except CLINotFoundError:
        print("Install Claude Code: curl -fsSL https://claude.ai/install.sh | bash")
        raise
    except ProcessError as e:
        print(f"Agent failed: {e.stderr}")
        raise
    except CLIJSONDecodeError as e:
        print(f"Parse error: {e.line}")
        raise
```

### 5. Cost Optimization

```python
# Use appropriate models for task complexity
agents = {
    # Fast, cheap - for simple tasks
    "explorer": AgentDefinition(
        description="Quick file search",
        model="haiku",
        tools=["Read", "Glob"]
    ),

    # Balanced - for most tasks
    "reviewer": AgentDefinition(
        description="Code review",
        model="sonnet",
        tools=["Read", "Grep", "Glob"]
    ),

    # Powerful - for complex reasoning
    "architect": AgentDefinition(
        description="System design",
        model="opus",
        tools=["Read", "Write", "Glob"]
    )
}
```

---

## Anti-patterns to Avoid

| Anti-pattern | Problem | Solution |
|--------------|---------|----------|
| God Agent | One agent does everything | Split into specialized agents |
| Over-permissioning | Agents have unnecessary tools | Apply least privilege |
| No session management | Context lost between calls | Use session preservation |
| Hardcoded prompts | Can't adapt to different projects | Use templates with config |
| No error handling | Failures crash the system | Implement try/catch |
| Wrong model selection | Waste money or capability | Match model to task |

---

## Checklist for Production

```
[ ] All agents have explicit tool restrictions
[ ] Models matched to task complexity
[ ] Session management implemented
[ ] Error handling for all failure modes
[ ] Hooks configured for validation
[ ] Sandbox enabled for untrusted operations
[ ] Permissions explicitly allow/deny
[ ] CLAUDE.md documents project context
[ ] Tests cover agent workflows
[ ] Cost monitoring in place
```

---

## References

- `references/sdk-guide.md` - Claude Agent SDK documentation
- `references/orchestration-patterns.md` - Advanced orchestration patterns
- `references/agent-definitions.md` - Agent definition examples

## Scripts

- `scripts/scaffold-project.sh` - Scaffold new agent project
- `scripts/validate-agents.py` - Validate agent configurations
