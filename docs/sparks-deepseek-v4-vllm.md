# DeepSeek-V4-Flash on 2× NVIDIA GB10 (vLLM tensor-parallel)

How the NVIDIA "Spark" pair runs DeepSeek at speed. Companion to the Apple-Silicon
pipeline recipe — same goal (a model too big for one node), different stack
(CUDA + vLLM instead of MLX), different parallelism (tensor-parallel instead of
pipeline).

`smoke: false`

## Hardware

Two **NVIDIA GB10 Grace-Blackwell** nodes (ARM64, Ubuntu 24.04, ~128 GB unified
each, 48 SM). Two networks between them:

| Node | LAN | QSFP56 200G | Role |
|---|---|---|---|
| `gpu-node-1` | `GPU_NODE_1_LAN` | `GPU_NODE_1_QSFP` | node-rank 0 — master + API :8000 |
| `gpu-node-2` | `GPU_NODE_2_LAN` | `GPU_NODE_2_QSFP` | node-rank 1 — headless worker |

## The model

**`deepseek-ai/DeepSeek-V4-Flash`** — 149 GB on disk (46 safetensors), does not fit
in one 128 GB node → split across two via tensor-parallel.

- `DeepseekV4ForCausalLM`, 43 layers, hidden 4096
- MoE: **256 experts, 6 active + 1 shared**
- Native **FP8** weights (e4m3, block 128×128) + FP8 KV cache
- 1 MTP (multi-token-prediction) layer, context up to 262144

## Launch (vLLM, both nodes)

Identical command on both nodes; only `--node-rank` and `--headless` (on the
worker) differ. Real IPs live in your private overlay — placeholders here:

```bash
vllm serve deepseek-ai/DeepSeek-V4-Flash --served-model-name ChatGPTN \
  --host 0.0.0.0 --port 8000 --trust-remote-code \
  --tensor-parallel-size 2 --pipeline-parallel-size 1 \
  --kv-cache-dtype fp8 --block-size 256 \
  --max-model-len 262144 --max-num-seqs 8 --max-num-batched-tokens 8192 \
  --gpu-memory-utilization 0.8 --enable-prefix-caching \
  --speculative-config '{"method":"mtp","num_speculative_tokens":2}' \
  --tokenizer-mode deepseek_v4 --distributed-executor-backend mp \
  --enable-flashinfer-autotune \
  --nnodes 2 --node-rank {0|1} \
  --master-addr GPU_NODE_1_LAN --master-port 25000 \
  # add --headless on node-rank 1
```

## What makes it fast

1. **Distributed tensor-parallel-2** — each node holds ~half the weights.
2. **FP8 weights + FP8 KV cache** — half the memory and bandwidth.
3. **MTP speculative decoding** — DeepSeek's native multi-token-prediction layer
   proposes 2 tokens per step (`--speculative-config method=mtp`).
4. **Prefix caching + flashinfer autotune**.

## Measured (single-stream)

| Metric | Value |
|---|---|
| decode | ~17.4 tok/s |
| TTFT | ~0.89 s |

`--max-num-seqs 8` enables continuous batching, so aggregate throughput under load
is higher than single-stream.

## Known optimization headroom

Inter-node tensor-parallel traffic currently rides the **ordinary LAN**, not the
**QSFP56 200G** link — the fast fabric sits idle for inference. Pointing
NCCL at the QSFP subnet is an untapped speedup. (Observed: dozens of established
connections on the LAN subnet, ~1 idle on QSFP.)

## Contrast with the Apple-Silicon path

| | GB10 pair (this doc) | M3 Ultra pair (recipe) |
|---|---|---|
| Engine | vLLM | MLX / mlx-lm |
| Parallelism | tensor-parallel-2 | pipeline-parallel |
| Model | DeepSeek-V4-Flash (FP8, 149 GB) | DeepSeek-V3.1 671B (8-bit, 713 GB) |
| Decode | ~17 tok/s | ~13.8 tok/s |
| MoE deadlock? | no (vLLM/NCCL handles it) | yes on tensor-parallel → use pipeline |

## Provenance

- Date: 2026-07-01 (live-measured against the running API)
- Hardware: 2× NVIDIA GB10, LAN + QSFP56 200G
- Verified: two live requests to the vLLM endpoint (short + streaming essay).
- Not found: the vLLM launcher unit itself (runs as root); no historical
  record-throughput logs for V4-Flash on these nodes.
