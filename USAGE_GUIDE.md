# Email Template Builder Skill - Usage Guide

## Overview

Skill `email-template-builder` được tạo để giúp bạn xây dựng template email với HTML thuần, sử dụng Mustache placeholder syntax (`{{variableName}}`) để fill data động - tương tự như cách Novu xử lý templates.

## Cấu Trúc Skill

```
.claude/skills/email-template-builder/
├── SKILL.md                         # Tài liệu skill chính
├── email-template-builder.skill     # File skill đóng gói (sử dụng khi import)
├── scripts/
│   └── validate_template.py         # Script kiểm tra syntax placeholder
├── assets/                          # Template examples
│   ├── welcome-email.html          # Email xác thực tài khoản
│   ├── password-reset.html         # Email reset mật khẩu
│   ├── order-confirmation.html     # Email xác nhận đơn hàng
│   └── invoice-email.html          # Email hóa đơn
└── references/                      # Tài liệu chi tiết
    ├── quick-reference.md          # Lookup nhanh
    ├── email-best-practices.md     # Best practices email
    └── template-examples.md        # Ví dụ placeholder chi tiết
```

## Quick Start

### 1. Chọn Template Base

Copy từ `assets/` và bắt đầu từ template gần nhất với yêu cầu:

```bash
cp assets/welcome-email.html my-custom-template.html
```

### 2. Tùy Chỉnh Template

Chỉnh sửa HTML:
- Thay đổi màu sắc, font, layout
- Chỉnh nội dung chính
- Giữ placeholder Mustache như `{{firstName}}`, `{{email}}`

### 3. Kiểm Tra Syntax

```bash
python3 scripts/validate_template.py my-custom-template.html
```

Output sẽ hiển thị:
- ✓ Syntax validation results
- 📋 Danh sách tất cả placeholders tìm thấy
- ✅ Hoặc ❌ Kết quả cuối cùng

## Placeholder Syntax

### Cú Pháp Cơ Bản

```html
<!-- Simple variable -->
<p>Hello {{firstName}},</p>

<!-- Nested object property -->
<p>Email: {{user.email}}</p>

<!-- Trong link -->
<a href="{{resetLink}}">Reset Password</a>
```

### Qui Tắc Đặt Tên

- ✓ `{{firstName}}` - camelCase
- ✓ `{{user.email}}` - Dots cho nested
- ✗ `{{first_name}}` - Không dùng underscore
- ✗ `{{1count}}` - Không bắt đầu với số

## Template Examples Có Sẵn

### Welcome Email
Dùng khi: Xác thực email mới hoặc onboarding user

Placeholders chính:
```
{{firstName}}, {{email}}, {{appName}}, {{verificationLink}},
{{expirationTime}}, {{unsubscribeLink}}, {{privacyLink}}
```

### Password Reset
Dùng khi: User quên mật khẩu

Placeholders chính:
```
{{firstName}}, {{resetLink}}, {{resetCode}}, {{expirationTime}},
{{supportLink}}, {{appName}}
```

### Order Confirmation
Dùng khi: User hoàn tất mua hàng

Placeholders chính:
```
{{customerFirstName}}, {{orderNumber}}, {{itemName}}, {{totalAmount}},
{{shippingAddress}}, {{estimatedDelivery}}, {{trackingLink}}
```

### Invoice
Dùng khi: Gửi hóa đơn thanh toán

Placeholders chính:
```
{{invoiceNumber}}, {{dueDate}}, {{clientName}}, {{totalAmount}},
{{paymentTerms}}, {{bankDetails}}
```

## Tích Hợp Với Novu

### Bước 1: Validate Template
```bash
python3 scripts/validate_template.py template.html
```

### Bước 2: Copy HTML Vào Novu

1. Đăng nhập Novu Dashboard
2. Tạo Template mới → Email
3. Copy toàn bộ HTML từ template
4. Paste vào Novu Editor

### Bước 3: Map Variables

Trong Novu, khi tạo trigger:
```json
{
  "firstName": "John",
  "email": "john@example.com",
  "appName": "MyApp",
  "verificationLink": "https://app.com/verify?token=xyz",
  "expirationTime": "24"
}
```

Novu sẽ tự động replace `{{firstName}}` → "John", etc.

### Bước 4: Test & Publish

- Test với sample data
- Preview ở Novu
- Publish template

## Best Practices

### Email Design
- Max width: 600px (chuẩn ngành)
- Responsive: Include viewport meta tag
- Inline CSS: Dùng `<style>` tags, không external stylesheets
- Fonts: System fonts (không custom font downloads)

