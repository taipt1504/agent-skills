# Quick Reference

## File Organization

```
email-template-builder/
├── SKILL.md                          # Main skill documentation
├── scripts/
│   └── validate_template.py          # Template validator script
├── references/
│   ├── email-best-practices.md       # Best practices & guidelines
│   ├── template-examples.md          # Placeholder examples & variations
│   └── quick-reference.md            # This file
└── assets/
    ├── welcome-email.html            # Email verification template
    ├── password-reset.html           # Account recovery template
    ├── order-confirmation.html       # E-commerce order template
    └── invoice-email.html            # Invoice/billing template
```

## Template Placeholders Quick Lookup

### Welcome Email
```
{{appName}}, {{firstName}}, {{email}}, {{verificationLink}},
{{expirationTime}}, {{unsubscribeLink}}, {{privacyLink}}
```

### Password Reset
```
{{firstName}}, {{resetLink}}, {{resetCode}}, {{expirationTime}},
{{supportLink}}, {{securityLink}}, {{appName}}
```

### Order Confirmation
```
{{customerFirstName}}, {{orderNumber}}, {{orderDate}}, {{itemName}},
{{itemQuantity}}, {{itemPrice}}, {{subtotal}}, {{shippingCost}},
{{taxAmount}}, {{totalAmount}}, {{shippingAddress}}, {{shippingCity}},
{{shippingState}}, {{shippingZip}}, {{shippingCountry}},
{{estimatedDelivery}}, {{trackingLink}}, {{supportEmail}}, {{appName}},
{{termsLink}}, {{privacyLink}}, {{supportLink}}
```

### Invoice
```
{{invoiceNumber}}, {{invoiceDate}}, {{dueDate}}, {{companyName}},
{{companyAddress}}, {{companyCity}}, {{companyState}}, {{companyZip}},
{{companyPhone}}, {{companyEmail}}, {{clientName}}, {{clientCompany}},
{{clientAddress}}, {{clientCity}}, {{clientState}}, {{clientZip}},
{{itemDescription}}, {{itemQuantity}}, {{itemUnitPrice}}, {{itemTotal}},
{{subtotal}}, {{taxRate}}, {{taxAmount}}, {{discountAmount}},
{{totalAmount}}, {{paymentStatus}}, {{paymentStatusLabel}},
{{paymentTerms}}, {{paymentMethod}}, {{bankDetails}}, {{notes}},
{{invoiceLink}}, {{paymentLink}}, {{supportEmail}}, {{termsLink}},
{{privacyLink}}, {{supportLink}}
```

## Common Tasks

### Create a new template
1. Copy an existing template: `cp assets/welcome-email.html my-template.html`
2. Edit content and customize colors
3. Replace text values with placeholders: `{{variableName}}`
4. Validate: `python3 scripts/validate_template.py my-template.html`

### Validate template syntax
```bash
python3 scripts/validate_template.py template.html
```

### Check what placeholders are used
Run validator to see extracted placeholders:
```bash
python3 scripts/validate_template.py template.html
# Output shows: 📋 Placeholders found (8):
```

### Deploy to Novu
1. Copy template HTML
2. Paste into Novu Template Editor
3. Map placeholders to Novu variables
4. Test with sample data
5. Publish

## Placeholder Naming Tips

| Good ✓ | Bad ✗ | Why |
|--------|-------|-----|
| `{{firstName}}` | `{{first_name}}` | Use camelCase |
| `{{email}}` | `{{user-email}}` | No special chars |
| `{{orderTotal}}` | `{{1total}}` | Start with letter |
| `{{user.email}}` | `{{user[email]}}` | Use dots for nesting |
| `{{appName}}` | `{{app_name}}` | No underscores |

## CSS for Email Clients

### What Works ✓
- `background-color`, `color`, `padding`, `margin`
- `border`, `border-radius`, `box-shadow`
- `text-align`, `font-weight`, `font-size`
- Media queries (some clients)
- Inline styles

### What Doesn't ✓
- External stylesheets (use `<style>` instead)
- CSS Grid, Flexbox (limited support)
- Pseudo-elements (`:hover`, `:before`)
- JavaScript
- Fixed positioning

## Email Client Testing

### Must Test
- Gmail (web & app)
- Outlook (web & desktop)
- Apple Mail
- Thunderbird
- Mobile (iOS Mail, Gmail app)

### Testing Tips
- [ ] Test with images disabled
- [ ] Test in dark mode
- [ ] Test on mobile screens
- [ ] Check all links are absolute URLs
- [ ] Verify fonts fallback correctly

## Color Palette Recommendations

### Professional/Corporate
```css
Primary: #2c3e50    /* Dark blue-gray */
Secondary: #3498db  /* Sky blue */
Accent: #27ae60     /* Green */
Background: #f5f5f5 /* Light gray */
```

### Friendly/Startup
```css
Primary: #667eea    /* Purple-blue */
Secondary: #764ba2  /* Purple */
Accent: #ff6b6b     /* Red */
Background: #f9f9f9 /* Almost white */
```

### Minimal/Modern
```css
Primary: #000000    /* Black */
Secondary: #333333  /* Dark gray */
Accent: #ffb84d     /* Gold */
Background: #ffffff /* White */
```

## Performance Tips
- Keep total size < 100KB
- Compress images
- Minimize CSS/HTML
- Use simple tables for layout
- Avoid heavy fonts
- Limit animations (if supported)

## Accessibility Checklist
- [ ] Include `lang="en"` on `<html>`
- [ ] Use semantic HTML tags
- [ ] Add `alt` text to images
- [ ] Color contrast ratio ≥ 4.5:1
- [ ] Readable font sizes (min 14px body)
- [ ] Proper heading hierarchy
- [ ] Descriptive link text (not "click here")

## Novu-Specific Features

### Conditional Rendering
```html
{{#if isPremium}}
  <p>Premium feature...</p>
{{/if}}
```

### Loops
```html
{{#each items}}
  <li>{{this.name}}</li>
{{/each}}
```

### Fallback Values
```html
Hello {{firstName "Friend"}},
```

## Resources

- **Email best practices**: `references/email-best-practices.md`
- **Placeholder examples**: `references/template-examples.md`
- **Validator tool**: `scripts/validate_template.py`
- **Pre-built templates**: `assets/`

## Support

To validate templates:
```bash
python3 scripts/validate_template.py your-template.html
```

For questions about:
- Placeholders → See `template-examples.md`
- Email design → See `email-best-practices.md`
- Syntax validation → Run validator script
