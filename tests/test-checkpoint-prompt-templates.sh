#!/usr/bin/env bash
# Tests for checkpoint review prompt templates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=========================================="
echo "Checkpoint Prompt Template Tests"
echo "=========================================="
echo ""

TEMPLATES=(
  checkpoint-review.md
  parent-checkpoint-review.md
  next-checkpoint-prompt.md
  reproduction-report.md
)

for template in "${TEMPLATES[@]}"; do
  file="$PROJECT_ROOT/prompt-template/paper/$template"
  if [[ -s "$file" ]]; then
    pass "prompt template exists: $template"
  else
    fail "prompt template exists: $template" "non-empty file" "missing"
  fi
done

if [[ -s "$PROJECT_ROOT/prompt-template/paper/parent-checkpoint-review.md" ]] && grep -q "two independent reviewers" "$PROJECT_ROOT/prompt-template/paper/parent-checkpoint-review.md" && grep -q "independence_group" "$PROJECT_ROOT/prompt-template/paper/parent-checkpoint-review.md"; then
  pass "parent checkpoint prompt requires independent reviewers"
else
  fail "parent checkpoint prompt requires independent reviewers" "two independent reviewers and independence_group" "missing"
fi

if [[ -s "$PROJECT_ROOT/prompt-template/paper/next-checkpoint-prompt.md" ]] && grep -q "reasonable findings" "$PROJECT_ROOT/prompt-template/paper/next-checkpoint-prompt.md" && grep -q "arbitration" "$PROJECT_ROOT/prompt-template/paper/next-checkpoint-prompt.md"; then
  pass "next checkpoint prompt carries findings and arbitration"
else
  fail "next checkpoint prompt carries findings and arbitration" "reasonable findings and arbitration" "missing"
fi

print_test_summary "Checkpoint Prompt Template Tests"
