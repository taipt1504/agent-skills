# Claude Agent SDK Guide

## Installation

### Python

```bash
pip install claude-agent-sdk
```

### TypeScript/Node.js

```bash
npm install @anthropic-ai/claude-agent-sdk
```

### Prerequisites

- Claude Code CLI installed
- `ANTHROPIC_API_KEY` environment variable set

---

## Core API

### query() Function

The main entry point for running agent queries.

**Python:**

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        allowed_tools=["Read", "Write", "Edit", "Bash"],
        permission_mode="acceptEdits",
        cwd="/path/to/project",
        model="sonnet"
    )

    async for message in query(
        prompt="Analyze this codebase",
        options=options
    ):
        if hasattr(message, 'result'):
            print(message.result)
        elif hasattr(message, 'content'):
            for block in message.content:
                if hasattr(block, 'text'):
                    print(block.text)

asyncio.run(main())
```

**TypeScript:**

```typescript
import { query, ClaudeAgentOptions } from "@anthropic-ai/claude-agent-sdk";

async function main() {
  const options: ClaudeAgentOptions = {
    allowedTools: ["Read", "Write", "Edit", "Bash"],
    permissionMode: "acceptEdits",
    cwd: "/path/to/project",
    model: "sonnet"
  };

  for await (const message of query({
    prompt: "Analyze this codebase",
    options
  })) {
    if ("result" in message) {
      console.log(message.result);
    }
  }
}

main();
```

---

## ClaudeAgentOptions

| Option | Type | Description |
|--------|------|-------------|
| `allowed_tools` | `list[str]` | Tools the agent can use |
| `permission_mode` | `str` | Permission handling mode |
| `cwd` | `str` | Working directory |
| `model` | `str` | Model to use (haiku/sonnet/opus) |
| `agents` | `dict` | Custom agent definitions |
| `resume` | `str` | Session ID to resume |
| `max_turns` | `int` | Maximum conversation turns |
| `system_prompt` | `str` | Custom system prompt |
| `hooks` | `dict` | Hook configurations |

### Permission Modes

```python
# Ask before each operation (default)
permission_mode="default"

# Auto-accept file changes
permission_mode="acceptEdits"

# Skip all permission checks
permission_mode="bypassPermissions"

# Read-only exploration
permission_mode="plan"
```

---

## AgentDefinition

Define custom agents for specialized tasks.

```python
from claude_agent_sdk import AgentDefinition

agent = AgentDefinition(
    description="Short description for when to use this agent",
    prompt="Detailed instructions for the agent",
    tools=["Read", "Write", "Edit"],  # Optional: limit tools
    model="sonnet"  # Optional: specify model
)
```

### Using Custom Agents

```python
agents = {
    "my-agent": AgentDefinition(
        description="My specialized agent",
        prompt="You are an expert in...",
        tools=["Read", "Grep"],
        model="haiku"
    )
}

options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Task"],
    agents=agents
)

async for message in query(
    prompt="Use my-agent to analyze the code",
    options=options
):
    print(message)
```

---

## Message Types

### ResultMessage

Final result from the agent.

```python
if hasattr(message, 'result'):
    print(f"Result: {message.result}")
```

### AssistantMessage

Intermediate responses with content blocks.

```python
if hasattr(message, 'content'):
    for block in message.content:
        if hasattr(block, 'text'):
            print(block.text)
        elif hasattr(block, 'tool_use'):
            print(f"Tool: {block.tool_use.name}")
```

### InitMessage

Session initialization message.

```python
if hasattr(message, 'subtype') and message.subtype == 'init':
    session_id = message.session_id
```

---

## Session Management

Preserve context across multiple queries.

```python
class SessionManager:
    def __init__(self):
        self.session_id = None

    async def run(self, prompt, options):
        if self.session_id:
            options.resume = self.session_id

        async for message in query(prompt=prompt, options=options):
            if hasattr(message, 'subtype') and message.subtype == 'init':
                self.session_id = message.session_id
            yield message

    def reset(self):
        self.session_id = None
```

---

## Error Handling

```python
from claude_agent_sdk import (
    CLINotFoundError,
    ProcessError,
    CLIJSONDecodeError,
    MaxTurnsExceededError
)

try:
    async for message in query(prompt=prompt, options=options):
        pass
except CLINotFoundError:
    print("Claude Code CLI not installed")
except ProcessError as e:
    print(f"Process failed: exit_code={e.exit_code}")
    print(f"Stderr: {e.stderr}")
except CLIJSONDecodeError as e:
    print(f"JSON parse error: {e.line}")
except MaxTurnsExceededError:
    print("Max turns exceeded")
```

---

## Hooks

Intercept and validate agent actions.

### PreToolUse Hook

```python
async def validate_bash(input_data, tool_use_id, context):
    if input_data['tool_name'] == 'Bash':
        command = input_data['tool_input'].get('command', '')

        # Block dangerous commands
        if 'rm -rf' in command:
            return {
                'decision': 'block',
                'reason': 'Dangerous command blocked'
            }

        # Modify command
        if 'npm install' in command:
            return {
                'decision': 'modify',
                'tool_input': {
                    'command': command + ' --save-exact'
                }
            }

    return {}  # Allow

options = ClaudeAgentOptions(
    hooks={
        'PreToolUse': [
            {
                'matcher': 'Bash',
                'hooks': [validate_bash],
                'timeout': 120
            }
        ]
    }
)
```

### PostToolUse Hook

```python
async def log_edits(result, tool_use_id, context):
    if result.get('tool_name') == 'Edit':
        print(f"File edited: {result.get('file_path')}")
    return {}

options = ClaudeAgentOptions(
    hooks={
        'PostToolUse': [
            {
                'matcher': 'Edit',
                'hooks': [log_edits]
            }
        ]
    }
)
```

---

## Available Tools

| Tool | Description |
|------|-------------|
| `Read` | Read file contents |
| `Write` | Create new files |
| `Edit` | Modify existing files |
| `Bash` | Execute shell commands |
| `Glob` | Find files by pattern |
| `Grep` | Search file contents |
| `Task` | Spawn subagents |
| `WebFetch` | Fetch web content |
| `WebSearch` | Search the web |
| `TodoWrite` | Manage task lists |

---

## Best Practices

### 1. Minimal Tool Set

```python
# Reviewer: read-only
reviewer_agent = AgentDefinition(
    tools=["Read", "Glob", "Grep"]
)

# Builder: full access
builder_agent = AgentDefinition(
    tools=["Read", "Write", "Edit", "Bash"]
)
```

### 2. Model Selection

```python
# Quick tasks
model="haiku"  # Fast, cheap

# Standard tasks
model="sonnet"  # Balanced

# Complex reasoning
model="opus"  # Most capable
```

### 3. Streaming Results

```python
async for message in query(prompt=prompt, options=options):
    # Process incrementally
    if hasattr(message, 'content'):
        for block in message.content:
            if hasattr(block, 'text'):
                sys.stdout.write(block.text)
                sys.stdout.flush()
```

---

## External Links

- [Agent SDK Overview](https://platform.claude.com/docs/en/agent-sdk/overview.md)
- [Python SDK Reference](https://platform.claude.com/docs/en/agent-sdk/python.md)
- [TypeScript SDK Reference](https://platform.claude.com/docs/en/agent-sdk/typescript.md)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents.md)
