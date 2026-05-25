#!/usr/bin/env bash
# Tests for independent parent checkpoint reviewer run validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

AGENT_RUNNER="$PROJECT_ROOT/scripts/lib/agent-runner.sh"

echo "=========================================="
echo "Agent Run Independence Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -s "$AGENT_RUNNER" ]]; then
  pass "agent-runner.sh exists"
else
  fail "agent-runner.sh exists" "non-empty file" "missing"
  print_test_summary "Agent Run Independence Tests"
  exit 1
fi

# shellcheck source=../scripts/lib/agent-runner.sh
source "$AGENT_RUNNER"

cat > "$TEST_DIR/runs-valid.jsonl" <<'JSONL'
{"run_id":"RUN-REV-001","role":"checkpoint_reviewer","independence_group":"PARENT-CHK-001","output_artifacts":["reviews/rev1.json"],"summary_artifact":"reviews/rev1.md"}
{"run_id":"RUN-REV-002","role":"checkpoint_reviewer","independence_group":"PARENT-CHK-001","output_artifacts":["reviews/rev2.json"],"summary_artifact":"reviews/rev2.md"}
JSONL

if agent_runner_validate_independence "$TEST_DIR/runs-valid.jsonl" "PARENT-CHK-001" 2 >/tmp/independence.out 2>&1; then
  pass "distinct reviewer runs satisfy parent checkpoint independence"
else
  fail "distinct reviewer runs satisfy parent checkpoint independence" "exit 0" "$(cat /tmp/independence.out)"
fi

cat > "$TEST_DIR/runs-dup-id.jsonl" <<'JSONL'
{"run_id":"RUN-REV-001","role":"checkpoint_reviewer","independence_group":"PARENT-CHK-001","output_artifacts":["reviews/rev1.json"],"summary_artifact":"reviews/rev1.md"}
{"run_id":"RUN-REV-001","role":"checkpoint_reviewer","independence_group":"PARENT-CHK-001","output_artifacts":["reviews/rev2.json"],"summary_artifact":"reviews/rev2.md"}
JSONL

stderr_out=""
exit_code=0
stderr_out=$(agent_runner_validate_independence "$TEST_DIR/runs-dup-id.jsonl" "PARENT-CHK-001" 2 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "duplicate run_id" <<<"$stderr_out"; then
  pass "duplicated reviewer run_id cannot count as independent"
else
  fail "duplicated reviewer run_id cannot count as independent" "duplicate run_id error" "exit=$exit_code stderr=$stderr_out"
fi

cat > "$TEST_DIR/runs-dup-artifact.jsonl" <<'JSONL'
{"run_id":"RUN-REV-001","role":"checkpoint_reviewer","independence_group":"PARENT-CHK-001","output_artifacts":["reviews/shared.json"],"summary_artifact":"reviews/rev1.md"}
{"run_id":"RUN-REV-002","role":"checkpoint_reviewer","independence_group":"PARENT-CHK-001","output_artifacts":["reviews/shared.json"],"summary_artifact":"reviews/rev2.md"}
JSONL

stderr_out=""
exit_code=0
stderr_out=$(agent_runner_validate_independence "$TEST_DIR/runs-dup-artifact.jsonl" "PARENT-CHK-001" 2 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "duplicate output artifact" <<<"$stderr_out"; then
  pass "duplicated reviewer output artifacts cannot count as independent"
else
  fail "duplicated reviewer output artifacts cannot count as independent" "duplicate output artifact error" "exit=$exit_code stderr=$stderr_out"
fi

print_test_summary "Agent Run Independence Tests"
