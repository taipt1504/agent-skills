#!/bin/bash
# Scaffold a new agent-based project
#
# Usage:
#   ./scaffold-project.sh <project-name> [options]
#   ./scaffold-project.sh my-agent-product --python
#   ./scaffold-project.sh my-agent-product --typescript
#
# Options:
#   --python      Use Python SDK (default)
#   --typescript  Use TypeScript SDK
#   --minimal     Minimal setup without examples
#   --help        Show this help

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_usage() {
    echo "Scaffold Agent-Based Project"
    echo ""
    echo "Usage: $0 <project-name> [options]"
    echo ""
    echo "Options:"
    echo "  --python      Use Python SDK (default)"
    echo "  --typescript  Use TypeScript SDK"
    echo "  --minimal     Minimal setup"
    echo "  --help        Show this help"
    echo ""
    echo "Example:"
    echo "  $0 my-agent-product --python"
}

# Defaults
SDK="python"
MINIMAL=false

# Parse args
if [ $# -eq 0 ]; then
    print_usage
    exit 1
fi

PROJECT_NAME=$1
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --python)
            SDK="python"
            shift
            ;;
        --typescript)
            SDK="typescript"
            shift
            ;;
        --minimal)
            MINIMAL=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

echo ""
echo "Creating agent project: $PROJECT_NAME"
echo "SDK: $SDK"
echo "Minimal: $MINIMAL"
echo ""

# Create project directory
print_step "Creating project structure..."

mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Create .claude directory
mkdir -p .claude/agents .claude/skills

# Create src directory based on SDK
if [ "$SDK" = "python" ]; then
    mkdir -p src/agents src/hooks tests
elif [ "$SDK" = "typescript" ]; then
    mkdir -p src/agents src/hooks tests
fi

print_success "Project structure created"

# Create agent definitions
print_step "Creating agent definitions..."

cat > .claude/agents/code-reviewer.md << 'EOF'
---
name: code-reviewer
description: Expert code reviewer for quality and security. Use proactively after code changes.
tools: Read, Glob, Grep
model: sonnet
---

You are a senior code reviewer ensuring high standards.

## When Invoked
1. Run `git diff` to see recent changes
2. Focus on modified files
3. Begin review immediately

## Review Checklist
- Code is clear and readable
- Functions well-named
- No duplicated code
- Proper error handling
- No exposed secrets
- Input validation
- Test coverage

## Output Format
Provide feedback by priority:
- **Critical** (must fix)
- **Warnings** (should fix)
- **Suggestions** (consider)
EOF

cat > .claude/agents/bug-fixer.md << 'EOF'
---
name: bug-fixer
description: Debugging specialist for errors and test failures. Use when encountering bugs.
tools: Read, Edit, Bash, Grep, Glob
model: sonnet
---

You are an expert debugger.

## Process
1. Capture error message and stack trace
2. Identify reproduction steps
3. Isolate failure location
4. Implement minimal fix
5. Verify solution works
EOF

cat > .claude/agents/test-runner.md << 'EOF'
---
name: test-runner
description: Testing specialist for test execution and coverage. Use for running tests.
tools: Bash, Read, Glob
model: haiku
---

You are a testing expert.

## Process
1. Identify test suite location
2. Run appropriate test commands
3. Parse and analyze results
4. Report failures with context
EOF

print_success "Agent definitions created"

# Create CLAUDE.md
print_step "Creating CLAUDE.md..."

cat > .claude/CLAUDE.md << EOF
# $PROJECT_NAME

## Overview
Agent-based project using Claude Agent SDK.

## Agent Hierarchy
- code-reviewer: Quality and security review
- bug-fixer: Debugging and fixes
- test-runner: Test execution

## Conventions
- Commit messages: Conventional Commits
- Code style: Follow project linter

## Workflows
1. Code Review: Review → Tests → Done
2. Bug Fix: Diagnose → Fix → Verify → Review
EOF

print_success "CLAUDE.md created"

# Create settings.json
print_step "Creating settings.json..."

cat > .claude/settings.json << 'EOF'
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
      "Bash(sudo:*)"
    ]
  }
}
EOF

print_success "settings.json created"

# Create SDK-specific files
if [ "$SDK" = "python" ]; then
    print_step "Creating Python project files..."

    # requirements.txt
    cat > requirements.txt << 'EOF'
claude-agent-sdk>=0.1.0
pytest>=7.0.0
pytest-asyncio>=0.21.0
EOF

    # src/agents/__init__.py
    cat > src/agents/__init__.py << 'EOF'
from .definitions import AGENTS
from .orchestrator import WorkflowOrchestrator

__all__ = ['AGENTS', 'WorkflowOrchestrator']
EOF

    # src/agents/definitions.py
    cat > src/agents/definitions.py << 'EOF'
