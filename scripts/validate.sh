#!/usr/bin/env bash
# Local mirror of CI. Same gate order as .github/workflows/validate.yml.
# Run before every push. Stops at the first hard failure.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

step() { echo ""; echo "▶ $1"; }

step "🔒 secret & sensitive-data guard"
bash scripts/check-no-secrets.sh || exit 1
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-banner -c .gitleaks.toml || exit 1
else
  echo "  (gitleaks not installed — skipping, CI still enforces it)"
fi

step "structure & provenance"
bash scripts/check-structure.sh || exit 1

step "html well-formedness"
bash scripts/check-html.sh || exit 1

step "python lint"
if command -v ruff >/dev/null 2>&1; then ruff check . && ruff format --check .; else echo "  (ruff not installed)"; fi

step "shell lint"
if command -v shellcheck >/dev/null 2>&1; then shellcheck scripts/*.sh src/*.sh 2>/dev/null || true; else echo "  (shellcheck not installed)"; fi

step "markdown lint"
if command -v markdownlint >/dev/null 2>&1; then markdownlint '**/*.md' --ignore node_modules || true; else echo "  (markdownlint not installed)"; fi

echo ""
echo "✅ local validation complete"
