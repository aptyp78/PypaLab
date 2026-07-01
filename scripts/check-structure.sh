#!/usr/bin/env bash
# Structure & provenance guard (VALIDATION.md §2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0

for f in README.md LICENSE VALIDATION.md CONTRIBUTING.md .gitignore; do
  [ -f "$f" ] || { echo "❌ missing required file: $f"; fail=1; }
done

# Every recipe needs Prerequisites + Provenance blocks.
for r in recipes/*.md; do
  [ -e "$r" ] || continue
  grep -q '## Prerequisites' "$r" || { echo "❌ $r: missing '## Prerequisites'"; fail=1; }
  grep -qi 'provenance' "$r"      || { echo "❌ $r: missing provenance footer"; fail=1; }
done

# Every benchmark doc must carry a date and a reproduction command.
for b in benchmarks/*.md; do
  [ -e "$b" ] || continue
  grep -qiE '20[0-9]{2}' "$b" || { echo "❌ $b: no date"; fail=1; }
done

[ "$fail" -eq 0 ] && echo "✅ structure & provenance ok"
exit "$fail"
