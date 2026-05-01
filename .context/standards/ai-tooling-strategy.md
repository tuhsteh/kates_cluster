# AI Tooling Choices and Strategies

**Scope:** Operational guidance for AI-assisted coding and local LLM usage in this repository.  
**Primary repo context:** Ansible-managed Raspberry Pi cluster with role-based playbooks.

---

## Goals

1. Keep AI assistance useful on ARM edge hardware.
2. Prioritize reproducible, idempotent infrastructure changes.
3. Match model/tool choice to task latency and quality needs.
4. Preserve safety for cluster-level automation changes.

---

## Workload Classes

Use explicit classes so routing and model sizing stay predictable.

| Class | Typical tasks | Priority |
|------|---------------|----------|
| Fast Interactive | autocompletion, short fixes, command help | Low latency |
| Implementation | role edits, template changes, task refactors | Balanced latency/quality |
| Deep Review | architecture critique, risk analysis, migration planning | Higher quality over speed |
| Batch Generation | docs, repetitive scaffolding, inventory transforms | Throughput and consistency |

---

## Model Strategy

### Default approach

- Use smaller coding-tuned quantized models for fast interactive work.
- Use stronger models for review/planning jobs where latency is acceptable.
- Keep one "fallback quality" path available (local stronger model or remote provider) for difficult tasks.

### Practical tiers for SBC nodes

1. **Interactive tier (default):** 7B/8B class coding models, quantized for speed.
2. **Analysis tier:** 14B class where memory/latency budgets allow.
3. **Escalation tier:** remote or non-SBC compute for heavyweight reasoning/review when local quality is insufficient.

---

## Serving and Orchestration Pattern

For multi-node ARM clusters, prefer independent workers:

1. Run one inference worker per node.
2. Front with a lightweight router/gateway.
3. Route by workload class and queue depth.
4. Keep model artifacts local on NVMe for startup speed.
5. Avoid distributed single-model sharding across nodes unless there is a proven need.

Rationale: this yields better reliability and aggregate throughput than cross-node tensor/model splits on low-power networking.

---

## Tooling Selection Principles

When choosing AI tooling, optimize for:

1. **ARM support maturity** (build stability, SIMD support, packaging quality).
2. **Deterministic operation** (repeatable prompts and outputs where possible).
3. **Observability** (request logs, latency, tokens/sec, queue depth, failures).
4. **Low operational overhead** (simple deployment, restart behavior, health checks).
5. **Integration fit** with Ansible workflows and existing repo conventions.

---

## Prompt and Context Strategy for This Repo

### Context sources

- Use domain docs in `.context/domains/` for hardware and platform constraints.
- Use standards docs in `.context/standards/` for implementation rules and gotchas.
- Keep task-level notes in `.context/tasks/` for active changes and migrations.

### Prompt layering

1. Start with task objective and target playbook/role.
2. Add board/platform constraints (Pi vs NanoPC differences).
3. Add idempotence and safety constraints.
4. Request verification steps (`ansible-lint`, check-mode where safe).

---

## Safety and Quality Gates

All AI-generated infra changes should satisfy:

1. Use FQCN module names.
2. Prefer modules over shell/command where feasible.
3. Preserve idempotence (`changed_when`/`failed_when` for check commands).
4. Keep role ordering and tag semantics intact.
5. Pass `ansible-lint` before merge.

---

## Performance and Capacity Guidance

For local coding assistants on SBC clusters:

1. Optimize for concurrent small requests, not single massive models.
2. Treat NVMe as model and cache acceleration; RAM remains the hard limit for model size/context.
3. Define an explicit escalation path when local quality or speed is insufficient.

---

## Embedded GPU Position

Do not base the primary strategy on embedded GPU acceleration (Mali/VideoCore) for coding LLM workloads.

- Use CPU-first inference as the baseline.
- Treat embedded-GPU paths as experimental and benchmark-gated.

---

## Suggested Decision Checklist

Before adopting a model/tooling change, confirm:

1. Which workload class is being optimized?
2. What latency budget is acceptable?
3. What quality target is required (interactive vs review-grade)?
4. Can this run reliably on ARM with current ops capacity?
5. How will quality/safety be validated before cluster-wide rollout?
