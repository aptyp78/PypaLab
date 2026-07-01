<!-- PypaLab — heterogeneous distributed inference lab -->
# PypaLab

**Running frontier LLMs on your own metal.** Reproducible recipes, benchmarks and
patches for distributed inference across a *heterogeneous* cluster — Apple Silicon
(MLX) and NVIDIA (CUDA) — with a hard bias toward **sovereign, private** operation:
the weights and the data never leave your premises.

> Status: active. This repo is the working surface through which we operate and
> improve our clusters. Contributions and forks welcome (Apache-2.0).

---

## Why this exists

A single machine can't hold a 671B-parameter model. Pooling the memory of several
machines can — but "downloads", "loads" and "actually computes" are three
independent walls, and the third one (distributed compute) is where most setups
quietly deadlock or fall off a performance cliff.

PypaLab is the collected, validated know-how for getting past all three walls, on
hardware you own.

## Proven result

| Model | Cluster | Method | Throughput | Notes |
|---|---|---|---|---|
| DeepSeek-V3.1 671B (8-bit) | 2× Apple M3 Ultra 512 GB | pipeline-parallel (MLX ring, 10 GbE) | **13.8 tok/s** decode · ~95 tok/s prefill | coherent output, data stayed on-prem |
| DeepSeek-V4-Flash (FP8, 149 GB) | 2× NVIDIA GB10 | tensor-parallel-2 (vLLM) + MTP | **~17.4 tok/s** decode · TTFT 0.89 s | FP8 KV cache, speculative decoding |

Full method and raw numbers in [`benchmarks/RESULTS.md`](benchmarks/RESULTS.md).
Two stacks, two write-ups: [Apple Silicon / MLX](recipes/distributed-671b-apple-silicon.md)
and [NVIDIA GB10 / vLLM](docs/sparks-deepseek-v4-vllm.md).

## Repository map

| Path | What |
|---|---|
| [`recipes/`](recipes/) | Canonical, copy-pasteable procedures ("from bare nodes → distributed 671B") |
| [`src/`](src/) | Runnable scripts: benchmark harness, launchers, helpers |
| [`patches/`](patches/) | Upstream-engine fixes (e.g. MLX MoE distributed deadlock) |
| [`benchmarks/`](benchmarks/) | Measurements + methodology (honest numbers, repeatable) |
| [`docs/`](docs/) | Engineering write-ups (debugging detectives, performance studies) |
| [`scripts/`](scripts/) | Validation & tooling that mirrors CI |
| `research/` | **Private submodule** ([`pypalab-scientist`](https://github.com/aptyp78/pypalab-scientist)) — the autonomous research agent (НМА). Access-controlled; public clones see an empty gitlink. |

## Quick start

```bash
# 1. clone
git clone https://github.com/aptyp78/PypaLab && cd PypaLab

# 2. read the canonical recipe
$EDITOR recipes/distributed-671b-apple-silicon.md

# 3. run the distributed benchmark (fill in your own node IPs in a hostfile)
#    see recipes/ for the hostfile format and prerequisites
mlx.launch --backend ring --hostfile hosts.json --python <venv>/bin/python \
  src/pipeline_bench.py --model <local-model-path>
```

## Design principles

1. **Sovereign by default** — recipes assume the model and data must never leave
   the local network. Cloud is a fallback, not the target.
2. **Honest numbers** — every throughput figure ships with the method to reproduce
   it. No cherry-picking, no vendor multipliers presented as measurements.
3. **Pipeline over tensor-parallel for MoE** — pipeline parallelism structurally
   cannot hit the per-layer `all_sum` deadlock that sinks tensor-parallel MoE on
   ring backends. Cost: it's sequential and latency-bound. We document the trade.
4. **Nothing sensitive in the open** — access details, IPs, and secrets live in a
   private overlay, never in this repository. Enforced by CI (see below).

## Validation

This repo has **strict, blocking validation**. Nothing merges without passing it.
See [`VALIDATION.md`](VALIDATION.md). Highlights:

- 🔒 **Secret scan is a merge blocker** (gitleaks + custom guard for internal
  IPs / SSH aliases / Keychain references).
- Python: `ruff` + `mypy`. Bash: `shellcheck`. Markdown: `markdownlint`.
- HTML artifacts validated. Recipes carry a machine-checkable prerequisites block.

## License

[Apache-2.0](LICENSE) — fork it, use it commercially, patent grant included.
Copyright 2026 Arthur Ocheretny (@aptyp78).
