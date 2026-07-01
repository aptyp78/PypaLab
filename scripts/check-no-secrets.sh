#!/usr/bin/env bash
# PypaLab sensitive-data guard. Fails (exit 1) if any tracked file leaks
# internal IPs, real SSH host aliases, Keychain patterns or VPN material.
# Mirrors the rules in VALIDATION.md §1. Runs in CI as a merge blocker.
set -uo pipefail

# Only scan tracked, text files. Exclude LICENSE/NOTICE and the guard's own
# rule-definition files (they legitimately quote the patterns they detect).
META='^(LICENSE|NOTICE|VALIDATION\.md|CONTRIBUTING\.md|\.gitleaks\.toml|scripts/check-no-secrets\.sh)$'
FILES=$(git ls-files | grep -Ev "$META" || true)
fail=0

report() { echo "❌ $1"; fail=1; }

scan() { # $1=regex $2=label
  local hits
  hits=$(printf '%s\n' "$FILES" | xargs -I{} grep -EInH "$1" {} 2>/dev/null \
         | grep -Ev 'NODE_[AB]_IP|<SECRET_NAME>|gpu-node-|example\.com|0\.0\.0\.0|127\.0\.0\.1' || true)
  if [ -n "$hits" ]; then
    report "$2"
    echo "$hits" | sed 's/^/     /' | head -20
  fi
}

# Private / internal IPv4
scan '\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b'                 "internal IP (192.168.x.x)"
scan '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b'          "internal IP (10.x.x.x)"
scan '\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b' "internal IP (172.16-31.x.x)"
scan '\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b' "Tailscale CGNAT IP (100.64/10)"
# Real fleet SSH aliases / hostnames
scan '\b(mac-studio|spark-1|spark-2|m5max|frankfurt|MacStudio-0[12]|Mac-Studio-1)\b' "real SSH host alias / hostname"
# Keychain
scan 'security find-generic-password'                       "Keychain access command"
# VPN material
scan '\b(VLESS|REALITY)\b'                                  "VPN protocol material (VLESS/REALITY)"
scan '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' "UUID (possible secret)"

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Sensitive-data guard FAILED. Public files must use placeholders"
  echo "(NODE_A_IP, <SECRET_NAME>, gpu-node-1). See VALIDATION.md §1."
  exit 1
fi
echo "✅ sensitive-data guard passed"
