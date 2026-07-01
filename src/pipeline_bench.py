#!/usr/bin/env python3
"""Distributed pipeline-parallel benchmark for large MLX models.

Launch across N nodes with mlx.launch and a ring hostfile:

    mlx.launch --backend ring --hostfile hosts.json \
        --python <venv>/bin/python \
        src/pipeline_bench.py --model <local-model-path> --max-tokens 128

Pipeline parallelism (layer sharding + ordered send/recv) avoids the per-layer
all_sum deadlock that sinks tensor-parallel MoE on ring backends. Only the local
half of the model is materialized on each node, so a model too big for one node
still fits across the pool.
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import mlx.core as mx
from mlx_lm.utils import load_model, load_tokenizer
from mlx_lm.generate import stream_generate


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", required=True, help="Local path to the MLX model dir")
    p.add_argument("--max-tokens", type=int, default=128)
    p.add_argument(
        "--prefill-step-size",
        type=int,
        default=128,
        help="Chunk prefill into this many tokens per step. Keep small (128) to "
        "avoid the Metal GPU-timeout on long prompts.",
    )
    p.add_argument(
        "--prompt",
        default="Explain how a rainbow forms, step by step, in about 100 words.",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    model_path = Path(args.model)

    group = mx.distributed.init()
    rank, size = group.rank(), group.size()

    def rprint(*a: object) -> None:
        if rank == 0:
            print(*a, flush=True)

    rprint(f"[init] world_size={size} rank={rank} backend=ring")

    # --- load, shard, materialize only the local half -----------------------
    t0 = time.time()
    model, config = load_model(model_path, lazy=True, strict=False)
    tokenizer = load_tokenizer(
        model_path,
        {"trust_remote_code": True},
        eos_token_ids=config.get("eos_token_id", None),
    )
    model.model.pipeline(group)          # nulls non-local layers
    mx.eval(model.parameters())          # materializes only this rank's layers
    mx.eval(mx.distributed.all_sum(mx.array(1.0), stream=mx.cpu))  # barrier
    load_s = time.time() - t0
    rprint(f"[load] sharded + loaded in {load_s:.1f}s")

    # --- prompt -------------------------------------------------------------
    messages = [{"role": "user", "content": args.prompt}]
    prompt_ids = tokenizer.apply_chat_template(messages, add_generation_prompt=True)
    n_prompt = len(prompt_ids)
    rprint(f"[prompt] {n_prompt} tokens")

    # --- measured generation ------------------------------------------------
    mx.eval(mx.distributed.all_sum(mx.array(1.0), stream=mx.cpu))
    t_first = time.time()
    ttft: float | None = None
    t_gen0: float | None = None
    n = 0
    for resp in stream_generate(
        model,
        tokenizer,
        prompt_ids,
        max_tokens=args.max_tokens,
        prefill_step_size=args.prefill_step_size,
    ):
        if n == 0:
            ttft = time.time() - t_first
            t_gen0 = time.time()
        n += 1
        if rank == 0:
            print(resp.text, end="", flush=True)

    gen_s = (time.time() - t_gen0) if t_gen0 else 0.0
    decode_tps = (n - 1) / gen_s if gen_s > 0 else 0.0
    prefill_tps = n_prompt / ttft if ttft else 0.0

    rprint("\n\n===== RESULT =====")
    rprint(f"prompt_tokens = {n_prompt}")
    rprint(f"gen_tokens    = {n}")
    rprint(f"TTFT/prefill  = {ttft:.3f}s  (~{prefill_tps:.1f} tok/s)")
    rprint(f"decode tok/s  = {decode_tps:.2f}")
    rprint(f"load_time     = {load_s:.1f}s")
    rprint("==================")


if __name__ == "__main__":
    main()
