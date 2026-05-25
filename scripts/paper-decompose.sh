#!/usr/bin/env bash
# paper-decompose.sh
# Deterministic module decomposition from evidence map plus artifact profile classification.

set -euo pipefail

usage() {
    echo "Usage: $0 --evidence <evidence-map.json> --classification <classification.json> --output <paper-decomposition.json>" >&2
    exit 2
}

EVIDENCE_FILE=""
CLASSIFICATION_FILE=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --evidence)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            EVIDENCE_FILE="$2"
            shift 2
            ;;
        --classification)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            CLASSIFICATION_FILE="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            OUTPUT_FILE="$2"
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

[[ -n "$EVIDENCE_FILE" && -n "$CLASSIFICATION_FILE" && -n "$OUTPUT_FILE" ]] || usage

if [[ ! -f "$EVIDENCE_FILE" ]]; then
    echo "VALIDATION_ERROR: EVIDENCE_NOT_FOUND" >&2
    exit 1
fi
if [[ ! -r "$CLASSIFICATION_FILE" ]]; then
    echo "VALIDATION_ERROR: CLASSIFICATION_NOT_READABLE" >&2
    exit 1
fi
if [[ ! -d "$(dirname "$OUTPUT_FILE")" ]]; then
    echo "VALIDATION_ERROR: OUTPUT_DIR_NOT_FOUND" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2
    exit 1
fi
if ! jq empty "$EVIDENCE_FILE" >/dev/null 2>&1; then
    echo "VALIDATION_ERROR: INVALID_EVIDENCE_JSON" >&2
    exit 1
fi
if ! jq empty "$CLASSIFICATION_FILE" >/dev/null 2>&1; then
    echo "VALIDATION_ERROR: INVALID_CLASSIFICATION_JSON" >&2
    exit 1
fi

created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
  --arg created_at "$created_at" \
  --slurpfile evidence "$EVIDENCE_FILE" \
  --slurpfile classification "$CLASSIFICATION_FILE" \
  '
  def has_type($t): (($classification[0].paper_types // []) | index($t)) != null;
  def paper_module($id; $type; $origin; $origin_source; $title; $paper_evidence; $depends_on; $claims_supported; $needs; $kinds; $targets; $ambiguities; $risk): {
    module_id: $id,
    module_type: $type,
    origin: $origin,
    origin_source: $origin_source,
    title: $title,
    paper_evidence: $paper_evidence,
    depends_on: $depends_on,
    claims_supported: $claims_supported,
    reproduction_needs: $needs,
    expected_artifact_kinds: $kinds,
    verification_targets: $targets,
    ambiguities: $ambiguities,
    risk_level: $risk
  };
  def module_exp($experiment_id; $claim_id; $ambiguity_id):
    paper_module("EXP-001"; "experiment_design_module"; "paper"; $experiment_id; "Experiment protocol"; [$experiment_id]; ["ALG-001"]; [$claim_id]; ["benchmark protocol", "metric extraction"]; ["benchmark_harness", "result_table"]; ["records metrics from experiment evidence"]; [$ambiguity_id]; "medium");
  ($evidence[0].claims[0].evidence_id // "CLAIM-001") as $claim_id |
  ($evidence[0].methods[0].evidence_id // "METHOD-001") as $method_id |
  ($evidence[0].experiments[0].evidence_id // "EXPERIMENT-001") as $experiment_id |
  ($evidence[0].ambiguities[0].evidence_id // "AMBIG-001") as $ambiguity_id |
  [
    paper_module("ALG-001"; "algorithm_module"; "paper"; $method_id; "Core method"; [$method_id]; []; [$claim_id]; ["reference behavior", "correctness checks"]; ["source_module", "unit_test"]; ["matches method evidence"]; []; "medium"),
    (if has_type("inference-optimization") then paper_module("OPT-001"; "optimization_module"; "paper"; $claim_id; "Inference optimization"; [$claim_id]; ["ALG-001"]; [$claim_id]; ["benchmarkable optimization behavior"]; ["benchmark_harness", "profiling_or_measurement_script"]; ["captures latency and throughput effects"]; []; "medium") else empty end),
    (if has_type("ml-training") then paper_module("TRN-001"; "algorithm_module"; "paper"; $claim_id; "Training procedure"; [$claim_id]; ["ALG-001"]; [$claim_id]; ["training or finetuning reproduction"]; ["training_or_finetuning", "evaluation_script"]; ["captures training claim behavior"]; [$ambiguity_id]; "high") else empty end),
    (if has_type("data-analysis") then paper_module("DATA-001"; "data_module"; "paper"; $experiment_id; "Data pipeline"; [$experiment_id]; []; [$claim_id]; ["data acquisition and transformation lineage"]; ["data_acquisition", "data_cleaning", "data_provenance"]; ["documents data provenance and transformations"]; [$ambiguity_id]; "medium") else empty end),
    (if has_type("numerical-simulation") then paper_module("SIM-001"; "algorithm_module"; "paper"; $method_id; "Simulation solver"; [$method_id]; []; [$claim_id]; ["solver behavior and convergence checks"]; ["solver_implementation", "convergence_test"]; ["matches solver and convergence evidence"]; [$ambiguity_id]; "high") else empty end),
    module_exp($experiment_id; $claim_id; $ambiguity_id),
    paper_module("ENV-001"; "environment_module"; "policy"; "artifact_profile.environment_spec"; "Environment disclosure"; []; []; []; ["software and hardware metadata"]; ["environment_spec"]; ["documents execution environment"]; [$ambiguity_id]; "medium"),
    paper_module("EVAL-001"; "evaluation_module"; "reproduction_contract"; "final_package_contract.results_json"; "Result comparison"; []; ["EXP-001"]; [$claim_id]; ["machine-readable results", "claim comparison"]; ["results_json", "result_extraction"]; ["maps outputs to claims"]; []; "medium"),
    paper_module("INT-001"; "integration_module"; "reproduction_contract"; "final_package_contract.reproduce_sh"; "Reproduction entrypoint"; []; ["ALG-001", "EXP-001", "EVAL-001"]; []; ["top-level reproducible workflow"]; ["reproduce_entrypoint"]; ["provides reproduce.sh contract"]; []; "low")
  ] as $raw_modules |
  {
    schema_version: "paper-decomposition/v1",
    created_at: $created_at,
    paper_hash: ($evidence[0].paper_hash // ""),
    input_sources: ($evidence[0].input_sources // []),
    budget_profile: ($evidence[0].budget_profile // "smoke"),
    unsupported_items: ($evidence[0].unsupported_items // []),
    risk_level: ($evidence[0].risk_level // "medium"),
    privacy_mode: ($evidence[0].privacy_mode // "local_only"),
    modules: $raw_modules
  }
  ' > "$OUTPUT_FILE"

# Enforce decomposer boundary: modules only, no concrete implementation task fields.
if jq -e 'all(.modules[]; (has("expected_files") | not) and (has("commands") | not))' "$OUTPUT_FILE" >/dev/null; then
    :
else
    echo "VALIDATION_ERROR: decomposition contains implementation planning fields" >&2
    exit 1
fi

echo "PAPER_DECOMPOSE_SUCCESS"
echo "Output: $OUTPUT_FILE"
echo "Modules: $(jq '.modules | length' "$OUTPUT_FILE")"
