# Example: Library Selection Brainstorm

## User request

"Cần chọn JSON library cho high-throughput API."

## Phase 1 — Frame

**Problem:** Default Jackson is slower than alternatives. High-throughput endpoints (10k+ req/s) need lower CPU per request.

**Dimensions:**
- Performance (ops/sec on representative payload)
- Maintenance status (recent commits, contributor count)
- Compatibility (Spring Boot integration)
- Security (CVE history)
- Learning curve (team familiarity)
- Lock-in risk

**Constraints:** Spring Boot 3.x compatibility (Jakarta namespace)
**Assumptions:** must be JVM library

## Phase 2 — Tournament

### A1: Jackson (default in Spring Boot)

**Approach:** keep Jackson, the Spring Boot default.

**Self-assessment:**
| Dimension | Score | Notes |
|---|---|---|
| Performance | Baseline | ~500k ops/s on small payload |
| Maintenance | Excellent | FasterXML, daily activity |
| Compatibility | Native | Spring Boot autoconfig |
| Security | Strong | Active CVE response |
| Learning curve | Zero | Team already knows |
| Lock-in | Low | De facto standard |

**Weakness:** performance below alternatives.

### Challenge 1 — Beat A1 on performance

### A2: Gson

**Approach:** swap to Google Gson.

**A1 vs A2 evaluation:**
- Performance: Gson actually slower than Jackson for typical payloads
- Same paradigm (reflection-based runtime serialization)
- Marginal benefit, similar maintenance

→ **Reject A2 as cosmetic alternative.** Same paradigm, no meaningful gain.

### A2 (retry): Jackson with Afterburner module

**Approach:** Jackson + `jackson-module-afterburner` for bytecode-generated accessors.

**A1 vs A2:**
| Dimension | A1 | A2 (Jackson+Afterburner) | Winner |
|---|---|---|---|
| Performance | 500k ops/s | 700k ops/s | A2 |
| Maintenance | Excellent | Same project | Tie |
| Compatibility | Native | Drop-in module | A1 (smaller blast) |
| Security | Strong | Same | Tie |
| Learning curve | Zero | One-line config | A1 |
| Lock-in | Low | Low | Tie |

**Champion: A2** — same lib, performance optimization.

### Challenge 2 — Different paradigm

### A3: jsoniter (annotation-free, codegen-based)

**Paradigm shift:** compile-time code generation vs runtime reflection.

**Approach:** jsoniter generates serializer/deserializer at compile time. No reflection at runtime.

**A2 vs A3:**
| Dimension | A2 | A3 (jsoniter) | Winner |
|---|---|---|---|
| Performance | 700k ops/s | 1.5M+ ops/s | A3 |
| Maintenance | Excellent | Stagnant (last major release 2021) | A2 |
| Compatibility | Native | Custom Spring integration | A2 |
| Security | Strong | Sparse CVE response | A2 |
| Learning curve | Zero | Moderate (annotations, codegen) | A2 |
| Lock-in | Low | High (annotations in DTOs) | A2 |

**Champion: A2** — A3's performance is best but maintenance + lock-in disqualifying.

### Challenge 3 — Question assumption

**Assumption questioned:** "must be JVM library"

### A4: Process-level codec server (sidecar in Rust + UDS)

**Approach:** offload hot-path JSON encoding to a Rust sidecar communicating via Unix domain socket.

**Considered briefly:**
- Performance: 5M+ ops/s realistically
- Ops complexity: very high (deploy + monitor sidecar, IPC failure modes)
- Lock-in: significant
- Team skill: zero Rust experience

→ **Reject A4** — ops + skill cost not justified for the throughput delta vs A2. Revisit only if Jackson+Afterburner becomes a measured bottleneck (it isn't yet).

## Phase 3 — Synthesis

### Comparison matrix

| Dimension | A1: Jackson | A2: +Afterburner | A3: jsoniter |
|---|---|---|---|
| Performance | 500k ops/s | 700k ops/s | 1.5M ops/s |
| Maintenance | Excellent | Excellent | Stagnant 2021 |
| Compatibility | Native | Drop-in module | Custom integration |
| Security CVEs | Strong response | Same | Sparse |
| Learning curve | Zero | One-line | Moderate |
| Lock-in | Low | Low | High |

### Recommendation: A2 (Jackson + Afterburner)

**Why:** Best balance — 40% perf improvement over default Jackson, zero lock-in, no learning curve, full maintenance support, drop-in module.

**What we gain:**
- 40% throughput improvement
- Reuses existing Jackson knowledge
- Same security posture

**What we sacrifice:**
- Marginal: one module on classpath
- Performance ceiling lower than A3, but A3's risks disqualifying

**Confidence:** High

**Caveats:**
- Revisit A3 if profiling shows JSON encoding becomes hot path (>30% CPU) AND we can afford A3's maintenance + lock-in cost
- Revisit A4 (sidecar) only if scale demands 2M+ ops/s sustained

**Close call?** No — A1 strictly worse than A2 (same lib), A3 disqualified on maintenance + lock-in.

## What the user learns

- "Use library X" suggestions often confuse paradigm (reflection vs codegen)
- Rejecting A2:Gson saved tournament time — cosmetic alternatives wasted
- Assumption questioning (A4 sidecar) considered + rejected with measurable threshold for revisit
- Recommendation honest about ceiling (A2 lower than A3) but justifies why A2 still wins
