#!/usr/bin/env bash
# validate-paper-repro-plan.sh
# Validates a paper-repro-plan.json manifest for the Phase 1 dry-run gate.

set -euo pipefail

usage() {
    echo "Usage: $0 <paper-repro-plan.json>" >&2
    exit 2
}

PLAN_FILE="${1:-}"
[[ $# -eq 1 ]] || usage

if [[ -z "$PLAN_FILE" ]]; then
    usage
fi

if [[ ! -f "$PLAN_FILE" ]]; then
    echo "VALIDATION_ERROR: PLAN_NOT_FOUND" >&2
    echo "Plan file not found: $PLAN_FILE" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2
    echo "jq is required to validate paper reproduction plans." >&2
    exit 1
fi

if ! jq empty "$PLAN_FILE" >/dev/null 2>&1; then
    echo "VALIDATION_ERROR: INVALID_JSON" >&2
    echo "Plan file is not valid JSON: $PLAN_FILE" >&2
    exit 1
fi

ERRORS=0

error() {
    echo "VALIDATION_ERROR: $1" >&2
    ERRORS=$((ERRORS + 1))
}

require_path() {
    local path="$1"
    if ! jq -e "$path" "$PLAN_FILE" >/dev/null 2>&1; then
        error "missing required field: $path"
    fi
}

require_array() {
    local path="$1"
    if ! jq -e "$path | type == \"array\"" "$PLAN_FILE" >/dev/null 2>&1; then
        error "field must be array: $path"
    fi
}

require_object() {
    local path="$1"
    if ! jq -e "$path | type == \"object\"" "$PLAN_FILE" >/dev/null 2>&1; then
        error "field must be object: $path"
    fi
}

require_item_field() {
    local item_expr="$1"
    local field="$2"
    local label="$3"
    if ! jq -e "$item_expr | has(\"$field\")" "$PLAN_FILE" >/dev/null 2>&1; then
        error "$label.$field is required"
    fi
}

require_item_array() {
    local item_expr="$1"
    local field="$2"
    local label="$3"
    if ! jq -e "$item_expr | has(\"$field\") and (.${field} | type == \"array\")" "$PLAN_FILE" >/dev/null 2>&1; then
        error "$label.$field must be array"
    fi
}

require_item_nonempty_array() {
    local item_expr="$1"
    local field="$2"
    local label="$3"
    if ! jq -e "$item_expr | has(\"$field\") and (.${field} | type == \"array\") and (.${field} | length > 0)" "$PLAN_FILE" >/dev/null 2>&1; then
        error "$label.$field must be non-empty array"
    fi
}

root_fields=(
    .schema_version
    .created_at
    .paper_hash
    .input_sources
    .budget_profile
    .unsupported_items
    .risk_level
    .privacy_mode
    .paper
    .workspace
    .safety
    .budget
    .feasibility
    .evidence_map
    .decomposition
    .criteria
    .artifact_profile
    .assumption_ledger
    .checkpoint_graph
    .tasks
    .provider_roles
    .agent_runs
    .review_policy
    .final_package_contract
)

for field in "${root_fields[@]}"; do
    require_path "$field"
done

require_array .input_sources
require_array .unsupported_items
require_object .evidence_map
require_object .decomposition
require_array .criteria
require_array .assumption_ledger
require_object .checkpoint_graph
require_array .tasks
require_array .agent_runs

module_ids=$(jq -r '.decomposition.modules[]?.module_id // empty' "$PLAN_FILE" | sort -u)
criterion_ids=$(jq -r '.criteria[]?.criterion_id // empty' "$PLAN_FILE" | sort -u)
checkpoint_ids=$(jq -r '.checkpoint_graph.checkpoints[]?.checkpoint_id // empty' "$PLAN_FILE" | sort -u)

contains_line() {
    local needle="$1"
    local haystack="$2"
    printf '%s\n' "$haystack" | grep -Fxq "$needle"
}

# Paper module field and origin checks.
module_count=$(jq '.decomposition.modules | length' "$PLAN_FILE" 2>/dev/null || echo 0)
if [[ "$module_count" -eq 0 ]]; then
    error "decomposition.modules must contain at least one module"
fi

while IFS=$'\t' read -r idx module_id origin origin_source evidence_len; do
    [[ -n "$idx" ]] || continue
    [[ -n "$module_id" && "$module_id" != "null" ]] || error "module[$idx].module_id is required"
    [[ -n "$origin" && "$origin" != "null" ]] || error "module[$idx].origin is required"
    [[ -n "$origin_source" && "$origin_source" != "null" ]] || error "module[$idx].origin_source is required"
    case "$origin" in
        paper)
            if [[ "$evidence_len" -lt 1 ]]; then
                error "paper-origin module '$module_id' must include paper_evidence"
            fi
            ;;
        reproduction_contract|policy|assumption)
            :
            ;;
        *)
            error "module '$module_id' has invalid origin: $origin"
            ;;
    esac
