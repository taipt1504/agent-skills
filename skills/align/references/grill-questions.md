# Grill Question Library — 5 Patterns

Question patterns to surface ambiguity. Pick 1-2 per align session. Don't ask all 5.

## Pattern 1 — The 5 Whys (solution stated as problem)

User states a solution, not the problem behind it.

**Example:**
User: "Add Redis cache for user lookups"

```
Why cache? → "User API is slow"
Why slow? → "Database queries take 500ms"
Why slow queries? → "N+1 problem in JPA"
Why N+1? → "Lazy loading on UserRoles association"
Why lazy? → "Default JPA setting, never reviewed"
```

**Surfaced:** Real problem is N+1, not missing cache. Different solution space entirely. Maybe `@EntityGraph` fixes it without adding cache infrastructure.

## Pattern 2 — Goal vs Method

User picks a tool without stating the goal it serves.

**Example:**
User: "Use Strategy pattern for payment processing"

**Probe:**
- "What's the goal? Different payment methods? Easier testing? Future flexibility?"
- "What's wrong with the current implementation?"
- "What's the cost of changing the abstraction in 6 months if Strategy isn't right?"

**Surfaced:** Maybe Strategy is wrong tool. Maybe state machine fits multi-step flows better. Maybe chain of responsibility fits ordered validation better. Don't anchor on solution before understanding goal.

## Pattern 3 — Edge cases first

Force user to enumerate uncomfortable scenarios upfront.

**Example:**
User: "Add user deletion endpoint"

**Probe:**
- "What about user's orders? Delete? Anonymize? Retain for audit?"
- "Cascade to comments / reviews?"
- "Soft delete or hard delete?"
- "Who can call this? Admin only? Self-service?"
- "Compliance: GDPR right to be forgotten?"
- "Retention: how long to keep the deletion record?"
- "Idempotency: what if called twice?"
- "Concurrent: what if user has active session?"

**Surfaced:** Spec is often 10x more complex than initial ask. Better to know now than rebuild after launch.

## Pattern 4 — Failure modes

Distributed-systems probe.

**Example:**
User: "Send email on order completion"

**Probe:**
- "SMTP server down? Retry? Queue? Drop?"
- "User email invalid? Notify customer service?"
- "Order completion fails after email sent — compensating action?"
- "Idempotency: prevent duplicate emails on retry?"
- "Rate limiting: spam protection?"
- "Bounce handling?"
- "Template rendering fails?"

**Surfaced:** Reliability concerns that drive architecture choice (sync vs async, outbox pattern, retry policy).

## Pattern 5 — Performance characteristics

Non-functional requirements upfront.

**Example:**
User: "Add search functionality"

**Probe:**
- "Expected QPS?"
- "Data size — current, projected at 1 year?"
- "Latency targets — p50, p95, p99?"
- "Real-time freshness or eventual?"
- "Fuzzy matching needed?"
- "Internationalization (locale-aware tokenization)?"
- "Result ranking — relevance score or simple sort?"
- "Faceting / aggregations?"

**Surfaced:** "Search" can mean `WHERE LIKE '%x%'` or Elasticsearch — orders of magnitude apart in effort + ops cost.

## Combo selection guide

| Task signal | Patterns to use |
|---|---|
| Solution stated, problem unclear | 1 + 2 |
| New feature ("add X") | 3 + 4 |
| Async / distributed flow | 4 |
| New endpoint | 3 + 5 |
| Architecture decision | 2 + 4 + 5 |
| Bug fix ("fix Y") | 1 (root cause) |
| Performance work | 5 + 1 |

## Anti-patterns in grilling

- ❌ "Tell me everything about your domain" (overwhelming)
- ❌ "What's your vision for this product?" (abstract, slow)
- ❌ "Are there any edge cases?" (user will say no — be specific)
- ❌ Asking 10 questions before user responds (batch in 3-5)
- ❌ Pushing back on every assumption (lose rapport)

## When to stop grilling

Stop when:
- User confirms restated problem AND
- Assumptions confirmed or corrected AND
- ≥1 edge case from each relevant category surfaced AND
- Success criteria explicit (testable)

OR user signals "enough, let's move on" — respect with caveat: "I'll proceed but flagging unresolved questions for Plan/Spec."
