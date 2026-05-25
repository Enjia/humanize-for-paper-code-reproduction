#!/usr/bin/env bash
# Tests for paper reproduction checkpoint loop setup and gate validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SETUP_LOOP="$PROJECT_ROOT/scripts/setup-paper-repro-loop.sh"
STATUS_SCRIPT="$PROJECT_ROOT/scripts/paper-repro-status.sh"
CHECKPOINT_VALIDATE="$PROJECT_ROOT/scripts/checkpoint-validate.sh"
HOOK_FILE="$PROJECT_ROOT/hooks/loop-paper-repro-stop-hook.sh"

echo "=========================================="
echo "Paper Repro Loop Tests"
echo "=========================================="
echo ""

setup_test_dir

for file in "$SETUP_LOOP" "$STATUS_SCRIPT" "$CHECKPOINT_VALIDATE" "$HOOK_FILE"; do
  if [[ -x "$file" ]]; then
    pass "$(basename "$file") exists and is executable"
  else
    fail "$(basename "$file") exists and is executable" "executable file" "missing"
  fi
done

PLAN="$TEST_DIR/paper-repro-plan.json"
cat > "$PLAN" <<'JSON'
{
  "schema_version": "paper-repro-plan/v1",
  "created_at": "2026-05-24T00:00:00Z",
  "paper_hash": "sha256:abc",
  "input_sources": [],
  "budget_profile": "smoke",
  "unsupported_items": [],
  "risk_level": "medium",
  "privacy_mode": "local_only",
  "paper": {"title": "Fixture", "paper_types": ["algorithm-experiment"]},
  "workspace": {"path": "paper-repro/fixture"},
  "safety": {},
  "budget": {},
  "feasibility": {},
  "evidence_map": {"claims": [], "methods": [], "experiments": [], "ambiguities": []},
  "decomposition": {"modules": [{"module_id": "ALG-001", "module_type": "algorithm_module", "origin": "paper", "origin_source": "CLAIM-001", "title": "Algorithm", "paper_evidence": ["CLAIM-001"], "depends_on": [], "claims_supported": ["CLAIM-001"], "reproduction_needs": [], "expected_artifact_kinds": [], "verification_targets": [], "ambiguities": [], "risk_level": "medium"}]},
  "criteria": [{"criterion_id": "CRIT-001", "module_ids": ["ALG-001"], "type": "method", "paper_evidence": ["CLAIM-001"], "expected_artifacts": ["src/algorithm.py"], "expected_artifact_kinds": ["source_module"], "expected_outputs": [], "verification_method": "unit_test", "status": "pending", "blocking": true, "open_questions": []}],
  "artifact_profile": {},
  "assumption_ledger": [{"assumption_id": "ASM-001", "status": "open", "text": "driver unknown"}],
  "checkpoint_graph": {"checkpoints": [
    {"checkpoint_id": "CHK-CHILD", "kind": "child", "title": "Child", "depends_on": [], "covered_modules": ["ALG-001"], "covered_criteria": ["CRIT-001"], "expected_artifacts": ["src/algorithm.py"], "verification_commands": ["test -f src/algorithm.py"], "reviewer_count": 1, "reviewer_run_ids": ["RUN-REV-1"], "reviewer_provider_policy": {}, "base_snapshot": null, "target_snapshot": null, "changed_paths": [], "artifact_hashes": {}, "checkpoint_base_commit": null, "acceptance_rule": "all_blocking_criteria_pass", "open_question_policy": "block_if_material", "fallback_policy": "record_assumption", "failure_escalation": "revise_checkpoint"},
    {"checkpoint_id": "CHK-PARENT", "kind": "parent", "title": "Parent", "depends_on": ["CHK-CHILD"], "covered_modules": ["ALG-001"], "covered_criteria": ["CRIT-001"], "expected_artifacts": ["src/algorithm.py"], "verification_commands": ["test -f src/algorithm.py"], "reviewer_count": 2, "reviewer_run_ids": ["RUN-REV-1", "RUN-REV-2"], "reviewer_provider_policy": {}, "base_snapshot": null, "target_snapshot": null, "changed_paths": [], "artifact_hashes": {}, "checkpoint_base_commit": null, "acceptance_rule": "all_blocking_criteria_pass", "open_question_policy": "block_if_material", "fallback_policy": "record_assumption", "failure_escalation": "revise_checkpoint"}
  ]},
  "tasks": [],
  "provider_roles": {},
  "agent_runs": [
    {"run_id": "RUN-REV-1", "role": "checkpoint_reviewer", "parent_run_id": null, "independence_group": "CHK-PARENT", "provider": "mock", "model": "default", "effort": "medium", "tool_policy": {}, "workspace_scope": "read_only", "write_policy": "none", "network_policy": "disabled", "timeout_seconds": 60, "input_artifacts": ["checkpoint-CHK-PARENT-summary.md"], "output_artifacts": ["reviews/rev1.json"], "summary_artifact": "reviews/rev1.md", "redaction_status": "not_needed", "started_at": "2026-05-24T00:00:00Z", "ended_at": "2026-05-24T00:01:00Z", "exit_status": "success"},
    {"run_id": "RUN-REV-2", "role": "checkpoint_reviewer", "parent_run_id": null, "independence_group": "CHK-PARENT", "provider": "mock", "model": "default", "effort": "medium", "tool_policy": {}, "workspace_scope": "read_only", "write_policy": "none", "network_policy": "disabled", "timeout_seconds": 60, "input_artifacts": ["checkpoint-CHK-PARENT-summary.md"], "output_artifacts": ["reviews/rev2.json"], "summary_artifact": "reviews/rev2.md", "redaction_status": "not_needed", "started_at": "2026-05-24T00:00:00Z", "ended_at": "2026-05-24T00:01:00Z", "exit_status": "success"}
  ],
  "review_policy": {"child_reviewers": 1, "parent_reviewers": 2},
  "final_package_contract": {"entrypoint": "reproduce.sh", "results": "results.json"}
}
JSON