done < <(jq -r '.decomposition.modules // [] | to_entries[] | [.key, (.value.module_id // ""), (.value.origin // ""), (.value.origin_source // ""), ((.value.paper_evidence // []) | length)] | @tsv' "$PLAN_FILE")

# Criteria must bind to existing modules.
criterion_count=$(jq '.criteria | length' "$PLAN_FILE" 2>/dev/null || echo 0)
if [[ "$criterion_count" -eq 0 ]]; then
    error "criteria must contain at least one criterion"
fi

criterion_required_fields=(
    criterion_id
    module_ids
    type
    paper_evidence
    expected_artifacts
    expected_artifact_kinds
    expected_outputs
    verification_method
    status
    blocking
    open_questions
)

criterion_idx=0
while [[ "$criterion_idx" -lt "$criterion_count" ]]; do
    criterion_label="criteria[$criterion_idx]"
    criterion_expr=".criteria[$criterion_idx]"
    for field in "${criterion_required_fields[@]}"; do
        require_item_field "$criterion_expr" "$field" "$criterion_label"
    done
    require_item_nonempty_array "$criterion_expr" module_ids "$criterion_label"
    require_item_array "$criterion_expr" paper_evidence "$criterion_label"
    require_item_array "$criterion_expr" expected_artifacts "$criterion_label"
    require_item_array "$criterion_expr" expected_artifact_kinds "$criterion_label"
    require_item_array "$criterion_expr" expected_outputs "$criterion_label"
    require_item_array "$criterion_expr" open_questions "$criterion_label"
    criterion_idx=$((criterion_idx + 1))
done

while IFS=$'\t' read -r idx criterion_id module_id; do
    [[ -n "$idx" ]] || continue
    if [[ -z "$criterion_id" || "$criterion_id" == "null" ]]; then
        error "criteria[$idx].criterion_id is required"
    fi
    if [[ -z "$module_id" || "$module_id" == "null" ]]; then
        error "criterion '$criterion_id' has empty module_ids"
    elif ! contains_line "$module_id" "$module_ids"; then
        error "criterion '$criterion_id' references unknown module_id '$module_id'"
    fi
done < <(jq -r '.criteria // [] | to_entries[] as $c | ($c.value.module_ids // [])[]? as $m | [$c.key, ($c.value.criterion_id // ""), $m] | @tsv' "$PLAN_FILE")

# Checkpoints must use verification_commands and bind to modules/criteria.
checkpoint_count=$(jq '.checkpoint_graph.checkpoints | length' "$PLAN_FILE" 2>/dev/null || echo 0)
if [[ "$checkpoint_count" -eq 0 ]]; then
    error "checkpoint_graph.checkpoints must contain at least one checkpoint"
fi

