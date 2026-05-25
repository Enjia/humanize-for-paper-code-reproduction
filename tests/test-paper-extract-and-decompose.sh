#!/usr/bin/env bash
# Tests for standalone paper extraction and deterministic decomposition pipeline stages.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

EXTRACT="$PROJECT_ROOT/scripts/paper-extract.sh"
DECOMPOSE="$PROJECT_ROOT/scripts/paper-decompose.sh"
VALIDATOR="$PROJECT_ROOT/scripts/validate-paper-repro-plan.sh"

echo "=========================================="
echo "Paper Extract And Decompose Tests"
echo "=========================================="
echo ""

setup_test_dir
INPUT="$TEST_DIR/paper.md"
SANITIZED="$TEST_DIR/sanitized.json"
EVIDENCE="$TEST_DIR/evidence-map.json"
DECOMPOSITION="$TEST_DIR/paper-decomposition.json"

cat > "$INPUT" <<'TEXT'
# Routing Kernel Paper

Abstract: We claim the routing kernel improves inference throughput by 20 percent.

Section 3 Method: Algorithm 1 computes a route score using Equation 2.

Section 4 Experiments: We evaluate latency, throughput, memory, and warmup on one A100 GPU in Table 1.

Limitation: The exact driver version is not specified.
TEXT

for script in "$EXTRACT" "$DECOMPOSE"; do
  if [[ -x "$script" ]]; then
    pass "$(basename "$script") exists and is executable"
  else
    fail "$(basename "$script") exists and is executable" "executable script" "missing"
  fi
done

if "$EXTRACT" --input "$INPUT" --sanitized-output "$SANITIZED" --evidence-output "$EVIDENCE" >/tmp/paper-extract.out 2>&1; then
  pass "paper-extract pipeline runs"
else
  fail "paper-extract pipeline runs" "exit 0" "$(cat /tmp/paper-extract.out)"
fi

if [[ -s "$SANITIZED" ]] && jq -e '.untrusted_input == true and .supplementary_code_executed == false' "$SANITIZED" >/dev/null; then
  pass "paper-extract writes sanitized untrusted input record"
else
  fail "paper-extract writes sanitized untrusted input record" "sanitized JSON" "$(cat "$SANITIZED" 2>/dev/null || true)"
fi

if [[ -s "$EVIDENCE" ]] && jq -e '(.claims | length >= 1) and (.methods | length >= 1) and (.experiments | length >= 1) and (has("criteria") | not)' "$EVIDENCE" >/dev/null; then
  pass "paper-extract writes evidence map without criteria"
else
  fail "paper-extract writes evidence map without criteria" "claims/methods/experiments and no criteria" "$(cat "$EVIDENCE" 2>/dev/null || true)"
fi

if "$DECOMPOSE" --evidence "$EVIDENCE" --classification <("$PROJECT_ROOT/scripts/paper-classify.sh" --input "$INPUT") --output "$DECOMPOSITION" >/tmp/paper-decompose.out 2>&1; then
  pass "paper-decompose runs"
else
  fail "paper-decompose runs" "exit 0" "$(cat /tmp/paper-decompose.out)"
fi

if [[ -s "$DECOMPOSITION" ]] && jq -e '(.modules | length >= 4) and all(.modules[]; has("module_id") and has("origin") and has("origin_source") and has("reproduction_needs") and has("expected_artifact_kinds"))' "$DECOMPOSITION" >/dev/null; then
  pass "paper-decompose writes module decomposition"
else
  fail "paper-decompose writes module decomposition" "modules with required lineage fields" "$(cat "$DECOMPOSITION" 2>/dev/null || true)"
fi

if jq -e 'all(.modules[]; (has("expected_files") | not) and (has("commands") | not))' "$DECOMPOSITION" >/dev/null; then
  pass "paper-decompose does not emit implementation paths or commands"
else
  fail "paper-decompose does not emit implementation paths or commands" "no expected_files/commands" "$(cat "$DECOMPOSITION" 2>/dev/null || true)"
fi

if jq -e 'all(.modules[] | select(.origin == "paper"); (.paper_evidence | length >= 1))' "$DECOMPOSITION" >/dev/null; then
  pass "paper-origin modules include evidence lineage"
else
  fail "paper-origin modules include evidence lineage" "non-empty paper_evidence" "$(cat "$DECOMPOSITION" 2>/dev/null || true)"
fi

print_test_summary "Paper Extract And Decompose Tests"
