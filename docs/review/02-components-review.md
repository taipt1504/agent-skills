# Components Review — Agents, Skills, Commands, Rules & Hooks

> **Reviewer**: components-reviewer | **Overall Quality**: 4.3/5
> **Scope**: Plugin code only. `docs/` excluded (document storage, not plugin structure).
> **Structure Note**: Skills are **flat** (`skills/{name}/SKILL.md`) since v3.0. No nested `generic/`/`summer/`/`meta/` subdirectories.

---

## 1. Agents (8 total)

| Agent | Quality | Model | Tokens | Key Strength | Key Issue |
|-------|---------|-------|--------|-------------|-----------|
| planner | 4/5 | opus | ~3,800 | Comprehensive planning, scalability tiers, ADRs | Token bloat from code examples (~40% overlap with skills) |
| spec-writer | **5/5** | opus | ~2,900 | Best agent — 7-step process, 5 templates, test mapping | Minor: no memory/knowledge-graph section |
| implementer | 4/5 | opus | ~2,900 | Clear TDD cycle, good mocking patterns | Missing `maxTurns`, model contradiction with build.md |
| reviewer | **5/5** | opus | ~3,800 | 7 conditional checklists, file-pattern activation | Token-heavy, diagnostic commands could be reference file |
| build-fixer | 4/5 | sonnet | ~2,900 | Clear scope, minimal diff strategy | Some pattern overlap with reviewer |
| test-runner | 3.5/5 | sonnet | ~2,500 | E2E + blackbox separation, fix table | Line 157: old path `skills/generic/` (should be `skills/`) |
| database-reviewer | 4/5 | sonnet | ~2,300 | Engine-specific guidance (PG vs MySQL) | Overlaps heavily with reviewer's DB checklist |
| refactorer | 3/5 | sonnet | ~1,800 | Safety hierarchy (SAFE/CAREFUL/RISKY) | Thinnest agent, fragile shell commands |

### Top Agent Issues
1. Memory preamble duplicated in 4 agents (~400 tokens wasted)
2. test-runner line 157: old path `skills/generic/` → should be `skills/`
3. Implementer missing `maxTurns` (could loop indefinitely)
4. database-reviewer may be mergeable into reviewer's conditional checklist

---

## 2. Skills (18 total)

| Skill | Quality | Tokens | Key Issue |
|-------|---------|--------|-----------|
| bootstrap | **5/5** | ~1,300 | Crown jewel — skill registry + workflow engine |
| spring-patterns | **5/5** | ~1,100 | Exemplary — MVC/WebFlux decision table |
| spring-security | 4.5/5 | ~870 | OWASP Top 10 quick rules |
| database-patterns | **5/5** | ~900 | Engine differences table |
| messaging-patterns | **5/5** | ~1,000 | Kafka vs RabbitMQ decision table |
| testing-workflow | **5/5** | ~940 | 7-phase verification pipeline |
| coding-standards | 4.5/5 | ~870 | **Inconsistency**: >30 lines smell vs CLAUDE.md 50 max |
| architecture | 4.5/5 | ~960 | Hexagonal layers + CQRS + mapping strategy |
| api-design | 4.5/5 | ~1,000 | HTTP methods, RFC 7807, pagination |
| redis-patterns | 4.5/5 | ~1,200 | **BUG**: `.subscribe()` anti-pattern in own code |
| observability-patterns | 4.5/5 | ~1,400 | Over token budget — YAML configs should be reference |
| continuous-learning | 3.5/5 | ~930 | **Incomplete**: references non-existent `observe.sh` |
| summer-core | **5/5** | ~880 | Hard gate for summer detection |
| summer-rest | 4.5/5 | ~1,000 | Handler pattern |
| summer-data | 4.5/5 | ~1,300 | Over budget — outbox YAML to reference |
| summer-security | 4.5/5 | ~1,200 | APISIX + Keycloak |
| summer-ratelimit | **5/5** | ~1,200 | Clear strategies + YAML config |
| summer-test | 4/5 | ~1,100 | TestCaseUtils source unclear |

