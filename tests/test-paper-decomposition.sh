#!/usr/bin/env bash
#
# Tests for paper-decomposer prompt, schema, and fixtures.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

AGENT_FILE="$PROJECT_ROOT/agents/paper-decomposer.md"
PROMPT_FILE="$PROJECT_ROOT/prompt-template/paper/paper-decomposition.md"
SCHEMA_FILE="$PROJECT_ROOT/schema/paper-decomposition.schema.json"
FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/paper-decomposition"

echo "=========================================="
echo "Paper Decomposition Tests"
echo "=========================================="
echo ""

if [[ -s "$AGENT_FILE" ]]; then
  pass "paper-decomposer agent exists"
else
  fail "paper-decomposer agent exists" "non-empty file" "missing or empty"
fi

if [[ -s "$PROMPT_FILE" ]]; then
  pass "paper decomposition prompt template exists"
else
  fail "paper decomposition prompt template exists" "non-empty file" "missing or empty"
fi

if [[ -s "$SCHEMA_FILE" ]]; then
  pass "paper-decomposition schema exists"
else
  fail "paper-decomposition schema exists" "non-empty file" "missing or empty"
fi

if [[ -d "$FIXTURE_DIR" ]] && find "$FIXTURE_DIR" -name '*.md' -type f | grep -q .; then
  pass "paper decomposition markdown fixtures exist"
else
  fail "paper decomposition markdown fixtures exist" "at least one .md fixture" "missing"
fi

if [[ -s "$AGENT_FILE" ]] && grep -q "must not write implementation plans" "$AGENT_FILE"; then
  pass "paper-decomposer forbids implementation planning"
else
  fail "paper-decomposer forbids implementation planning" "must not write implementation plans" "missing"
fi

if [[ -s "$PROMPT_FILE" ]] && grep -q "reproduction_needs" "$PROMPT_FILE" && grep -q "expected_artifact_kinds" "$PROMPT_FILE"; then
  pass "paper decomposition prompt uses needs and artifact kinds"
else
  fail "paper decomposition prompt uses needs and artifact kinds" "reproduction_needs and expected_artifact_kinds" "missing"
fi

if [[ -s "$PROMPT_FILE" ]] && ! grep -q "expected_files" "$PROMPT_FILE" && ! grep -q "implementation path" "$PROMPT_FILE"; then
  pass "paper decomposition prompt does not request concrete implementation paths"
else
  fail "paper decomposition prompt does not request concrete implementation paths" "no expected_files or implementation path text" "found forbidden wording"
fi

for token in module_id module_type origin origin_source paper_evidence reproduction_needs expected_artifact_kinds verification_targets ambiguities risk_level; do
  if [[ -s "$SCHEMA_FILE" ]] && grep -q "\"$token\"" "$SCHEMA_FILE"; then
    pass "paper-decomposition schema includes $token"
  else
    fail "paper-decomposition schema includes $token" "$token" "missing"
  fi
done

for module_type in algorithm_module optimization_module data_module experiment_design_module environment_module evaluation_module reporting_module integration_module; do
  if [[ -s "$SCHEMA_FILE" ]] && grep -q "$module_type" "$SCHEMA_FILE"; then
    pass "paper-decomposition schema includes module type $module_type"
  else
    fail "paper-decomposition schema includes module type $module_type" "$module_type" "missing"
  fi
done

for origin in paper reproduction_contract policy assumption; do
  if [[ -s "$SCHEMA_FILE" ]] && grep -q "$origin" "$SCHEMA_FILE"; then
    pass "paper-decomposition schema includes origin $origin"
  else
    fail "paper-decomposition schema includes origin $origin" "$origin" "missing"
  fi
done

if [[ -d "$FIXTURE_DIR" ]] && grep -R "prompt injection" "$FIXTURE_DIR" >/dev/null 2>&1; then
  pass "paper decomposition fixtures include untrusted input case"
else
  fail "paper decomposition fixtures include untrusted input case" "fixture mentioning prompt injection" "missing"
fi

print_test_summary "Paper Decomposition Tests"
