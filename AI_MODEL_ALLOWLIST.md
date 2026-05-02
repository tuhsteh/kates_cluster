# AI Model Allowlist (EXO Cluster)

This document defines the recommended top-5 model allowlist for this NanoPC-T4 cluster.

## Why This Exists

The EXO model catalog includes many very large options that are not practical on this hardware.
A small, explicit allowlist keeps the Open WebUI model picker usable and improves latency consistency.

## Cluster Constraints

- 8 x NanoPC-T4 nodes
- RK3399 ARM CPUs
- 4 GB RAM per node
- CPU-first inference runtime

These constraints strongly favor smaller quantized models.

## Top-5 Allowlist

Prioritized for daily coding and infrastructure assistance.

| Rank | Model ID | Approx Size (MB) | Primary Use | Why It Made The List |
|---|---|---:|---|---|
| 1 | mlx-community/Qwen3.5-9B-4bit | 5674 | Default coding model | Best quality/speed balance among practical Qwen options in this catalog. |
| 2 | mlx-community/Meta-Llama-3.1-8B-Instruct-4bit | 4423 | General fallback | Stable, strong fallback if Qwen response quality drifts for a task. |
| 3 | mlx-community/NVIDIA-Nemotron-Nano-9B-v2-4bits | 4771 | Alternate coding/general | Useful alternate model family at similar size envelope. |
| 4 | mlx-community/Qwen3.5-2B-MLX-8bit | 2539 | Fast interactive | Lower quality than 9B, but much faster for quick command/help loops. |
| 5 | mlx-community/Llama-3.2-3B-Instruct-4bit | 1777 | Ultra-fast fallback | Very small option when responsiveness matters more than depth. |

## Optional Add-On (Vision)

If vision input is needed, add:

- mlx-community/Qwen3-VL-4B-Instruct-4bit (3185 MB)

Keep this as optional to avoid cluttering default model choices.

## Excluded Families and Variants

Not recommended for this cluster as daily defaults:

- DeepSeek V3/V4 variants in this catalog (very large storage footprints)
- Qwen 27B+ and large MoE variants
- BF16/FP16 variants for most model families

Rationale: these are likely to cause severe latency, memory pressure, or poor concurrent throughput on this hardware profile.

## Selection Rules

1. Prefer 4-bit quantized models for defaults.
2. Keep default models at or below about 6,000 MB where possible.
3. Use 2B-4B models for speed-first interactive loops.
4. Treat models above about 15,000 MB as experimental only.

## Open WebUI Organization

Use a small, consistent naming convention for favorites and tags so model selection stays fast.

### Favorites Convention

Mark only these as favorites:

- `Qwen3.5-9B-4bit` (daily default)
- `Meta-Llama-3.1-8B-Instruct-4bit` (fallback)
- `Qwen3.5-2B-MLX-8bit` (fast mode)

Keep favorites to 3-5 entries max.

### Tag Convention

Apply these tags in Open WebUI (or maintain them as saved naming prefixes if tags are unavailable):

- `daily-default`: primary model for most prompts
- `fallback-quality`: second-choice when output quality is weak
- `fast-latency`: smallest, quickest model for short iterative work
- `vision-optional`: only models with image capability
- `experimental-large`: anything above 15,000 MB

### Suggested Display Prefixes

If the UI does not support per-model tags cleanly, use prefixes in saved model aliases:

- `[D1] Qwen3.5-9B-4bit`
- `[D2] Meta-Llama-3.1-8B-Instruct-4bit`
- `[FAST] Qwen3.5-2B-MLX-8bit`
- `[VIS] Qwen3-VL-4B-Instruct-4bit`

This keeps the dropdown sorted with your preferred models at the top.

### Daily Workflow

1. Start with `[D1]` for most coding/infrastructure prompts.
2. Switch to `[D2]` if answers are weak or inconsistent.
3. Use `[FAST]` during rapid command/iteration loops.
4. Use `[VIS]` only for image tasks.
5. Avoid `experimental-large` models unless explicitly benchmarking.

## Review Cadence

Revisit this list when one of the following changes:

- hardware (RAM/CPU class)
- runtime backend capabilities
- model catalog composition