mkdir -p "$TEST_DIR/paper-repro/fixture/src"
printf 'def route():\n    return "ok"\n' > "$TEST_DIR/paper-repro/fixture/src/algorithm.py"
mkdir -p "$TEST_DIR/.humanize/memory" "$TEST_DIR/.humanize/skills"
cat > "$TEST_DIR/.humanize/memory/events.jsonl" <<'JSONL'
{"event_id":"EV-001","module_id":"ALG-001","criterion_id":"CRIT-001","checkpoint_id":"CHK-CHILD","paper_hash":"sha256:abc","summary":"parser fix","tags":["algorithm"]}
{"event_id":"EV-002","module_id":"ALG-001","criterion_id":"CRIT-001","checkpoint_id":"CHK-CHILD","paper_hash":"sha256:abc","summary":"review note","tags":["review"]}
JSONL
cat > "$TEST_DIR/.humanize/skills/registry.json" <<'JSON'
{
  "skills": [
    {"skill_id": "benchmark-checklist", "state": "candidate"},
    {"skill_id": "paper-env-audit", "state": "active"}
  ]
}
JSON

if "$SETUP_LOOP" "$PLAN" --state-dir "$TEST_DIR/.humanize/paper-repro" >/tmp/paper-loop-setup.out 2>&1; then
  pass "setup-paper-repro-loop initializes checkpoint state"
else
  fail "setup-paper-repro-loop initializes checkpoint state" "exit 0" "$(cat /tmp/paper-loop-setup.out)"
fi

