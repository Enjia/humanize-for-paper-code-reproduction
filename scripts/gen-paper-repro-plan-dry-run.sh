#!/usr/bin/env bash
# gen-paper-repro-plan-dry-run.sh
# Deterministic Phase 1 pipeline that produces a dry-run paper reproduction plan.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <paper> --output <paper-repro-plan.md> --manifest <paper-repro-plan.json> [--workspace paper-repro/<slug>] [--budget smoke|standard|full] [--paper-type <type>]" >&2
    exit 2
}

INPUT_FILE=""
OUTPUT_FILE=""
MANIFEST_FILE=""
WORKSPACE_PATH="paper-repro/default"
BUDGET="smoke"
PAPER_TYPE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            INPUT_FILE="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --manifest)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            MANIFEST_FILE="$2"
            shift 2
            ;;
        --workspace)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            WORKSPACE_PATH="$2"
            shift 2
            ;;
        --budget)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            BUDGET="$2"
            shift 2
            ;;
        --paper-type)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            PAPER_TYPE_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage
            ;;
    esac
done

[[ -n "$INPUT_FILE" && -n "$OUTPUT_FILE" && -n "$MANIFEST_FILE" ]] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=scripts/lib/config-loader.sh
source "$PROJECT_ROOT/scripts/lib/config-loader.sh"
# shellcheck source=scripts/lib/agent-runner.sh
source "$PROJECT_ROOT/scripts/lib/agent-runner.sh"
# shellcheck source=scripts/lib/provider-router.sh
source "$PROJECT_ROOT/scripts/lib/provider-router.sh"

"$PROJECT_ROOT/scripts/validate-paper-repro-plan-io.sh" \
    --input "$INPUT_FILE" \
    --output "$OUTPUT_FILE" \
    --manifest "$MANIFEST_FILE" \
    --workspace "$WORKSPACE_PATH" \
    --budget "$BUDGET"

SANITIZED="$TMP_DIR/sanitized.json"
CLASSIFICATION="$TMP_DIR/classification.json"
EVIDENCE="$TMP_DIR/evidence-map.json"
DECOMPOSITION="$TMP_DIR/paper-decomposition.json"
AGENT_RUNS_JSONL="$TMP_DIR/agent-runs.jsonl"
PLANNER_A_ARTIFACT="$TMP_DIR/planner-a-plan.json"
PLANNER_B_ARTIFACT="$TMP_DIR/planner-b-plan.json"
SYNTHESIS_ARTIFACT="$TMP_DIR/synthesis.json"
CHECKPOINT_PLAN_ARTIFACT="$TMP_DIR/checkpoint-plan.json"
PLANNER_GROUP="PLAN-GEN-001"

merged_config="$(load_merged_config "$PROJECT_ROOT" "$PWD")"
project_config_path="${HUMANIZE_CONFIG:-$PWD/.humanize/config.json}"
if [[ -f "$project_config_path" ]]; then
    planner_strategy="$(get_config_value "$merged_config" "planner_strategy")"
    planner_strategy="${planner_strategy:-single}"
    planner_a_role_json="$(resolve_provider_role "$merged_config" "planner_a" "$WORKSPACE_PATH")"
    planner_b_role_json="$(resolve_provider_role "$merged_config" "planner_b" "$WORKSPACE_PATH")"
    synthesizer_role_json="$(resolve_provider_role "$merged_config" "planner_synthesizer" "$WORKSPACE_PATH")"
    checkpoint_planner_role_json="$(
        resolve_provider_role "$merged_config" "checkpoint_planner" "$WORKSPACE_PATH" 2>/dev/null || \
        resolve_provider_role "$merged_config" "planner_synthesizer" "$WORKSPACE_PATH" | jq '.role = "checkpoint_planner"'
    )"
