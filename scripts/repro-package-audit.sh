#!/usr/bin/env bash
# repro-package-audit.sh
# Audits final paper reproduction package contract.

set -euo pipefail

usage() {
    echo "Usage: $0 --workspace <paper-repro-workspace>" >&2
    exit 2
}

WORKSPACE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            WORKSPACE="$2"
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

[[ -n "$WORKSPACE" ]] || usage
[[ -d "$WORKSPACE" ]] || { echo "AUDIT_ERROR: workspace not found: $WORKSPACE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "AUDIT_ERROR: jq is required" >&2; exit 1; }

if [[ ! -x "$WORKSPACE/reproduce.sh" ]]; then
    echo "AUDIT_ERROR: reproduce.sh is missing or not executable" >&2
    exit 1
fi

if [[ ! -s "$WORKSPACE/results.json" ]]; then
    echo "AUDIT_ERROR: results.json is missing" >&2
    exit 1
fi
if ! jq empty "$WORKSPACE/results.json" >/dev/null 2>&1; then
    echo "AUDIT_ERROR: results.json is invalid JSON" >&2
    exit 1
fi
results_schema="$(jq -r '.schema_version // empty' "$WORKSPACE/results.json")"
if [[ "$results_schema" == "paper-repro-results/v1" ]]; then
    if ! jq -e '(.runs | type == "array") and (.summary | type == "object")' "$WORKSPACE/results.json" >/dev/null; then
        echo "AUDIT_ERROR: results.json does not satisfy paper-repro-results/v1 contract" >&2
        exit 1
    fi
    if ! jq -e 'all(.runs[]?; has("checkpoint_id") and has("module_ids") and has("criterion_ids") and has("status"))' "$WORKSPACE/results.json" >/dev/null; then
        echo "AUDIT_ERROR: results.json runs must bind checkpoint_id, module_ids, criterion_ids, and status" >&2
        exit 1
    fi
elif [[ "$results_schema" == "paper-repro-results-index/v1" ]]; then
    if ! jq -e '(.latest_run_id | type == "string") and (.run_ids | type == "array") and (.latest_run.path | type == "string") and (.summary | type == "object")' "$WORKSPACE/results.json" >/dev/null; then
        echo "AUDIT_ERROR: root results.json does not satisfy paper-repro-results-index/v1 contract" >&2
        exit 1
    fi
    latest_run_path="$(jq -r '.latest_run.path' "$WORKSPACE/results.json")"
    case "$latest_run_path" in
        ""|/*|../*|*/../*|..)
            echo "AUDIT_ERROR: latest run result path must stay inside workspace" >&2
            exit 1
            ;;
    esac
    if [[ ! -s "$WORKSPACE/$latest_run_path" ]]; then
        echo "AUDIT_ERROR: latest per-run results.json is missing: $latest_run_path" >&2
        exit 1
    fi
    if ! jq -e '.schema_version == "paper-repro-run-results/v1" and (.run_id | type == "string") and (.checkpoint_results | type == "array") and (.summary | type == "object")' "$WORKSPACE/$latest_run_path" >/dev/null; then
        echo "AUDIT_ERROR: per-run results.json does not satisfy paper-repro-run-results/v1 contract" >&2
        exit 1
    fi
else
    echo "AUDIT_ERROR: results.json does not satisfy a supported paper reproduction results contract" >&2
    exit 1
fi

if [[ ! -s "$WORKSPACE/reproduction-report.md" ]]; then
    echo "AUDIT_ERROR: reproduction-report.md is missing" >&2
    exit 1
fi
if ! grep -q "module_id" "$WORKSPACE/reproduction-report.md" || ! grep -q "criterion_id" "$WORKSPACE/reproduction-report.md" || ! grep -q "checkpoint_id" "$WORKSPACE/reproduction-report.md"; then
    echo "AUDIT_ERROR: reproduction-report.md must map module_id, criterion_id, and checkpoint_id" >&2
    exit 1
fi

while IFS= read -r large_file; do
    rel_path="${large_file#"$WORKSPACE"/}"
    case "$rel_path" in
        outputs/*|src/*|tests/*|scripts/*|environment/*|paper-repro-plan.md|paper-repro-plan.json|reproduction-report.md|results.json|reproduce.sh)
            ;;
        *)
            echo "AUDIT_ERROR: large generated artifact must live under outputs/ or a declared deliverable/source directory: $rel_path" >&2
            exit 1
            ;;
    esac
done < <(find "$WORKSPACE" -type f -size +1024k 2>/dev/null)

echo "REPRO_PACKAGE_AUDIT_SUCCESS"
echo "workspace=$WORKSPACE"
if [[ "$results_schema" == "paper-repro-results-index/v1" ]]; then
    echo "runs=$(jq '.run_ids | length' "$WORKSPACE/results.json")"
else
    echo "runs=$(jq '.runs | length' "$WORKSPACE/results.json")"
fi
