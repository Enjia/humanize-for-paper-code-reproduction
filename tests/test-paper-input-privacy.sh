#!/usr/bin/env bash
#
# Tests that paper input sanitization does not execute or expand untrusted content.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SANITIZER="$PROJECT_ROOT/scripts/paper-input-sanitize.sh"

echo "=========================================="
echo "Paper Input Privacy Tests"
echo "=========================================="
echo ""

setup_test_dir

INPUT="$TEST_DIR/privacy-paper.md"
OUTPUT="$TEST_DIR/privacy-sanitized.json"
export HUMANIZE_SECRET_TEST_TOKEN="do-not-leak-token"
cat > "$INPUT" <<'PAPER'
# Privacy Fixture

The paper contains shell-looking text that must not execute:

```bash
echo "$HUMANIZE_SECRET_TEST_TOKEN" > leaked.txt
```

It also mentions `$HUMANIZE_SECRET_TEST_TOKEN` as literal paper content.
PAPER

if "$SANITIZER" --input "$INPUT" --output "$OUTPUT" >/tmp/paper-privacy.out 2>&1; then
  pass "sanitizer runs on privacy fixture"
else
  fail "sanitizer runs on privacy fixture" "exit 0" "$(cat /tmp/paper-privacy.out)"
fi

if [[ ! -e "$TEST_DIR/leaked.txt" ]]; then
  pass "sanitizer does not execute paper shell snippets"
else
  fail "sanitizer does not execute paper shell snippets" "no leaked.txt" "leaked.txt created"
fi

if grep -q 'do-not-leak-token' "$OUTPUT"; then
  fail "sanitizer does not expand environment variables" "no secret value in output" "secret value found"
else
  pass "sanitizer does not expand environment variables"
fi

if jq -e '.normalized_text | contains("$HUMANIZE_SECRET_TEST_TOKEN")' "$OUTPUT" >/dev/null 2>&1; then
  pass "sanitizer preserves variable reference as literal paper data"
else
  fail "sanitizer preserves variable reference as literal paper data" 'literal $HUMANIZE_SECRET_TEST_TOKEN' "$(cat "$OUTPUT" 2>/dev/null || true)"
fi

if jq -e '.supplementary_code_executed == false' "$OUTPUT" >/dev/null 2>&1; then
  pass "sanitizer records no supplementary execution"
else
  fail "sanitizer records no supplementary execution" "supplementary_code_executed=false" "$(cat "$OUTPUT" 2>/dev/null || true)"
fi

print_test_summary "Paper Input Privacy Tests"
