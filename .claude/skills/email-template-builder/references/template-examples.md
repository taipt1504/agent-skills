# Email Template Examples & Variations

## Placeholder Examples by Type

### Simple Welcome Flow

**Setup Requirements**
- `{{firstName}}` - User first name
- `{{email}}` - User email address
- `{{appName}}` - Application name
- `{{verificationLink}}` - Unique verification URL
- `{{expirationTime}}` - Hours until link expires

**HTML Usage**
```html
<p>Hi {{firstName}},</p>
<p>Welcome to {{appName}}! Verify your email:</p>
<a href="{{verificationLink}}">Verify Email</a>
<p>Link expires in {{expirationTime}} hours</p>
```

**Novu Payload Example**
```json
{
  "firstName": "Alice",
  "email": "alice@example.com",
  "appName": "TaskApp",
  "verificationLink": "https://taskapp.com/verify?token=abc123xyz",
  "expirationTime": "24"
}
```

### Password Reset Flow

**Setup Requirements**
- `{{firstName}}` - User first name
- `{{resetLink}}` - Reset URL with token
- `{{resetCode}}` - Alternative code for manual entry
- `{{expirationTime}}` - Hours until link expires
- `{{supportLink}}` - Help contact link

**HTML Usage**
```html
<p>Hi {{firstName}},</p>
<p>Click to reset your password:</p>
<a href="{{resetLink}}" class="button">Reset Password</a>
<p>Or enter this code:</p>
<code>{{resetCode}}</code>
<p>This link expires in {{expirationTime}} hours</p>
<p><a href="{{supportLink}}">Need help?</a></p>
```

**Novu Payload Example**
```json
{
  "firstName": "Bob",
  "resetLink": "https://app.com/reset?token=xyz789",
  "resetCode": "ABC123DEF456",
  "expirationTime": "1",
  "supportLink": "https://support.app.com"
}
```

### Order Confirmation Flow

**Setup Requirements**
- `{{customerFirstName}}` - Customer first name
- `{{orderNumber}}` - Unique order ID
- `{{orderDate}}` - Order creation date (ISO format)
- `{{itemName}}` - Product name
- `{{itemQuantity}}` - Quantity ordered
- `{{itemPrice}}` - Price per item
- `{{subtotal}}` - Before tax/shipping
- `{{shippingCost}}` - Shipping fee
- `{{taxAmount}}` - Tax calculated
- `{{totalAmount}}` - Final total
- `{{shippingAddress}}` - Street address
- `{{shippingCity}}` - City
- `{{shippingState}}` - State/Province
- `{{shippingZip}}` - Postal code
- `{{shippingCountry}}` - Country
- `{{estimatedDelivery}}` - Expected delivery date
- `{{trackingLink}}` - Tracking URL

**HTML Usage - Item Loop (Novu)**
```html
{{#each items}}
  <tr>
    <td>{{this.name}}</td>
    <td>{{this.quantity}}</td>
    <td>{{this.price}}</td>
  </tr>
{{/each}}
```

**Novu Payload Example**
```json
{
  "customerFirstName": "Charlie",
  "orderNumber": "ORD-2024-001",
  "orderDate": "2024-01-26",
  "items": [
    {
      "name": "Widget Pro",
      "quantity": 2,
      "price": "$29.99"
    },
    {
      "name": "Premium Support",
      "quantity": 1,
      "price": "$49.99"
    }
  ],
  "subtotal": "$109.97",
  "shippingCost": "$10.00",
  "taxAmount": "$9.80",
  "totalAmount": "$129.77",
  "shippingAddress": "123 Main St",
  "shippingCity": "San Francisco",
  "shippingState": "CA",
  "shippingZip": "94102",
  "shippingCountry": "USA",
  "estimatedDelivery": "2024-01-29",
  "trackingLink": "https://tracking.carrier.com/123456"
}
```

## Advanced Patterns

### Conditional Content (Novu Syntax)

**VIP Customer Special**
```html
{{#if isPremium}}
  <p>🎉 Enjoy your premium benefits:</p>
  <ul>
    <li>Free shipping</li>
    <li>Priority support</li>
  </ul>
{{/if}}
```

**Payment Method Notice**
```html
{{#if paymentMethod}}
  <p>Paid with {{paymentMethod}}</p>
{{/if}}
```

