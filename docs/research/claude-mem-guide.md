# Claude-Mem Deep Dive Guide

> Tài liệu hướng dẫn toàn diện cho anh Tài — từ cài đặt, cấu hình, đến best practices và quản lý memory trong Claude Code.

**Version:** 10.5.5 | **Repo:** https://github.com/thedotmack/claude-mem | **License:** MIT

---

## Mục lục

1. [Tổng quan](#1-tổng-quan)
2. [Kiến trúc hệ thống](#2-kiến-trúc-hệ-thống)
3. [Cài đặt](#3-cài-đặt)
4. [Configuration](#4-configuration)
5. [AI Providers](#5-ai-providers)
6. [Cách claude-mem hoạt động](#6-cách-claude-mem-hoạt-động)
7. [Memory Management](#7-memory-management)
8. [Search & Retrieval](#8-search--retrieval)
9. [Context Engineering](#9-context-engineering)
10. [Best Practices cho Claude Code](#10-best-practices-cho-claude-code)
11. [Troubleshooting](#11-troubleshooting)
12. [Dành riêng cho VPS VN](#12-dành-riêng-cho-vps-vn)

---

## 1. Tổng quan

### claude-mem là gì?

claude-mem là **persistent memory plugin** cho Claude Code. Nó giải quyết vấn đề lớn nhất của Claude Code: **mỗi session bắt đầu từ zero** — không nhớ session trước làm gì, fix bug gì, quyết định gì.

### Nó làm gì?

- **Tự động quan sát** mọi tool execution (file read, write, exec, search...)
- **AI phân tích** mỗi observation → extract structured learnings (title, narrative, facts, concepts, type)
- **Lưu vào SQLite** + FTS5 full-text search
- **Inject context** vào session mới → Claude biết mình đã làm gì trước đó
- **Search** qua lịch sử bằng MCP tools hoặc HTTP API

### Không phải gì?

- Không phải RAG truyền thống (không dùng embeddings làm primary)
- Không phải simple key-value store
- Không phải file-based memory (như MEMORY.md) — đây là structured database + AI processing

---

## 2. Kiến trúc hệ thống

### Components

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code CLI Session                                  │
│                                                          │
│  Hook 1: SessionStart                                    │
│  ├── Smart Install (check deps, cached)                  │
│  └── Context Hook → inject past observations             │
│                                                          │
│  Hook 2: UserPromptSubmit                                │
│  └── New Hook → create session, save raw prompt          │
│                                                          │
│  Hook 3: PostToolUse (fires 100+ times/session)          │
│  └── Save Hook → capture tool input/output               │
│                                                          │
│  Hook 4: Stop                                            │
│  └── Summary Hook → generate session summary             │
│                                                          │
│  Hook 5: SessionEnd                                      │
│  └── Cleanup Hook → mark session complete                │
└────────────────────┬────────────────────────────────────┘
                     │ HTTP API
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Worker Service (port 37777)                              │
│ ├── Express.js HTTP server                               │
│ ├── Bun runtime (background process)                     │
│ ├── Claude Agent SDK / Gemini / OpenRouter               │
│ ├── SQLite + FTS5 database                               │
│ ├── SSE real-time stream                                 │
│ └── Viewer UI (React)                                    │
└─────────────────────────────────────────────────────────┘
```

### Data Flow (1 session)

```
1. Session Start
   → Smart Install (10ms nếu cached)
   → Load 50 observations gần nhất từ DB
   → Inject vào Claude Code context

2. User gõ prompt
   → Save raw prompt vào user_prompts table
   → Tạo/update session record

3. Claude dùng tool (Read, Write, Bash, etc.)
   → PostToolUse hook fire
   → Tool name + input + output → gửi Worker
   → Worker dùng AI (Claude/Gemini/OpenRouter) phân tích
   → Extract: title, narrative, facts, concepts, type, files
   → Save observation vào SQLite + FTS5 index

4. Claude stops (user sends /stop hoặc task xong)
   → Summary Hook fire
   → Generate session summary: request, investigated, learned, completed, next_steps

5. Session End
   → Mark session complete
   → Data sẵn sàng cho session tiếp theo
```

### Database Schema (SQLite + FTS5)

**4 core tables:**

| Table | Mục đích | Key fields |
|-------|----------|------------|
| `sdk_sessions` | Track sessions | sdk_session_id, project, status, prompt_counter |
| `observations` | Individual learnings | title, narrative, facts, concepts, type, files_read, files_modified |
| `session_summaries` | Session summaries | request, investigated, learned, completed, next_steps |
| `user_prompts` | Raw user prompts | prompt_text, prompt_number |

**3 FTS5 virtual tables** (full-text search):
- `observations_fts` → search title, narrative, facts, concepts
- `session_summaries_fts` → search request, learned, completed, next_steps
- `user_prompts_fts` → search prompt_text

Auto-sync bằng INSERT/UPDATE/DELETE triggers.

### Observation Types

| Type | Ý nghĩa |
|------|---------|
| `decision` | Quyết định kiến trúc / design |
| `bugfix` | Fix bug |
| `feature` | Feature mới |
| `refactor` | Refactor code |
| `discovery` | Học được điều gì đó về codebase |
| `change` | Thay đổi chung |

### Observation Concepts (tags)

| Concept | Ý nghĩa |
|---------|---------|
| `how-it-works` | Cách hệ thống hoạt động |
| `why-it-exists` | Lý do code/design tồn tại |
| `what-changed` | Tóm tắt thay đổi |
| `problem-solution` | Cặp problem→solution |
| `gotcha` | Edge cases, pitfalls |
| `pattern` | Recurring patterns |
| `trade-off` | Trade-offs trong design |

---

## 3. Cài đặt

### Prerequisites

| Dependency | Version | Ghi chú |
|-----------|---------|---------|
| Node.js | ≥ 18.0.0 | Để chạy hooks |
| Claude Code CLI | Latest | Plugin host |
| Bun | Auto-installed | Worker runtime |
| SQLite 3 | Bundled | Database |

### Quick Install (Recommended)

Mở Claude Code CLI session, chạy:

```
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
```

**Xong.** Plugin tự động:
- Download prebuilt binaries
- Install dependencies (Bun, SQLite)
- Configure hooks
- Auto-start worker trên session đầu tiên

### Install từ Source (Development)

```bash
git clone https://github.com/thedotmack/claude-mem.git
cd claude-mem
npm install
npm run build

# Start worker thủ công
npm run worker:start
npm run worker:status
```

### Verify cài đặt

```bash
# Check hooks
cat plugin/hooks/hooks.json

# Check data directory
ls -la ~/.claude-mem/

# Check worker
npm run worker:status

# Test context
npm run test:context
```

### Data Directory

```
~/.claude-mem/
├── claude-mem.db           # SQLite database
├── .install-version        # Version cache cho smart installer
├── worker.port             # Worker port file
├── settings.json           # User settings
└── logs/
    └── worker-YYYY-MM-DD.log  # Daily logs
```

Override: `export CLAUDE_MEM_DATA_DIR=/custom/path`

### Upgrade

Tự động khi update qua marketplace. Notable changes:
- **v7.1.0**: PM2 → native Bun process management
- **v7.0.0+**: 11 config settings, dual-tag privacy
- **v5.4.0+**: Skill-based search (saves ~2,250 tokens/session)

⚠️ **QUAN TRỌNG**: `npm install -g claude-mem` chỉ install SDK/library, KHÔNG register hooks. Luôn dùng `/plugin` commands.

---

## 4. Configuration

### Settings File

`~/.claude-mem/settings.json` — tự tạo với defaults khi chạy lần đầu.

### Core Settings

| Setting | Default | Mô tả |
|---------|---------|-------|
| `CLAUDE_MEM_MODEL` | `sonnet` | AI model cho processing (khi dùng Claude provider) |
| `CLAUDE_MEM_PROVIDER` | `claude` | AI provider: `claude`, `gemini`, `openrouter` |
| `CLAUDE_MEM_MODE` | `code` | Mode profile (vd: `code--vi` cho tiếng Việt) |
| `CLAUDE_MEM_CONTEXT_OBSERVATIONS` | `50` | Số observations inject vào session mới |
| `CLAUDE_MEM_WORKER_PORT` | `37777` | Worker service port |
| `CLAUDE_MEM_WORKER_HOST` | `127.0.0.1` | Worker host |
| `CLAUDE_MEM_SKIP_TOOLS` | `ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion` | Tools không capture observation |

### Context Injection Settings

| Setting | Default | Range | Mô tả |
|---------|---------|-------|-------|
| `CLAUDE_MEM_CONTEXT_OBSERVATIONS` | `50` | 1-200 | Số observations inject |
| `CLAUDE_MEM_CONTEXT_SESSION_COUNT` | `10` | 1-50 | Số sessions gần nhất để pull |
| `CLAUDE_MEM_CONTEXT_FULL_COUNT` | `5` | 0-20 | Số observations hiện expanded |
| `CLAUDE_MEM_CONTEXT_FULL_FIELD` | `narrative` | narrative/facts | Field nào expand |
| `CLAUDE_MEM_CONTEXT_OBSERVATION_TYPES` | all | Comma-separated | Filter by type |
| `CLAUDE_MEM_CONTEXT_OBSERVATION_CONCEPTS` | all | Comma-separated | Filter by concept |
| `CLAUDE_MEM_CONTEXT_SHOW_LAST_SUMMARY` | `false` | true/false | Include summary session trước |
| `CLAUDE_MEM_CONTEXT_SHOW_LAST_MESSAGE` | `false` | true/false | Include message cuối session trước |

### Token Economics Settings

| Setting | Default | Mô tả |
|---------|---------|-------|
| `CLAUDE_MEM_CONTEXT_SHOW_READ_TOKENS` | `true` | Hiện cost đọc mỗi observation |
| `CLAUDE_MEM_CONTEXT_SHOW_WORK_TOKENS` | `true` | Hiện tokens đã dùng tạo observation |
| `CLAUDE_MEM_CONTEXT_SHOW_SAVINGS_AMOUNT` | `true` | Hiện tokens tiết kiệm nhờ cache |

### System Settings

| Setting | Default | Mô tả |
|---------|---------|-------|
| `CLAUDE_MEM_DATA_DIR` | `~/.claude-mem` | Data directory |
| `CLAUDE_MEM_LOG_LEVEL` | `INFO` | Log verbosity: DEBUG, INFO, WARN, ERROR, SILENT |
| `CLAUDE_MEM_FOLDER_CLAUDEMD_ENABLED` | `false` | Auto-generate folder CLAUDE.md files |

### Modes & Languages

Format: `<mode>--<variant>` hoặc `<mode>--<lang>`

**Code mode variants:**
- `code` — default
- `code--chill` — ít observations hơn, chỉ ghi "painful to rediscover"

**Multilingual:**
- `code--vi` — Tiếng Việt 🇻🇳
- `code--ja` — 日本語
- `code--ko` — 한국어
- `code--zh` — 中文
- ... 29 ngôn ngữ khác

**Specialized modes:**
- `email-investigation` — phân tích email dumps

```json
{
  "CLAUDE_MEM_MODE": "code--vi"
}
```

### Config via UI

Mở `http://localhost:37777` → Settings gear icon. Live preview trong Terminal Preview panel. Settings auto-save.

---

## 5. AI Providers

claude-mem hỗ trợ **3 providers** cho observation extraction:

### Provider 1: Claude (Default)

- **Mechanism**: Claude Agent SDK (subscription billing qua Claude Code CLI)
- **Setup**: Tự động, không cần config
- **Cost**: Dùng subscription Claude Code
- **Quality**: Cao nhất
- **Model options**: `haiku`, `sonnet` (default), `opus`

```json
{
  "CLAUDE_MEM_PROVIDER": "claude",
  "CLAUDE_MEM_MODEL": "sonnet"
}
```

### Provider 2: Gemini (Free tier)

- **Mechanism**: Google Gemini API trực tiếp
- **Setup**: Cần API key từ https://aistudio.google.com/app/apikey
- **Cost**: Free tier generous (có billing = 4000 RPM, không billing = 10 RPM)
- **Quality**: Cao
- **⚠️ VN Issue**: Bị geo-block, cần proxy (xem [Section 12](#12-dành-riêng-cho-vps-vn))

```json
{
  "CLAUDE_MEM_PROVIDER": "gemini",
  "CLAUDE_MEM_GEMINI_API_KEY": "your-key",
  "CLAUDE_MEM_GEMINI_MODEL": "gemini-2.5-flash-lite"
}
```

| Model | Free RPM (no billing) | Free RPM (with billing) |
|-------|----------------------|------------------------|
| `gemini-2.5-flash-lite` | 10 | 4,000 |
| `gemini-2.5-flash` | 5 | 1,000 |
| `gemini-3-flash-preview` | 5 | 1,000 |

### Provider 3: OpenRouter (100+ models)

- **Mechanism**: OpenRouter unified API
- **Setup**: Cần API key từ https://openrouter.ai/keys
- **Cost**: Free models available (không cần credit card)
- **Quality**: Varies by model
- **Default model**: `xiaomi/mimo-v2-flash:free` (309B MoE, #1 SWE-bench)

```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "sk-or-v1-...",
  "CLAUDE_MEM_OPENROUTER_MODEL": "xiaomi/mimo-v2-flash:free"
}
```

**Free models đáng dùng:**

| Model | Parameters | Context |
|-------|-----------|---------|
| `xiaomi/mimo-v2-flash:free` | 309B (15B active) | 256K |
| `google/gemini-2.5-flash-preview:free` | — | 1M |
| `deepseek/deepseek-r1:free` | 671B | 64K |
| `meta-llama/llama-3.1-70b-instruct:free` | 70B | 128K |

### Provider Switching

- **Hot-swap**: Đổi provider không cần restart worker
- **Auto-fallback**: Gemini/OpenRouter fail → tự động fallback về Claude
- **Conversation preserved**: Context giữ nguyên khi switch

### So sánh

| Feature | Claude | Gemini | OpenRouter |
|---------|--------|--------|------------|
| Cost | Subscription | Free tier | Free models |
| Quality | Cao nhất | Cao | Varies |
| Rate limits | Theo plan | 5-4000 RPM | Varies |
| Setup | Tự động | API key | API key |
| Fallback | Primary | → Claude | → Claude |
| VN geo-block | ❌ Không | ⚠️ Có | ❌ Không |

**Recommendation cho anh Tài**: Dùng **OpenRouter** với `xiaomi/mimo-v2-flash:free` — free, không bị geo-block VN, quality tốt cho observation extraction.

---

## 6. Cách claude-mem hoạt động

### Session Lifecycle chi tiết

**Phase 0: Smart Install** (pre-hook)
```
Hook chain: smart-install.js → context-hook.js
- Check .install-version file
- Nếu version match → skip (10ms)
- Nếu khác → install dependencies, update cache
```

**Phase 1: Context Injection** (SessionStart)
```
1. Start Bun worker nếu chưa chạy
2. Query DB: 50 observations gần nhất từ 10 sessions gần nhất
3. Format:
   - 5 observations mới nhất: full narrative/facts
   - 45 còn lại: compact table (title, type, token count)
4. Inject vào Claude Code context
```

**Phase 2: Prompt Capture** (UserPromptSubmit)
```
1. Tạo session record trong sdk_sessions
2. Save raw prompt → user_prompts table + FTS5
3. Strip <private> tags trước khi save
4. Increment prompt_counter
```

**Phase 3: Observation Capture** (PostToolUse — fires 100+ lần)
```
For each tool execution:
1. Check tool_name ∉ SKIP_TOOLS
2. Strip <private> tags từ input + output
3. Gửi tới Worker HTTP API
4. Worker queue observation
5. AI (Claude/Gemini/OpenRouter) phân tích:
   - Extract title, subtitle
   - Write narrative (what happened, why it matters)
   - Extract facts (structured data points)
   - Tag concepts (how-it-works, gotcha, pattern...)
   - Classify type (bugfix, feature, decision...)
   - Track files_read, files_modified
6. Save processed observation → SQLite + FTS5
7. SSE broadcast (for Viewer UI)
```

**Phase 4: Summary Generation** (Stop)
```
1. Generate session summary from all observations:
   - request: what user asked
   - investigated: what was explored
   - learned: key learnings
   - completed: what was done
   - next_steps: suggested follow-ups
2. Save → session_summaries + FTS5
```

**Phase 5: Cleanup** (SessionEnd)
```
1. Mark session status = 'complete'
2. Record completed_at timestamp
3. Skip cleanup on /clear (preserve ongoing context)
```

### Private Tags

Wrap content không muốn lưu vào memory:

```
<private>
API_KEY=sk-abc123
Database host: internal-db-prod.company.com
</private>

Analyze this connection error.
```

- Claude thấy content trong session hiện tại
- Nhưng **không save** vào observations/prompts
- Works ở cả prompt text, tool inputs, tool outputs

### Folder Context Files (Optional)

Khi enable `CLAUDE_MEM_FOLDER_CLAUDEMD_ENABLED=true`:
- Auto-generate `CLAUDE.md` trong mỗi folder có activity
- Chứa timeline observations gần đây
- User content ngoài `<claude-mem-context>` tags được preserve
- Project root (có `.git`) bị exclude
- Cleanup: `bun scripts/regenerate-claude-md.ts --clean`

---

## 7. Memory Management

### Xem Memory

**Web Viewer:** `http://localhost:37777`
- Real-time memory stream (SSE)
- Filter by project
- Infinite scroll
- Dark/light mode

**CLI:**
```bash
# Worker status
npm run worker:status

# Worker logs
npm run worker:logs

# Database stats
sqlite3 ~/.claude-mem/claude-mem.db "
  SELECT 'sessions', COUNT(*) FROM sdk_sessions
  UNION ALL SELECT 'observations', COUNT(*) FROM observations
  UNION ALL SELECT 'summaries', COUNT(*) FROM session_summaries
  UNION ALL SELECT 'prompts', COUNT(*) FROM user_prompts;
"
```

### Export Memory

```bash
# Export theo query
npx tsx scripts/export-memories.ts "authentication" auth-memories.json

# Export theo project
npx tsx scripts/export-memories.ts "bugfix" bugfixes.json --project=my-project

# Export theo type
npx tsx scripts/export-memories.ts "type:decision" decisions.json
```

Output: JSON file portable, có thể share.

### Import Memory

```bash
npx tsx scripts/import-memories.ts auth-memories.json
```

- **Duplicate prevention**: Tự detect records đã tồn tại
- **Transactional**: All-or-nothing import
- **Order**: Sessions → Summaries → Observations → Prompts

### Database Maintenance

```bash
# Check integrity
sqlite3 ~/.claude-mem/claude-mem.db "PRAGMA integrity_check;"

# Optimize/compact
sqlite3 ~/.claude-mem/claude-mem.db "VACUUM;"

# Rebuild FTS5 indexes
sqlite3 ~/.claude-mem/claude-mem.db "
  INSERT INTO observations_fts(observations_fts) VALUES('rebuild');
  INSERT INTO session_summaries_fts(session_summaries_fts) VALUES('rebuild');
  INSERT INTO user_prompts_fts(user_prompts_fts) VALUES('rebuild');
"

# Delete old data (>30 days)
sqlite3 ~/.claude-mem/claude-mem.db "
  DELETE FROM observations WHERE created_at_epoch < $(date -d '30 days ago' +%s000);
  DELETE FROM session_summaries WHERE created_at_epoch < $(date -d '30 days ago' +%s000);
  DELETE FROM sdk_sessions WHERE created_at_epoch < $(date -d '30 days ago' +%s000);
"
# Rebuild FTS5 after delete!

# Check database size
ls -lh ~/.claude-mem/claude-mem.db
```

### Queue Recovery

Sau worker crash, observations có thể bị stuck:

```bash
# Check queue status
bun scripts/check-pending-queue.ts

# Process pending
bun scripts/check-pending-queue.ts --process --limit 5

# Or via API
curl http://localhost:37777/api/pending-queue
curl -X POST http://localhost:37777/api/pending-queue/process \
  -H "Content-Type: application/json" \
  -d '{"sessionLimit": 10}'
```

### Worker Management

```bash
npm run worker:start     # Start
npm run worker:stop      # Stop
npm run worker:restart   # Restart
npm run worker:status    # Status
npm run worker:logs      # Logs
```

Worker auto-start khi SessionStart hook fire. Manual start optional.

---

## 8. Search & Retrieval

### 3-Layer Progressive Disclosure

claude-mem dùng skill-based search (v5.4.0+) thay MCP tools — tiết kiệm ~2,250 tokens/session.

**Layer 1: Search** (index format, compact)
```
search observations "authentication bug"
search sessions "payment integration"
search prompts "database migration"
```
→ Returns: ID, title, type, timestamp (compact table)

**Layer 2: Timeline** (chronological context)
```
timeline "2025-01-15"
timeline-by-query "redis caching"
```
→ Returns: Chronological view of sessions + observations

**Layer 3: Get Full Details** (expanded)
```
get_observations [123, 456, 789]
```
→ Returns: Full narrative, facts, concepts

**Rule**: Luôn start từ Layer 1 → narrow down → Layer 3 chỉ cho relevant IDs. Tránh dump toàn bộ.

### HTTP API Endpoints

Worker expose 22 HTTP endpoints:

**Data Retrieval:**
- `GET /api/observations?project=X&limit=20&offset=0`
- `GET /api/observation/:id`
- `POST /api/observations/batch` (body: `{ids: [1,2,3]}`)
- `GET /api/summaries?project=X&limit=20&offset=0`
- `GET /api/prompts?project=X&limit=20&offset=0`
- `GET /api/session/:id`
- `GET /api/prompt/:id`
- `GET /api/stats`
- `GET /api/projects`

**Viewer:**
- `GET /` → Viewer UI
- `GET /health` → Health check
- `GET /stream` → SSE real-time

**Settings:**
- `GET /api/settings`
- `POST /api/settings`

**Queue:**
- `GET /api/pending-queue`
- `POST /api/pending-queue/process`

**Sessions:**
- `POST /sessions/:id/init`
- `POST /sessions/:id/observations`
- `POST /sessions/:id/summarize`
- `GET /sessions/:id/status`
- `DELETE /sessions/:id`

### FTS5 Query Syntax

```sql
-- Simple
"error handling"

-- AND
"error" AND "handling"

-- OR
"bug" OR "fix"

-- NOT
"bug" NOT "feature"

-- Phrase
"'exact phrase'"

-- Column-specific
title:"authentication"
```

---

## 9. Context Engineering

### Nguyên tắc cốt lõi

> **Tìm tập token nhỏ nhất, signal cao nhất, maximize khả năng đạt kết quả mong muốn.**

### Context là tài nguyên hữu hạn

- Mỗi token attend mọi token khác (n² relationships)
- Context dài hơn → accuracy giảm
- "Attention budget" bị cạn khi context grows
- Nhiều context ≠ tốt hơn

### Context Rot

Sau nhiều turns, context bị ô nhiễm bởi:
- Old tool outputs không còn relevant
- Intermediate steps đã complete
- Redundant information lặp lại

### 3 Techniques cho Long-Horizon Tasks

**1. Compaction** (condensing context)
- Summarize conversation khi gần limit
- Preserve: decisions, bugs found, implementation details
- Discard: old tool outputs, intermediate steps
- Tuning: maximize recall trước → improve precision sau

**2. Structured Note-Taking** (agentic memory)
- Agent viết notes ra file (NOTES.md, TODO.md)
- Persistent across sessions
- Minimal context overhead
- **Đây chính là cách claude-mem hoạt động** — observations là structured notes

**3. Sub-Agent Architectures**
- Main agent coordinates
- Sub-agents handle focused tasks
- Return condensed summaries (1-2K tokens)
- Clean context windows cho mỗi sub-agent

### Optimal Settings cho claude-mem

| Project type | Observations | Sessions | Full count | Notes |
|-------------|-------------|----------|------------|-------|
| **Solo project đơn giản** | 30 | 5 | 3 | Ít context, nhanh |
| **Microservice (multi-repo)** | 50 | 10 | 5 | Default, balanced |
| **Large monolith** | 80 | 15 | 8 | Nhiều context |
| **Debugging intensive** | 100 | 20 | 10 | Max context cho bug hunting |

**Higher values** = nhiều context hơn, SessionStart chậm hơn, nhiều tokens hơn
**Lower values** = nhanh hơn, ít tokens, ít historical awareness

---

## 10. Best Practices cho Claude Code

### Setup tối ưu

```json
// ~/.claude-mem/settings.json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "sk-or-v1-...",
  "CLAUDE_MEM_OPENROUTER_MODEL": "xiaomi/mimo-v2-flash:free",
  "CLAUDE_MEM_MODE": "code--vi",
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "50",
  "CLAUDE_MEM_CONTEXT_SESSION_COUNT": "10",
  "CLAUDE_MEM_CONTEXT_FULL_COUNT": "5",
  "CLAUDE_MEM_SKIP_TOOLS": "ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion",
  "CLAUDE_MEM_LOG_LEVEL": "INFO"
}
```

### Workflow daily

1. **Mở Claude Code** → claude-mem tự inject context
2. **Làm việc bình thường** → observations tự capture
3. **Khi cần tìm lại** → "What bugs did we fix yesterday?"
4. **Sensitive data** → wrap trong `<private>` tags
5. **Khi xong** → session summary tự generate
6. **Xem lại** → `http://localhost:37777` viewer

### Tips hiệu quả

**1. Đừng skip tools quan trọng**
Default SKIP_TOOLS là hợp lý. Chỉ remove tools khỏi skip list nếu muốn track thêm (vd: TodoWrite cho task planning).

**2. Dùng `<private>` cho secrets**
```
<private>
DB_PASSWORD=supersecret
PROD_API_KEY=sk-xxx
</private>
```

**3. Project naming nhất quán**
claude-mem dùng project name từ folder. Đặt tên folder rõ ràng:
- ✅ `aml-ms`, `wallet-ms`, `payment-gateway`
- ❌ `project1`, `temp`, `test`

**4. Periodic database maintenance**
Mỗi tháng:
```bash
sqlite3 ~/.claude-mem/claude-mem.db "VACUUM;"
```

**5. Export before machine change**
```bash
npx tsx scripts/export-memories.ts "" all-memories.json
# Copy file sang machine mới → import
```

**6. Chọn mode phù hợp**
- `code` — general coding (default)
- `code--chill` — chỉ ghi learnings "painful to rediscover", ít noise
- `code--vi` — output tiếng Việt

**7. Xem token economics**
Context injection hiện estimated tokens cho mỗi observation. Dùng thông tin này để tune `CONTEXT_OBSERVATIONS` cho phù hợp budget.

**8. Clean folder CLAUDE.md trước commit**
Nếu enable folder context:
```bash
bun scripts/regenerate-claude-md.ts --clean
```
Hoặc thêm vào `.gitignore`: `**/CLAUDE.md`

### Anti-patterns

- ❌ Đặt `CONTEXT_OBSERVATIONS=200` — quá nhiều, context rot
- ❌ Không dùng `<private>` cho secrets — sẽ persist vào DB
- ❌ Kill worker giữa session — observations bị stuck trong queue
- ❌ Manually edit database — phá FTS5 index
- ❌ Share database file trực tiếp — dùng export/import thay vì copy .db

---

## 11. Troubleshooting

### Worker không start

```bash
# Check nếu port đã bị chiếm
ss -tlnp | grep 37777

# Kill process cũ
pkill -f "bun.*worker-service"
sleep 2

# Restart
npm run worker:start
npm run worker:status
```

### Observations không được process

```bash
# Check queue
curl http://localhost:37777/api/pending-queue

# Process manually
curl -X POST http://localhost:37777/api/pending-queue/process \
  -H "Content-Type: application/json" \
  -d '{"sessionLimit": 10}'
```

### Context không inject

```bash
# Check worker health
curl http://localhost:37777/api/health

# Check database has data
sqlite3 ~/.claude-mem/claude-mem.db "SELECT COUNT(*) FROM observations;"

# Check settings
cat ~/.claude-mem/settings.json
```

### "Agent pool slot timeout"

Provider `claude` dùng Claude Agent SDK pool. Nếu timeout:
- Switch sang `gemini` hoặc `openrouter`
- Hoặc restart Claude Code CLI

### Database corrupted

```bash
# Backup
cp ~/.claude-mem/claude-mem.db ~/.claude-mem/claude-mem.db.bak

# Check integrity
sqlite3 ~/.claude-mem/claude-mem.db "PRAGMA integrity_check;"

# If failed, rebuild from scratch
rm ~/.claude-mem/claude-mem.db
# Restart worker — auto-creates new DB with migrations
npm run worker:restart
```

### FTS5 search trả về kết quả rỗng

```bash
# Rebuild FTS5 indexes
sqlite3 ~/.claude-mem/claude-mem.db "
  INSERT INTO observations_fts(observations_fts) VALUES('rebuild');
  INSERT INTO session_summaries_fts(session_summaries_fts) VALUES('rebuild');
  INSERT INTO user_prompts_fts(user_prompts_fts) VALUES('rebuild');
"
```

### Hook không fire

Verify hooks registered:
```bash
# Check hooks.json exists in plugin directory
find ~/.claude/plugins -name "hooks.json" | head -5

# Verify Claude Code loads plugin
# Trong Claude Code session, chạy:
/plugin list
```

---

## 12. Dành riêng cho VPS VN

### Vấn đề Gemini API Geo-Block

Google Gemini API **block requests từ VN**. Khi dùng provider `gemini`:
```
Error: 400 FAILED_PRECONDITION
"User location is not supported for the API use."
```

### Bun và SOCKS5 Proxy

Worker chạy trên Bun runtime. **Bun không hỗ trợ SOCKS5 proxy qua env vars** (`HTTPS_PROXY=socks5://...` bị ignore). Nên Cloudflare WARP proxy (SOCKS5 trên port 40000) **không work**.

### Solutions

**Option 1: Dùng OpenRouter (Recommended)**
- Không bị geo-block
- Free models available
- Không cần proxy

```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "sk-or-v1-...",
  "CLAUDE_MEM_OPENROUTER_MODEL": "xiaomi/mimo-v2-flash:free"
}
```

**Option 2: Dùng Claude provider**
- Không bị geo-block (dùng Claude Code CLI subscription)
- Tốn subscription token
- Có thể gặp agent pool timeout

```json
{
  "CLAUDE_MEM_PROVIDER": "claude",
  "CLAUDE_MEM_MODEL": "haiku"
}
```

**Option 3: proxychains cho Gemini**
```bash
# Install
sudo apt install proxychains4

# Config: /etc/proxychains4.conf
# socks5 127.0.0.1 40000

# Start worker qua proxychains
proxychains4 bun plugin/scripts/worker-service.cjs
```
⚠️ Chưa test, có thể không work với Bun.

**Option 4: HTTP proxy bridge**
```bash
# Install HTTP-to-SOCKS bridge
pip install pproxy
pproxy -l http://0.0.0.0:8118 -r socks5://127.0.0.1:40000 &

# Set HTTP proxy
export HTTP_PROXY=http://127.0.0.1:8118
export HTTPS_PROXY=http://127.0.0.1:8118

# Start worker
CLAUDE_MEM_WORKER_PORT=37777 bun plugin/scripts/worker-service.cjs
```
⚠️ Cần test xem Bun respect HTTP_PROXY hay không.

### Recommendation cho VPS VN

```
Provider priority:
1. OpenRouter (free, no geo-block) ← BEST
2. Claude (subscription, no geo-block)
3. Gemini + proxychains (free, complex setup)
```

---

## Tóm tắt

| Khía cạnh | Chi tiết |
|-----------|---------|
| **Bản chất** | AI-powered persistent memory plugin cho Claude Code |
| **Storage** | SQLite + FTS5 (full-text search) |
| **Processing** | Claude Agent SDK / Gemini / OpenRouter |
| **Hooks** | 6 lifecycle hooks auto-capture tool executions |
| **Search** | 3-layer progressive disclosure + HTTP API |
| **Privacy** | `<private>` tags strip content trước khi persist |
| **Export/Import** | JSON format, duplicate prevention, share-able |
| **Install** | `/plugin marketplace add thedotmack/claude-mem` |
| **VN Setup** | Dùng OpenRouter (free, no geo-block) |

---

_Tài liệu bởi Tèo em 🦞 — March 2026_