else
    planner_strategy="single"
    planner_a_role_json='{"role":"planner_a","provider":"mock","model":"deterministic-fixture","effort":"none","timeout_seconds":60,"sandbox_mode":"read-only","write_policy":"none","network_policy":"disabled","workspace_root":"paper-repro"}'
    planner_b_role_json='{"role":"planner_b","provider":"mock","model":"deterministic-fixture","effort":"none","timeout_seconds":60,"sandbox_mode":"read-only","write_policy":"none","network_policy":"disabled","workspace_root":"paper-repro"}'
    synthesizer_role_json='{"role":"synthesizer","provider":"mock","model":"deterministic-fixture","effort":"none","timeout_seconds":60,"sandbox_mode":"read-only","write_policy":"none","network_policy":"disabled","workspace_root":"paper-repro"}'
    checkpoint_planner_role_json='{"role":"checkpoint_planner","provider":"mock","model":"deterministic-fixture","effort":"none","timeout_seconds":60,"sandbox_mode":"read-only","write_policy":"none","network_policy":"disabled","workspace_root":"paper-repro"}'
fi

"$PROJECT_ROOT/scripts/paper-extract.sh" \
    --input "$INPUT_FILE" \
    --sanitized-output "$SANITIZED" \
    --evidence-output "$EVIDENCE" >/dev/null
if [[ -n "$PAPER_TYPE_OVERRIDE" ]]; then
    "$PROJECT_ROOT/scripts/paper-classify.sh" --input "$INPUT_FILE" --paper-type "$PAPER_TYPE_OVERRIDE" > "$CLASSIFICATION"
else
    "$PROJECT_ROOT/scripts/paper-classify.sh" --input "$INPUT_FILE" > "$CLASSIFICATION"
fi
"$PROJECT_ROOT/scripts/paper-decompose.sh" \
    --evidence "$EVIDENCE" \
    --classification "$CLASSIFICATION" \
    --output "$DECOMPOSITION" >/dev/null

agent_runner_run \
    --role planner_a \
    --provider "$(jq -r '.provider' <<<"$planner_a_role_json")" \
    --model "$(jq -r '.model' <<<"$planner_a_role_json")" \
    --effort "$(jq -r '.effort' <<<"$planner_a_role_json")" \
    --timeout "$(jq -r '.timeout_seconds' <<<"$planner_a_role_json")" \
    --workspace "$WORKSPACE_PATH" \
    --workspace-scope "$(jq -r '.sandbox_mode | gsub("-"; "_")' <<<"$planner_a_role_json")" \
    --write-policy "$(jq -r '.write_policy' <<<"$planner_a_role_json")" \
    --network-policy "$(jq -r '.network_policy' <<<"$planner_a_role_json")" \
    --input-artifact "$EVIDENCE" \
    --input-artifact "$DECOMPOSITION" \
    --output-artifact "$PLANNER_A_ARTIFACT" \
    --manifest "$AGENT_RUNS_JSONL" \
    --independence-group "$PLANNER_GROUP" >/dev/null

agent_runner_run \
    --role planner_b \
    --provider "$(jq -r '.provider' <<<"$planner_b_role_json")" \
    --model "$(jq -r '.model' <<<"$planner_b_role_json")" \
    --effort "$(jq -r '.effort' <<<"$planner_b_role_json")" \
    --timeout "$(jq -r '.timeout_seconds' <<<"$planner_b_role_json")" \
    --workspace "$WORKSPACE_PATH" \
    --workspace-scope "$(jq -r '.sandbox_mode | gsub("-"; "_")' <<<"$planner_b_role_json")" \
    --write-policy "$(jq -r '.write_policy' <<<"$planner_b_role_json")" \
    --network-policy "$(jq -r '.network_policy' <<<"$planner_b_role_json")" \
    --input-artifact "$EVIDENCE" \
    --input-artifact "$DECOMPOSITION" \
    --output-artifact "$PLANNER_B_ARTIFACT" \
    --manifest "$AGENT_RUNS_JSONL" \
    --independence-group "$PLANNER_GROUP" >/dev/null

