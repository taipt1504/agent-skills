---
name: email-template-builder
description: Build professional HTML email templates with Mustache placeholders for dynamic content. Use when creating or modifying email templates for transactional emails (welcome, password reset, order confirmation, etc.). Supports template validation, placeholder syntax checking, and best practices for email client compatibility. Includes pre-built templates and comprehensive reference documentation.
---

# Email Template Builder

Build production-ready HTML email templates with proper Mustache placeholder syntax and responsive design patterns compatible with major email clients.

## Quick Start

### Creating a Template

1. Choose a base template from examples: `welcome-email.html`, `password-reset.html`, or `order-confirmation.html`
2. Customize with your content and branding colors
3. Replace placeholder values with Mustache variables: `{{variableName}}`
4. Validate syntax with the included script

### Validating Templates

```bash
python3 scripts/validate_template.py your-template.html
```

The validator checks:
- Mustache syntax correctness
- Matching brace pairs
- HTML structure
- Extracted placeholders

## Placeholder Syntax

### Basic Variables
```html
<p>Hello {{firstName}},</p>
<p>Your email: {{email}}</p>
```

### Nested Properties
```html
<p>Order for {{customer.name}}</p>
<p>Shipping to {{address.city}}, {{address.state}}</p>
```

### Placeholder Naming Rules
- Use camelCase: `{{firstName}}` not `{{first_name}}`
- Alphanumeric + dots only
- Start with letter: `{{item1}}` ✓ not `{{1item}}` ✗

## Template Structure

Each template should include:

1. **Doctype & Meta Tags** - HTML5 + viewport for responsiveness
2. **Inline Styles** - Use `<style>` tags, avoid external stylesheets
3. **Header** - Branding area with gradient or solid color
4. **Content** - Main message body with clear hierarchy
5. **Footer** - Links and company info
6. **Responsive Layout** - Max-width: 600px container

### Example Structure
```html
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <style>/* Inline CSS */</style>
  </head>
  <body>
    <div class="container">
      <div class="header">Header content</div>
      <div class="content">
        <p>Hello {{firstName}},</p>
        <!-- Dynamic content with placeholders -->
      </div>
      <div class="footer">Footer links</div>
    </div>
  </body>
</html>
```

## Placeholder Categories

### Authentication Emails
- `{{firstName}}` - Recipient first name
- `{{email}}` - Email address
- `{{verificationLink}}` - Email verification URL
- `{{resetLink}}` - Password reset URL
- `{{expirationTime}}` - Link expiration hours
- `{{resetCode}}` - Reset code alternative

### Transactional Emails
- `{{orderNumber}}` - Unique order ID
- `{{orderDate}}` - Order creation date
- `{{itemName}}`, `{{itemPrice}}` - Product details
- `{{totalAmount}}` - Order total
- `{{trackingLink}}` - Shipping tracking URL

### User & Company
- `{{appName}}` - Application/company name
- `{{supportLink}}` - Customer support URL
- `{{unsubscribeLink}}` - Unsubscribe URL
- `{{privacyLink}}` - Privacy policy URL

## Best Practices

See `references/email-best-practices.md` for:
- Responsive design patterns
- Email client compatibility
- Accessibility guidelines
- Novu integration specifics
- Testing checklist

### Key Points
- Maximum 600px width for reliable rendering
- Use system fonts (no custom font downloads)
- Absolute URLs only (never relative paths)
- Test with images disabled
- Verify placeholder syntax before deployment

## Working with Novu

### Integration Pattern
1. Create template with Mustache syntax
2. Validate all placeholders: `python3 scripts/validate_template.py template.html`
3. Copy to Novu template editor
4. Map placeholders to Novu variables in trigger data
5. Test with sample data

### Example Novu Payload
```json
{
  "firstName": "John",
  "email": "john@example.com",
  "verificationLink": "https://app.com/verify?code=abc123",
  "appName": "MyApp",
  "expirationTime": "24"
}
```

## Available Templates

### `assets/welcome-email.html`
- User onboarding and email verification
- Gradients, welcoming tone
- ~12 placeholders

### `assets/password-reset.html`
- Account security recovery
- Red alert styling, code alternative
- ~6 placeholders

### `assets/order-confirmation.html`
- E-commerce order confirmation
- Itemized table, shipping details
- ~15 placeholders

## Validation Examples

### Valid Placeholder
```html
<p>Order {{orderNumber}} total: {{totalAmount}}</p>
```

### Invalid Placeholders
```html
<!-- ❌ Unmatched braces -->
<p>Hello {{firstName}</p>

<!-- ❌ Invalid name (starts with number) -->
<p>Thank you {{1user}}</p>

<!-- ❌ Special characters -->
<p>Email: {{user-email}}</p>
```

## Scripts

### `scripts/validate_template.py`
Validates Mustache syntax and HTML structure. Reports:
- Syntax errors
- HTML issues
- Found placeholders with count
- Validation summary

Usage:
```bash
python3 scripts/validate_template.py template.html
```

Output:
```
✓ Mustache syntax valid
✓ HTML structure looks good
📋 Placeholders found (8):
  - {{ firstName }}
  - {{ email }}
  - {{ verificationLink }}
  ...
✅ Template validation passed!
```

## Tips

1. **Test Early** - Run validator before pushing to production
2. **Consistent Naming** - Use same placeholder names across templates
3. **Document Variables** - Create a schema of required placeholders
4. **Dark Mode** - Test templates in dark mode email clients
5. **Mobile Preview** - Always test on mobile email apps
6. **Fallback Values** - Provide sensible defaults in Novu trigger data
