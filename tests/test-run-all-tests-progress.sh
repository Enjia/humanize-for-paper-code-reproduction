#!/usr/bin/env bash
#
# Tests for live progress output in tests/run-all-tests.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=========================================="
echo "Run All Tests Progress Tests"
echo "=========================================="
echo ""

RUNNER="$PROJECT_ROOT/tests/run-all-tests.sh"
OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

SUITES="fixtures/run-all-tests-progress/slow-suite.sh,fixtures/run-all-tests-progress/fast-suite.sh"

(
  HUMANIZE_TEST_JOBS=2 \
  HUMANIZE_TEST_SUITES="$SUITES" \
  "$RUNNER" >"$OUTPUT_FILE" 2>&1
) &
RUNNER_PID=$!

progress_seen=0
runner_alive_when_progress_seen=0
attempt=0
while [[ "$attempt" -lt 3 ]]; do
  if grep -q '^\[[0-9][0-9]*/[0-9][0-9]*\] PASSED:' "$OUTPUT_FILE" 2>/dev/null; then
    progress_seen=1
    if kill -0 "$RUNNER_PID" 2>/dev/null; then
      runner_alive_when_progress_seen=1
    fi
    break
  fi
  if ! kill -0 "$RUNNER_PID" 2>/dev/null; then
    break
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if wait "$RUNNER_PID"; then
  pass "fixture run-all-tests invocation exits successfully"
else
  fail "fixture run-all-tests invocation exits successfully" "exit 0" "$(cat "$OUTPUT_FILE")"
fi

if [[ "$progress_seen" -eq 1 ]]; then
  pass "run-all-tests emits progress lines before final summary"
else
  fail "run-all-tests emits progress lines before final summary" "line matching [n/total] PASSED:" "$(cat "$OUTPUT_FILE")"
fi

if [[ "$runner_alive_when_progress_seen" -eq 1 ]]; then
  pass "run-all-tests emits progress while slower suites are still running"
else
  fail "run-all-tests emits progress while slower suites are still running" "progress appears before slowest suite exits" "$(cat "$OUTPUT_FILE")"
fi

if grep -q "All tests passed!" "$OUTPUT_FILE" && grep -q "Total Passed:" "$OUTPUT_FILE"; then
  pass "run-all-tests still prints final summary"
else
  fail "run-all-tests still prints final summary" "summary with total counts" "$(cat "$OUTPUT_FILE")"
fi

print_test_summary "Run All Tests Progress Tests"
