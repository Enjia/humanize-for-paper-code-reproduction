#!/usr/bin/env bash
# paper-repro-status.sh
# Prints concise status for checkpoint-aware paper reproduction loop.

set -euo pipefail

usage() {
    echo "Usage: $0 --state <state.json>" >&2
    exit 2
}

STATE_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --state)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            STATE_FILE="$2"
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

[[ -f "$STATE_FILE" ]] || { echo "VALIDATION_ERROR: STATE_NOT_FOUND" >&2; exit 1; }
plan_path="$(jq -r '.plan_path' "$STATE_FILE")"
[[ -f "$plan_path" ]] || { echo "VALIDATION_ERROR: PLAN_NOT_FOUND" >&2; exit 1; }

active_checkpoint="$(jq -r '.active_checkpoint_id' "$STATE_FILE")"
paper_types="$(jq -r '(.paper.paper_types // []) | join(",")' "$plan_path")"
module_count="$(jq '.decomposition.modules | length' "$plan_path")"
criteria_count="$(jq '.criteria | length' "$plan_path")"
open_assumptions="$(jq '[.assumption_ledger[]? | select((.status // "open") == "open")] | length' "$plan_path")"
completed_count="$(jq '.completed_checkpoints | length' "$STATE_FILE")"
checkpoint_count="$(jq '.checkpoint_graph.checkpoints | length' "$plan_path")"
state_dir="$(cd "$(dirname "$STATE_FILE")" && pwd)"
memory_events_file="$(cd "$state_dir/.." && pwd)/memory/events.jsonl"
skill_registry_file="$(cd "$state_dir/.." && pwd)/skills/registry.json"
covered_module_count="$(jq -r --arg checkpoint "$active_checkpoint" '
  (.checkpoint_graph.checkpoints[]? | select(.checkpoint_id == $checkpoint) | (.covered_modules // []) | length) // 0
' "$plan_path")"
covered_criteria_count="$(jq -r --arg checkpoint "$active_checkpoint" '
  (.checkpoint_graph.checkpoints[]? | select(.checkpoint_id == $checkpoint) | (.covered_criteria // []) | length) // 0
' "$plan_path")"
reviewer_ready_count="$(jq -r --arg checkpoint "$active_checkpoint" '
  (.checkpoint_graph.checkpoints[]? | select(.checkpoint_id == $checkpoint) | (.reviewer_run_ids // []) | length) // 0
' "$plan_path")"
reviewer_required_count="$(jq -r --arg checkpoint "$active_checkpoint" '
  (.checkpoint_graph.checkpoints[]? | select(.checkpoint_id == $checkpoint) | (.reviewer_count // 0)) // 0
' "$plan_path")"
if [[ "$reviewer_required_count" -gt 0 && "$reviewer_ready_count" -ge "$reviewer_required_count" ]]; then
    reviewer_status="${reviewer_ready_count}/${reviewer_required_count}-ready"
else
    reviewer_status="${reviewer_ready_count}/${reviewer_required_count}-pending"
fi

memory_delta=0
if [[ -f "$memory_events_file" ]]; then
    memory_delta="$(wc -l < "$memory_events_file" | tr -d ' ')"
fi

skill_delta=0
if [[ -f "$skill_registry_file" ]] && jq -e '.skills | type == "array"' "$skill_registry_file" >/dev/null 2>&1; then
    skill_delta="$(jq '[.skills[]? | select((.state // "") == "candidate")] | length' "$skill_registry_file")"
fi

echo "loop_kind=paper_repro"
echo "paper_types=$paper_types"
echo "active_checkpoint=$active_checkpoint"
echo "module_count=$module_count"
echo "criteria_count=$criteria_count"
echo "completed_checkpoints=$completed_count"
echo "open_assumptions=$open_assumptions"
echo "module_coverage=${completed_count}/${module_count}"
echo "criteria_coverage=${completed_count}/${criteria_count}"
echo "reviewer_status=$reviewer_status"
echo "memory_delta=$memory_delta"
echo "skill_delta=$skill_delta"
echo "reproduction_progress=${completed_count}/${checkpoint_count}"
