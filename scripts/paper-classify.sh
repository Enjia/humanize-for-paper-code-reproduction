#!/usr/bin/env bash
# paper-classify.sh
# Deterministic fixture-oriented paper type classifier for Phase 1 dry runs.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <paper-text> [--paper-type <profile-id>]" >&2
    exit 2
}

INPUT_FILE=""
OVERRIDE_TYPE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            INPUT_FILE="$2"
            shift 2
            ;;
        --paper-type)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            OVERRIDE_TYPE="$2"
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

[[ -n "$INPUT_FILE" ]] || usage

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "VALIDATION_ERROR: INPUT_NOT_FOUND" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_DIR="$PROJECT_ROOT/profiles"

valid_type() {
    [[ -f "$PROFILE_DIR/$1.json" ]]
}

text_lower=$(tr '[:upper:]' '[:lower:]' < "$INPUT_FILE")

declare -a types=()
declare -a reasons=()

add_type() {
    local t="$1"
    local r="$2"
    for existing in "${types[@]:-}"; do
        [[ "$existing" == "$t" ]] && return
    done
    types+=("$t")
    reasons+=("$r")
}

if [[ -n "$OVERRIDE_TYPE" ]]; then
    if ! valid_type "$OVERRIDE_TYPE"; then
        echo "VALIDATION_ERROR: UNKNOWN_PAPER_TYPE" >&2
        echo "Unknown paper type: $OVERRIDE_TYPE" >&2
        exit 1
    fi
    add_type "$OVERRIDE_TYPE" "explicit override"
else
    if grep -Eiq 'inference|latency|throughput|tokens per second|kernel|gpu memory|profiler|warmup' <<< "$text_lower"; then
        add_type "inference-optimization" "matched inference optimization benchmark terms"
    fi
    if grep -Eiq 'training|fine-?tuning|epoch|checkpoint|optimizer|backprop' <<< "$text_lower"; then
        add_type "ml-training" "matched training terms"
    fi
    if grep -Eiq 'compiler|linker|optimization pass|ir|assembly|code generation' <<< "$text_lower"; then
        add_type "compiler" "matched compiler terms"
    fi
    if grep -Eiq 'system|distributed|operating system|benchmark workload|configuration flags' <<< "$text_lower"; then
        add_type "systems" "matched systems terms"
    fi
    if grep -Eiq 'simulation|solver|partial differential|finite[- ]volume|mesh|convergence|analytic solution|precision' <<< "$text_lower"; then
        add_type "numerical-simulation" "matched numerical simulation terms"
    fi
    if grep -Eiq 'dataset|clean|feature|statistical test|empirical study|figure|table|provenance' <<< "$text_lower"; then
        add_type "data-analysis" "matched data analysis terms"
    fi
    if grep -Eiq 'algorithm|correctness|complexity|synthetic instance|benchmark instance' <<< "$text_lower"; then
        add_type "algorithm-experiment" "matched algorithm experiment terms"
    fi
fi

if [[ "${#types[@]}" -eq 0 ]]; then
    add_type "algorithm-experiment" "default fallback for computational paper dry run"
fi

json_types=$(printf '%s\n' "${types[@]}" | jq -R . | jq -s .)
json_reasons=$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)

required=$(jq -n '[]')
optional=$(jq -n '[]')
not_applicable=$(jq -n '[]')

for t in "${types[@]}"; do
    profile="$PROFILE_DIR/$t.json"
    required=$(jq -n --argjson a "$required" --slurpfile p "$profile" '$a + ($p[0].required_artifact_kinds // []) | unique')
    optional=$(jq -n --argjson a "$optional" --slurpfile p "$profile" '$a + ($p[0].optional_artifact_kinds // []) | unique')
    not_applicable=$(jq -n --argjson a "$not_applicable" --slurpfile p "$profile" '$a + ($p[0].not_applicable_artifact_kinds // []) | unique')
done

jq -n \
    --argjson paper_types "$json_types" \
    --argjson reasons "$json_reasons" \
    --argjson required "$required" \
    --argjson optional "$optional" \
    --argjson not_applicable "$not_applicable" \
    --arg override_applied "$([[ -n "$OVERRIDE_TYPE" ]] && echo true || echo false)" \
    '{
      schema_version: "paper-classification/v1",
      paper_types: $paper_types,
      classification_reasons: $reasons,
      profile_rule_packs: $paper_types,
      required_artifacts: $required,
      optional_artifacts: $optional,
      not_applicable_artifacts: $not_applicable,
      override_applied: ($override_applied == "true")
    }'
