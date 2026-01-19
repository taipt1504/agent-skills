# Agent Skills

Hệ thống quản lý skills cho Claude Code CLI.

## Quick Links

- [GUIDE.md](./GUIDE.md) - Hướng dẫn chi tiết sử dụng các skills
- [SYSTEM_PROMPT.md](./SYSTEM_PROMPT.md) - System prompt cho Skill Creator Agent

## Cấu trúc

```
agent-skills/
├── SYSTEM_PROMPT.md              # System prompt cho Skill Creator Agent
├── GUIDE.md                      # Hướng dẫn sử dụng skills
├── skills/                       # Chứa các skills đã tạo
│   ├── postgres-java-reactive-pro/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   └── scripts/
│   ├── git-pro/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   └── scripts/
│   └── workflow-agents/
│       ├── SKILL.md
│       ├── references/
│       ├── scripts/
│       └── templates/
├── templates/
│   ├── SKILL.md            # Template skill đơn giản
│   └── advanced-skill/           # Template skill với refs & scripts
└── README.md
```

## Available Skills

| Skill                                                              | Description                                   | Command              |
| ------------------------------------------------------------------ | --------------------------------------------- | -------------------- |
| [postgres-java-reactive-pro](./skills/postgres-java-reactive-pro/) | High-performance PostgreSQL with R2DBC        | `/postgres-reactive` |
| [git-pro](./skills/git-pro/)                                       | Advanced Git with intelligent commit messages | `/git-pro`           |
| [workflow-agents](./skills/workflow-agents/)                       | Multi-agent workflow orchestration            | `/workflow-agents`   |

## Sử dụng

### Tạo skill đơn giản

1. Copy `templates/SKILL.md` vào `skills/`
2. Rename và điền nội dung

### Tạo skill phức tạp (với references và scripts)

1. Copy folder `templates/advanced-skill/` vào `skills/`
2. Rename folder và cập nhật nội dung:
   - `SKILL.md` - File chính
   - `references/` - Tài liệu tham khảo
   - `scripts/` - Scripts hỗ trợ

### Sử dụng Skill Creator Agent

Load `SYSTEM_PROMPT.md` làm system prompt cho Claude để có AI assistant hỗ trợ tạo skills.

## Skill Components

| Component     | Mô tả                              | Bắt buộc |
| ------------- | ---------------------------------- | -------- |
| `SKILL.md`    | File chính chứa instructions       | Yes      |
| `references/` | API docs, examples, external links | No       |
| `scripts/`    | Setup, helpers, validators         | No       |

## Skill Format

```yaml
---
name: skill-name
description: Mô tả ngắn
triggers:
  - keyword
  - /command
tools:
  - Read
  - Write
references: # Optional
  - references/api-docs.md
scripts: # Optional
  - scripts/helper.py
---
```

## Tools hỗ trợ

| Tool      | Chức năng        |
| --------- | ---------------- |
| Read      | Đọc file         |
| Write     | Tạo file         |
| Edit      | Sửa file         |
| Glob      | Tìm files        |
| Grep      | Tìm nội dung     |
| Bash      | Shell commands   |
| WebFetch  | Fetch web        |
| WebSearch | Tìm kiếm web     |
| Task      | Spawn sub-agents |

## Documentation

Xem [GUIDE.md](./GUIDE.md) để biết chi tiết về:

- Cách sử dụng từng skill
- Scripts và commands
- Quick reference và examples
- Anti-patterns cần tránh