### Top Skill Issues
1. **redis-patterns**: `.subscribe()` in locking code contradicts reviewer's anti-pattern check
2. **coding-standards**: Method length >30 smell vs CLAUDE.md 50 max — needs alignment
3. **continuous-learning**: References `hooks/observe.sh` that doesn't exist — incomplete feature
4. **observability-patterns** and **summer-data**: Over ~800 token budget

### Gaps Identified
- No **gRPC patterns** skill (mentioned in planner's package structure)
- No **Resilience4j** dedicated skill (mentioned in several places)

---

## 3. Commands (12 total)

| Command | Quality | Tokens | Key Issue |
|---------|---------|--------|-----------|
| /plan | **5/5** | ~1,000 | |
| /spec | **5/5** | ~2,300 | Templates duplicated with spec-writer agent |
| /build | 4.5/5 | ~1,600 | **Says sonnet but agent says opus** |
| /verify | **5/5** | ~1,500 | 4 modes with clear escalation |
| /review | 4/5 | ~1,200 | Nesting depth >4 conflicts with rules <=3 |
| /build-fix | 4/5 | ~1,700 | Overlaps with build-fixer agent |
| /db-migrate | 4.5/5 | ~1,300 | |
| /e2e | 4/5 | ~2,000 | Hardcoded Testcontainers version |
| /setup | 4.5/5 | ~1,500 | |
| /status | 4/5 | ~2,900 | **BUG**: Old skill path structure |
| /refactor | 3.5/5 | ~1,200 | Thin wrapper |
| /meta | 4/5 | ~2,500 | References incomplete continuous-learning |

### Top Command Issues
1. **/status** lines 111-148: scans non-existent `skills/generic/`, `skills/summer/` → should scan flat `skills/*/`
2. **/build** model inconsistency (sonnet vs opus)
3. **Spec templates duplicated** between /spec command and spec-writer agent
4. **/review** nesting depth threshold inconsistency

---

## 4. Rules (9 total)

| Rule | Quality | Globs | Issue |
|------|---------|-------|-------|
| spec-driven | **5/5** | `*` | |
| coding-style | **5/5** | `*.java` | |
| architecture-patterns | **5/5** | `*.java` | |
| api-design | **5/5** | `*.java` | |
| security | **5/5** | `*.java` | |
| observability | 4.5/5 | `*.java` | Could add `*.yml` |
| testing | 4.5/5 | `*.java` | |
| git-workflow | 4/5 | `*` | Brief compared to others |
| development-workflow | 4.5/5 | `*` | Overlaps with bootstrap workflow section |

**Average: 4.7/5** — Highest quality category. Concise, actionable, well-targeted.

---

## 5. Hooks (7 scripts + hooks.json)

| Script | Quality | Issue |
|--------|---------|-------|
| run-with-flags.sh | **5/5** | Default profile may conflict with intent |
| session-init.sh | 4.5/5 | Fragile sed escaping for bootstrap content |
| skill-router.sh | 4/5 | Lines 82-83: log message uses old paths (routing logic itself is correct) |
| quality-gate.sh | 4/5 | 90s timeout; macOS has no `timeout` command |
| compact-advisor.sh | 4.5/5 | Counter in /tmp resets on reboot |
| pre-compact.sh | 3.5/5 | **Shell injection vulnerability**; recovery never used |
| session-save.sh | 4/5 | python3 dependency; learning signals never consumed |

---

## Cross-Cutting: Content Duplication

| Duplication Zone | Estimated Token Waste |
|-----------------|----------------------|
| Memory preamble in 4 agents | ~400 |
| development-workflow rule + bootstrap workflow | ~300 |
| spec templates in agent + command | ~800 |
| reviewer + database-reviewer overlap | ~500 |
| implementer + testing-workflow overlap | ~400 |
| **Total estimated waste** | **~2,400** |
