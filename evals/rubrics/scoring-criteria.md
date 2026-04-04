# Scoring Criteria — 9 Dimensions

## Overview

Each session is scored on 9 criteria. Each criterion produces a score from 0.0 to 1.0.
The composite score is a weighted average.

---

## 1. Code Quality (Weight: 15%)

**What:** Does the generated code compile, pass tests, and follow best practices?

**Measurement (automated):**
- Compile success: `./gradlew compileJava` exit 0 → +0.30
- Test success: `./gradlew test` exit 0 → +0.30
- No critical violations (`.block()`, `@Autowired` field, exposed entities) → +0.20
- Test coverage ≥ 80% (JaCoCo) → +0.20

**Formula:**
```
score = 0.30 * compile_pass + 0.30 * tests_pass + 0.20 * no_critical_violations + 0.20 * coverage_met
```

---

## 2. Convention Compliance (Weight: 10%)

**What:** Does the output follow CLAUDE.md hard rules and coding standards?

**Measurement (automated grep checks):**
- No `.block()` in reactive code → +0.20
- No `@Autowired` field injection → +0.15
- DTOs are records (not classes with getters) → +0.15
- Entities not exposed in API responses → +0.15
- `@Valid` on API boundaries → +0.10
- Parameterized queries (no string concat) → +0.10
- Constructor injection via `@RequiredArgsConstructor` → +0.10
- Domain exceptions (not RuntimeException) → +0.05

**Formula:**
```
score = sum(check_weight * check_passed for each check)
```

---

## 3. Workflow Compliance (Weight: 10%)

**What:** Did the agent follow the 5-phase workflow?

**Measurement (from workflow-state.json + execution traces):**
- PLAN phase executed → +0.25
- SPEC phase executed (skip OK for ≤5-line fixes) → +0.20
- BUILD phase completed → +0.15
- VERIFY phase executed (tests/compile ran) → +0.25
- REVIEW phase executed → +0.15

**Penalties:**
- Skip VERIFY → score × 0.5
- Skip REVIEW → score × 0.7
- Stop at BUILD → score = 0.15 (BUILD only credit)

**Formula:**
```
base = sum(phase_weight * phase_executed)
score = base * skip_penalty_multiplier
```

---

## 4. Skill Utilization Effectiveness (Weight: 15%)

**What:** Did agents use the right skills, and use them effectively?

**Measurement (from session-metrics.json + execution traces):**

### 4a. Skill Coverage (0.40)
```
expected_skills = set(skills listed in task's "Expected Skill Usage")
used_skills = set(skills from session traces where skill != "untagged")
coverage = len(expected_skills & used_skills) / len(expected_skills)
```

### 4b. Skill Announcement (0.20)
Did agent announce skills before use? ("Applying skill: {name}")
```
announcements = count("Applying skill:" in agent output)
skill_uses = count(distinct skills in traces)
announcement_rate = min(announcements / max(skill_uses, 1), 1.0)
```

### 4c. Skill Usage Report (0.20)
Did agent generate the mandatory Skill Usage Report table at task end?
```
report_present = 1.0 if "Skill Usage Report" table found in output else 0.0
```

### 4d. Commands Usage (0.20)
Did agent use relevant plugin commands (/plan, /spec, /verify, /build, etc.)?
```
expected_commands = commands matching task workflow phases
used_commands = commands detected in session
command_coverage = len(expected_commands & used_commands) / len(expected_commands)
```

**Formula:**
```
score = 0.40 * coverage + 0.20 * announcement_rate + 0.20 * report_present + 0.20 * command_coverage
```

---

## 5. Skill Trigger Accuracy (Weight: 10%)

**What:** When a skill should have been loaded, was it? When it shouldn't have been, was it not?

**Measurement:**

### 5a. True Positive Rate (0.50)
Skills that should have been used AND were used.
```
tpr = len(expected & used) / len(expected)
```

### 5b. False Positive Rate (0.30)
Skills loaded that had no relevance to the task.
```
irrelevant = used - expected - always_loaded
fpr = 1.0 - (len(irrelevant) / max(len(used), 1))
```

### 5c. Trigger Latency (0.20)
How many tool calls before the first relevant skill was loaded?
```
first_skill_call = index of first skill-related trace entry
latency_score = max(0, 1.0 - (first_skill_call / 10))  # penalty after 10 calls
```

**Formula:**
```
score = 0.50 * tpr + 0.30 * fpr_inverse + 0.20 * latency_score
```

---

## 6. Context Efficiency & Memory (Weight: 10%)

**What:** Is context budget used optimally? Is memory leveraged cross-session?

