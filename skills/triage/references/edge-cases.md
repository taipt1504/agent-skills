# Triage Edge Cases

## Ambiguous task description

User: "Improve user lookup"

**Default:** Standard lane + immediately fire Align gate to surface specifics.

**Output:**
```
## Triage decision
**Lane:** Standard (provisional)
**Reasoning:** Description is vague ("improve" without target metric).
**Next gate:** Align — clarify what "improve" means (latency? error rate? coverage?)
**Re-triage after Align if scope shifts.**
```

## Multi-task request

User: "Add pagination to user list AND migrate orders table to JSONB"

**Process:**
1. Decompose into sub-tasks
2. Triage each independently:
   - "Add pagination to user list" → Standard
   - "Migrate orders table to JSONB" → High-stakes
3. Process highest-lane first (high-stakes dominates)
4. Each sub-task gets its own lane in `current-triage.json` (array of triage decisions)

## Hotfix under time pressure

User: "Production is down — fix the NullPointerException in checkout NOW"

**Default:** High-stakes (production impact + likely needs rollback plan).

User may downgrade: "skip brainstorm, I know the fix" → standard lane permitted ONLY with explicit `user_override: true` + reviewer notified post-hoc.

NEVER auto-downgrade hotfixes to trivial — even one-line fixes to production need spec scenario + review.

## Exploratory / prototype / spike

User: "Spike: try TigerBeetle for ledger writes"

**Default:** Standard with caveat — skip Spec gate but keep Plan.

**Output:**
```
**Lane:** Standard (exploratory)
**Skipped gates:** Spec
**Required:** Plan, Execute (sandbox/branch only), Verify (smoke only)
**Constraint:** prototype branch — do not merge to main without re-triage to high-stakes.
```

## Refactor that touches "many files mechanically"

User: "Rename `getUsersByStatus` to `findUsersByStatus` everywhere"

**Decision tree:**
- Internal method (private/package) → Trivial (mechanical rename)
- Public method on service interface → Standard (callers may exist)
- Public REST API → High-stakes (breaking change for clients)

Use `grep -rln` to count callers before deciding. If ≥10 cross-package callers, consider standard regardless of visibility.

## Dependency bump

User: "Bump Spring Boot from 3.1.5 to 3.1.6"

**Default:** Standard (patch version).

User: "Bump Spring Boot from 3.1 to 3.2"

**Default:** High-stakes (minor version, behavior changes likely, cross-service impact in microservice cluster).

User: "Bump from Spring Boot 2 to 3"

**Default:** High-stakes (major version, Jakarta EE namespace change, mandatory ADR).

## Bug fix complexity

User: "Fix the bug in OrderService.processPayment"

**Heuristic:**
1. Reproducer ≤5 lines + fix ≤5 lines + unit test covers it → Trivial
2. Reproducer requires integration test OR fix touches >1 method → Standard
3. Root cause is design flaw (race condition, ordering bug, distributed state) → High-stakes

Always write spec scenario for the bug regardless of lane — bug fix without test = regression magnet.

## Config-only change

User: "Increase database connection pool from 10 to 50"

**Default:** Standard (production impact on resource consumption).

**Reasoning:** Configuration affects observed behavior under load — not trivial. Requires load test verification or rollback plan.

## Test-only change

User: "Add unit test for UserService.findById"

**Default:** Standard (new test = new behavior assertion).

**Trivial exception:** if test fixes a known typo or completes a partial test stub already in repo (≤5 lines added, no new assertions).

## Documentation change

User: "Update README example to use the new API"

**Default:** Trivial (no production code change, no behavior change).

**Escalate to standard if:** documentation includes runnable example that constitutes a contract (e.g., README is the API reference).

## User explicitly says "trivial"

User: "This is trivial, just rename the variable"

If task meets trivial criteria → proceed.

If task does NOT meet criteria (e.g., user wants to "trivially" change DB schema):
- Warn: "Task meets high-stakes criteria (schema change). Override required."
- Require explicit second confirmation ("yes, override to standard")
- Log `user_override: true` in current-triage.json
- Flag for reviewer attention

NEVER silently accept misclassification.