checkpoint_required_fields=(
    checkpoint_id
    kind
    title
    depends_on
    covered_modules
    covered_criteria
    expected_artifacts
    verification_commands
    reviewer_count
    reviewer_run_ids
    reviewer_provider_policy
    base_snapshot
    target_snapshot
    changed_paths
    artifact_hashes
    checkpoint_base_commit
    acceptance_rule
    open_question_policy
    fallback_policy
    failure_escalation
)

checkpoint_idx=0
while [[ "$checkpoint_idx" -lt "$checkpoint_count" ]]; do
    checkpoint_label="checkpoint_graph.checkpoints[$checkpoint_idx]"
    checkpoint_expr=".checkpoint_graph.checkpoints[$checkpoint_idx]"
    for field in "${checkpoint_required_fields[@]}"; do
        require_item_field "$checkpoint_expr" "$field" "$checkpoint_label"
    done
    require_item_array "$checkpoint_expr" depends_on "$checkpoint_label"
    require_item_nonempty_array "$checkpoint_expr" covered_modules "$checkpoint_label"
    require_item_nonempty_array "$checkpoint_expr" covered_criteria "$checkpoint_label"
    require_item_array "$checkpoint_expr" expected_artifacts "$checkpoint_label"
    require_item_array "$checkpoint_expr" verification_commands "$checkpoint_label"
    require_item_array "$checkpoint_expr" reviewer_run_ids "$checkpoint_label"
    if ! jq -e "$checkpoint_expr | has(\"reviewer_provider_policy\") and (.reviewer_provider_policy | type == \"object\")" "$PLAN_FILE" >/dev/null 2>&1; then
        error "$checkpoint_label.reviewer_provider_policy must be object"
    fi
    require_item_array "$checkpoint_expr" changed_paths "$checkpoint_label"
    if ! jq -e "$checkpoint_expr | has(\"artifact_hashes\") and (.artifact_hashes | type == \"object\")" "$PLAN_FILE" >/dev/null 2>&1; then
        error "$checkpoint_label.artifact_hashes must be object"
    fi
    checkpoint_idx=$((checkpoint_idx + 1))
done

while IFS=$'\t' read -r idx checkpoint_id has_commands has_verification reviewer_count kind; do
    [[ -n "$idx" ]] || continue
    if [[ "$has_commands" == "true" ]]; then
        error "checkpoint '$checkpoint_id' must use verification_commands, not commands"
    fi
    if [[ "$has_verification" != "true" ]]; then
        error "checkpoint '$checkpoint_id' missing verification_commands"
    fi
    if [[ "$reviewer_count" == "null" || "$reviewer_count" -lt 1 ]]; then
        error "checkpoint '$checkpoint_id' reviewer_count must be >= 1"
    fi
    if [[ "$kind" == "parent" && "$reviewer_count" -lt 2 ]]; then
        error "parent checkpoint '$checkpoint_id' must require at least two reviewers"
    fi
done < <(jq -r '.checkpoint_graph.checkpoints // [] | to_entries[] | [.key, (.value.checkpoint_id // ""), (.value | has("commands")), (.value | has("verification_commands")), (.value.reviewer_count // null), (.value.kind // "")] | @tsv' "$PLAN_FILE")

while IFS=$'\t' read -r checkpoint_id module_id; do
    [[ -n "$checkpoint_id" ]] || continue
    if [[ -z "$module_id" || "$module_id" == "null" ]]; then
        error "checkpoint '$checkpoint_id' has empty covered_modules"
    elif ! contains_line "$module_id" "$module_ids"; then
        error "checkpoint '$checkpoint_id' references unknown covered module '$module_id'"
    fi
done < <(jq -r '.checkpoint_graph.checkpoints // [] | .[] as $c | ($c.covered_modules // [])[]? as $m | [($c.checkpoint_id // ""), $m] | @tsv' "$PLAN_FILE")

while IFS=$'\t' read -r checkpoint_id criterion_id; do
    [[ -n "$checkpoint_id" ]] || continue
    if [[ -z "$criterion_id" || "$criterion_id" == "null" ]]; then
        error "checkpoint '$checkpoint_id' has empty covered_criteria"
    elif ! contains_line "$criterion_id" "$criterion_ids"; then
        error "checkpoint '$checkpoint_id' references unknown covered criterion '$criterion_id'"
    fi