agent_runner_run \
    --role synthesizer \
    --provider "$(jq -r '.provider' <<<"$synthesizer_role_json")" \
    --model "$(jq -r '.model' <<<"$synthesizer_role_json")" \
    --effort "$(jq -r '.effort' <<<"$synthesizer_role_json")" \
    --timeout "$(jq -r '.timeout_seconds' <<<"$synthesizer_role_json")" \
    --workspace "$WORKSPACE_PATH" \
    --workspace-scope "$(jq -r '.sandbox_mode | gsub("-"; "_")' <<<"$synthesizer_role_json")" \
    --write-policy "$(jq -r '.write_policy' <<<"$synthesizer_role_json")" \
    --network-policy "$(jq -r '.network_policy' <<<"$synthesizer_role_json")" \
    --input-artifact "$PLANNER_A_ARTIFACT" \
    --input-artifact "$PLANNER_B_ARTIFACT" \
    --output-artifact "$SYNTHESIS_ARTIFACT" \
    --manifest "$AGENT_RUNS_JSONL" >/dev/null

agent_runner_run \
    --role checkpoint_planner \
    --provider "$(jq -r '.provider' <<<"$checkpoint_planner_role_json")" \
    --model "$(jq -r '.model' <<<"$checkpoint_planner_role_json")" \
    --effort "$(jq -r '.effort' <<<"$checkpoint_planner_role_json")" \
    --timeout "$(jq -r '.timeout_seconds' <<<"$checkpoint_planner_role_json")" \
    --workspace "$WORKSPACE_PATH" \
    --workspace-scope "$(jq -r '.sandbox_mode | gsub("-"; "_")' <<<"$checkpoint_planner_role_json")" \
    --write-policy "$(jq -r '.write_policy' <<<"$checkpoint_planner_role_json")" \
    --network-policy "$(jq -r '.network_policy' <<<"$checkpoint_planner_role_json")" \
    --input-artifact "$SYNTHESIS_ARTIFACT" \
    --input-artifact "$DECOMPOSITION" \
    --output-artifact "$CHECKPOINT_PLAN_ARTIFACT" \
    --manifest "$AGENT_RUNS_JSONL" >/dev/null

created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
paper_hash="$(jq -r '.source_hash' "$SANITIZED")"
title="$(grep -m1 '^# ' "$INPUT_FILE" | sed 's/^# *//' || true)"
[[ -n "$title" ]] || title="Untitled Paper"

