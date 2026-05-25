#!/usr/bin/env bash
#
# Tests for deterministic evidence map extraction helper.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

EXTRACTOR="$PROJECT_ROOT/scripts/paper-evidence-map.sh"

echo "=========================================="
echo "Paper Evidence Map Tests"
echo "=========================================="
echo ""

setup_test_dir
INPUT="$TEST_DIR/paper.md"
OUTPUT="$TEST_DIR/evidence-map.json"
cat > "$INPUT" <<'TEXT'
# Example Paper

Abstract: We claim the proposed routing algorithm improves throughput by 20 percent.

Section 3 Method: Algorithm 1 computes a route score using Equation 2 and a tie-breaking rule.

Section 4 Experiments: We evaluate on Benchmark-A, compare against Baseline-B, report accuracy and latency in Table 1, and use one A100 GPU.

Limitation: The seed and exact driver version are not specified.
TEXT

if [[ -x "$EXTRACTOR" ]]; then
  pass "paper-evidence-map.sh exists and is executable"
else
  fail "paper-evidence-map.sh exists and is executable" "executable extractor" "missing or not executable"
fi

if "$EXTRACTOR" --input "$INPUT" --output "$OUTPUT" >/tmp/evidence-map.out 2>&1; then
  pass "evidence extractor runs"
else
  fail "evidence extractor runs" "exit 0" "$(cat /tmp/evidence-map.out)"
fi

if [[ -s "$OUTPUT" ]] && jq empty "$OUTPUT" >/dev/null 2>&1; then
  pass "evidence extractor writes valid JSON"
else
  fail "evidence extractor writes valid JSON" "valid JSON" "missing or invalid"
fi

for section in claims methods experiments ambiguities; do
  if jq -e --arg section "$section" '.[$section] | type == "array" and length >= 1' "$OUTPUT" >/dev/null 2>&1; then
    pass "evidence map includes non-empty $section"
  else
    fail "evidence map includes non-empty $section" "$section array with entries" "$(cat "$OUTPUT" 2>/dev/null || true)"
  fi
done

if jq -e 'has("criteria") | not' "$OUTPUT" >/dev/null 2>&1; then
  pass "evidence extractor does not generate criteria"
else
  fail "evidence extractor does not generate criteria" "no criteria field" "$(cat "$OUTPUT" 2>/dev/null || true)"
fi

if jq -e '.claims[0].source_refs[0].source_hash | startswith("sha256:")' "$OUTPUT" >/dev/null 2>&1; then
  pass "evidence records include source hash"
else
  fail "evidence records include source hash" "sha256 source hash" "$(cat "$OUTPUT" 2>/dev/null || true)"
fi

print_test_summary "Paper Evidence Map Tests"