### Placeholder
- Đặt tên rõ ràng: `{{orderTotal}}` không phải `{{amt}}`
- Consistent naming: Dùng camelCase ở tất cả
- Document: Giữ schema của placeholders cần

### Testing
- [ ] Validate với script validator
- [ ] Test ở Gmail, Outlook, Apple Mail
- [ ] Test mobile view
- [ ] Test with images disabled
- [ ] Test dark mode
- [ ] Verify all links là absolute URLs

### Performance
- Giữ dưới 100KB total
- Compress images
- Minimize CSS/HTML
- Simple table layout (không dùng CSS Grid/Flexbox)

## Troubleshooting

### Error: "Unmatched braces"
```html
<!-- ❌ Sai - thiếu }}
<p>Hello {{firstName}</p>

<!-- ✓ Đúng -->
<p>Hello {{firstName}}</p>
```

### Error: "Invalid placeholder name"
```html
<!-- ❌ Sai - bắt đầu với số -->
<p>{{1user}}</p>

<!-- ✓ Đúng -->
<p>{{user}}</p>
```

### Links không hoạt động
```html
<!-- ❌ Sai - relative URL -->
<a href="/reset">Reset</a>

<!-- ✓ Đúng - absolute URL -->
<a href="{{resetLink}}">Reset</a>
<!-- Trong data: resetLink = "https://app.com/reset?token=xyz" -->
```

## Tài Liệu Chi Tiết

Để tìm hiểu sâu hơn:

- **Quick Reference**: `references/quick-reference.md`
  - Lookup nhanh placeholders
  - Color palettes recommendation
  - Common tasks

- **Email Best Practices**: `references/email-best-practices.md`
  - Responsive design patterns
  - Email client compatibility
  - Accessibility guidelines
  - Novu integration specifics

- **Template Examples**: `references/template-examples.md`
  - Ví dụ placeholder chi tiết
  - Advanced patterns (conditional, loops)
  - Industry-specific variations

## Ví Dụ Hoàn Chỉnh

### Tạo Template Đơn Giản

```bash
# 1. Copy base template
cp assets/welcome-email.html my-welcome.html

# 2. Edit file với editor yêu thích
# - Thay màu primary từ #667eea → #00ff00
# - Thay nội dung nếu cần
# - Giữ {{placeholders}} nguyên

# 3. Validate
python3 scripts/validate_template.py my-welcome.html

# Output:
# ✓ Mustache syntax valid
# ✓ HTML structure looks good
# 📋 Placeholders found (7):
#   - {{ appName }}
#   - {{ email }}
#   - {{ expirationTime }}
#   - {{ firstName }}
#   - {{ privacyLink }}
#   - {{ unsubscribeLink }}
#   - {{ verificationLink }}
# ✅ Template validation passed!

# 4. Sử dụng với Novu
# - Copy HTML content
# - Paste vào Novu Template Editor
# - Map variables trong trigger
# - Test & publish
```

### Novu Trigger Example

```json
{
  "to": "user@example.com",
  "trigger": {
    "name": "send-welcome-email",
    "payload": {
      "firstName": "Alice",
      "email": "alice@example.com",
      "appName": "TaskManager",
      "verificationLink": "https://taskmanager.com/verify?token=abc123xyz",
      "expirationTime": "24",
      "unsubscribeLink": "https://taskmanager.com/unsubscribe",
      "privacyLink": "https://taskmanager.com/privacy"
    }
  }
}
```

## FAQ

**Q: Tôi có thể dùng HTML tags tùy ý không?**
A: Hầu hết HTML tags được support, nhưng tránh JavaScript, `<form>`, Flash, plugins.

**Q: Có thể dùng CSS animations không?**
A: Email clients có hạn chế support cho animations. Tránh để tối ưu.

**Q: Placeholder có case-sensitive không?**
A: Có - `{{firstName}}` khác với `{{firstname}}`.

**Q: Tôi có thể lồng placeholders không?**
A: Không - `{{user.firstName}}` ✓ nhưng `{{{{var}}}}` ✗

**Q: Làm sao test trước khi deploy?**
A: Run validator script + test ở các email clients (Gmail, Outlook, etc)

---

**Skill Package**: `/Users/taiphan/Documents/Projects/lab/agent-skills/.claude/skills/email-template-builder/email-template-builder.skill`

Để import skill này vào Claude, sử dụng file `.skill` đóng gói.
