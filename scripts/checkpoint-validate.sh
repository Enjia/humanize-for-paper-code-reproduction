#!/usr/bin/env bash
# checkpoint-validate.sh
# Validates paper reproduction checkpoint gate conditions.

set -euo pipefail

usage() {
    echo "Usage: $0 --plan <paper-repro-plan.json> --checkpoint <checkpoint_id>" >&2
    exit 2
}

PLAN_FILE=""
CHECKPOINT_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            PLAN_FILE="$2"
            shift 2
            ;;
        --checkpoint)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            CHECKPOINT_ID="$2"
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

[[ -n "$PLAN_FILE" && -n "$CHECKPOINT_ID" ]] || usage
[[ -f "$PLAN_FILE" ]] || { echo "VALIDATION_ERROR: PLAN_NOT_FOUND" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
"$SCRIPT_DIR/validate-paper-repro-plan.sh" "$PLAN_FILE" >/dev/null

checkpoint_json="$(jq -c --arg id "$CHECKPOINT_ID" '.checkpoint_graph.checkpoints[]? | select(.checkpoint_id == $id)' "$PLAN_FILE")"
if [[ -z "$checkpoint_json" ]]; then
    echo "VALIDATION_ERROR: checkpoint not found: $CHECKPOINT_ID" >&2
    exit 1
fi

plan_dir="$(cd "$(dirname "$PLAN_FILE")" && pwd)"
workspace_path="$(jq -r '.workspace.path // empty' "$PLAN_FILE")"
if [[ -z "$workspace_path" || "$workspace_path" == "null" ]]; then
    echo "VALIDATION_ERROR: workspace.path is required for checkpoint artifact validation" >&2
    exit 1
fi
case "$workspace_path" in
    /*) workspace_root="$workspace_path" ;;
    *) workspace_root="$plan_dir/$workspace_path" ;;
esac

kind="$(jq -r '.kind' <<<"$checkpoint_json")"
reviewer_count="$(jq -r '.reviewer_count // 0' <<<"$checkpoint_json")"
reviewer_ids_json="$(jq -c '.reviewer_run_ids // []' <<<"$checkpoint_json")"
reviewer_id_count="$(jq 'length' <<<"$reviewer_ids_json")"
unique_reviewer_id_count="$(jq 'unique | length' <<<"$reviewer_ids_json")"

if [[ "$kind" == "child" ]]; then
    if [[ "$reviewer_count" -lt 1 || "$reviewer_id_count" -lt 1 ]]; then
        echo "VALIDATION_ERROR: child checkpoint requires one reviewer verdict" >&2
        exit 1
    fi
elif [[ "$kind" == "parent" ]]; then
    if [[ "$reviewer_count" -lt 2 || "$reviewer_id_count" -lt 2 ]]; then
        echo "VALIDATION_ERROR: parent checkpoint requires two reviewer verdicts" >&2
        exit 1
    fi
    if [[ "$unique_reviewer_id_count" -ne "$reviewer_id_count" ]]; then
        echo "VALIDATION_ERROR: parent checkpoint reviewer run IDs must be distinct" >&2
        exit 1
    fi

    runs_json="$(jq -c --argjson ids "$reviewer_ids_json" '[.agent_runs[]? | select(.run_id as $id | $ids | index($id))]' "$PLAN_FILE")"
    run_count="$(jq 'length' <<<"$runs_json")"
    if [[ "$run_count" -lt "$reviewer_id_count" ]]; then
        echo "VALIDATION_ERROR: parent checkpoint reviewer run IDs must exist in agent_runs" >&2
        exit 1
    fi
    group_count="$(jq '[.[].independence_group] | unique | length' <<<"$runs_json")"
    if [[ "$group_count" -ne 1 ]]; then
        echo "VALIDATION_ERROR: parent checkpoint reviewer runs must share an independence_group" >&2
        exit 1
    fi
    group_value="$(jq -r '.[0].independence_group // empty' <<<"$runs_json")"
    if [[ -z "$group_value" || "$group_value" == "null" ]]; then
        echo "VALIDATION_ERROR: parent checkpoint reviewer runs require independence_group" >&2
        exit 1
    fi
    output_count="$(jq '[.[] | ((.output_artifacts // [])[]?, (.summary_artifact // empty))] | length' <<<"$runs_json")"
    unique_output_count="$(jq '[.[] | ((.output_artifacts // [])[]?, (.summary_artifact // empty))] | unique | length' <<<"$runs_json")"
    if [[ "$output_count" -eq 0 || "$unique_output_count" -ne "$output_count" ]]; then
        echo "VALIDATION_ERROR: parent checkpoint reviewer outputs must be separate" >&2
        exit 1
    fi
else
    echo "VALIDATION_ERROR: unknown checkpoint kind: $kind" >&2
    exit 1
fi

if jq -e '(.covered_modules // []) | length >= 1' <<<"$checkpoint_json" >/dev/null && jq -e '(.covered_criteria // []) | length >= 1' <<<"$checkpoint_json" >/dev/null; then
    :
else
    echo "VALIDATION_ERROR: checkpoint must cover modules and criteria" >&2
    exit 1
fi

if jq -e 'has("verification_commands") and (has("commands") | not)' <<<"$checkpoint_json" >/dev/null; then
    :
else
    echo "VALIDATION_ERROR: checkpoint must use verification_commands and not commands" >&2
    exit 1
fi

while IFS= read -r artifact; do
    [[ -n "$artifact" ]] || continue
    case "$artifact" in
        /*|../*|*/../*|..)
            echo "VALIDATION_ERROR: checkpoint expected artifact path must stay inside workspace: $artifact" >&2
            exit 1
            ;;
    esac
    if [[ ! -e "$workspace_root/$artifact" ]]; then
        echo "VALIDATION_ERROR: missing checkpoint expected artifact before review: $artifact" >&2
        exit 1
    fi
done < <(jq -r '.expected_artifacts[]?' <<<"$checkpoint_json")

echo "CHECKPOINT_VALIDATION_SUCCESS"
echo "checkpoint_id=$CHECKPOINT_ID"
echo "kind=$kind"
echo "reviewer_run_ids=$reviewer_id_count"