**Measurement:**

### 6a. Progressive Disclosure (0.30)
Did agent load SKILL.md first and references only when needed?
```
ref_loads = count(Read tool on references/ files)
skill_loads = count(Read tool on SKILL.md files)
ratio = skill_loads / max(skill_loads + ref_loads, 1)
# Good: ratio > 0.5 (more SKILL.md than references)
# Bad: ratio < 0.3 (loaded too many references upfront)
progressive_score = min(ratio / 0.5, 1.0)
```

### 6b. Context Budget (0.30)
Total context consumed vs task complexity.
```
total_tool_calls = from session-metrics.json
expected_calls = task.estimated_complexity * 15  # rough baseline
efficiency = min(expected_calls / max(total_tool_calls, 1), 1.0)
```

### 6c. Memory Load (0.20)
Did agent search memory at session start?
```
memory_searched = 1.0 if mcp__memory__search_nodes in first 5 tool calls else 0.0
```

### 6d. Memory Write (0.20)
Did agent create/update memory entities after completing task?
```
memory_written = 1.0 if mcp__memory__create_entities in last 10 tool calls else 0.0
```

**Formula:**
```
score = 0.30 * progressive + 0.30 * budget + 0.20 * memory_load + 0.20 * memory_write
```

---

## 7. Task Completion Rate (Weight: 15%)

**What:** Did the task reach successful completion?

**Measurement:**

### 7a. REVIEW Pass (0.50)
Did the task reach REVIEW phase and pass?
```
review_passed = 1.0 if final phase == REVIEW and status == PASS else 0.0
```

### 7b. Verify Pass Rate (0.30)
How many verify attempts before passing?
```
verify_attempts = from verify-fix-state.json
verify_score = 1.0 if attempts <= 1 else max(0.3, 1.0 - (attempts - 1) * 0.2)
```

### 7c. No Escalation (0.20)
Did the task complete without escalating to user due to stuck loops?
```
no_escalation = 0.0 if "ESCALATE" or "NO_PROGRESS" in traces else 1.0
```

**Formula:**
```
score = 0.50 * review_passed + 0.30 * verify_score + 0.20 * no_escalation
```

---

## 8. Task Execution Optimality (Weight: 10%)

**What:** Was the task executed efficiently (minimal tool calls, no wasted work)?

**Measurement:**

### 8a. Tool Call Efficiency (0.40)
```
actual_calls = total tool calls from metrics
baseline_calls = task.estimated_complexity * 12  # empirical baseline
efficiency = min(baseline_calls / max(actual_calls, 1), 1.0)
```

### 8b. No Redundant Work (0.30)
Same file edited more than 3 times → redundancy detected.
```
file_edits = count edits per file from traces
max_edits = max(file_edits.values())
redundancy_score = 1.0 if max_edits <= 3 else max(0.3, 1.0 - (max_edits - 3) * 0.15)
```

### 8c. Error Recovery Speed (0.30)
When verify fails, how many tool calls to fix?
```
recovery_calls = calls between verify failure and next verify success
recovery_score = 1.0 if recovery_calls <= 5 else max(0.2, 1.0 - (recovery_calls - 5) * 0.1)
```

**Formula:**
```
score = 0.40 * efficiency + 0.30 * no_redundancy + 0.30 * recovery_speed
```

---

## 9. Cross-Session Memory (Weight: 5%)

**What:** Does information persist and get used across sessions?

**Measurement (requires 2-session eval — task 13):**

### 9a. Memory Recall (0.50)
Did Session 2 retrieve relevant decisions from Session 1?
```
recall = 1.0 if session2 applied session1 decisions without being told else 0.0
```

### 9b. Memory Accuracy (0.25)
Were recalled decisions correctly applied?
```
accuracy = correct_applications / total_applications
```

### 9c. Knowledge Graph Update (0.25)
Did Session 2 update the knowledge graph with new learnings?
```
updated = 1.0 if new entities/observations created in session 2 else 0.0
```

**Formula:**
```
score = 0.50 * recall + 0.25 * accuracy + 0.25 * updated
```

---

## Composite Score

```
composite = sum(criterion_weight * criterion_score for all 9 criteria)
```

### Grade Mapping

| Score Range | Grade | Interpretation |
|-------------|-------|----------------|
| 0.90 – 1.00 | A | Excellent — plugin maximally utilized |
| 0.80 – 0.89 | B | Good — minor inefficiencies |
| 0.70 – 0.79 | C | Acceptable — notable gaps |
| 0.60 – 0.69 | D | Below expectations — significant issues |
| 0.00 – 0.59 | F | Failed — plugin not effectively used |
