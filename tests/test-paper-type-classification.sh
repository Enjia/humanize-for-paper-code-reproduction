#!/usr/bin/env bash
#
# Tests for deterministic paper type classification helper.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLASSIFIER="$PROJECT_ROOT/scripts/paper-classify.sh"

echo "=========================================="
echo "Paper Type Classification Tests"
echo "=========================================="
echo ""

setup_test_dir

INFERENCE="$TEST_DIR/inference.md"
SIMULATION="$TEST_DIR/simulation.md"
DATA="$TEST_DIR/data.md"

cat > "$INFERENCE" <<'TEXT'
We optimize transformer inference latency with a fused kernel. Experiments report throughput, tokens per second, warmup iterations, GPU memory, and profiler traces. No model training is performed.
TEXT
cat > "$SIMULATION" <<'TEXT'
We solve a partial differential equation using a finite-volume numerical simulation. The study reports convergence tolerance, solver precision, mesh resolution, and comparison to an analytic solution.
TEXT
cat > "$DATA" <<'TEXT'
This empirical study acquires a public dataset, cleans missing values, extracts features, runs a statistical test, and regenerates figures and tables.
TEXT

if [[ -x "$CLASSIFIER" ]]; then
  pass "paper-classify.sh exists and is executable"
else
  fail "paper-classify.sh exists and is executable" "executable classifier" "missing or not executable"
fi

if "$CLASSIFIER" --input "$INFERENCE" >/tmp/paper-classify.json 2>/tmp/paper-classify.err && jq -e '.paper_types | index("inference-optimization")' /tmp/paper-classify.json >/dev/null; then
  pass "classifier detects inference optimization"
else
  fail "classifier detects inference optimization" "inference-optimization" "$(cat /tmp/paper-classify.err /tmp/paper-classify.json 2>/dev/null || true)"
fi

if "$CLASSIFIER" --input "$INFERENCE" >/tmp/paper-classify.json 2>/tmp/paper-classify.err && jq -e '.not_applicable_artifacts | index("training_script")' /tmp/paper-classify.json >/dev/null; then
  pass "classifier marks training not applicable for inference fixture"
else
  fail "classifier marks training not applicable for inference fixture" "training_script not applicable" "$(cat /tmp/paper-classify.err /tmp/paper-classify.json 2>/dev/null || true)"
fi

if "$CLASSIFIER" --input "$SIMULATION" >/tmp/paper-classify.json 2>/tmp/paper-classify.err && jq -e '.paper_types | index("numerical-simulation")' /tmp/paper-classify.json >/dev/null; then
  pass "classifier detects numerical simulation"
else
  fail "classifier detects numerical simulation" "numerical-simulation" "$(cat /tmp/paper-classify.err /tmp/paper-classify.json 2>/dev/null || true)"
fi

if "$CLASSIFIER" --input "$DATA" >/tmp/paper-classify.json 2>/tmp/paper-classify.err && jq -e '.paper_types | index("data-analysis")' /tmp/paper-classify.json >/dev/null; then
  pass "classifier detects data analysis"
else
  fail "classifier detects data analysis" "data-analysis" "$(cat /tmp/paper-classify.err /tmp/paper-classify.json 2>/dev/null || true)"
fi

if "$CLASSIFIER" --input "$INFERENCE" --paper-type systems >/tmp/paper-classify.json 2>/tmp/paper-classify.err && jq -e '.paper_types[0] == "systems" and .override_applied == true' /tmp/paper-classify.json >/dev/null; then
  pass "classifier honors explicit paper type override"
else
  fail "classifier honors explicit paper type override" "systems override" "$(cat /tmp/paper-classify.err /tmp/paper-classify.json 2>/dev/null || true)"
fi

print_test_summary "Paper Type Classification Tests"