done < <(jq -r '.checkpoint_graph.checkpoints // [] | .[] as $c | ($c.covered_criteria // [])[]? as $cr | [($c.checkpoint_id // ""), $cr] | @tsv' "$PLAN_FILE")

# Implementation task lineage rules.
while IFS=$'\t' read -r idx task_id lineage_mode primary_module_id module_len primary_criterion_id criterion_len checkpoint_id; do
    [[ -n "$idx" ]] || continue
    if [[ -z "$task_id" || "$task_id" == "null" ]]; then
        error "tasks[$idx].task_id is required"
    fi
    case "$lineage_mode" in
        single|primary|multi_equal)
            ;;
        *)
            error "task '$task_id' has invalid lineage_mode '$lineage_mode'"
            ;;
    esac
    if [[ "$module_len" -lt 1 ]]; then
        error "task '$task_id' module_ids must be non-empty"
    fi
    if [[ "$criterion_len" -lt 1 ]]; then
        error "task '$task_id' criterion_ids must be non-empty"
    fi
    if ! contains_line "$checkpoint_id" "$checkpoint_ids"; then
        error "task '$task_id' references unknown checkpoint_id '$checkpoint_id'"
    fi
    if [[ "$lineage_mode" == "single" ]]; then
        if [[ "$module_len" -ne 1 || "$criterion_len" -ne 1 ]]; then
            error "task '$task_id' lineage_mode single requires exactly one module_id and one criterion_id"
        fi
        only_module=$(jq -r --argjson i "$idx" '.tasks[$i].module_ids[0] // ""' "$PLAN_FILE")
        only_criterion=$(jq -r --argjson i "$idx" '.tasks[$i].criterion_ids[0] // ""' "$PLAN_FILE")
        if [[ "$primary_module_id" != "$only_module" ]]; then
            error "task '$task_id' single primary_module_id must equal its only module_id"
        fi
        if [[ "$primary_criterion_id" != "$only_criterion" ]]; then
            error "task '$task_id' single primary_criterion_id must equal its only criterion_id"
        fi
    elif [[ "$lineage_mode" == "primary" ]]; then
        if [[ -z "$primary_module_id" || "$primary_module_id" == "__MISSING__" || "$primary_module_id" == "null" ]]; then
            error "task '$task_id' primary_module_id is required for primary lineage_mode"
        elif ! jq -e --argjson i "$idx" --arg id "$primary_module_id" '.tasks[$i].module_ids | index($id)' "$PLAN_FILE" >/dev/null; then
            error "task '$task_id' primary_module_id must be present in module_ids"
        fi
        if [[ -z "$primary_criterion_id" || "$primary_criterion_id" == "__MISSING__" || "$primary_criterion_id" == "null" ]]; then
            error "task '$task_id' primary_criterion_id is required for primary lineage_mode"
        elif ! jq -e --argjson i "$idx" --arg id "$primary_criterion_id" '.tasks[$i].criterion_ids | index($id)' "$PLAN_FILE" >/dev/null; then
            error "task '$task_id' primary_criterion_id must be present in criterion_ids"
        fi
    elif [[ "$lineage_mode" == "multi_equal" ]]; then
        if jq -e --argjson i "$idx" '.tasks[$i] | has("primary_module_id") or has("primary_criterion_id")' "$PLAN_FILE" >/dev/null; then
            error "task '$task_id' multi_equal must omit primary_module_id and primary_criterion_id"
        fi
    fi
done < <(jq -r '.tasks // [] | to_entries[] | [.key, (.value.task_id // ""), (.value.lineage_mode // ""), (.value.primary_module_id // "__MISSING__"), ((.value.module_ids // []) | length), (.value.primary_criterion_id // "__MISSING__"), ((.value.criterion_ids // []) | length), (.value.checkpoint_id // "__MISSING__")] | @tsv' "$PLAN_FILE")

