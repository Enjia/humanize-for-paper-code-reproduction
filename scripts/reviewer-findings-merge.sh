#!/usr/bin/env bash
# reviewer-findings-merge.sh
# Merges checkpoint reviewer findings without dropping reasonable findings or conflicts.

set -euo pipefail

usage() {
    echo "Usage: $0 --output <merged.json> <reviewer-verdict.json>..." >&2
    exit 2
}

OUTPUT_FILE=""
INPUTS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            INPUTS+=("$1")
            shift
            ;;
    esac
done

[[ -n "$OUTPUT_FILE" && "${#INPUTS[@]}" -ge 1 ]] || usage
command -v jq >/dev/null 2>&1 || { echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2; exit 1; }
[[ -d "$(dirname "$OUTPUT_FILE")" ]] || { echo "VALIDATION_ERROR: OUTPUT_DIR_NOT_FOUND" >&2; exit 1; }

for input in "${INPUTS[@]}"; do
    [[ -f "$input" ]] || { echo "VALIDATION_ERROR: REVIEW_NOT_FOUND: $input" >&2; exit 1; }
    jq empty "$input" >/dev/null 2>&1 || { echo "VALIDATION_ERROR: INVALID_REVIEW_JSON: $input" >&2; exit 1; }
done

jq -s '
  def all_reasonable:
    [ .[] as $review
      | ($review.reasonable_findings // [])[]
      | . + {reviewer_run_id: ($review.reviewer_run_id // null), checkpoint_id: ($review.checkpoint_id // null)} ];

  def conflict_groups($findings):
    [ $findings
      | map(select((.conflict_key // "") != "" and (.position // "") != ""))
      | group_by(.conflict_key)
      | .[]
      | select(([.[].position] | unique | length) > 1)
      | {
          conflict_key: .[0].conflict_key,
          positions: ([.[].position] | unique),
          finding_ids: [.[].finding_id],
          reviewer_run_ids: ([.[].reviewer_run_id] | unique),
          action: "arbitrate reviewer disagreement before next checkpoint"
        }
    ];

  all_reasonable as $findings |
  conflict_groups($findings) as $arbitration_tasks |
  {
    checkpoint_id: (.[0].checkpoint_id // null),
    reviewer_run_ids: ([.[].reviewer_run_id] | unique),
    reasonable_findings: $findings,
    conflicting_findings: $arbitration_tasks,
    arbitration_required: (($arbitration_tasks | length) > 0),
    arbitration_tasks: $arbitration_tasks,
    next_prompt_actions: ($findings | map({finding_id, module_id: (.module_id // null), criterion_id: (.criterion_id // null), summary, severity: (.severity // "medium"), reviewer_run_id}))
  }
' "${INPUTS[@]}" > "$OUTPUT_FILE"

echo "REVIEWER_FINDINGS_MERGE_SUCCESS"
echo "Output: $OUTPUT_FILE"
echo "Findings: $(jq '.reasonable_findings | length' "$OUTPUT_FILE")"
echo "Arbitration tasks: $(jq '.arbitration_tasks | length' "$OUTPUT_FILE")"
