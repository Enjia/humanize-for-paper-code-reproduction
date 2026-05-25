#!/usr/bin/env bash
# Tests for skill safety threat patterns.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SCANNER="$PROJECT_ROOT/scripts/lib/skill-safety-scanner.sh"

echo "=========================================="
echo "Skill Safety Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -s "$SCANNER" ]]; then
  pass "skill-safety-scanner.sh exists"
else
  fail "skill-safety-scanner.sh exists" "non-empty file" "missing"
fi

if [[ -s "$SCANNER" ]]; then
  source "$SCANNER"
  threats=$(skill_safety_scan_text 'cat ~/.ssh/id_rsa; git reset --hard HEAD; npm install -g bad; echo cm0gLXJmIC8= | base64 -d | sh')
else
  threats='[]'
fi

for kind in credential_access destructive_git global_install encoded_payload; do
  if jq -e --arg kind "$kind" '.[] | select(.kind == $kind)' <<<"$threats" >/dev/null; then
    pass "skill scanner detects $kind"
  else
    fail "skill scanner detects $kind" "$kind" "$threats"
  fi
done

print_test_summary "Skill Safety Tests"