while IFS=$'\t' read -r idx task_id module_id; do
    [[ -n "$idx" ]] || continue
    if ! contains_line "$module_id" "$module_ids"; then
        error "task '$task_id' references unknown module_id '$module_id'"
    fi
done < <(jq -r '.tasks // [] | to_entries[] as $t | ($t.value.module_ids // [])[]? as $m | [$t.key, ($t.value.task_id // ""), $m] | @tsv' "$PLAN_FILE")

while IFS=$'\t' read -r idx task_id criterion_id; do
    [[ -n "$idx" ]] || continue
    if ! contains_line "$criterion_id" "$criterion_ids"; then
        error "task '$task_id' references unknown criterion_id '$criterion_id'"
    fi
done < <(jq -r '.tasks // [] | to_entries[] as $t | ($t.value.criterion_ids // [])[]? as $c | [$t.key, ($t.value.task_id // ""), $c] | @tsv' "$PLAN_FILE")

# Agent run audit fields.
agent_run_required_fields=(
    run_id
    role
    parent_run_id
    independence_group
    provider
    model
    effort
    tool_policy
    workspace_scope
    write_policy
    network_policy
    timeout_seconds
    input_artifacts
    output_artifacts
    summary_artifact
    redaction_status
    started_at
    ended_at
    exit_status
)

agent_run_count=$(jq '.agent_runs | length' "$PLAN_FILE" 2>/dev/null || echo 0)
agent_run_idx=0
while [[ "$agent_run_idx" -lt "$agent_run_count" ]]; do
    agent_run_label="agent_runs[$agent_run_idx]"
    agent_run_expr=".agent_runs[$agent_run_idx]"
    for field in "${agent_run_required_fields[@]}"; do
        require_item_field "$agent_run_expr" "$field" "$agent_run_label"
    done
    if ! jq -e "$agent_run_expr | has(\"tool_policy\") and (.tool_policy | type == \"object\")" "$PLAN_FILE" >/dev/null 2>&1; then
        error "$agent_run_label.tool_policy must be object"
    fi
    require_item_array "$agent_run_expr" input_artifacts "$agent_run_label"
    require_item_array "$agent_run_expr" output_artifacts "$agent_run_label"
    agent_run_idx=$((agent_run_idx + 1))
done

while IFS=$'\t' read -r idx run_id role redaction_status timeout; do
    [[ -n "$idx" ]] || continue
    [[ -n "$run_id" && "$run_id" != "null" ]] || error "agent_runs[$idx].run_id is required"
    [[ -n "$role" && "$role" != "null" ]] || error "agent_run '$run_id' role is required"
    case "$redaction_status" in
        not_needed|redacted|blocked)
            ;;
        *)
            error "agent_run '$run_id' redaction_status must be not_needed, redacted, or blocked"
            ;;
    esac
    if [[ "$timeout" == "null" || "$timeout" -lt 1 ]]; then
        error "agent_run '$run_id' timeout_seconds must be >= 1"
    fi
done < <(jq -r '.agent_runs // [] | to_entries[] | [.key, (.value.run_id // ""), (.value.role // ""), (.value.redaction_status // ""), (.value.timeout_seconds // null)] | @tsv' "$PLAN_FILE")

if [[ "$ERRORS" -ne 0 ]]; then
    echo "VALIDATION_FAILED: $ERRORS error(s)" >&2
    exit 1
fi

echo "VALIDATION_SUCCESS"
echo "Plan file: $PLAN_FILE"
echo "Modules: $module_count"
echo "Criteria: $criterion_count"
echo "Checkpoints: $checkpoint_count"
echo "Tasks: $(jq '.tasks | length' "$PLAN_FILE")"
echo "Agent runs: $(jq '.agent_runs | length' "$PLAN_FILE")"
