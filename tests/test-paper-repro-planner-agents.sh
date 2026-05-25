#!/usr/bin/env bash
# Tests for paper reproduction planning agent artifacts and command contracts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

COMMAND_FILE="$PROJECT_ROOT/commands/gen-paper-repro-plan.md"
TEMPLATE_FILE="$PROJECT_ROOT/prompt-template/paper/gen-paper-repro-plan-template.md"
AGENTS=(
  paper-repro-planner-a.md
  paper-repro-planner-b.md
  paper-repro-synthesizer.md
  checkpoint-planner.md
  paper-type-classifier.md
  paper-evidence-extractor.md
)

echo "=========================================="
echo "Paper Repro Planner Agent Tests"
echo "=========================================="
echo ""

for agent in "${AGENTS[@]}"; do
  path="$PROJECT_ROOT/agents/$agent"
  if [[ -s "$path" ]]; then
    pass "agent exists: $agent"
  else
    fail "agent exists: $agent" "non-empty file" "missing"
  fi
done

if [[ -s "$TEMPLATE_FILE" ]]; then
  pass "gen paper repro plan template exists"
else
  fail "gen paper repro plan template exists" "non-empty file" "missing"
fi

for agent in paper-repro-planner-a.md paper-repro-planner-b.md; do
  path="$PROJECT_ROOT/agents/$agent"
  if [[ -s "$path" ]] && grep -q "after paper decomposition" "$path" && grep -q "module_ids" "$path" && grep -q "criterion_ids" "$path" && grep -q "checkpoint_id" "$path"; then
    pass "$agent binds tasks to module, criterion, and checkpoint lineage"
  else
    fail "$agent binds tasks to module, criterion, and checkpoint lineage" "lineage wording" "missing"
  fi
done

if [[ -s "$PROJECT_ROOT/agents/paper-repro-synthesizer.md" ]] && grep -q "unresolved disagreements" "$PROJECT_ROOT/agents/paper-repro-synthesizer.md" && grep -q "synthesis decisions" "$PROJECT_ROOT/agents/paper-repro-synthesizer.md"; then
  pass "synthesizer records decisions and unresolved disagreements"
else
  fail "synthesizer records decisions and unresolved disagreements" "decisions/disagreements" "missing"
fi

if [[ -s "$PROJECT_ROOT/agents/checkpoint-planner.md" ]] && grep -q "verification_commands" "$PROJECT_ROOT/agents/checkpoint-planner.md" && grep -q "parent" "$PROJECT_ROOT/agents/checkpoint-planner.md" && grep -q "reviewer_count" "$PROJECT_ROOT/agents/checkpoint-planner.md"; then
  pass "checkpoint planner specifies checkpoint contract fields"
else
  fail "checkpoint planner specifies checkpoint contract fields" "verification_commands/reviewer_count" "missing"
fi

if [[ -s "$COMMAND_FILE" ]] && grep -q "agent-runner" "$COMMAND_FILE" && grep -q "Planner A" "$COMMAND_FILE" && grep -q "Planner B" "$COMMAND_FILE" && grep -q "Synthesizer" "$COMMAND_FILE"; then
  pass "gen-paper-repro-plan command requires planner agents through agent-runner"
else
  fail "gen-paper-repro-plan command requires planner agents through agent-runner" "agent-runner and planner names" "missing"
fi

if [[ -s "$TEMPLATE_FILE" ]] && grep -q "evidence map plus paper decomposition" "$TEMPLATE_FILE" && grep -q "paper-repro-plan.json" "$TEMPLATE_FILE" && grep -q "start-paper-repro-loop" "$TEMPLATE_FILE"; then
  pass "gen paper repro template anchors final manifest contract"
else
  fail "gen paper repro template anchors final manifest contract" "evidence/decomposition/manifest/loop" "missing"
fi

print_test_summary "Paper Repro Planner Agent Tests"
