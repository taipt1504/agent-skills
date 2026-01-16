# Agent Skills Guide

Hướng dẫn chi tiết sử dụng các skills trong hệ thống.

---

## Mục lục

1. [Tổng quan](#tổng-quan)
2. [Cách sử dụng Skills](#cách-sử-dụng-skills)
3. [Danh sách Skills](#danh-sách-skills)
   - [postgres-java-reactive-pro](#postgres-java-reactive-pro)
   - [git-pro](#git-pro)
4. [Tạo Skill mới](#tạo-skill-mới)

---

## Tổng quan

Skills là các module kiến thức chuyên biệt giúp AI agent thực hiện các tác vụ cụ thể một cách hiệu quả. Mỗi skill bao gồm:

| Component     | Mô tả                                          |
| ------------- | ---------------------------------------------- |
| `SKILL.md`    | File chính chứa instructions và best practices |
| `references/` | Tài liệu tham khảo, API docs, examples         |
| `scripts/`    | Scripts hỗ trợ (setup, validation, benchmark)  |

## Cách sử dụng Skills

### 1. Kích hoạt bằng Triggers

Mỗi skill có các trigger keywords. Khi user đề cập đến các keywords này, agent sẽ tự động áp dụng skill tương ứng.

```
User: "Giúp tôi optimize query r2dbc postgresql"
Agent: [Áp dụng skill postgres-java-reactive-pro]
```

### 2. Kích hoạt bằng Slash Command

Một số skills hỗ trợ slash command để kích hoạt trực tiếp:

```
User: "/postgres-reactive"
Agent: [Áp dụng skill postgres-java-reactive-pro]
```

### 3. Sử dụng Scripts

Các scripts trong skill có thể được chạy độc lập:

```bash
# Chạy script phân tích
python skills/postgres-java-reactive-pro/scripts/analyze-queries.py --help

# Chạy benchmark
./skills/postgres-java-reactive-pro/scripts/benchmark.sh --help
```

---

## Danh sách Skills

---

### postgres-java-reactive-pro

**Expert guidance for high-performance PostgreSQL with Java Reactive using R2DBC**

#### Thông tin

| Field         | Value                                      |
| ------------- | ------------------------------------------ |
| Name          | `postgres-java-reactive-pro`               |
| Slash Command | `/postgres-reactive`                       |
| Stack         | PostgreSQL, Java, R2DBC, Spring Data R2DBC |

#### Triggers

Skill được kích hoạt khi user đề cập:

- `r2dbc postgresql`
- `reactive postgres java`
- `spring data r2dbc`
- `high performance reactive database`

#### Use Cases

| Scenario                  | Skill giúp gì                                                 |
| ------------------------- | ------------------------------------------------------------- |
| Thiết kế repository layer | Hướng dẫn patterns cho ReactiveCrudRepository, custom queries |
| Tối ưu connection pool    | Config pool size, timeouts, validation                        |
| Batch operations          | Patterns cho bulk insert, upsert, batch update                |
| Query optimization        | Keyset pagination, covering indexes, avoiding N+1             |
| Streaming large data      | Backpressure handling, limitRate, buffer                      |
| Transaction management    | Reactive transactions, savepoints                             |

#### References

| File                               | Nội dung                                                            |
| ---------------------------------- | ------------------------------------------------------------------- |
| `references/r2dbc-config.md`       | Dependencies, connection config, pool settings, SSL, converters     |
| `references/query-patterns.md`     | Repository patterns, pagination, batch ops, joins, locking          |
| `references/performance-tuning.md` | PostgreSQL config, index strategies, query optimization, monitoring |

#### Scripts

##### analyze-queries.py

Phân tích slow queries từ PostgreSQL logs hoặc pg_stat_statements.

```bash
# Phân tích log file
python scripts/analyze-queries.py --log /var/log/postgresql/postgresql.log

# Với threshold tùy chỉnh (mặc định 100ms)
python scripts/analyze-queries.py --log postgresql.log --threshold 50

# Lấy stats từ pg_stat_statements
python scripts/analyze-queries.py --stats --host localhost --database mydb --user postgres

# Xem top 30 slow queries
python scripts/analyze-queries.py --log postgresql.log --top 30
```

**Output example:**

```
Found 156 slow queries
+--------+----------+----------+------------+--------------------------------------------------+
|  Count |  Avg(ms) |  Max(ms) |  Total(ms) | Query                                            |
+--------+----------+----------+------------+--------------------------------------------------+
|     45 |   250.3  |   892.1  |   11263.5  | SELECT * FROM orders WHERE user_id = ?...        |
|     32 |   180.2  |   445.6  |    5766.4  | SELECT * FROM users WHERE id = ANY(?)...         |
+--------+----------+----------+------------+--------------------------------------------------+

Recommendations:
- Query: SELECT * FROM orders WHERE user_id = ?
  - Consider selecting only needed columns instead of SELECT *
  - Check EXPLAIN ANALYZE for this query
```

##### benchmark.sh

Benchmark connection pool với các pool sizes khác nhau.

```bash
# Chạy với defaults
./scripts/benchmark.sh

# Custom configuration
./scripts/benchmark.sh \
  --url "r2dbc:postgresql://localhost:5432/mydb" \
  --user postgres \
  --password secret \
  --iterations 5000 \
  --concurrency 100 \
  --pool-sizes "10 25 50 75 100"
```

**Output example:**

```
==========================================
R2DBC Connection Pool Benchmark
==========================================

Testing pool size: 10
  Throughput: 2340 queries/sec

Testing pool size: 25
  Throughput: 4521 queries/sec

Testing pool size: 50
  Throughput: 5892 queries/sec

==========================================
Summary
==========================================

Pool Size    Total (ms)      Avg (ms)        RPS
------------------------------------------------------------
10           427.35          0.427           2340
25           221.12          0.221           4521
50           169.73          0.170           5892

Recommendation: Choose pool size with best RPS that doesn't exhaust database connections.
```

#### Quick Reference

##### Connection Pool Config

```java
ConnectionPoolConfiguration.builder()
    .connectionFactory(connectionFactory)
    .initialSize(10)
    .maxSize(50)
    .maxIdleTime(Duration.ofMinutes(30))
    .maxAcquireTime(Duration.ofSeconds(5))
    .validationQuery("SELECT 1")
    .build();
```

##### Keyset Pagination

```java
public Flux<User> getUsersAfter(Long lastId, int size) {
    return databaseClient.sql(
        "SELECT * FROM users WHERE id > :lastId ORDER BY id LIMIT :size")
        .bind("lastId", lastId)
        .bind("size", size)
        .map(this::mapToUser)
        .all();
}
```

##### Batch Insert

```java
public Mono<Void> batchInsert(List<User> users) {
    return Flux.fromIterable(users)
        .buffer(1000)
        .flatMap(this::insertBatch, 4)
        .then();
}
```

##### Backpressure Handling

```java
public Flux<User> streamUsers() {
    return userRepository.findAll()
        .limitRate(100);
}
```

#### Anti-patterns to Avoid

| Anti-pattern                    | Problem                | Solution                   |
| ------------------------------- | ---------------------- | -------------------------- |
| `.block()` trong reactive chain | Blocks event loop      | Keep chain fully reactive  |
| `SELECT *`                      | Over-fetching          | Select only needed columns |
| Offset pagination               | Slow với large offsets | Use keyset pagination      |
| N+1 queries                     | Multiple round trips   | Use JOINs hoặc batch fetch |
| Unbounded queries               | Memory exhaustion      | Always use LIMIT           |

#### Checklist Production

```
[ ] Connection pool sized correctly
[ ] Prepared statement cache enabled
[ ] All queries có proper indexes
[ ] No N+1 queries
[ ] Large result sets dùng streaming/pagination
[ ] Transactions có proper timeout
[ ] Metrics và logging configured
[ ] Slow query threshold set
[ ] Health check endpoint cho database
[ ] Graceful shutdown handling
```

---

### git-pro

**Advanced Git source control with intelligent commit message generation**

#### Thông tin

| Field         | Value              |
| ------------- | ------------------ |
| Name          | `git-pro`          |
| Slash Command | `/git-pro`         |
| Stack         | Git, Shell, Python |

#### Triggers

Skill được kích hoạt khi user đề cập:

- `git advanced`
- `git workflow`
- `commit message`
- `source control`
- `git analyze`

#### Use Cases

| Scenario                | Skill giúp gì                                              |
| ----------------------- | ---------------------------------------------------------- |
| Phân tích repo status   | Comprehensive analysis của working tree, branches, remotes |
| Generate commit message | Tự động tạo message theo Conventional Commits              |
| Branch management       | Patterns cho branching, merging, rebasing                  |
| History analysis        | Search commits, blame, bisect                              |
| Conflict resolution     | Strategies và commands cho merge conflicts                 |
| Repository cleanup      | Prune, gc, stale branches                                  |

#### References

| File                               | Nội dung                                      |
| ---------------------------------- | --------------------------------------------- |
| `references/commands.md`           | Full Git command reference với examples       |
| `references/workflows.md`          | GitFlow, GitHub Flow, Trunk-Based Development |
| `references/commit-conventions.md` | Conventional Commits specification            |

#### Scripts

##### analyze-repo.sh

Phân tích toàn diện trạng thái repository.

```bash
# Full analysis
./scripts/analyze-repo.sh

# Status only
./scripts/analyze-repo.sh --status

# Staged changes analysis
./scripts/analyze-repo.sh --staged

# Branch analysis
./scripts/analyze-repo.sh --branches

# History analysis
./scripts/analyze-repo.sh --history

# JSON output
./scripts/analyze-repo.sh --json
```

**Output example:**

```
════════════════════════════════════════════════════════════
  REPOSITORY STATUS
════════════════════════════════════════════════════════════

Repository:  my-project
Branch:      feature/user-auth
Upstream:    origin/feature/user-auth
Ahead:       2 commits
Behind:      0 commits

── Working Tree ──
Staged:      3 files
Unstaged:    1 files
Untracked:   2 files

── Staged Files ──
  [+] src/auth/login.ts
  [~] src/api/users.ts
  [~] package.json

── Detected Change Type ──
  ✓ New files added (possible feat)
  ? Small change (possible fix or refactor)
```

##### generate-commit-msg.py

Generate commit message tối ưu từ staged changes.

```bash
# Generate message
python scripts/generate-commit-msg.py

# Analyze only (không generate)
python scripts/generate-commit-msg.py --analyze

# Force specific type
python scripts/generate-commit-msg.py --type feat

# Force specific scope
python scripts/generate-commit-msg.py --scope auth

# Interactive mode
python scripts/generate-commit-msg.py --interactive

# Subject only (no body)
python scripts/generate-commit-msg.py --no-body
```

**Output example:**

```
════════════════════════════════════════════════════════════
STAGED CHANGES ANALYSIS
════════════════════════════════════════════════════════════

Files Added:    1
Files Modified: 2
Files Deleted:  0
Files Renamed:  0

Insertions: +45
Deletions:  -12

File Types:
  .ts: 2
  .json: 1

Directories: src/auth, src/api

Detected Type: feat
Detected Scope: auth

════════════════════════════════════════════════════════════
GENERATED COMMIT MESSAGE
════════════════════════════════════════════════════════════

feat(auth): add login functionality

Added:
- src/auth/login.ts

Modified:
- src/api/users.ts
- package.json

════════════════════════════════════════════════════════════

To use this message:
  git commit -m "feat(auth): add login functionality"
```

#### Quick Reference

##### Commit Message Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

##### Commit Types

| Type       | Description      |
| ---------- | ---------------- |
| `feat`     | New feature      |
| `fix`      | Bug fix          |
| `docs`     | Documentation    |
| `style`    | Formatting       |
| `refactor` | Code restructure |
| `perf`     | Performance      |
| `test`     | Tests            |
| `chore`    | Other            |

##### Useful Commands

```bash
# Status với branch info
git status -sb

# Log với graph
git log --oneline --graph -20

# Stash với message
git stash push -m "WIP: feature"

# Interactive rebase
git rebase -i HEAD~5

# Cherry-pick
git cherry-pick abc123

# Reset soft (keep staged)
git reset --soft HEAD~1
```

##### Keyset Pagination

```bash
# Tìm commits by message
git log --grep="keyword" --oneline

# Tìm commits by code
git log -S "function_name" --oneline

# Blame specific lines
git blame -L 10,20 file.ts
```

#### Anti-patterns to Avoid

| Anti-pattern              | Problem                    | Solution                    |
| ------------------------- | -------------------------- | --------------------------- |
| Commit trực tiếp vào main | Risk, no review            | Use feature branches        |
| Force push shared branch  | Overwrites others' work    | Use `--force-with-lease`    |
| Vague commit messages     | Hard to understand history | Follow Conventional Commits |
| Large commits             | Hard to review, revert     | Atomic commits              |
| Commit secrets            | Security risk              | Use .gitignore, git-secrets |

#### Checklist trước Commit

```
[ ] Review tất cả changes (git diff --cached)
[ ] Không commit files không cần thiết
[ ] Không commit sensitive data
[ ] Commit message theo conventions
[ ] Tests pass
[ ] Code đã format
```

#### Checklist trước Push

```
[ ] Pull/rebase latest changes
[ ] Resolve conflicts
[ ] Run tests locally
[ ] Review commit history
[ ] Đúng branch
```

---

## Tạo Skill mới

### Sử dụng Template

```bash
# Skill đơn giản
cp templates/SKILL.md skills/SKILL.md

# Skill phức tạp
cp -r templates/advanced-skill skills/my-new-skill
```

### Skill Structure

```
skills/my-new-skill/
├── SKILL.md              # Required
├── references/           # Optional
│   ├── api-docs.md
│   └── examples.md
└── scripts/              # Optional
    ├── setup.sh
    └── helper.py
```

### Frontmatter Format

```yaml
---
name: my-new-skill
description: Short description of the skill
triggers:
  - keyword 1
  - keyword 2
  - /slash-command
tools:
  - Read
  - Write
  - Edit
references:
  - references/api-docs.md
scripts:
  - scripts/setup.sh
---
```

### Best Practices

1. **Clear triggers** - Chọn keywords cụ thể, tránh quá chung chung
2. **Focused scope** - Một skill làm một việc tốt
3. **Examples** - Cung cấp code examples cụ thể
4. **Anti-patterns** - Liệt kê những gì KHÔNG nên làm
5. **Scripts** - Tạo scripts hữu ích cho automation

---

## Contributing

Khi thêm skill mới:

1. Tạo skill theo template
2. Test skill với các scenarios khác nhau
3. Cập nhật GUIDE.md với documentation
4. Đảm bảo scripts có `--help` option
