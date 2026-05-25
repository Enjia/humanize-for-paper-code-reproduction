#!/usr/bin/env bash
# Tests for structured paper reproduction memory capture, consolidation, and retrieval.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CAPTURE="$PROJECT_ROOT/scripts/memory-capture.sh"
CONSOLIDATE="$PROJECT_ROOT/scripts/memory-consolidate.sh"
SELECT="$PROJECT_ROOT/scripts/memory-select.sh"

echo "=========================================="
echo "Memory Workflow Tests"
echo "=========================================="
echo ""

setup_test_dir

missing=0
for file in "$CAPTURE" "$CONSOLIDATE" "$SELECT" "$PROJECT_ROOT/agents/memory-consolidator.md" "$PROJECT_ROOT/agents/memory-selector.md"; do
  if [[ -s "$file" ]]; then
    pass "memory workflow artifact exists: $(basename "$file")"
  else
    fail "memory workflow artifact exists: $(basename "$file")" "non-empty file" "missing"
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  print_test_summary "Memory Workflow Tests"
  exit 1
fi

INPUT="$TEST_DIR/checkpoint-events.jsonl"
MEMORY_DIR="$TEST_DIR/.humanize/memory"
cat > "$INPUT" <<'JSONL'
{"event_id":"EV-001","module_id":"ALG-001","criterion_id":"CRIT-001","checkpoint_id":"CHK-001","paper_hash":"sha256:abc","summary":"Kernel fix worked; token=abc123456789 should be removed.","tags":["optimization"],"paper_type":"inference-optimization"}
{"event_id":"EV-002","module_id":"EXP-001","criterion_id":"CRIT-002","checkpoint_id":"CHK-001","paper_hash":"sha256:abc","summary":"Benchmark warmup must be recorded.","tags":["benchmark"],"paper_type":"inference-optimization"}
JSONL

if "$CAPTURE" --input "$INPUT" --memory-dir "$MEMORY_DIR" >/tmp/memory-capture.out 2>&1; then
  pass "memory capture persists redacted event records"
else
  fail "memory capture persists redacted event records" "exit 0" "$(cat /tmp/memory-capture.out)"
fi

if [[ -s "$MEMORY_DIR/events.jsonl" ]] && [[ "$(wc -l < "$MEMORY_DIR/events.jsonl" | tr -d ' ')" == "2" ]] && ! grep -q "abc123456789" "$MEMORY_DIR/events.jsonl"; then
  pass "captured events contain no raw secret text"
else
  fail "captured events contain no raw secret text" "2 redacted records" "$(cat "$MEMORY_DIR/events.jsonl" 2>/dev/null || true)"
fi

if "$CONSOLIDATE" --memory-dir "$MEMORY_DIR" >/tmp/memory-consolidate.out 2>&1; then
  pass "memory consolidation builds memories and index"
else
  fail "memory consolidation builds memories and index" "exit 0" "$(cat /tmp/memory-consolidate.out)"
fi

if [[ -s "$MEMORY_DIR/memories.jsonl" && -s "$MEMORY_DIR/links.jsonl" && -s "$MEMORY_DIR/index.json" ]] && jq -e '.memory_count == 2 and (.module_ids | index("ALG-001"))' "$MEMORY_DIR/index.json" >/dev/null; then
  pass "memory consolidation emits structured stores"
else
  fail "memory consolidation emits structured stores" "memories/links/index" "$(cat "$MEMORY_DIR/index.json" 2>/dev/null || true)"
fi

if "$SELECT" --memory-dir "$MEMORY_DIR" --module ALG-001 --limit 5 > "$TEST_DIR/selected.json"; then
  pass "memory selection runs with lineage filter"
else
  fail "memory selection runs with lineage filter" "exit 0" "selection failed"
fi

if jq -e 'length == 1 and .[0].memory_id == "MEM-EV-001" and (. [0].module_ids | index("ALG-001"))' "$TEST_DIR/selected.json" >/dev/null; then
  pass "memory selection returns matching structured memory"
else
  fail "memory selection returns matching structured memory" "ALG-001 memory only" "$(cat "$TEST_DIR/selected.json" 2>/dev/null || true)"
fi

print_test_summary "Memory Workflow Tests"
