---
name: skill-name
description: Mô tả ngắn gọn về skill (1-2 câu)
triggers:
  - từ khóa trigger 1
  - /slash-command
tools:
  - Read
  - Write
  - Edit
  - Bash
references:
  - references/api-docs.md
  - references/examples.md
scripts:
  - scripts/setup.sh
  - scripts/helper.py
---

# Tên Skill

## Mục đích

Mô tả skill này làm gì và giải quyết vấn đề gì cho user.

## Khi nào sử dụng

- Scenario 1: ...
- Scenario 2: ...

## Khi nào KHÔNG sử dụng

- Anti-pattern 1: ...
- Anti-pattern 2: ...

## Prerequisites

Trước khi sử dụng skill này, chạy script setup:
```bash
./scripts/setup.sh
```

## Hướng dẫn thực hiện

### Bước 1: [Tên bước]

Mô tả chi tiết cần làm gì.

Sử dụng helper script nếu cần:
```bash
python scripts/helper.py --option value
```

### Bước 2: [Tên bước]

Mô tả chi tiết cần làm gì.

## References

Xem thêm tài liệu trong:
- `references/api-docs.md` - API documentation
- `references/examples.md` - Các ví dụ chi tiết

## Examples

### Example 1: [Tên scenario]

**Input:**
```
User request example
```

**Output:**
```
Expected result
```

## Error Handling

| Error | Nguyên nhân | Cách xử lý |
|-------|-------------|------------|
| Error A | Lý do | Solution |
| Error B | Lý do | Solution |

## Notes

- Lưu ý quan trọng 1
- Lưu ý quan trọng 2
