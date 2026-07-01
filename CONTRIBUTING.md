# Contributing to PypaLab

PypaLab is a working engineering asset, not a demo. Contributions are held to a
production bar. Read this fully before opening a PR.

## Golden rule

**Never commit anything sensitive.** No internal IPs, SSH aliases, Keychain
references, VPN material, tokens, or real hostnames. Public files use placeholders
(`NODE_A_IP`, `NODE_B_IP`, `<SECRET_NAME>`, `gpu-node-1`). Real values live in your
own `.gitignore`d private overlay. CI enforces this and **will block your PR**.

## Workflow

1. Fork or branch off `main` (protected — no direct pushes).
2. Make your change. Keep it focused.
3. Run the full gate locally: `./scripts/validate.sh` — it must be green.
4. Open a PR. CI re-runs the gate. At least one review is required.
5. Squash-merge once green + approved.

## What "done" means by change type

- **Recipe** — includes a `## Prerequisites` block and a `## Provenance` footer
  (who / when / on what hardware / how verified). Reproducible by a stranger.
- **Benchmark number** — ships with the exact command, date, hardware, and is
  reproducible. A number without a repro method is not accepted.
- **Patch** — states upstream project + version, symptom, root cause, and a
  reversible apply/rollback. Prefer a `.patch` plus a prose explainer.
- **Code** — passes `ruff` + `mypy`; scripts pass `shellcheck`.

## Honesty policy

We publish numbers that are lower than a vendor's marketing on purpose when that's
what we measured. If a trade-off exists (e.g. pipeline parallelism is slower than
tensor-parallel), the docs say so. Overstated results are a bug.

## Provenance footer template

```
## Provenance
- Author: <name / handle>
- Date: YYYY-MM-DD
- Hardware: <nodes, chips, RAM, interconnect>
- Verified: <command run + observed result>
```
