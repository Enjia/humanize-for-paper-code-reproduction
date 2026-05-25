#!/usr/bin/env bash
#
# Tests for checkpoint graph validation semantics in paper repro manifests.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$PROJECT_ROOT/scripts/validate-paper-repro-plan.sh"

echo "=========================================="
echo "Checkpoint Graph Tests"
echo "=========================================="
echo ""

setup_test_dir
PLAN="$TEST_DIR/checkpoint-plan.json"
cat > "$PLAN" <<'JSON'
{
  "schema_version": "paper-repro-plan/v1",
  "created_at": "2026-05-24T00:00:00Z",
  "paper_hash": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "input_sources": [{"source_id": "SRC-001", "kind": "markdown", "path": "paper.md", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],
  "budget_profile": "smoke",
  "unsupported_items": [],
  "risk_level": "medium",
  "privacy_mode": "local_only",
  "paper": {"title": "Fixture"},
  "workspace": {"path": "paper-repro/fixture"},
  "safety": {"paper_text_untrusted": true},
  "budget": {"profile": "smoke"},
  "feasibility": {"status": "smoke_only"},
  "evidence_map": {"claims": [], "methods": [], "experiments": [], "ambiguities": []},
  "decomposition": {"modules": [{"module_id": "ALG-001", "module_type": "algorithm_module", "origin": "paper", "origin_source": "CLAIM-001", "title": "Algorithm", "paper_evidence": ["CLAIM-001"], "depends_on": [], "claims_supported": ["CLAIM-001"], "reproduction_needs": ["implementation"], "expected_artifact_kinds": ["source_module"], "verification_targets": ["works"], "ambiguities": [], "risk_level": "medium"}]},
  "criteria": [{"criterion_id": "CRIT-001", "module_ids": ["ALG-001"], "type": "method", "paper_evidence": ["CLAIM-001"], "expected_artifacts": ["src/algorithm.py"], "expected_artifact_kinds": ["source_module"], "expected_outputs": [], "verification_method": "unit_test", "tolerance": null, "status": "pending", "blocking": true, "open_questions": []}],
  "artifact_profile": {"paper_types": ["algorithm-experiment"], "profile_rule_packs": ["algorithm-experiment"], "required_artifacts": [], "optional_artifacts": [], "not_applicable_artifacts": [], "rationale": [], "source_criteria": ["CRIT-001"]},
  "assumption_ledger": [],
  "checkpoint_graph": {"checkpoints": [{"checkpoint_id": "CHK-001", "kind": "parent", "title": "Parent", "depends_on": [], "covered_modules": ["ALG-001"], "covered_criteria": ["CRIT-001"], "expected_artifacts": ["src/algorithm.py"], "verification_commands": ["pytest"], "reviewer_count": 2, "reviewer_run_ids": [], "reviewer_provider_policy": {"independence": "distinct_run_id"}, "base_snapshot": null, "target_snapshot": null, "changed_paths": [], "artifact_hashes": {}, "checkpoint_base_commit": null, "acceptance_rule": "all_blocking_criteria_pass", "open_question_policy": "block_if_material", "fallback_policy": "record_assumption", "failure_escalation": "revise_checkpoint"}]},
  "tasks": [{"task_id": "TASK-001", "title": "Task", "lineage_mode": "single", "primary_module_id": "ALG-001", "module_ids": ["ALG-001"], "primary_criterion_id": "CRIT-001", "criterion_ids": ["CRIT-001"], "checkpoint_id": "CHK-001", "expected_files": ["src/algorithm.py"], "commands": ["pytest"], "risk_level": "medium", "budget_impact": "low"}],
  "provider_roles": {},
  "agent_runs": [{"run_id": "RUN-001", "role": "checkpoint_planner", "parent_run_id": null, "independence_group": null, "provider": "codex", "model": "default", "effort": "high", "tool_policy": {}, "workspace_scope": "read_only", "write_policy": "none", "network_policy": "disabled", "timeout_seconds": 600, "input_artifacts": ["paper.md"], "output_artifacts": ["checkpoint-graph.json"], "summary_artifact": null, "redaction_status": "not_needed", "started_at": "2026-05-24T00:00:00Z", "ended_at": "2026-05-24T00:01:00Z", "exit_status": "success"}],
  "review_policy": {"parent_reviewers": 2},
  "final_package_contract": {"entrypoint": "reproduce.sh", "results": "results.json"}
}
JSON

if "$VALIDATOR" "$PLAN" >/tmp/checkpoint-graph.out 2>&1; then
  pass "valid parent checkpoint graph passes"
else
  fail "valid parent checkpoint graph passes" "exit 0" "$(cat /tmp/checkpoint-graph.out)"
fi

make_invalid() {
  jq "$2" "$PLAN" > "$1"
}

BAD_REVIEWERS="$TEST_DIR/bad-reviewers.json"
make_invalid "$BAD_REVIEWERS" '.checkpoint_graph.checkpoints[0].reviewer_count = 1'
if "$VALIDATOR" "$BAD_REVIEWERS" >/tmp/checkpoint-graph.out 2>&1; then
  fail "parent checkpoint with one reviewer is rejected" "non-zero exit" "validation passed"
else
  if grep -q "parent checkpoint" /tmp/checkpoint-graph.out; then
    pass "parent checkpoint with one reviewer is rejected"
  else
    fail "parent reviewer error mentions parent checkpoint" "parent checkpoint" "$(cat /tmp/checkpoint-graph.out)"
  fi
fi

BAD_MODULE="$TEST_DIR/bad-module.json"
make_invalid "$BAD_MODULE" '.checkpoint_graph.checkpoints[0].covered_modules = ["MISSING-001"]'
if "$VALIDATOR" "$BAD_MODULE" >/tmp/checkpoint-graph.out 2>&1; then
  fail "checkpoint with unknown module coverage is rejected" "non-zero exit" "validation passed"
else
  if grep -q "covered module" /tmp/checkpoint-graph.out; then
    pass "checkpoint with unknown module coverage is rejected"
  else
    fail "unknown module error mentions covered module" "covered module" "$(cat /tmp/checkpoint-graph.out)"
  fi
fi

BAD_CRITERION="$TEST_DIR/bad-criterion.json"
make_invalid "$BAD_CRITERION" '.checkpoint_graph.checkpoints[0].covered_criteria = ["MISSING-CRIT"]'
if "$VALIDATOR" "$BAD_CRITERION" >/tmp/checkpoint-graph.out 2>&1; then
  fail "checkpoint with unknown criterion coverage is rejected" "non-zero exit" "validation passed"
else
  if grep -q "covered criterion" /tmp/checkpoint-graph.out; then
    pass "checkpoint with unknown criterion coverage is rejected"
  else
    fail "unknown criterion error mentions covered criterion" "covered criterion" "$(cat /tmp/checkpoint-graph.out)"
  fi
fi

print_test_summary "Checkpoint Graph Tests"
