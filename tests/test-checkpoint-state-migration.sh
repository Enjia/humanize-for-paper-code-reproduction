#!/usr/bin/env bash
# Tests for paper checkpoint state migration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MIGRATE="$PROJECT_ROOT/scripts/checkpoint-state-migrate.sh"

echo "=========================================="
echo "Checkpoint State Migration Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -x "$MIGRATE" ]]; then
  pass "checkpoint-state-migrate.sh exists and is executable"
else
  fail "checkpoint-state-migrate.sh exists and is executable" "executable script" "missing"
fi

OLD="$TEST_DIR/old-state.json"
NEW="$TEST_DIR/new-state.json"
cat > "$OLD" <<'JSON'
{
  "loop_kind": "paper_repro",
  "plan_path": "paper-repro-plan.json",
  "current_checkpoint": "CHK-001",
  "done": ["CHK-000"]
}
JSON

if "$MIGRATE" --input "$OLD" --output "$NEW" >/tmp/migrate.out 2>&1; then
  pass "checkpoint state migration runs"
else
  fail "checkpoint state migration runs" "exit 0" "$(cat /tmp/migrate.out)"
fi

if jq -e '.schema_version == "paper-repro-state/v1" and .active_checkpoint_id == "CHK-001" and (.completed_checkpoints | index("CHK-000")) and .loop_kind == "paper_repro"' "$NEW" >/dev/null; then
  pass "checkpoint migration normalizes legacy fields"
else
  fail "checkpoint migration normalizes legacy fields" "normalized state" "$(cat "$NEW" 2>/dev/null || true)"
fi

PLAN="$TEST_DIR/paper-repro-plan.json"
ADVANCED="$TEST_DIR/advanced-state.json"
cat > "$PLAN" <<'JSON'
{
  "checkpoint_graph": {
    "checkpoints": [
      {"checkpoint_id": "CHK-001"},
      {"checkpoint_id": "CHK-002"},
      {"checkpoint_id": "CHK-003"}
    ]
  }
}
JSON
cat > "$NEW" <<JSON
{
  "schema_version": "paper-repro-state/v1",
  "loop_kind": "paper_repro",
  "plan_path": "$PLAN",
  "active_checkpoint_id": "CHK-001",
  "completed_checkpoints": [],
  "created_at": "2026-05-24T00:00:00Z",
  "updated_at": "2026-05-24T00:00:00Z"
}
JSON

if "$MIGRATE" --input "$NEW" --output "$ADVANCED" --advance CHK-001 >/tmp/migrate.out 2>&1; then
  pass "checkpoint state advance runs"
else
  fail "checkpoint state advance runs" "exit 0" "$(cat /tmp/migrate.out)"
fi

if jq -e '.active_checkpoint_id == "CHK-002" and (.completed_checkpoints | index("CHK-001")) and .status == "in_progress"' "$ADVANCED" >/dev/null; then
  pass "checkpoint state advance moves to next checkpoint"
else
  fail "checkpoint state advance moves to next checkpoint" "active CHK-002 and completed CHK-001" "$(cat "$ADVANCED" 2>/dev/null || true)"
fi

BAD_ADVANCE="$TEST_DIR/bad-advance.json"
stderr_out=""
exit_code=0
stderr_out=$("$MIGRATE" --input "$NEW" --output "$BAD_ADVANCE" --advance CHK-999 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "active checkpoint" <<<"$stderr_out"; then
  pass "checkpoint state advance rejects non-active checkpoint"
else
  fail "checkpoint state advance rejects non-active checkpoint" "non-zero active checkpoint error" "exit=$exit_code stderr=$stderr_out"
fi

print_test_summary "Checkpoint State Migration Tests"