### Array/Loop Pattern

**Multiple Products**
```html
<table>
  {{#each products}}
    <tr>
      <td>{{this.name}}</td>
      <td>{{this.quantity}} x {{this.price}}</td>
    </tr>
  {{/each}}
</table>
```

**Recipients List** (for newsletters)
```html
<ul>
  {{#each recipients}}
    <li>{{this.name}} - {{this.email}}</li>
  {{/each}}
</ul>
```

### Fallback Values (Novu Syntax)

```html
<!-- If firstName missing, uses "Friend" -->
<p>Hello {{firstName "Friend"}},</p>

<!-- With object fallback -->
<p>Hi {{user.name "Valued Customer"}},</p>
```

## Template Variations by Industry

### E-Commerce
Required placeholders:
- Order/product info: `{{orderNumber}}`, `{{productName}}`
- Pricing: `{{price}}`, `{{taxAmount}}`, `{{totalAmount}}`
- Shipping: `{{trackingNumber}}`, `{{estimatedDelivery}}`
- Links: `{{trackingLink}}`, `{{supportLink}}`

### SaaS/Subscription
Required placeholders:
- Account: `{{accountName}}`, `{{planName}}`
- Billing: `{{billingDate}}`, `{{amount}}`, `{{nextDueDate}}`
- Links: `{{invoiceLink}}`, `{{manageLink}}`, `{{supportLink}}`

### Appointment/Booking
Required placeholders:
- User: `{{userName}}`, `{{userEmail}}`
- Appointment: `{{appointmentDate}}`, `{{appointmentTime}}`
- Provider: `{{providerName}}`, `{{location}}`
- Actions: `{{confirmLink}}`, `{{cancelLink}}`, `{{rescheduleLink}}`

### Two-Factor Authentication
Required placeholders:
- Code: `{{verificationCode}}` (6 digits)
- User: `{{firstName}}`
- Security: `{{expirationTime}}`, `{{ipAddress}}`
- Note: Never include recovery codes in email

### Promotional/Newsletter
Required placeholders:
- User: `{{firstName}}`
- Campaign: `{{campaignName}}`, `{{campaignDate}}`
- Content: `{{offer}}`, `{{discountCode}}`
- Links: `{{ctaLink}}`, `{{unsubscribeLink}}`

## Placeholder Naming Convention

### Recommended Patterns
```
// User info
{{firstName}}, {{lastName}}, {{email}}, {{phoneNumber}}

// Order/Transaction
{{orderNumber}}, {{orderDate}}, {{orderStatus}}, {{totalAmount}}

// Product
{{productName}}, {{productId}}, {{productPrice}}, {{quantity}}

// Addresses
{{shippingAddress}}, {{shippingCity}}, {{shippingState}}
{{billingAddress}}, {{billingCity}}, {{billingState}}

// Dates
{{orderDate}}, {{deliveryDate}}, {{expirationTime}}

// URLs
{{verificationLink}}, {{resetLink}}, {{trackingLink}}, {{supportLink}}

// Company
{{appName}}, {{companyName}}, {{brandName}}, {{logoUrl}}

// Nested objects
{{user.firstName}}, {{order.id}}, {{product.price}}
```

### Avoid
- Underscores: Use camelCase not snake_case
- Mixed naming: Be consistent across templates
- Unclear names: `{{data}}` ❌ use `{{totalAmount}}` ✓
- Abbreviations: `{{fName}}` ❌ use `{{firstName}}` ✓

## Testing Variables

### Test Payload Template
```json
{
  "firstName": "John",
  "lastName": "Doe",
  "email": "john.doe@example.com",
  "appName": "MyApp",
  "orderNumber": "ORD-123456",
  "orderDate": "2024-01-26",
  "totalAmount": "$99.99",
  "itemName": "Premium Plan",
  "itemQuantity": 1,
  "itemPrice": "$99.99",
  "verificationLink": "https://app.example.com/verify?token=abc123",
  "resetLink": "https://app.example.com/reset?token=xyz789",
  "trackingLink": "https://carrier.example.com/track/123456",
  "supportLink": "https://support.example.com",
  "expirationTime": "24"
}
```

Use this template when validating with test data before deploying to production.
