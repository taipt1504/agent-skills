# Working Workflow — 5-Layer Adaptive

> Operational reference for the v4.0 workflow. Read this once. Skim later as needed.
> Companion to `CLAUDE.md` (hard rules) and `MIGRATION_v2.md` (v1→v2 changes).

---

## The 5-layer flow

```
REQ → BOOT → PREFLIGHT0 → TRIAGE
                            ├── trivial → EXECUTE (light) → REVIEW (S2 only) → COMMIT
                            └── standard / high-stakes →
                                ALIGN → PREFLIGHT1 → BRAINSTORM →
                                PREFLIGHT2 → PLAN → PREFLIGHT3 → SPEC →
                                PREFLIGHT4 → EXECUTE (subagent dispatch) →
                                PREFLIGHT5 → REVIEW (S1 + S2) → LEARN → COMMIT
```

Six pre-flights (0..5). Three lanes. Two review stages. One commit at the end (by user, never agent).

---

## Lane decision flowchart

```
Task description received
        │
        ▼
Is task ≤5 lines AND no behavior change AND no new dep?
        │
   ┌────┴────┐
   YES       NO
   │         │
   ▼         ▼
TRIVIAL    Does task touch ANY of:
           - System architecture / design pattern?
           - DB migration / schema change?
           - Auth / secrets / security boundary?
           - Public API contract?
           - Breaking change to existing behavior?
           - New external dependency?
                 │
            ┌────┴────┐
            YES       NO
            │         │
            ▼         ▼
       HIGH-STAKES  STANDARD
```

Triage agent emits `.claude/memory/state/current-triage.json` with the verdict + reasoning. Override available: `/triage <lane>`.

---

## Lane behavior reference

### Trivial lane

**Examples:** typo, rename internal variable, add Javadoc, reformat, copyright year bump.

```
Boot → Pre-flight 0 (light, 3-5 lines) → Triage
     → Execute (orchestrator direct, no subagent)
     → Verify (compile + format only)
     → Review Stage 2 (quality only, no Stage 1)
     → COMMIT (by user)
```

**Skipped:** Align, Brainstorm, Plan, Spec, Review Stage 1.

**Time-to-edit:** ~30 seconds.

### Standard lane (default)

**Examples:** add endpoint, fix bug, refactor service, add validation, optimize query.

```
Boot → Pre-flight 0 → Triage
     → Align (if vague request, skip if specific)
     → Pre-flight 1 → Brainstorm (if multi-path, skip if obvious)
     → Pre-flight 2 → Plan → user approves
     → Pre-flight 3 → Spec → user approves
     → Pre-flight 4 → Execute (one subagent per slice, parallel where independent)
     → Verify (full: compile + tests + coverage)
     → Pre-flight 5 → Review Stage 1 (binary) → Stage 2 (severity-tagged)
     → Learn (instinct extraction)
     → COMMIT (by user)
```

**Optional:** worktree per slice (user can request via `/build --worktree`).

### High-stakes lane

**Examples:** architecture change, DB migration, auth change, public API breaking change, new dep, cross-service work.

```
Boot → Pre-flight 0 → Triage
     → Align (mandatory)
     → Pre-flight 1 → Brainstorm (mandatory, ≥3 options) → ADR auto-generated
     → Architect review (auto)
     → Pre-flight 2 → Plan (extra detail on dependency graph + risk register)
     → Pre-flight 3 → Spec (extra rigorous scenarios)
     → Pre-flight 4 → Execute (subagent + worktree per slice)
     → Verify (full + security CVE scan + dependency audit)
     → Pre-flight 5 → Review Stage 1 → Stage 2 (security deep-dive)
     → Learn → ADR completion check
     → COMMIT (by user)
```

**Mandatory artifacts:** Align, Brainstorm, ADR.

---

## The 1% rule (pre-flight discovery)

