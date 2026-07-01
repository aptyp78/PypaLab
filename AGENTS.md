# AGENTS.md — read this first (for AI agents & automation)

You are an agent working in or around the **PypaLab** cluster environment. This
file is the contract. Humans: see [README.md](README.md) and
[CONTRIBUTING.md](CONTRIBUTING.md).

## What PypaLab is

The working repository through which we operate and improve our inference
clusters — heterogeneous Apple Silicon (MLX) + NVIDIA (CUDA/vLLM). It holds the
canonical recipes, the benchmark harness, engine patches, and honest numbers for
running frontier LLMs on our own metal. Repo: `github.com/aptyp78/PypaLab`.

## Hard rules (non-negotiable)

1. **Never commit anything sensitive.** No internal IPs, SSH aliases, Keychain
   references, VPN material, tokens, real hostnames. Use placeholders
   (`NODE_A_IP`, `NODE_B_IP`, `<SECRET_NAME>`, `gpu-node-1`). Real values live in
   a private, `.gitignore`d overlay. **CI blocks leaks and so must you.**
2. **Validate before you push.** Run `./scripts/validate.sh`; it must be green.
   `main` is protected — required checks + no force-push. Work via PR/branch.
3. **Honest numbers only.** Every throughput figure ships with a reproduction
   command, date, and hardware. No number without a method. Trade-offs are stated,
   not hidden.
4. **Don't destabilize live clusters.** Read-only by default. Never restart a
   running node's inference while a peer depends on it. Free memory deliberately
   before large loads (see recipes).

## Where things are

| Need | Go to |
|---|---|
| Run 671B distributed (Apple) | `recipes/distributed-671b-apple-silicon.md` |
| Run DeepSeek on NVIDIA GB10 | `docs/sparks-deepseek-v4-vllm.md` |
| Benchmark harness | `src/pipeline_bench.py` |
| Engine bug + fix | `patches/` |
| Numbers | `benchmarks/RESULTS.md` |
| The full rulebook | `VALIDATION.md` |

## When you improve a cluster

Land the knowledge here: a recipe, a benchmark row, or a patch — with provenance.
The repo is the memory of the cluster program; scattered scripts on node home
directories are not. If it isn't in PypaLab (sanitized), it doesn't count as done.
