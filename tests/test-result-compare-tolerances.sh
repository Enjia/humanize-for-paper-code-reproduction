#!/usr/bin/env bash
# Tests for result comparison tolerance modes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

COMPARE="$PROJECT_ROOT/scripts/result-compare.sh"

echo "=========================================="
echo "Result Compare Tolerance Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -x "$COMPARE" ]]; then
  pass "result-compare.sh exists and is executable"
else
  fail "result-compare.sh exists and is executable" "executable script" "missing"
fi

EXPECTED="$TEST_DIR/expected.json"
ACTUAL="$TEST_DIR/actual.json"
OUTPUT="$TEST_DIR/comparison.json"
cat > "$EXPECTED" <<'JSON'
{
  "comparisons": [
    {"comparison_id": "C-EXACT", "module_id": "ALG-001", "criterion_id": "CRIT-001", "checkpoint_id": "CHK-001", "evidence": ["CLAIM-001"], "mode": "exact", "expected": "pass", "actual_path": "status"},
    {"comparison_id": "C-TOL", "module_id": "EXP-001", "criterion_id": "CRIT-EXP-001", "checkpoint_id": "CHK-002", "evidence": ["TABLE-001"], "mode": "numeric_tolerance", "expected": 100.0, "actual_path": "throughput", "tolerance": {"absolute": 5.0}},
    {"comparison_id": "C-TREND", "module_id": "EXP-001", "criterion_id": "CRIT-EXP-002", "checkpoint_id": "CHK-002", "evidence": ["FIG-002"], "mode": "trend", "expected": "decrease", "baseline_path": "baseline_latency", "actual_path": "latency"},
    {"comparison_id": "C-STRUCT", "module_id": "EVAL-001", "criterion_id": "CRIT-EVAL-001", "checkpoint_id": "CHK-003", "evidence": ["APP-A"], "mode": "qualitative_structural", "expected_keys": ["latency", "throughput"], "actual_path": "metrics"},
    {"comparison_id": "C-MISSING", "module_id": "EVAL-001", "criterion_id": "CRIT-EVAL-002", "checkpoint_id": "CHK-003", "evidence": ["APP-B"], "mode": "exact", "expected": 1, "actual_path": "missing_metric"},
    {"comparison_id": "C-UNIT", "module_id": "ENV-001", "criterion_id": "CRIT-ENV-001", "checkpoint_id": "CHK-004", "evidence": ["SEC-4.1"], "mode": "numeric_tolerance", "expected": 1.0, "expected_unit": "s", "actual_path": "duration", "actual_unit_path": "duration_unit", "tolerance": {"absolute": 0.1}}
  ]
}
JSON
cat > "$ACTUAL" <<'JSON'
{
  "status": "pass",
  "throughput": 103.0,
  "baseline_latency": 20.0,
  "latency": 10.0,
  "metrics": {"latency": 10.0, "throughput": 103.0},
  "duration": 1.0,
  "duration_unit": "ms"
}
JSON

if "$COMPARE" --expected "$EXPECTED" --actual "$ACTUAL" --output "$OUTPUT" >/tmp/result-compare.out 2>&1; then
  pass "result comparison runs"
else
  fail "result comparison runs" "exit 0" "$(cat /tmp/result-compare.out)"
fi

for status in exact_match tolerance_match trend_match qualitative_structural_match missing_output unit_mismatch; do
  if jq -e --arg status "$status" '.results[] | select(.status == $status)' "$OUTPUT" >/dev/null; then
    pass "result comparison emits $status"
  else
    fail "result comparison emits $status" "$status" "$(cat "$OUTPUT" 2>/dev/null || true)"
  fi
done

if jq -e 'all(.results[]; has("module_id") and has("criterion_id") and has("checkpoint_id") and has("evidence"))' "$OUTPUT" >/dev/null; then
  pass "result comparison preserves lineage fields for report mapping"
else
  fail "result comparison preserves lineage fields for report mapping" "module_id criterion_id checkpoint_id evidence on every result" "$(cat "$OUTPUT" 2>/dev/null || true)"
fi

print_test_summary "Result Compare Tolerance Tests"
