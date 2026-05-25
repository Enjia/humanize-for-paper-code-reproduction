#!/usr/bin/env bash
# Tests for merging parent/child checkpoint reviewer findings.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MERGE_SCRIPT="$PROJECT_ROOT/scripts/reviewer-findings-merge.sh"

echo "=========================================="
echo "Parent Child Review Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -x "$MERGE_SCRIPT" ]]; then
  pass "reviewer-findings-merge.sh exists and is executable"
else
  fail "reviewer-findings-merge.sh exists and is executable" "executable script" "missing"
fi

REV1="$TEST_DIR/reviewer-1.json"
REV2="$TEST_DIR/reviewer-2.json"
MERGED="$TEST_DIR/merged.json"
cat > "$REV1" <<'JSON'
{
  "reviewer_run_id": "RUN-REV-1",
  "checkpoint_id": "CHK-PARENT",
  "reasonable_findings": [
    {"finding_id": "F-1", "module_id": "ALG-001", "criterion_id": "CRIT-001", "summary": "Algorithm edge case is untested", "severity": "high"}
  ],
  "conflicting_findings": [],
  "verdict": "fail"
}
JSON
cat > "$REV2" <<'JSON'
{
  "reviewer_run_id": "RUN-REV-2",
  "checkpoint_id": "CHK-PARENT",
  "reasonable_findings": [
    {"finding_id": "F-2", "module_id": "EXP-001", "criterion_id": "CRIT-EXP-001", "summary": "Benchmark warmup is missing", "severity": "medium"}
  ],
  "conflicting_findings": [],
  "verdict": "fail"
}
JSON

if "$MERGE_SCRIPT" --output "$MERGED" "$REV1" "$REV2" >/tmp/review-merge.out 2>&1; then
  pass "reviewer finding merge runs"
else
  fail "reviewer finding merge runs" "exit 0" "$(cat /tmp/review-merge.out)"
fi

if jq -e '.reasonable_findings | length == 2' "$MERGED" >/dev/null; then
  pass "non-conflicting reasonable findings from both reviewers are preserved"
else
  fail "non-conflicting reasonable findings from both reviewers are preserved" "2 findings" "$(cat "$MERGED" 2>/dev/null || true)"
fi

if jq -e '(.next_prompt_actions | length == 2) and (.arbitration_required == false)' "$MERGED" >/dev/null; then
  pass "merged reasonable findings become next prompt actions"
else
  fail "merged reasonable findings become next prompt actions" "2 next actions" "$(cat "$MERGED" 2>/dev/null || true)"
fi

REV3="$TEST_DIR/reviewer-3.json"
REV4="$TEST_DIR/reviewer-4.json"
CONFLICT="$TEST_DIR/conflict.json"
cat > "$REV3" <<'JSON'
{
  "reviewer_run_id": "RUN-REV-3",
  "checkpoint_id": "CHK-PARENT",
  "reasonable_findings": [
    {"finding_id": "F-3", "module_id": "ALG-001", "criterion_id": "CRIT-001", "summary": "Use exact metric tolerance", "severity": "medium", "conflict_key": "CRIT-001:tolerance", "position": "exact"}
  ],
  "verdict": "fail"
}
JSON
cat > "$REV4" <<'JSON'
{
  "reviewer_run_id": "RUN-REV-4",
  "checkpoint_id": "CHK-PARENT",
  "reasonable_findings": [
    {"finding_id": "F-4", "module_id": "ALG-001", "criterion_id": "CRIT-001", "summary": "Use trend tolerance", "severity": "medium", "conflict_key": "CRIT-001:tolerance", "position": "trend"}
  ],
  "verdict": "fail"
}
JSON

if "$MERGE_SCRIPT" --output "$CONFLICT" "$REV3" "$REV4" >/tmp/review-merge.out 2>&1; then
  pass "reviewer finding merge handles conflicting findings"
else
  fail "reviewer finding merge handles conflicting findings" "exit 0" "$(cat /tmp/review-merge.out)"
fi

if jq -e '.arbitration_required == true and (.arbitration_tasks | length == 1)' "$CONFLICT" >/dev/null; then
  pass "conflicting reviewer findings create arbitration task"
else
  fail "conflicting reviewer findings create arbitration task" "arbitration_required true" "$(cat "$CONFLICT" 2>/dev/null || true)"
fi

print_test_summary "Parent Child Review Tests"