Before EVERY gate, enumerate ALL skills + rules with ≥1% relevance. Score each. Decide APPLY or SKIP per item. Justify every SKIP with concrete evidence.

**Cost asymmetry:**
- False positive (enumerate then SKIP) = few tokens overhead
- False negative (miss applicable skill/rule) = technical debt, rework

→ **Bias toward over-enumeration.**

**Format per gate:**

```markdown
# Pre-flight: <Gate>
**Date:** YYYY-MM-DD HH:MM
**Lane:** <trivial | standard | high-stakes>

## Skills (N total)

### APPLY (count)
| Skill | Score | Action |
|---|---|---|
| ... | 90% | ... |

### SKIP (count)
| Skill | Reason (concrete evidence) |
|---|---|
| grpc-patterns | No gRPC in build.gradle (verified `grep -r '@GrpcService' src/` = 0) |

## Rules (N total)
... (same structure)
```

Trivial lane uses **light format** — 3-5 lines, no full tables. Still mandatory.

**SKIP justification rules:**
- ✅ "verified no Kafka dependencies in build.gradle"
- ✅ "no @PreAuthorize in scope (verified grep)"
- ❌ "not relevant" (vague — potential blind spot)
- ❌ "doesn't apply" (vague)

---

## Skill announcement contract

When loading a skill, announce in chat:

```
Using skill: <name> for <reason>
```

Cite skill names in commit messages + PR descriptions. NO file-based gate (`skills-loaded.json` removed in v4.0). Pre-flight discovery is the enforcement.

---

## Gate-by-gate cookbook

### Triage (every task)

```
User: /triage <task description>
Agent: applies decision tree → emits `.claude/memory/state/current-triage.json`
       outputs lane + reasoning + next gate
```

Auto-fires from `session-init.sh` when fresh task description detected.

### Align (standard if vague, high-stakes always)

```
User: /align    (or auto-fires)
Agent: 1. Restates problem in own words → user confirms
       2. Lists assumptions → user corrects
       3. Probes unstated requirements (5 question patterns, picks 3)
       4. Extracts vocabulary → updates CONTEXT.md
       5. Writes alignment artifact
```

Output: `.claude/memory/align-artifacts/<date>-<task>.md` + CONTEXT.md update.

### Brainstorm (high-stakes mandatory ≥3, standard conditional)

```
User: /brainstorm    (or auto-fires)
Agent: 1. Frame: 3-5 evaluation dimensions, constraints vs assumptions
       2. Generate A1 + self-critique
       3. Adversarial Challenge 1: beat A1's weakness → A2
       4. Adversarial Challenge 2: different paradigm → A3
       5. Adversarial Challenge 3: question assumption → A4 (high-stakes)
       6. Stop at hard cap 5 OR diminishing returns OR honest "no alternative"
       7. Comparison matrix (concrete values, not ✅/❌)
       8. Recommendation with explicit trade-offs
       9. ADR auto-generated for high-stakes
```

Output: `.claude/memory/brainstorm-artifacts/<date>-<task>.md` + optional ADR.

### Plan

```
User: /plan
Agent: 1. Reads Align + Brainstorm artifacts
       2. Decomposes chosen solution into vertical slices
       3. Builds dependency graph
       4. Risk-assesses each slice
       5. Orders slices (dependencies first, high-risk early)
       6. Estimates complexity (S/M/L)
       7. PICKS SHAPE per threshold:
          - ≤2 slices → single-file .claude/docs/plans/<feature>.md
          - 3+ slices → split .claude/docs/plans/<feature>/{index.md, slices/<NN>-<slug>.md}
       8. Validates: bash scripts/ci/validate-plan-spec-templates.sh
       9. Waits for user CONFIRM
```