jq -n \
  --arg schema_version "paper-repro-plan/v1" \
  --arg created_at "$created_at" \
  --arg paper_hash "$paper_hash" \
  --arg input_path "$INPUT_FILE" \
  --arg budget "$BUDGET" \
  --arg title "$title" \
  --arg workspace "$WORKSPACE_PATH" \
  --slurpfile sanitized "$SANITIZED" \
  --slurpfile classification "$CLASSIFICATION" \
  --slurpfile evidence "$EVIDENCE" \
  --slurpfile decomposition "$DECOMPOSITION" \
  --slurpfile agent_runs "$AGENT_RUNS_JSONL" \
  --arg planner_group "$PLANNER_GROUP" \
  --arg planner_a_artifact "$PLANNER_A_ARTIFACT" \
  --arg planner_b_artifact "$PLANNER_B_ARTIFACT" \
  --arg synthesis_artifact "$SYNTHESIS_ARTIFACT" \
  --arg checkpoint_plan_artifact "$CHECKPOINT_PLAN_ARTIFACT" \
  --arg planner_strategy "$planner_strategy" \
  --argjson planner_a_role "$planner_a_role_json" \
  --argjson planner_b_role "$planner_b_role_json" \
  --argjson synthesizer_role "$synthesizer_role_json" \
  --argjson checkpoint_planner_role "$checkpoint_planner_role_json" \
  '
  def source_ref: {source_id: "SRC-001", kind: "text", path: $input_path, sha256: $paper_hash};
  def has_type($t): (($classification[0].paper_types // []) | index($t)) != null;
  def criterion($id; $modules; $type; $evidence; $artifacts; $kinds; $outputs; $method; $blocking): {
    criterion_id: $id,
    module_ids: $modules,
    type: $type,
    paper_evidence: $evidence,
    expected_artifacts: $artifacts,
    expected_artifact_kinds: $kinds,
    expected_outputs: $outputs,
    verification_method: $method,
    tolerance: null,
    status: "pending",
    blocking: $blocking,
    open_questions: []
  };
  def finalized_agent_runs: [$agent_runs[] | select((.exit_status // "") != "running" and (.ended_at != null))];
  ($evidence[0].claims[0].evidence_id // "CLAIM-001") as $claim_id |
  ($evidence[0].methods[0].evidence_id // "METHOD-001") as $method_id |
  ($evidence[0].experiments[0].evidence_id // "EXPERIMENT-001") as $experiment_id |
  ($evidence[0].ambiguities[0].evidence_id // "AMBIG-001") as $ambiguity_id |
  ($decomposition[0].modules // []) as $modules |
  ([
    criterion("CRIT-ALG-001"; ["ALG-001"]; "method"; [$method_id]; ["src/", "tests/"]; ["source_module", "unit_test"]; []; "unit_test"; true),
    (if has_type("inference-optimization") then criterion("CRIT-OPT-001"; ["OPT-001", "EXP-001"]; "metric"; [$claim_id, $experiment_id]; ["scripts/benchmark.sh"]; ["benchmark_harness"]; ["throughput", "latency", "memory"]; "benchmark_smoke"; true) else empty end),
    criterion("CRIT-EXP-001"; ["EXP-001", "ENV-001"]; "experiment"; [$experiment_id]; ["environment/", "scripts/"]; ["environment_spec", "result_table"]; ["experiment_metadata"]; "metadata_check"; true),
    criterion("CRIT-EVAL-001"; ["EVAL-001"]; "artifact"; []; ["results.json"]; ["results_json"]; ["results.json"]; "json_schema"; true),
    criterion("CRIT-INT-001"; ["INT-001"]; "artifact"; []; ["reproduce.sh"]; ["reproduce_entrypoint"]; []; "script_exists"; true)
  ]) as $criteria |
  {
    schema_version: $schema_version,
    created_at: $created_at,
    paper_hash: $paper_hash,
    input_sources: [source_ref],
    budget_profile: $budget,
    unsupported_items: [],
    risk_level: "medium",
    privacy_mode: "local_only",
    paper: {title: $title, paper_types: $classification[0].paper_types},
    workspace: {path: $workspace, commit_policy: "source-and-manifest"},
    safety: {paper_text_untrusted: true, supplementary_code_executed: false, threats: $sanitized[0].threats},
    budget: {profile: $budget, network_allowed: false, gpu_allowed: false, full_datasets_allowed: false},
    feasibility: {status: "smoke_only", reasons: ["Phase 1 dry-run manifest; implementation not started"]},
    evidence_map: $evidence[0],
    decomposition: {modules: $modules},
    criteria: $criteria,
    artifact_profile: {
      paper_types: $classification[0].paper_types,
      profile_rule_packs: $classification[0].profile_rule_packs,
      required_artifacts: $classification[0].required_artifacts,
      optional_artifacts: $classification[0].optional_artifacts,
      not_applicable_artifacts: $classification[0].not_applicable_artifacts,
      rationale: $classification[0].classification_reasons,
      source_criteria: ($criteria | map(.criterion_id))
    },
    assumption_ledger: [
      {assumption_id: "ASM-001", source: $ambiguity_id, text: "Underspecified environment details remain open until implementation planning.", status: "open"}
    ],
    checkpoint_graph: {
      checkpoints: [
        {
          checkpoint_id: "CHK-001",
          kind: "parent",
          title: "Dry-run plan completeness",
          depends_on: [],
          covered_modules: ($modules | map(.module_id)),
          covered_criteria: ($criteria | map(.criterion_id)),
          expected_artifacts: ["paper-repro-plan.md", "paper-repro-plan.json"],
          verification_commands: ["scripts/validate-paper-repro-plan.sh paper-repro-plan.json"],
          reviewer_count: 2,
          reviewer_run_ids: [],
          reviewer_provider_policy: {independence: "distinct_run_id"},
          base_snapshot: null,
          target_snapshot: null,
          changed_paths: [],
          artifact_hashes: {},
          checkpoint_base_commit: null,
          acceptance_rule: "all_blocking_criteria_pass",
          open_question_policy: "block_if_material",
          fallback_policy: "record_assumption",
          failure_escalation: "revise_plan"
        }
      ]
    },
    planning_trace: {
      independent_plans: {
        planner_a_artifact: $planner_a_artifact,
        planner_b_artifact: $planner_b_artifact,
        independence_group: $planner_group
      },
      synthesis_artifact: $synthesis_artifact,
      checkpoint_plan_artifact: $checkpoint_plan_artifact,
      synthesis_decisions: [
        {decision_id: "SYN-001", text: "Dry-run synthesis preserves module-bound criteria and checkpoint lineage from both planners."}
      ],
      unresolved_disagreements: [],
      final_review_notes: [
        "Dry-run planning artifacts were produced by mock agent-runner invocations; implementation is deferred to the checkpoint loop."
      ]
    },
    tasks: [
      {
        task_id: "TASK-001",
        title: "Implement core dry-run criteria later",
        lineage_mode: "multi_equal",
        module_ids: ($modules | map(.module_id)),
        criterion_ids: ($criteria | map(.criterion_id)),
        checkpoint_id: "CHK-001",
        expected_files: ["paper-repro-plan.md", "paper-repro-plan.json"],
        commands: ["scripts/validate-paper-repro-plan.sh paper-repro-plan.json"],
        risk_level: "medium",
        budget_impact: "low"
      }
    ],
    provider_roles: {
      planner_strategy: $planner_strategy,
      dry_run: true,
      planner_a: $planner_a_role,
      planner_b: $planner_b_role,
      synthesizer: $synthesizer_role,
      checkpoint_planner: $checkpoint_planner_role
    },
    agent_runs: finalized_agent_runs,
    review_policy: {child_reviewers: 1, parent_reviewers: 2},
    final_package_contract: {entrypoint: "reproduce.sh", results: "results.json", report: "reproduction-report.md"}
  }
  ' > "$MANIFEST_FILE"

"$PROJECT_ROOT/scripts/validate-paper-repro-plan.sh" "$MANIFEST_FILE" >/dev/null

{
    echo "# Paper Reproduction Plan"
    echo ""
    echo "## Paper"
    jq -r '.paper.title' "$MANIFEST_FILE"
    echo ""
    echo "## Paper Types"
    jq -r '.paper.paper_types[] | "- " + .' "$MANIFEST_FILE"
    echo ""
    echo "## Modules"
    jq -r '.decomposition.modules[] | "- " + .module_id + ": " + .title + " (" + .module_type + ", " + .origin + ")"' "$MANIFEST_FILE"
    echo ""
    echo "## Criteria"
    jq -r '.criteria[] | "- " + .criterion_id + ": " + (.module_ids | join(","))' "$MANIFEST_FILE"
    echo ""
    echo "## Checkpoints"
    jq -r '.checkpoint_graph.checkpoints[] | "- " + .checkpoint_id + ": " + .title' "$MANIFEST_FILE"
    echo ""
    echo "## Safety"
    echo "Paper input is untrusted data. Supplementary code was not executed."
} > "$OUTPUT_FILE"

echo "DRY_RUN_SUCCESS"
echo "Output: $OUTPUT_FILE"
echo "Manifest: $MANIFEST_FILE"
