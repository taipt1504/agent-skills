# Evaluation Dimensions — Catalog by Task Type

Pick 3-5 dimensions BEFORE generating A1. Post-hoc dimensions = rationalization.

## Feature implementation

- **Correctness** — does it produce right output for all inputs?
- **Performance** — latency, throughput, resource usage
- **Code complexity** — cyclomatic, line count, abstraction depth
- **Maintainability** — readability, test coverage, debuggability
- **Time-to-ship** — calendar days from start to deployable
- **Test coverage gain** — does this make testing easier or harder?

## Refactor

- **Reversibility** — can we roll back if approach fails mid-implementation?
- **Blast radius** — how many files/modules/services affected?
- **Test coverage impact** — net change in coverage during/after refactor
- **Team familiarity** — does team know the new pattern?
- **Risk of regression** — likelihood of introducing bugs
- **Migration path** — incremental possible or big-bang only?

## Architecture decision

- **Scalability** — handles 10x growth?
- **Operational cost** — infrastructure $, ops complexity, on-call burden
- **Lock-in** — vendor, technology, paradigm
- **Team expertise** — existing skill or learning curve?
- **Rollback cost** — if wrong choice, what to undo?
- **Time to implement** — proof-of-concept to production
- **Maintenance burden** — ongoing care + feeding

## Bug fix

- **Risk of regression** — does fix break adjacent behavior?
- **Root cause depth** — symptom vs cause
- **Test coverage gain** — does fix add reproducible test?
- **Scope creep risk** — does fix tempt unrelated changes?
- **Reproduction difficulty** — can fix be validated locally?

## Library / tool selection

- **License compatibility** — Apache 2.0, MIT, GPL, commercial?
- **Maintenance status** — last commit, contributor count, issue response time
- **Community size** — Stack Overflow questions, GitHub stars, corporate sponsors
- **Integration cost** — config + adapter + migration effort
- **Performance benchmarks** — measured on representative workload
- **Migration cost** — if we want to switch away later
- **Lock-in risk** — proprietary APIs that resist replacement
- **Security CVE history** — vulnerability disclosure record

## Performance optimization

- **Speedup factor** — measured, not estimated
- **Memory overhead** — bytes added per request/operation
- **Complexity added** — cache invalidation, cache stampede, sync logic
- **Cache coherence** — staleness window acceptable?
- **Cost** — infra $ vs developer-hour saved

## Security work

- **Threat model coverage** — which threats does this mitigate?
- **Attack surface change** — net + or − on exposed surface
- **Operational friction** — does it slow developers/operators?
- **Compliance fit** — satisfies regulatory requirement?
- **Detection / response** — auditable + alertable?

## Migration / breaking change

- **User disruption** — clients affected, downtime required
- **Backward compat window** — old + new coexist for N months?
- **Rollback cost** — if migration fails midway
- **Coordination cost** — teams to align, communication overhead
- **Data integrity** — risk of loss/corruption during cutover

## Anti-patterns

- ❌ Vague dimension ("good code") — be measurable
- ❌ Single dimension ("simple") — minimum 3
- ❌ Too many dimensions (>7) — paralysis, hard to compare
- ❌ Dimensions that ALL favor one solution — biased framing
- ❌ Dimensions invented post-A1 — rationalization

## When to add a dimension mid-tournament

If A2 reveals a property A1 lacks (e.g., A1 missed "rollback cost"), add the dimension to the matrix. Update A1's score retroactively (honestly). Continue tournament.