from claude_agent_sdk import AgentDefinition

AGENTS = {
    "code-reviewer": AgentDefinition(
        description="Expert code reviewer for quality and security",
        prompt="""You are a senior code reviewer.
Focus on code quality, security, and best practices.
Provide feedback by priority: Critical > Warnings > Suggestions.""",
        tools=["Read", "Glob", "Grep"],
        model="sonnet"
    ),

    "bug-fixer": AgentDefinition(
        description="Debugging specialist for errors and fixes",
        prompt="""You are an expert debugger.
1. Capture error and stack trace
2. Isolate the failure
3. Implement minimal fix
4. Verify the solution""",
        tools=["Read", "Edit", "Bash", "Grep", "Glob"],
        model="sonnet"
    ),

    "test-runner": AgentDefinition(
        description="Testing specialist for execution and coverage",
        prompt="""You are a testing expert.
Run tests, analyze results, and report failures with context.""",
        tools=["Bash", "Read", "Glob"],
        model="haiku"
    )
}
EOF

    # src/agents/orchestrator.py
    cat > src/agents/orchestrator.py << 'EOF'
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

    async def run(
        self,
        prompt: str,
        agents: dict,
        tools: list = None
    ) -> AsyncIterator[Message]:
        """Execute a workflow with specified agents"""

        default_tools = ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Task"]

        options = ClaudeAgentOptions(
            allowed_tools=tools or default_tools,
            permission_mode=self.permission_mode,
            agents=agents,
            cwd=self.cwd,
            model=self.model,
            resume=self.session_id
        )

        async for message in query(prompt=prompt, options=options):
            if hasattr(message, 'subtype') and message.subtype == 'init':
                self.session_id = message.session_id
            yield message

    async def code_review(self, agents: dict) -> AsyncIterator[Message]:
        """Run code review workflow"""
        prompt = """
        Execute code review:
        1. Use code-reviewer to analyze quality and security
        2. Use test-runner to verify tests pass
        Provide summary of findings.
        """
        async for msg in self.run(prompt, agents):
            yield msg

    async def bug_fix(self, bug_report: str, agents: dict) -> AsyncIterator[Message]:
        """Run bug fix workflow"""
        prompt = f"""
        Fix this bug: {bug_report}

        1. Use bug-fixer to diagnose and fix
        2. Use test-runner to verify fix
        3. Use code-reviewer for quality check
        """
        async for msg in self.run(prompt, agents):
            yield msg

    def reset_session(self):
        """Clear session context"""
        self.session_id = None
EOF

    # src/main.py
    cat > src/main.py << 'EOF'
import asyncio
import sys
from agents import AGENTS, WorkflowOrchestrator


async def run_code_review():
    """Run code review workflow"""
    orchestrator = WorkflowOrchestrator()

    print("Starting code review...")
    async for message in orchestrator.code_review(AGENTS):
        if hasattr(message, 'result'):
            print(f"\nResult: {message.result}")


async def run_bug_fix(bug_report: str):
    """Run bug fix workflow"""
    orchestrator = WorkflowOrchestrator()

    print(f"Fixing bug: {bug_report}")
    async for message in orchestrator.bug_fix(bug_report, AGENTS):
        if hasattr(message, 'result'):
            print(f"\nResult: {message.result}")


async def main():
    if len(sys.argv) < 2:
        print("Usage: python main.py <command> [args]")
        print("Commands:")
        print("  review              - Run code review")
        print("  fix <bug_report>    - Fix a bug")
        return

    command = sys.argv[1]

    if command == "review":
        await run_code_review()
    elif command == "fix":
        if len(sys.argv) < 3:
            print("Please provide bug report")
            return
        await run_bug_fix(" ".join(sys.argv[2:]))
    else:
        print(f"Unknown command: {command}")


if __name__ == "__main__":
    asyncio.run(main())
EOF

    # tests/test_agents.py
    cat > tests/test_agents.py << 'EOF'
import pytest
from src.agents import AGENTS, WorkflowOrchestrator


def test_agents_defined():
    """Test all required agents are defined"""
    assert "code-reviewer" in AGENTS
    assert "bug-fixer" in AGENTS
    assert "test-runner" in AGENTS


def test_code_reviewer_tools():
    """Test code-reviewer has correct tools"""
    agent = AGENTS["code-reviewer"]
    assert "Read" in agent.tools
    assert "Write" not in agent.tools  # Should be read-only


def test_orchestrator_creation():
    """Test orchestrator can be created"""
    orchestrator = WorkflowOrchestrator()
    assert orchestrator.model == "sonnet"
    assert orchestrator.session_id is None
EOF

    print_success "Python files created"

