#!/usr/bin/env bash
# HTML well-formedness & self-containment guard (VALIDATION.md §6).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0

while IFS= read -r f; do
  [ -e "$f" ] || continue
  grep -qi '<!DOCTYPE html>' "$f" || { echo "❌ $f: missing <!DOCTYPE html>"; fail=1; }
  grep -qi '</html>' "$f"         || { echo "❌ $f: missing closing </html>"; fail=1; }
  # self-contained: no external CDN / framework
  if grep -qiE 'src="https?://|href="https?://[^"]*\.(css|js)|cdn\.|unpkg\.|jsdelivr' "$f"; then
    echo "❌ $f: external CDN/asset reference (must be self-contained)"; fail=1
  fi
done < <(git ls-files '*.html')

[ "$fail" -eq 0 ] && echo "✅ html ok"
exit "$fail"
