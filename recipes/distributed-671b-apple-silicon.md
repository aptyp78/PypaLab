# Recipe: distributed 671B on 2× Apple Silicon (pipeline-parallel, MLX)

Run DeepSeek-V3.1 671B (8-bit, ~713 GB of weights) across two Apple M3 Ultra
512 GB machines using **pipeline parallelism** over MLX's ring backend. The model
does not fit on one node; the pooled memory does.

`smoke: true`

## Prerequisites

- 2 nodes, each Apple Silicon with ≥ 512 GB unified memory (M3 Ultra class).
- Same Python venv path on both nodes with `mlx`, `mlx-lm` installed.
- Passwordless SSH from the launching node to **both** nodes (including itself).
- A fast link between nodes (10 GbE works; Thunderbolt is better — see Tuning).
- The model already downloaded and byte-identical on **both** nodes at the same path.
- ≥ 356 GB free per node at launch (each node holds ~half the model).

Placeholders used below — substitute your own, keep them out of git:

| Placeholder | Meaning |
|---|---|
| `NODE_A_IP` | rank 0 — holds the last layers + head |
| `NODE_B_IP` | rank 1 — holds the first layers + embeddings |
| `<MODEL_PATH>` | local dir with `config.json`, `*.safetensors`, tokenizer, `model.safetensors.index.json` |
| `<VENV>` | path to the shared Python venv |

## Step 1 — Free the memory

Each node must hold ~356 GB. Stop anything large; reclaim the file cache:

```bash
# stop competing model servers / services first (your setup-specific)
sudo sysctl iogpu.wired_limit_mb=480000   # allow MLX to wire ~356 GB
sudo purge                                # evict file cache → clean start
```

Target: ≥ 400 GB free per node before launch. Starting too high → jetsam SIGKILL
mid-load.

## Step 2 — Ring hostfile

`hosts.json` (this file is `.gitignore`d — never commit real IPs):

```json
[
  {"ssh": "NODE_A_IP", "ips": ["NODE_A_IP"]},
  {"ssh": "NODE_B_IP", "ips": ["NODE_B_IP"]}
]
```

First entry = rank 0. Verify `ssh NODE_A_IP` and `ssh NODE_B_IP` both work
passwordlessly from the launching node (rank 0 launches over SSH to itself too).

## Step 3 — Launch the benchmark

```bash
mlx.launch \
  --backend ring \
  --hostfile hosts.json \
  --python <VENV>/bin/python \
  src/pipeline_bench.py --model <MODEL_PATH> --max-tokens 128
```

## Why pipeline, not tensor-parallel

Tensor-parallel MoE ends every expert layer with a cluster-wide `all_sum`. On the
ring backend those collectives desync the paired blocking `send`/`recv` between
ranks → mutual spin-wait (GPU at 100% residency but ~3 W — no real compute). This
is the classic distributed-MoE deadlock. See `patches/` for the tensor-parallel
mitigation.

**Pipeline parallelism avoids it structurally:** ranks exchange one hidden vector
via strictly-ordered `recv`/`send` and do a single final `all_gather`. No
per-layer `all_sum` → the deadlock cannot occur. Cost: pipeline is sequential
(node waits for node), so single-stream throughput is latency-bound, not faster
than one node — but it *fits* a model one node can't hold.

## Loading detail (why `sharded_load` is bypassed)

`mlx_lm.utils.sharded_load(pipeline_group=...)` raises
`"Pipeline loading is only supported for MLX converted models"` on MLA-absorbed
checkpoints: its download planner iterates *all* parameter keys, including derived
weights (`embed_q` / `unembed_out`) that `sanitize()` synthesizes from `kv_b_proj`
and which are absent from the index by design.

Since all shards are already local, skip the planner and load directly:

```python
model, config = load_model(MODEL, lazy=True, strict=False)   # lazy: nothing materialized yet
model.model.pipeline(group)                                  # nulls non-local layers
mx.eval(model.parameters())                                  # materializes ONLY the local half
```

`src/pipeline_bench.py` implements exactly this.

## Tuning

- **Long prompts deadlock the GPU?** A long prefill runs as one giant Metal command
  buffer and trips the GPU watchdog (`kIOGPUCommandBufferCallbackErrorTimeout`).
  Fix: chunk prefill — pass `prefill_step_size=128` to `stream_generate`. Short
  prompts hide this; realistic prompts expose it.
- **Toward higher throughput:** move the interconnect from 10 GbE to Thunderbolt
  and use the `jaccl-ring` backend (RDMA) — the published tensor-parallel reference
  reaches ~18.6 tok/s that way. Pipeline over 10 GbE measures ~13.8 tok/s.

## Provenance

- Author: PypaLab / @aptyp78 (CTO track)
- Date: 2026-07-01
- Hardware: 2× Apple M3 Ultra 512 GB, 10 GbE interconnect
- Verified: `src/pipeline_bench.py` → 13.8 tok/s decode, TTFT 0.55 s, coherent
  output on DeepSeek-V3.1-8bit; reproduced across two runs (13.77 / 13.81).
