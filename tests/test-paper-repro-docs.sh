#!/usr/bin/env bash
# Tests for paper reproduction documentation skeleton.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=========================================="
echo "Paper Repro Docs Tests"
echo "=========================================="
echo ""

DOCS=(
  docs/paper-reproduction.md
  docs/provider-roles.md
  docs/runtime-adapter-layer.md
  docs/paper-repro-core.md
  docs/checkpoint-reviews.md
  docs/memory-and-skills.md
  docs/paper-artifact-profiles.md
  docs/paper-decomposition.md
  docs/paper-workspace-contract.md
  docs/examples/paper-repro-ml.md
  docs/examples/paper-repro-inference-optimization.md
  docs/examples/paper-repro-systems.md
  docs/examples/paper-repro-numerical-simulation.md
  docs/examples/paper-repro-data-analysis.md
)

for doc in "${DOCS[@]}"; do
  path="$PROJECT_ROOT/$doc"
  if [[ -s "$path" ]]; then
    pass "doc exists: $doc"
  else
    fail "doc exists: $doc" "non-empty file" "missing"
  fi
done

CORE="$PROJECT_ROOT/docs/paper-reproduction.md"
if [[ -s "$CORE" ]] && grep -q "paper-decomposer" "$CORE" && grep -q "agent-runner" "$CORE" && grep -q "reproduce.sh" "$CORE" && grep -q "results.json" "$CORE"; then
  pass "paper reproduction docs cover decomposer, agent-runner, reproduce.sh, and results.json"
else
  fail "paper reproduction docs cover decomposer, agent-runner, reproduce.sh, and results.json" "required topics" "missing"
fi

if [[ -s "$PROJECT_ROOT/docs/runtime-adapter-layer.md" ]] && grep -q "Hermes" "$PROJECT_ROOT/docs/runtime-adapter-layer.md" && grep -q "optional" "$PROJECT_ROOT/docs/runtime-adapter-layer.md"; then
  pass "runtime docs explain Hermes as optional adapter"
else
  fail "runtime docs explain Hermes as optional adapter" "Hermes optional" "missing"
fi

README_FILE="$PROJECT_ROOT/README.md"
if [[ -s "$README_FILE" ]] \
  && grep -q "paper reproduction superproject" "$README_FILE" \
  && grep -q "gen-paper-repro-plan" "$README_FILE" \
  && grep -q "start-paper-repro-loop" "$README_FILE" \
  && grep -q "paper-decomposer" "$README_FILE" \
  && grep -q "results.json" "$README_FILE"; then
  pass "README reflects paper reproduction superproject positioning"
else
  fail "README reflects paper reproduction superproject positioning" "paper reproduction superproject quick start and deliverables" "missing"
fi

print_test_summary "Paper Repro Docs Tests"