elif [ "$SDK" = "typescript" ]; then
    print_step "Creating TypeScript project files..."

    # package.json
    cat > package.json << 'EOF'
{
  "name": "agent-project",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "tsx src/main.ts",
    "test": "vitest",
    "build": "tsc"
  },
  "dependencies": {
    "@anthropic-ai/claude-agent-sdk": "^0.1.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "tsx": "^4.0.0",
    "vitest": "^1.0.0",
    "@types/node": "^20.0.0"
  }
}
EOF

    # tsconfig.json
    cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "node",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
EOF

    # src/agents/definitions.ts
    cat > src/agents/definitions.ts << 'EOF'
import { AgentDefinition } from "@anthropic-ai/claude-agent-sdk";

export const AGENTS: Record<string, AgentDefinition> = {
  "code-reviewer": {
    description: "Expert code reviewer for quality and security",
    prompt: `You are a senior code reviewer.
Focus on code quality, security, and best practices.
Provide feedback by priority: Critical > Warnings > Suggestions.`,
    tools: ["Read", "Glob", "Grep"],
    model: "sonnet"
  },

  "bug-fixer": {
    description: "Debugging specialist for errors and fixes",
    prompt: `You are an expert debugger.
1. Capture error and stack trace
2. Isolate the failure
3. Implement minimal fix
4. Verify the solution`,
    tools: ["Read", "Edit", "Bash", "Grep", "Glob"],
    model: "sonnet"
  },

  "test-runner": {
    description: "Testing specialist for execution and coverage",
    prompt: `You are a testing expert.
Run tests, analyze results, and report failures with context.`,
    tools: ["Bash", "Read", "Glob"],
    model: "haiku"
  }
};
EOF

    # src/main.ts
    cat > src/main.ts << 'EOF'
import { query, ClaudeAgentOptions } from "@anthropic-ai/claude-agent-sdk";
import { AGENTS } from "./agents/definitions.js";

async function runCodeReview() {
  const options: ClaudeAgentOptions = {
    allowedTools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Task"],
    permissionMode: "acceptEdits",
    agents: AGENTS
  };

  console.log("Starting code review...");

  for await (const message of query({
    prompt: `Execute code review:
1. Use code-reviewer to analyze quality
2. Use test-runner to verify tests`,
    options
  })) {
    if ("result" in message) {
      console.log("\nResult:", message.result);
    }
  }
}

const command = process.argv[2];

if (command === "review") {
  runCodeReview();
} else {
  console.log("Usage: npm start review");
}
EOF

    print_success "TypeScript files created"
fi

# Create .gitignore
print_step "Creating .gitignore..."

cat > .gitignore << 'EOF'
# Dependencies
node_modules/
__pycache__/
*.pyc
.venv/
venv/

# Build
dist/
build/
*.egg-info/

# IDE
.idea/
.vscode/
*.swp

# Environment
.env
.env.local

# Coverage
coverage/
htmlcov/
.coverage

# OS
.DS_Store
Thumbs.db
EOF

print_success ".gitignore created"

# Create README
print_step "Creating README.md..."

cat > README.md << EOF
# $PROJECT_NAME

Agent-based project using Claude Agent SDK.

## Setup

\`\`\`bash
# Install dependencies
$(if [ "$SDK" = "python" ]; then echo "pip install -r requirements.txt"; else echo "npm install"; fi)

# Set API key
export ANTHROPIC_API_KEY=your-key
\`\`\`

## Usage

\`\`\`bash
# Run code review
$(if [ "$SDK" = "python" ]; then echo "python src/main.py review"; else echo "npm start review"; fi)

# Fix a bug
$(if [ "$SDK" = "python" ]; then echo "python src/main.py fix \"description of bug\""; else echo "npm start fix \"description\""; fi)
\`\`\`

## Agents

| Agent | Purpose | Model |
|-------|---------|-------|
| code-reviewer | Quality and security review | Sonnet |
| bug-fixer | Debugging and fixes | Sonnet |
| test-runner | Test execution | Haiku |

## Project Structure

\`\`\`
$PROJECT_NAME/
├── .claude/
│   ├── agents/           # Agent definitions
│   ├── CLAUDE.md         # Project context
│   └── settings.json     # Permissions
├── src/
│   ├── agents/           # Agent code
│   └── main.$(if [ "$SDK" = "python" ]; then echo "py"; else echo "ts"; fi)
└── tests/
\`\`\`
EOF

print_success "README.md created"

# Done
echo ""
echo -e "${GREEN}Project scaffolded successfully!${NC}"
echo ""
echo "Next steps:"
echo "  cd $PROJECT_NAME"
if [ "$SDK" = "python" ]; then
    echo "  pip install -r requirements.txt"
    echo "  export ANTHROPIC_API_KEY=your-key"
    echo "  python src/main.py review"
else
    echo "  npm install"
    echo "  export ANTHROPIC_API_KEY=your-key"
    echo "  npm start review"
fi
