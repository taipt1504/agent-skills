# Email Template Best Practices

## Mustache Placeholder Guidelines

### Basic Syntax
- Simple variable: `{{variableName}}`
- Nested object: `{{object.property}}`
- Only alphanumeric characters and dots are allowed

### Naming Conventions
- Use camelCase for placeholders: `{{firstName}}`, `{{orderTotal}}`
- Use dots for nested data: `{{user.email}}`, `{{order.items}}`
- Avoid special characters: `{{user-name}}` ❌ use `{{userName}}` ✓

### Placeholder Organization by Email Type

**Welcome Email**
- User data: `{{firstName}}`, `{{email}}`
- Account data: `{{appName}}`, `{{verificationLink}}`
- Links: `{{unsubscribeLink}}`, `{{privacyLink}}`

**Password Reset**
- User data: `{{firstName}}`
- Reset data: `{{resetLink}}`, `{{resetCode}}`, `{{expirationTime}}`
- Security: `{{supportLink}}`, `{{securityLink}}`

**Order Confirmation**
- Customer: `{{customerFirstName}}`, `{{customerEmail}}`
- Order: `{{orderNumber}}`, `{{orderDate}}`, `{{totalAmount}}`
- Shipping: `{{shippingAddress}}`, `{{estimatedDelivery}}`
- Tracking: `{{trackingLink}}`

## HTML Email Guidelines

### Responsive Design
- Use max-width: 600px for container (industry standard)
- Include `<meta name="viewport" content="width=device-width, initial-scale=1.0">`
- Use inline CSS or `<style>` tags (some clients strip external stylesheets)

### Email Client Compatibility
- Use HTML tables for layout instead of CSS Grid/Flexbox
- Avoid CSS Grid, CSS Flexbox (limited support in Outlook)
- Use inline styles for critical styling
- Keep CSS selectors simple (avoid pseudo-elements)

### Font & Typography
- System fonts: `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto`
- Fallback: Sans-serif for all text
- Avoid custom fonts unless using web-safe variants
- Use at least 14px for body text

### Color & Contrast
- Ensure WCAG AA compliance (contrast ratio 4.5:1 for text)
- Use color names or hex codes, not rgb()
- Test colors on different email clients

### Images
- Always include `alt` text for accessibility
- Use images hosting URL, not base64 (reduces file size)
- Test in dark mode (emails support dark mode media queries)
- Fallback for images disabled: use color backgrounds

### Links
- Always include `href` attribute
- Use absolute URLs: `https://example.com/page` not `/page`
- Test email client link tracking compatibility

### Testing Checklist
- [ ] Validate with validator_template.py script
- [ ] Test in Gmail, Outlook, Apple Mail, Thunderbird
- [ ] Test on mobile (iOS Mail, Gmail app)
- [ ] Test with images disabled
- [ ] Test in dark mode
- [ ] Verify all links are absolute URLs
- [ ] Check placeholder syntax correctness

## Novu-Specific Integration

### Variable Syntax (Mustache)
Novu uses Handlebars/Mustache syntax:
```html
<p>Hello {{firstName}},</p>
```

### Dynamic Content
Use conditional rendering in Novu:
```
{{#if isPremium}}
  <p>Premium member benefits...</p>
{{/if}}
```

### Fallback Values
Provide sensible defaults:
```
Hello {{firstName "there"}},
```

### Array Iteration
For loops in Novu:
```html
{{#each items}}
  <li>{{this.name}} - {{this.price}}</li>
{{/each}}
```

## File Size & Performance
- Keep template < 100KB
- Minimize CSS and whitespace
- Compress images
- Avoid tracking pixels > 1x1px if possible
- Use semantic HTML (reduces code)

## Accessibility
- Use semantic HTML: `<h1>`, `<p>`, `<strong>` not `<div>` styling
- Include `lang="en"` attribute on `<html>` tag
- Use proper heading hierarchy
- Include `alt` text for all images
- Use sufficient color contrast
- Avoid blinking/animated content

## Common Pitfalls
- ❌ Using external stylesheets (use `<style>` instead)
- ❌ JavaScript (not supported in emails)
- ❌ Relative URLs (use absolute URLs)
- ❌ Form elements (not actionable in emails)
- ❌ Flash or plugins
- ❌ Fixed positioning
- ❌ CSS3 features (limited support)
