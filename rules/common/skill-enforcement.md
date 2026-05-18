---
name: skill-enforcement
description: 1% rule for skill + rule discovery. Mandatory pre-flight enumeration before every workflow gate. Bias toward over-enumeration.
globs: "*"
applicability:
  always: true
---

# Skill + Rule Enforcement — 1% Rule

> Pre-flight protocol supersedes the old file-glob skill matcher.

## The 1% rule

Before EVERY workflow gate, enumerate ALL skills/rules with **≥1% relevance**. Justify every SKIP with concrete evidence.

**Asymmetric cost:** false positive (SKIP) = few tokens. False negative (miss) = debt, rework.

→ Bias toward **over-enumeration**.

## Protocol

Before Align / Brainstorm / Plan / Spec / Execute / Review:

1. **Enumerate** ALL skills (`find skills -name SKILL.md`) + rules
2. **Score** relevance (0–100%)
3. **Decide** APPLY or SKIP per item
4. **Justify** every SKIP with concrete evidence (file path, dep check, grep result)
5. **Output** artifact to `.claude/memory/preflight/<gate>-<timestamp>.md`
6. **Reference** during gate execution

### Rule directory structure (v4.0)

```
rules/
├── common/      # Language-agnostic; ALWAYS enumerated
├── java/        # Java + Spring; ALWAYS enumerated for Java projects
└── summer/      # Summer-specific; CONDITIONAL — only when project-profile.json summer:true OR io.f8a.summer in build.gradle
```

`scripts/hooks/preflight-discovery.sh` omits `rules/summer/` when Summer not detected. Same for `summer-*` skills.

## Score thresholds

| Score | Threshold |
|---|---|
| 90–100% | Central to gate, definitely applies |
| 60–89% | Likely applies, supports gate |
| 30–59% | Possibly applies, edge case |
| 1–29% | Marginal, verify carefully |
| 0% | Not relevant — justify with evidence |

## SKIP justification requirements

Always concrete:
- ✅ "SKIP: no Kafka (grep -r 'spring-kafka' build.gradle = 0)"
- ✅ "SKIP: WebFlux not MVC (servlet stack disabled)"
- ❌ "SKIP: not relevant" (vague)
- ❌ "SKIP: doesn't apply" (vague)

## Announce-on-load

- `Using skill: {name} for {reason}`
- `Apply rule: {path} — {reason}`

NO file-based gate. NO blocking persistence. Announcement is the contract.

## Per-gate mappings

See `skills/preflight/references/gate-mappings.md` for which skills/rules typically apply per gate.

## This is non-negotiable

Workflow blocks gates without pre-flight artifact. No bypass — pre-flight is foundation.

## Related

- `skills/preflight/SKILL.md` — pre-flight protocol detail
- `rules/common/lanes.md` — lane-based gate routing
- `scripts/hooks/preflight-gate.sh` — enforcement hook
