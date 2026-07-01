# Benchmark results

Honest, reproducible numbers. Every row ships with the method to reproduce it.
Numbers we couldn't reproduce are not here.

## DeepSeek-V3.1 671B (8-bit) — 2× Apple M3 Ultra 512 GB, pipeline-parallel

Interconnect: 10 GbE. Backend: MLX ring. Weights: ~713 GB, ~356 GB materialized
per node.

### Synthetic (short prompt)

| Metric | Value |
|---|---|
| decode | **13.8 tok/s** (two runs: 13.77 / 13.81) |
| TTFT | 0.55 s |
| load time | ~52 s |
| output | coherent, correct |

### Realistic task (long prompt — a CTO-grade analytical brief)

| Metric | Value |
|---|---|
| prompt (prefill) | 1161 tokens → 12.2 s (**~95 tok/s prefill**) |
| decode | 13.63 tok/s |
| generated | 1474 tokens in 108 s (natural stop) |
| total wall-clock | 172 s (~2.9 min) |

Also produced a full self-contained HTML infographic end-to-end on-cluster:
1040-token prompt → 3785 tokens of valid HTML, decode 13.23 tok/s, ~5.8 min total.

### Reproduce

```bash
mlx.launch --backend ring --hostfile hosts.json --python <VENV>/bin/python \
  src/pipeline_bench.py --model <MODEL_PATH> --max-tokens 128
```

### Key findings

1. **The deadlock is avoidable.** Tensor-parallel MoE deadlocks on the ring
   backend (100% GPU residency, ~3 W — spin-wait). Pipeline parallelism does not:
   no per-layer `all_sum`.
2. **Long-prompt prefill trips the Metal GPU watchdog** unless prefill is chunked
   (`prefill_step_size=128`). Short-prompt benchmarks hide this — a synthetic
   "hello world" would never surface it.
3. **Reproducible & stable** — decode within 0.3 % across runs.

### Honest comparison

The published tensor-parallel reference reaches ~18.6 tok/s over Thunderbolt-5
(JACCL/RDMA). Our 13.8 tok/s is lower because pipeline is sequential (node waits
for node) and 10 GbE has higher latency than Thunderbolt. The trade we accept:
pipeline *cannot* hit the MoE deadlock. Path to ~18.6 is documented in the recipe
(Thunderbolt + `jaccl-ring`).

## Provenance

- Date: 2026-07-01
- Hardware: 2× Apple M3 Ultra 512 GB, 10 GbE
- Verified: raw run logs captured on-cluster; two independent synthetic runs plus
  two long-prompt runs.
