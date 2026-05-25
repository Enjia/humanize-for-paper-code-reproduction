#!/usr/bin/env bash
#
# Tests for paper reproduction plan schema and manifest validation.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$PROJECT_ROOT/scripts/validate-paper-repro-plan.sh"
SCHEMA_DIR="$PROJECT_ROOT/schema"

echo "=========================================="
echo "Paper Reproduction Plan Tests"
echo "=========================================="
echo ""

setup_test_dir

required_schemas=(
  paper-input.schema.json
  paper-evidence-map.schema.json
  paper-decomposition.schema.json
  reproduction-criteria.schema.json
  artifact-profile.schema.json
  checkpoint-graph.schema.json
  reproduction-plan.schema.json
  agent-run.schema.json
  runtime-adapter.schema.json
  provider-role.schema.json
  reviewer-verdict.schema.json
  memory-entry.schema.json
  skill-entry.schema.json
)

for schema in "${required_schemas[@]}"; do
  if [[ -s "$SCHEMA_DIR/$schema" ]]; then
    pass "schema exists: $schema"
  else
    fail "schema exists: $schema" "non-empty file" "missing or empty"
  fi
done

if [[ -x "$VALIDATOR" ]]; then
  pass "validate-paper-repro-plan.sh exists and is executable"
else
  fail "validate-paper-repro-plan.sh exists and is executable" "executable validator" "missing or not executable"
fi

