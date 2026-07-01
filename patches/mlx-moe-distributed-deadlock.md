# Patch: MLX tensor-parallel MoE distributed deadlock

## Upstream

- Project: MLX / mlx-lm auto-parallel MoE sharding (`auto_parallel.py`, `ShardedMoE`)
- Applies to: tensor-parallel (`shard`) path on the **ring** distributed backend.

## Symptom

Distributed MoE inference hangs during the forward pass. Telemetry:

```
GPU HW active residency: 100.00%
GPU Power: ~3 W        # real matmul would be 50–150 W
```

100 % residency at ~3 W = **GPU spin-wait**. Both ranks are parked on an
inter-node `recv` that never arrives. Dense models distribute fine; MoE hangs.

## Root cause

Each MoE layer ends with `mx.distributed.all_sum(y, group=...)`. On the ring
backend these collectives materialize lazily and batch at chunk boundaries; the
blocking `send`/`recv` pair carries no tags/sequence numbers, so the two ranks
desync on which collective they're posting → mutual wait.

## Fix (tensor-parallel path)

Force per-layer materialization so the ring collectives serialize
deterministically on both ranks:

```python
# in ShardedMoE.__call__, right after the all_sum:
y = mx.distributed.all_sum(y, group=self.sharding_group)
mx.eval(y)  # PATCH: force per-layer materialization → serialize ring collectives
```

Reversible: remove the `mx.eval(y)` line to roll back. Back up the file before
editing.

## Better fix (recommended): don't use tensor-parallel for MoE

Pipeline parallelism has **no per-layer `all_sum`** and therefore cannot hit this
deadlock. For MoE across a memory pool, prefer pipeline — see
[`../recipes/distributed-671b-apple-silicon.md`](../recipes/distributed-671b-apple-silicon.md).
The `mx.eval` patch is the mitigation if you must stay tensor-parallel.

## Provenance

- Date: 2026-07-01
- Root cause found via GPU-power telemetry (spin-wait signature) + collective
  ordering analysis; pipeline path verified working at 13.8 tok/s on 671B.