**Split shape file layout (3+ slices):**
```
.claude/docs/plans/<feature>/
├── index.md              # Scope + Slice index + Dep graph + Risk register (aggregate) + Out-of-scope + Execution order
└── slices/
    ├── 01-<slug>.md      # per-slice: Description, Files, Skills, Rules, Rationale, Effort
    ├── 02-<slug>.md
    └── 03-<slug>.md
```

User responds: "approve" / "modify slice <id>: <changes>" / "reject".

**Per-slice status:** each slice file has `status: DRAFT|APPROVED|REVISED` frontmatter. Index aggregates: `APPROVED` only when ALL slices APPROVED. `PARTIALLY_APPROVED` if mixed — `/build` blocked until full approval.

### Spec

```
User: /spec
Agent: 1. Reads Plan + Align artifact
       2. INHERITS shape from plan:
          - Single-file plan → single-file spec .claude/docs/specs/<feature>.md
          - Split plan → split spec .claude/docs/specs/<feature>/{index.md, slices/*.md}
       3. Per slice: defines inputs, outputs, error cases, scenarios
       4. Each scenario maps 1:1 to a future test
       5. Split shape: index.md §1 Cross-cutting defines auth/logging/error envelope ONCE
                       per-slice spec §0 references index — NEVER duplicates
       6. Validates: bash scripts/ci/validate-plan-spec-templates.sh
       7. Waits for user CONFIRM
```

**Cross-cutting authority (split shape):** `index.md §1` is AUTHORITATIVE. Per-slice `§0 Cross-cutting reference` points to it. Override forbidden without ADR + slice §"Cross-cutting override" block.

### Execute (Build)

```
User: /build
Agent (orchestrator):
       1. Reads plan dependency graph
       2. Dispatches one slice-executor subagent per slice (parallel where independent)
       3. Each subagent receives: slice + spec + pre-flight 4 artifact + CONTEXT vocabulary
       4. Subagent runs RED→GREEN→REFACTOR per scenario
       5. Subagent reports results to orchestrator
       6. Orchestrator aggregates → triggers /verify
```

High-stakes: worktree per slice via `Agent` tool `isolation: "worktree"`.

### Verify

```
Auto-invoked by orchestrator after Build:
1. ./gradlew clean test (compile + unit + integration)
2. Coverage check (≥80% per rule)
3. Security scan (high-stakes: dep CVE + static analysis)
4. ./gradlew bootRun smoke (high-stakes only)

On fail: verify/fix loop → /build-fix → re-verify (max 3 retries)
On pass: → /dc-review
```

### Review (two-stage)

```
/dc-review orchestrates:
Stage 1 — spec-compliance-reviewer (binary PASS/FAIL):
  - Map every spec scenario to passing test
  - Verify contract clauses match code
  - Fail → BUILD with fix list, Stage 2 NOT run
  - Pass → Stage 2

Stage 2 — code-quality-reviewer (severity-tagged):
  - Security (OWASP, secrets, injection)
  - Performance (N+1, blocking calls, leaks)
  - Maintainability (DRY, SOLID, complexity)
  - Readability (naming, structure)
  - Test quality (assertions, edge cases)

  Critical → BLOCK (must fix)
  Major → recommend fix (user decides)
  Minor → note for future
```

### Learn (Stop hook)

```
At session end:
1. session-save.sh → workflow-state.json updates
2. auto-adr.sh (high-stakes lane) → prompt user if ADR missing
3. evolution-check.sh → scan instincts.jsonl → promotion candidates → notify user
```

User decides via `/meta evolve` whether to promote candidates.

---

## Memory tiers

| Tier | Location | Persistence | Examples |
|---|---|---|---|
| 1 — Session | `.claude/memory/{preflight,align-artifacts,brainstorm-artifacts,sessions,state}/` | Ephemeral (git-ignored) | Pre-flight artifacts, current triage, workflow state |
| 2 — Project | `CONTEXT.md`, `docs/adr/*.md` | Git-tracked | Domain vocabulary, ADRs |
| 3 — Global | `~/.claude/instincts/`, `~/.claude/skills/auto-evolved/` | Cross-repo | Instincts, evolved skills |

