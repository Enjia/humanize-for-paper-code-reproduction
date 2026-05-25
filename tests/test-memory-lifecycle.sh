#!/usr/bin/env bash
# Tests for redacted paper reproduction memory lifecycle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

AUDIT="$PROJECT_ROOT/scripts/memory-safety-audit.sh"
SCANNER="$PROJECT_ROOT/scripts/lib/memory-safety-scanner.sh"

echo "=========================================="
echo "Memory Lifecycle Tests"
echo "=========================================="
echo ""

setup_test_dir

for file in "$AUDIT" "$SCANNER"; do
  if [[ -s "$file" ]]; then
    pass "memory file exists: $(basename "$file")"
  else
    fail "memory file exists: $(basename "$file")" "non-empty file" "missing"
  fi
done

INPUT="$TEST_DIR/events.jsonl"
OUTPUT="$TEST_DIR/redacted-memory.jsonl"
cat > "$INPUT" <<'JSONL'
{"event_id":"EV-001","module_id":"ALG-001","criterion_id":"CRIT-001","checkpoint_id":"CHK-001","paper_hash":"sha256:abc","summary":"API key sk-test-1234567890abcdef should not persist","raw_log":"full transcript must be dropped"}
JSONL

if "$AUDIT" --input "$INPUT" --output "$OUTPUT" >/tmp/memory-audit.out 2>&1; then
  pass "memory audit writes redacted event records"
else
  fail "memory audit writes redacted event records" "exit 0" "$(cat /tmp/memory-audit.out)"
fi

if [[ -s "$OUTPUT" ]] && jq -e '.module_id == "ALG-001" and .criterion_id == "CRIT-001" and .checkpoint_id == "CHK-001" and .redaction_status == "redacted"' "$OUTPUT" >/dev/null; then
  pass "redacted memory preserves lineage fields"
else
  fail "redacted memory preserves lineage fields" "module/criterion/checkpoint lineage" "$(cat "$OUTPUT" 2>/dev/null || true)"
fi

if [[ -s "$OUTPUT" ]] && jq -e '
  .memory_type == "episodic" and
  (.source_events | index("EV-001")) and
  (.module_ids | index("ALG-001")) and
  (.criterion_ids | index("CRIT-001")) and
  (.checkpoint_ids | index("CHK-001")) and
  (.tags | index("paper-repro-event"))
' "$OUTPUT" >/dev/null; then
  pass "memory audit writes structured memory-entry lineage arrays"
else
  fail "memory audit writes structured memory-entry lineage arrays" "source_events/module_ids/criterion_ids/checkpoint_ids/tags" "$(cat "$OUTPUT" 2>/dev/null || true)"
fi

if ! grep -q "sk-test" "$OUTPUT" && ! grep -q "raw_log" "$OUTPUT"; then
  pass "memory audit removes secrets and raw logs before write"
else
  fail "memory audit removes secrets and raw logs before write" "no secret or raw_log" "$(cat "$OUTPUT")"
fi

BAD_INPUT="$TEST_DIR/bad-events.jsonl"
BAD_OUTPUT="$TEST_DIR/bad-redacted-memory.jsonl"
cat > "$BAD_INPUT" <<'JSONL'
{"event_id":"EV-BAD","module_id":"ALG-001","summary":"missing criterion and checkpoint lineage"}
JSONL
stderr_out=""
exit_code=0
stderr_out=$("$AUDIT" --input "$BAD_INPUT" --output "$BAD_OUTPUT" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "lineage" <<<"$stderr_out"; then
  pass "memory audit rejects events missing required lineage"
else
  fail "memory audit rejects events missing required lineage" "non-zero lineage error" "exit=$exit_code stderr=$stderr_out output=$(cat "$BAD_OUTPUT" 2>/dev/null || true)"
fi

print_test_summary "Memory Lifecycle Tests"
