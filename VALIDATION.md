# Validation rules (STRICT — merge-blocking)

PypaLab treats the repository as a production intangible asset. Every change goes
through pull request; `main` is protected; **all checks below must pass green
before merge.** No exceptions, no force-push to `main`.

## 0. Gate order

CI runs the checks in this order and stops at the first failure:

1. **Secret scan** (blocking, runs first — a leak must never even reach later stages)
2. Structure & provenance
3. Python lint + types
4. Shell lint
5. Markdown lint
6. HTML validation
7. Recipe reproducibility (smoke)

## 1. 🔒 Secret / sensitive-data scan — BLOCKING

The single most important rule: **nothing sensitive ships in the open repo.**

- `gitleaks detect` over the full history — any finding fails the build.
- Custom guard `scripts/check-no-secrets.sh` fails on any of:
  - Private/internal IPv4 in tracked files: `192.168.*`, `10.*`, `172.16–31.*`,
    Tailscale `100.64.0.0/10`.
  - Real SSH host aliases from our fleet (`mac-studio`, `spark-1`, `spark-2`,
    `frankfurt`, `m5max`, …).
  - Keychain access patterns: `security find-generic-password`, key names.
  - VPN material: `VLESS`, `REALITY`, private endpoint IPs, UUIDs.
- **Placeholders only** in public files: `NODE_A_IP`, `NODE_B_IP`, `<SECRET_NAME>`,
  `gpu-node-1`, etc. Real values live in the private overlay (never committed).

If you need a real value to run something, it comes from *your own* private
`hosts.json` / env, which is `.gitignore`d.

## 2. Structure & provenance

- New recipe → must include a `## Prerequisites` block and a `## Provenance`
  footer (who, when, on what hardware, verified how).
- New benchmark number → must include the exact command + date + hardware, and be
  reproducible. Numbers without a repro method are rejected.
- New patch → must state upstream project, version, symptom, root cause, and a
  reversible apply/rollback.

## 3. Python

- `ruff check .` (lint) — zero errors.
- `ruff format --check .` (style) — must be formatted.
- `mypy --ignore-missing-imports src/` — zero type errors.

## 4. Shell

- `shellcheck scripts/*.sh src/*.sh` — zero warnings above `info`.

## 5. Markdown

- `markdownlint '**/*.md'` — house style (config in `.markdownlint.json`).

## 6. HTML artifacts

- Any committed `.html` must be well-formed: `<!DOCTYPE html>`, balanced tags,
  no external CDN/JS-framework dependencies (self-contained requirement).

## 7. Recipe reproducibility (smoke)

- Recipes tagged `smoke: true` must expose a dry-run that CI can execute without
  the real cluster (argument parsing, file presence, hostfile schema) — proving
  the recipe hasn't bit-rotted.

---

## Running validation locally

```bash
./scripts/validate.sh        # runs the same gate order as CI
./scripts/check-no-secrets.sh  # just the sensitive-data guard
```

Install once: `pip install ruff mypy`, `brew install shellcheck gitleaks`,
`npm i -g markdownlint-cli`.