**Boot loads:** Tier 2 (project) + filtered Tier 3 (by keywords) → Tier 1 (session).
**During session:** writes to Tier 1, proposes updates to Tier 2 (CONTEXT.md, ADRs).
**Session end:** extracts from Tier 1 → instincts → Tier 3.
**Evolution:** Tier 3 instincts with high confidence → skills (still Tier 3).

---

## Common operations

### Start a new task

```
Just describe what you want. session-init.sh fires triage automatically.
Or explicitly: /triage <task>
```

### Re-triage mid-session

```
/triage           # re-evaluate current task
/triage trivial   # force trivial (warns if criteria not met)
/triage high-stakes  # upgrade
```

### Skip Align for high-stakes

```
Not recommended. If genuinely needed:
/no-align
(logs align_skipped: true, flagged for reviewer attention)
```

### Skip Brainstorm for standard

```
Standard lane: agent skips automatically if single obvious solution.
To force: /no-brainstorm
```

### Inspect current state

```
/dc-status        # full plugin state: lane, phase, artifacts, skills loaded, hooks profile
```

### Resume after compaction

State persists on disk (`.claude/memory/state/`). Read:
- `current-triage.json` — lane
- `workflow-state.json` — phase
- `build-checkpoint.json` — Build progress

### Run architecture review

```
/meta improve-architecture        # full survey
/meta improve-architecture --quick # single-package
```

### Promote instinct to skill

```
/meta evolve                  # walk through candidates
/meta evolve promote <id>     # force-promote specific instinct
/meta evolve --auto           # promote all candidates meeting thresholds
```

### Create ADR manually

```
/meta adr <decision-name>     # creates docs/adr/NNNN-<slug>.md from template
                               # pre-fills from latest brainstorm artifact if exists
```

---

## Hard rules (CLAUDE.md hard blocks — never violate)

1. `.block()` in reactive code → CRITICAL
2. `@Autowired` field injection → use `@RequiredArgsConstructor`
3. Expose entities in API → use record DTOs
4. Log PII / credentials / tokens
5. Commit secrets to git
6. Skip input validation on API boundaries
7. `SELECT *` in queries → explicit columns
8. Write code without `/plan` + `/spec` (except trivial)
9. Agent commits to git → FORBIDDEN, only user commits
10. Stop after BUILD without VERIFY + REVIEW → FORBIDDEN

---

## Troubleshooting

### Pre-flight artifact missing

`preflight-gate.sh` blocks the gate. Read stderr message. Produce the artifact by running the gate explicitly (e.g., `/brainstorm` produces brainstorm-prep + brainstorm output).

### Multi-agent dispatch fails

Verify `skills-loaded.json` is NOT being written by any hook. v4.0 removed this gate. If failing on a project upgraded from v1, run `/dc-setup` to migrate.

### Worktree accumulates

`.claude/memory/state/active-worktrees.json` tracks. `session-init.sh` warns if >5. Clean stale ones:
```bash
git worktree list
git worktree remove <path>
```

### Spec/Plan file missing

`/plan` and `/spec` write to `.claude/docs/plans/` and `.claude/docs/specs/`. Verify directory exists. If missing, `/dc-setup` scaffolds.

### Stage 2 review skipped

Check `.claude/memory/state/review-stage1.json`. If `status: FAIL`, Stage 2 intentionally did not run. Fix Stage 1 issues first, then re-run `/dc-review`.

---

## Related

- `CLAUDE.md` — hard rules + 1% rule mandate
- `MIGRATION_v2.md` — v1→v2 migration guide
- `REFACTOR_PLAN.md` — full plan that produced v4.0
- `.claude/docs/devco-improve-docs/` — design references (vendored)
- `examples/` — 3 end-to-end walkthroughs (trivial, standard, high-stakes)