if jq -e '
  (."$defs".task.allOf // []) as $rules |
  (
    any($rules[];
      (.if.properties.lineage_mode.const == "single")
      and (.then.required | index("primary_module_id"))
      and (.then.required | index("primary_criterion_id"))
      and (.then.properties.module_ids.minItems == 1)
      and (.then.properties.module_ids.maxItems == 1)
      and (.then.properties.criterion_ids.minItems == 1)
      and (.then.properties.criterion_ids.maxItems == 1)
    )
    and any($rules[];
      (.if.properties.lineage_mode.const == "primary")
      and (.then.required | index("primary_module_id"))
      and (.then.required | index("primary_criterion_id"))
    )
    and any($rules[];
      (.if.properties.lineage_mode.const == "multi_equal")
      and (.then.not.anyOf | map(.required[0]) | index("primary_module_id"))
      and (.then.not.anyOf | map(.required[0]) | index("primary_criterion_id"))
    )
  )
' "$SCHEMA_DIR/reproduction-plan.schema.json" >/dev/null; then
  pass "reproduction-plan schema encodes task lineage mode conditions"
else
  fail "reproduction-plan schema encodes task lineage mode conditions" "single/primary/multi_equal if-then rules" "missing"
fi

VALID_PLAN="$TEST_DIR/valid-paper-repro-plan.json"
cat > "$VALID_PLAN" <<'JSON'
{
  "schema_version": "paper-repro-plan/v1",
  "created_at": "2026-05-24T00:00:00Z",
  "paper_hash": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "input_sources": [{"source_id": "SRC-001", "kind": "markdown", "path": "paper.md", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],
  "budget_profile": "smoke",
  "unsupported_items": [],
  "risk_level": "medium",
  "privacy_mode": "local_only",
  "paper": {"title": "Fixture Paper", "paper_types": ["algorithm-experiment"]},
  "workspace": {"path": "paper-repro/fixture-paper", "commit_policy": "source-only"},
  "safety": {"paper_text_untrusted": true, "supplementary_code_executed": false},
  "budget": {"profile": "smoke", "network_allowed": false, "gpu_allowed": false},
  "feasibility": {"status": "smoke_only", "reasons": []},
  "evidence_map": {
    "claims": [{"evidence_id": "CLAIM-001", "summary": "Algorithm improves score", "source_refs": [{"section": "Abstract", "source_hash": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}], "confidence": "medium"}],
    "methods": [],
    "experiments": [],
    "ambiguities": []
  },
  "decomposition": {
    "modules": [
      {"module_id": "ALG-001", "module_type": "algorithm_module", "origin": "paper", "origin_source": "CLAIM-001", "title": "Core algorithm", "paper_evidence": ["CLAIM-001"], "depends_on": [], "claims_supported": ["CLAIM-001"], "reproduction_needs": ["reference implementation"], "expected_artifact_kinds": ["source_module", "unit_test"], "verification_targets": ["matches described behavior"], "ambiguities": [], "risk_level": "medium"},
      {"module_id": "INT-001", "module_type": "integration_module", "origin": "reproduction_contract", "origin_source": "final_package_contract.reproduce_sh", "title": "Entrypoint", "paper_evidence": [], "depends_on": ["ALG-001"], "claims_supported": [], "reproduction_needs": ["top-level CLI"], "expected_artifact_kinds": ["entrypoint"], "verification_targets": ["reproduce.sh exists"], "ambiguities": [], "risk_level": "low"}
    ]
  },
  "criteria": [
    {"criterion_id": "CRIT-001", "module_ids": ["ALG-001"], "type": "method", "paper_evidence": ["CLAIM-001"], "expected_artifacts": ["src/algorithm.py", "tests/test_algorithm.py"], "expected_artifact_kinds": ["source_module", "unit_test"], "expected_outputs": [], "verification_method": "unit_test", "tolerance": null, "status": "pending", "blocking": true, "open_questions": []},
    {"criterion_id": "CRIT-002", "module_ids": ["INT-001"], "type": "artifact", "paper_evidence": [], "expected_artifacts": ["reproduce.sh"], "expected_artifact_kinds": ["entrypoint"], "expected_outputs": ["results.json"], "verification_method": "script", "tolerance": null, "status": "pending", "blocking": true, "open_questions": []}
  ],
  "artifact_profile": {"paper_types": ["algorithm-experiment"], "profile_rule_packs": ["algorithm-experiment"], "required_artifacts": ["source", "tests", "reproduce.sh", "results.json"], "optional_artifacts": [], "not_applicable_artifacts": ["training-checkpoints"], "rationale": ["No training claims"], "source_criteria": ["CRIT-001", "CRIT-002"]},
  "assumption_ledger": [],
  "checkpoint_graph": {
    "checkpoints": [
      {"checkpoint_id": "CHK-001", "kind": "child", "title": "Algorithm smoke", "depends_on": [], "covered_modules": ["ALG-001"], "covered_criteria": ["CRIT-001"], "expected_artifacts": ["src/algorithm.py", "tests/test_algorithm.py"], "verification_commands": ["pytest tests/test_algorithm.py"], "reviewer_count": 1, "reviewer_run_ids": [], "reviewer_provider_policy": {"independence": "distinct_run_id"}, "base_snapshot": null, "target_snapshot": null, "changed_paths": [], "artifact_hashes": {}, "checkpoint_base_commit": null, "acceptance_rule": "all_blocking_criteria_pass", "open_question_policy": "block_if_material", "fallback_policy": "record_assumption", "failure_escalation": "revise_checkpoint"}
    ]
  },
  "tasks": [
    {"task_id": "TASK-001", "title": "Implement algorithm", "lineage_mode": "single", "primary_module_id": "ALG-001", "module_ids": ["ALG-001"], "primary_criterion_id": "CRIT-001", "criterion_ids": ["CRIT-001"], "checkpoint_id": "CHK-001", "expected_files": ["src/algorithm.py", "tests/test_algorithm.py"], "commands": ["pytest tests/test_algorithm.py"], "risk_level": "medium", "budget_impact": "low"}
  ],
  "provider_roles": {"planner_strategy": "single"},
  "agent_runs": [
    {"run_id": "RUN-001", "role": "paper_decomposer", "parent_run_id": null, "independence_group": null, "provider": "codex", "model": "default", "effort": "high", "tool_policy": {"tools": ["read"]}, "workspace_scope": "read_only", "write_policy": "none", "network_policy": "disabled", "timeout_seconds": 600, "input_artifacts": ["paper.md"], "output_artifacts": ["paper-decomposition.json"], "summary_artifact": "paper-decomposition-summary.md", "redaction_status": "not_needed", "started_at": "2026-05-24T00:00:00Z", "ended_at": "2026-05-24T00:01:00Z", "exit_status": "success"}
  ],
  "review_policy": {"child_reviewers": 1, "parent_reviewers": 2},
  "final_package_contract": {"entrypoint": "reproduce.sh", "results": "results.json", "report": "reproduction-report.md"}
}
JSON

if "$VALIDATOR" "$VALID_PLAN" >/tmp/paper-repro-valid.out 2>&1; then
  pass "valid paper-repro-plan manifest passes validation"
else
  fail "valid paper-repro-plan manifest passes validation" "exit 0" "$(cat /tmp/paper-repro-valid.out)"
fi

make_invalid() {
  local output="$1"
  local jq_filter="$2"
  jq "$jq_filter" "$VALID_PLAN" > "$output"
}

expect_invalid_plan() {
  local name="$1"
  local jq_filter="$2"
  local expected_message="$3"
  local output="$TEST_DIR/$name.json"

  make_invalid "$output" "$jq_filter"
  if "$VALIDATOR" "$output" >/tmp/paper-repro-invalid.out 2>&1; then
    fail "$name is rejected" "non-zero exit" "validation passed"
  else
    if grep -q "$expected_message" /tmp/paper-repro-invalid.out; then
      pass "$name is rejected"
    else
      fail "$name error mentions $expected_message" "$expected_message" "$(cat /tmp/paper-repro-invalid.out)"
    fi
  fi
}

INVALID_MISSING_LINEAGE="$TEST_DIR/missing-lineage.json"
make_invalid "$INVALID_MISSING_LINEAGE" 'del(.tasks[0].criterion_ids)'
if "$VALIDATOR" "$INVALID_MISSING_LINEAGE" >/tmp/paper-repro-invalid.out 2>&1; then
  fail "task without criterion_ids is rejected" "non-zero exit" "validation passed"
else
  if grep -q "criterion_ids" /tmp/paper-repro-invalid.out; then
    pass "task without criterion_ids is rejected"
  else
    fail "task without criterion_ids error mentions field" "criterion_ids" "$(cat /tmp/paper-repro-invalid.out)"
  fi
fi

INVALID_SINGLE_MULTI="$TEST_DIR/single-multi-lineage.json"
make_invalid "$INVALID_SINGLE_MULTI" '.tasks[0].module_ids=["ALG-001","INT-001"]'
if "$VALIDATOR" "$INVALID_SINGLE_MULTI" >/tmp/paper-repro-invalid.out 2>&1; then
  fail "single lineage task with multiple module_ids is rejected" "non-zero exit" "validation passed"
else
  if grep -q "single" /tmp/paper-repro-invalid.out; then
    pass "single lineage task with multiple module_ids is rejected"
  else
    fail "single lineage task error mentions single" "single" "$(cat /tmp/paper-repro-invalid.out)"
  fi
fi

INVALID_PRIMARY_NOT_IN_ARRAY="$TEST_DIR/primary-not-in-array.json"
make_invalid "$INVALID_PRIMARY_NOT_IN_ARRAY" '.tasks[0].lineage_mode="primary" | .tasks[0].primary_module_id="INT-001"'
if "$VALIDATOR" "$INVALID_PRIMARY_NOT_IN_ARRAY" >/tmp/paper-repro-invalid.out 2>&1; then
  fail "primary lineage task with primary_module_id outside module_ids is rejected" "non-zero exit" "validation passed"
else
  if grep -q "primary_module_id" /tmp/paper-repro-invalid.out; then
    pass "primary lineage task with primary_module_id outside module_ids is rejected"
  else
    fail "primary lineage error mentions primary_module_id" "primary_module_id" "$(cat /tmp/paper-repro-invalid.out)"
  fi
fi

INVALID_CHECKPOINT_COMMANDS="$TEST_DIR/checkpoint-commands.json"
make_invalid "$INVALID_CHECKPOINT_COMMANDS" '.checkpoint_graph.checkpoints[0].commands=["pytest"] | del(.checkpoint_graph.checkpoints[0].verification_commands)'
if "$VALIDATOR" "$INVALID_CHECKPOINT_COMMANDS" >/tmp/paper-repro-invalid.out 2>&1; then
  fail "checkpoint using commands instead of verification_commands is rejected" "non-zero exit" "validation passed"
else
  if grep -q "verification_commands" /tmp/paper-repro-invalid.out; then
    pass "checkpoint using commands instead of verification_commands is rejected"
  else
    fail "checkpoint command error mentions verification_commands" "verification_commands" "$(cat /tmp/paper-repro-invalid.out)"
  fi
fi

INVALID_AGENT_RUN="$TEST_DIR/agent-run-missing-redaction.json"
make_invalid "$INVALID_AGENT_RUN" 'del(.agent_runs[0].redaction_status)'
if "$VALIDATOR" "$INVALID_AGENT_RUN" >/tmp/paper-repro-invalid.out 2>&1; then
  fail "agent run without redaction_status is rejected" "non-zero exit" "validation passed"
else
  if grep -q "redaction_status" /tmp/paper-repro-invalid.out; then
    pass "agent run without redaction_status is rejected"
  else
    fail "agent run error mentions redaction_status" "redaction_status" "$(cat /tmp/paper-repro-invalid.out)"
  fi
fi

expect_invalid_plan "criterion-missing-expected-artifacts" \
  'del(.criteria[0].expected_artifacts)' \
  "expected_artifacts"

expect_invalid_plan "criterion-missing-expected-artifact-kinds" \
  'del(.criteria[0].expected_artifact_kinds)' \
  "expected_artifact_kinds"

expect_invalid_plan "criterion-missing-expected-outputs" \
  'del(.criteria[0].expected_outputs)' \
  "expected_outputs"

expect_invalid_plan "criterion-empty-module-ids" \
  '.criteria[0].module_ids=[]' \
  "module_ids"

expect_invalid_plan "checkpoint-empty-covered-modules" \
  '.checkpoint_graph.checkpoints[0].covered_modules=[]' \
  "covered_modules"

expect_invalid_plan "checkpoint-empty-covered-criteria" \
  '.checkpoint_graph.checkpoints[0].covered_criteria=[]' \
  "covered_criteria"

expect_invalid_plan "checkpoint-missing-reviewer-provider-policy" \
  'del(.checkpoint_graph.checkpoints[0].reviewer_provider_policy)' \
  "reviewer_provider_policy"

expect_invalid_plan "checkpoint-missing-acceptance-rule" \
  'del(.checkpoint_graph.checkpoints[0].acceptance_rule)' \
  "acceptance_rule"

expect_invalid_plan "checkpoint-missing-open-question-policy" \
  'del(.checkpoint_graph.checkpoints[0].open_question_policy)' \
  "open_question_policy"

expect_invalid_plan "checkpoint-missing-fallback-policy" \
  'del(.checkpoint_graph.checkpoints[0].fallback_policy)' \
  "fallback_policy"

expect_invalid_plan "checkpoint-missing-base-snapshot" \
  'del(.checkpoint_graph.checkpoints[0].base_snapshot)' \
  "base_snapshot"

expect_invalid_plan "checkpoint-missing-target-snapshot" \
  'del(.checkpoint_graph.checkpoints[0].target_snapshot)' \
  "target_snapshot"

expect_invalid_plan "checkpoint-missing-changed-paths" \
  'del(.checkpoint_graph.checkpoints[0].changed_paths)' \
  "changed_paths"

expect_invalid_plan "checkpoint-missing-artifact-hashes" \
  'del(.checkpoint_graph.checkpoints[0].artifact_hashes)' \
  "artifact_hashes"

expect_invalid_plan "checkpoint-missing-base-commit" \
  'del(.checkpoint_graph.checkpoints[0].checkpoint_base_commit)' \
  "checkpoint_base_commit"

expect_invalid_plan "agent-run-missing-parent-run-id" \
  'del(.agent_runs[0].parent_run_id)' \
  "parent_run_id"

expect_invalid_plan "agent-run-missing-independence-group" \
  'del(.agent_runs[0].independence_group)' \
  "independence_group"

print_test_summary "Paper Reproduction Plan Tests"