INVALID_PLAN="$TEST_DIR/invalid-plan.json"
jq 'del(.criteria[0].expected_artifacts)' "$PLAN" > "$INVALID_PLAN"
stderr_out=""
exit_code=0
stderr_out=$("$SETUP_LOOP" "$INVALID_PLAN" --state-dir "$TEST_DIR/.humanize/invalid-paper-repro" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "expected_artifacts" <<<"$stderr_out"; then
  pass "setup-paper-repro-loop rejects invalid manifest before state creation"
else
  fail "setup-paper-repro-loop rejects invalid manifest before state creation" "non-zero manifest validation error" "exit=$exit_code stderr=$stderr_out"
fi

STATE="$TEST_DIR/.humanize/paper-repro/state.json"
if [[ -s "$STATE" ]] && jq -e --arg plan "$PLAN" '.loop_kind == "paper_repro" and .active_checkpoint_id == "CHK-CHILD" and .plan_path == $plan' "$STATE" >/dev/null; then
  pass "paper loop state tracks loop kind and active checkpoint"
else
  fail "paper loop state tracks loop kind and active checkpoint" "state JSON" "$(cat "$STATE" 2>/dev/null || true)"
fi

if "$STATUS_SCRIPT" --state "$STATE" >/tmp/paper-status.out 2>&1 && \
   grep -q "active_checkpoint=CHK-CHILD" /tmp/paper-status.out && \
   grep -q "open_assumptions=1" /tmp/paper-status.out && \
   grep -q "module_coverage=0/1" /tmp/paper-status.out && \
   grep -q "criteria_coverage=0/1" /tmp/paper-status.out && \
   grep -q "reviewer_status=1/1-ready" /tmp/paper-status.out && \
   grep -q "memory_delta=2" /tmp/paper-status.out && \
   grep -q "skill_delta=1" /tmp/paper-status.out && \
   grep -q "reproduction_progress=0/2" /tmp/paper-status.out; then
  pass "paper-repro-status reports checkpoint coverage reviewer status and progress"
else
  fail "paper-repro-status reports checkpoint coverage reviewer status and progress" "status output with coverage and progress" "$(cat /tmp/paper-status.out)"
fi

if "$CHECKPOINT_VALIDATE" --plan "$PLAN" --checkpoint CHK-CHILD >/tmp/checkpoint-validate.out 2>&1; then
  pass "child checkpoint passes with one reviewer"
else
  fail "child checkpoint passes with one reviewer" "exit 0" "$(cat /tmp/checkpoint-validate.out)"
fi

if "$CHECKPOINT_VALIDATE" --plan "$PLAN" --checkpoint CHK-PARENT >/tmp/checkpoint-validate.out 2>&1; then
  pass "parent checkpoint passes with two independent reviewers"
else
  fail "parent checkpoint passes with two independent reviewers" "exit 0" "$(cat /tmp/checkpoint-validate.out)"
fi

HOOK_STATE_DIR="$TEST_DIR/.humanize/hook-paper-repro"
if "$SETUP_LOOP" "$PLAN" --state-dir "$HOOK_STATE_DIR" >/tmp/paper-loop-hook-setup.out 2>&1; then
  pass "hook fixture state initializes"
else
  fail "hook fixture state initializes" "exit 0" "$(cat /tmp/paper-loop-hook-setup.out)"
fi

HOOK_STATE="$HOOK_STATE_DIR/state.json"
if "$HOOK_FILE" --state "$HOOK_STATE" >/tmp/paper-hook.out 2>&1; then
  pass "paper repro stop hook runs checkpoint gate"
else
  fail "paper repro stop hook runs checkpoint gate" "exit 0" "$(cat /tmp/paper-hook.out)"
fi

if [[ -s "$HOOK_STATE" ]] && jq -e '.active_checkpoint_id == "CHK-PARENT" and (.completed_checkpoints | index("CHK-CHILD")) and .status == "in_progress"' "$HOOK_STATE" >/dev/null; then
  pass "paper repro stop hook advances state after passing child checkpoint"
else
  fail "paper repro stop hook advances state after passing child checkpoint" "state advanced to CHK-PARENT" "$(cat "$HOOK_STATE" 2>/dev/null || true)"
fi

if grep -q "checkpoint_advanced=CHK-CHILD" /tmp/paper-hook.out && grep -q "next_checkpoint=CHK-PARENT" /tmp/paper-hook.out; then
  pass "paper repro stop hook reports checkpoint advancement"
else
  fail "paper repro stop hook reports checkpoint advancement" "checkpoint_advanced and next_checkpoint output" "$(cat /tmp/paper-hook.out 2>/dev/null || true)"
fi

MISSING_ARTIFACT_PLAN="$TEST_DIR/missing-artifact-plan.json"
jq '.workspace.path = "paper-repro/missing-fixture"' "$PLAN" > "$MISSING_ARTIFACT_PLAN"
stderr_out=""
exit_code=0
stderr_out=$("$CHECKPOINT_VALIDATE" --plan "$MISSING_ARTIFACT_PLAN" --checkpoint CHK-CHILD 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "expected artifact" <<<"$stderr_out"; then
  pass "checkpoint gate rejects missing expected artifacts before review"
else
  fail "checkpoint gate rejects missing expected artifacts before review" "non-zero expected artifact error" "exit=$exit_code stderr=$stderr_out"
fi

INVALID_CHECKPOINT_PLAN="$TEST_DIR/invalid-checkpoint-plan.json"
jq 'del(.checkpoint_graph.checkpoints[1].acceptance_rule)' "$PLAN" > "$INVALID_CHECKPOINT_PLAN"
stderr_out=""
exit_code=0
stderr_out=$("$CHECKPOINT_VALIDATE" --plan "$INVALID_CHECKPOINT_PLAN" --checkpoint CHK-PARENT 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "acceptance_rule" <<<"$stderr_out"; then
  pass "checkpoint-validate rejects invalid manifest before gate validation"
else
  fail "checkpoint-validate rejects invalid manifest before gate validation" "non-zero manifest validation error" "exit=$exit_code stderr=$stderr_out"
fi

BAD_PARENT="$TEST_DIR/bad-parent.json"
jq '.checkpoint_graph.checkpoints[1].reviewer_run_ids = ["RUN-REV-1"]' "$PLAN" > "$BAD_PARENT"
stderr_out=""
exit_code=0
stderr_out=$("$CHECKPOINT_VALIDATE" --plan "$BAD_PARENT" --checkpoint CHK-PARENT 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "parent checkpoint" <<<"$stderr_out"; then
  pass "parent checkpoint with one reviewer is rejected by loop gate"
else
  fail "parent checkpoint with one reviewer is rejected by loop gate" "non-zero parent reviewer error" "exit=$exit_code stderr=$stderr_out"
fi

DUP_PARENT="$TEST_DIR/duplicate-parent.json"
jq '.checkpoint_graph.checkpoints[1].reviewer_run_ids = ["RUN-REV-1", "RUN-REV-1"]' "$PLAN" > "$DUP_PARENT"
stderr_out=""
exit_code=0
stderr_out=$("$CHECKPOINT_VALIDATE" --plan "$DUP_PARENT" --checkpoint CHK-PARENT 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "distinct" <<<"$stderr_out"; then
  pass "parent checkpoint with duplicated reviewer run ID is rejected by loop gate"
else
  fail "parent checkpoint with duplicated reviewer run ID is rejected by loop gate" "non-zero distinct reviewer error" "exit=$exit_code stderr=$stderr_out"
fi

DUP_OUTPUT="$TEST_DIR/duplicate-output.json"
jq '.agent_runs[1].output_artifacts = ["reviews/rev1.json"]' "$PLAN" > "$DUP_OUTPUT"
stderr_out=""
exit_code=0
stderr_out=$("$CHECKPOINT_VALIDATE" --plan "$DUP_OUTPUT" --checkpoint CHK-PARENT 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "outputs must be separate" <<<"$stderr_out"; then
  pass "parent checkpoint with duplicated reviewer output artifact is rejected by loop gate"
else
  fail "parent checkpoint with duplicated reviewer output artifact is rejected by loop gate" "non-zero separate output error" "exit=$exit_code stderr=$stderr_out"
fi

print_test_summary "Paper Repro Loop Tests"
