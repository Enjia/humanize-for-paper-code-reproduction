#!/usr/bin/env bash
# Audited paper-run-scoped agent runner with mock provider support.

[[ -n "${_AGENT_RUNNER_LOADED:-}" ]] && return 0 2>/dev/null || true
_AGENT_RUNNER_LOADED=1

_AGENT_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib/provider-router.sh
source "$_AGENT_RUNNER_DIR/provider-router.sh"
# shellcheck source=scripts/lib/provider-codex.sh
source "$_AGENT_RUNNER_DIR/provider-codex.sh"
# shellcheck source=scripts/lib/provider-claude.sh
source "$_AGENT_RUNNER_DIR/provider-claude.sh"

agent_runner_error() {
    echo "Error: $*" >&2
}

agent_runner_abs_path() {
    local path="${1:-}"
    if [[ "$path" = /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "$PWD" "$path"
    fi
}

agent_runner_is_within() {
    local child parent
    child="$(agent_runner_abs_path "$1")"
    parent="$(agent_runner_abs_path "$2")"
    [[ "$child" == "$parent" || "$child" == "$parent"/* ]]
}

agent_runner_new_run_id() {
    local role="${1:-agent}"
    local ts rand clean_role
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    rand="${RANDOM}${RANDOM}"
    clean_role="$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '-')"
    echo "RUN-${clean_role}-${ts}-${rand}"
}

agent_runner_build_record() {
    local record_exit_status="${1:-running}"
    local record_ended_at="${2:-null}"
    local record_redaction_status="${3:-not_needed}"
    local ended_json

    if [[ "$record_ended_at" == "null" || -z "$record_ended_at" ]]; then
        ended_json="null"
    else
        ended_json="$(jq -n --arg v "$record_ended_at" '$v')"
    fi

    jq -n \
        --arg run_id "$run_id" \
        --arg role "$role" \
        --arg provider "$provider" \
        --arg model "$model" \
        --arg effort "$effort" \
        --arg workspace_scope "$workspace_scope" \
        --arg write_policy "$write_policy" \
        --arg network_policy "$network_policy" \
        --argjson timeout_seconds "$timeout" \
        --argjson input_artifacts "$input_json" \
        --argjson output_artifacts "$output_json" \
        --argjson summary_artifact "$summary_json" \
        --argjson parent_run_id "$parent_json" \
        --argjson independence_group "$group_json" \
        --arg redaction_status "$record_redaction_status" \
        --arg started_at "$started_at" \
        --argjson ended_at "$ended_json" \
        --arg exit_status "$record_exit_status" \
        '{run_id:$run_id, role:$role, parent_run_id:$parent_run_id, independence_group:$independence_group, provider:$provider, model:$model, effort:$effort, tool_policy:{tools:[$provider]}, workspace_scope:$workspace_scope, write_policy:$write_policy, network_policy:$network_policy, timeout_seconds:$timeout_seconds, input_artifacts:$input_artifacts, output_artifacts:$output_artifacts, summary_artifact:$summary_artifact, redaction_status:$redaction_status, started_at:$started_at, ended_at:$ended_at, exit_status:$exit_status}'
}

agent_runner_provider_binary() {
    local target_provider="${1:-}"
    case "$target_provider" in
        mock)
            printf 'mock\n'
            ;;
        codex)
            provider_codex_binary
            ;;
        claude)
            provider_claude_binary
            ;;
        *)
            agent_runner_error "Unknown provider '$target_provider'."
            return 1
            ;;
    esac
}

agent_runner_execute_provider() {
    local binary role_json
    local cmd=()

    role_json="$(jq -n --arg role "$role" --arg provider "$provider" '{role:$role, provider:$provider}')"
    check_provider_role_dependency "$role_json" || return 10

    binary="$(agent_runner_provider_binary "$provider")" || return 11
    cmd=("$binary"
        "--role" "$role"
        "--model" "$model"
        "--effort" "$effort"
        "--timeout" "$timeout"
        "--workspace" "$workspace"
        "--workspace-scope" "$workspace_scope"
        "--write-policy" "$write_policy"
        "--network-policy" "$network_policy"
        "--run-id" "$run_id")

    local artifact
    for artifact in "${input_artifacts[@]}"; do
        cmd+=("--input-artifact" "$artifact")
    done
    for artifact in "${output_artifacts[@]}"; do
        cmd+=("--output-artifact" "$artifact")
    done
    if [[ -n "$summary_artifact" && "$summary_artifact" != "null" ]]; then
        cmd+=("--summary-artifact" "$summary_artifact")
    fi

    "${cmd[@]}"
}

agent_runner_run() {
    local role="" provider="mock" model="default" effort="medium" timeout="60"
    local workspace="" workspace_scope="read_only" write_policy="none" network_policy="disabled"
    local manifest="" summary_artifact="" parent_run_id="null" independence_group="null"
    local input_artifacts=() output_artifacts=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --role) role="$2"; shift 2 ;;
            --provider) provider="$2"; shift 2 ;;
            --model) model="$2"; shift 2 ;;
            --effort) effort="$2"; shift 2 ;;
            --timeout|--timeout-seconds) timeout="$2"; shift 2 ;;
            --workspace) workspace="$2"; shift 2 ;;
            --workspace-scope) workspace_scope="$2"; shift 2 ;;
            --write-policy) write_policy="$2"; shift 2 ;;
            --network-policy) network_policy="$2"; shift 2 ;;
            --input-artifact) input_artifacts+=("$2"); shift 2 ;;
            --output-artifact) output_artifacts+=("$2"); shift 2 ;;
            --summary-artifact) summary_artifact="$2"; shift 2 ;;
            --manifest) manifest="$2"; shift 2 ;;
            --parent-run-id) parent_run_id="$2"; shift 2 ;;
            --independence-group) independence_group="$2"; shift 2 ;;
            *) agent_runner_error "Unknown option: $1"; return 2 ;;
        esac
    done

    [[ -n "$role" ]] || { agent_runner_error "--role is required."; return 2; }
    [[ -n "$workspace" ]] || { agent_runner_error "--workspace is required."; return 2; }
    [[ -n "$manifest" ]] || { agent_runner_error "--manifest is required."; return 2; }
    [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -ge 1 ]] || { agent_runner_error "--timeout must be >= 1."; return 2; }

    local output
    for output in "${output_artifacts[@]}"; do
        if [[ "$workspace_scope" == "read_only" || "$write_policy" == "none" ]]; then
            if agent_runner_is_within "$output" "$workspace"; then
                agent_runner_error "read-only role '$role' cannot write to reproduction workspace: $output"
                return 1
            fi
        fi
        if [[ "$write_policy" == "workspace-only" ]]; then
            if ! agent_runner_is_within "$output" "$workspace"; then
                agent_runner_error "worker role '$role' cannot write outside configured reproduction workspace: $output"
                return 1
            fi
        fi
    done
    if [[ -n "$summary_artifact" && "$write_policy" == "workspace-only" ]]; then
        if ! agent_runner_is_within "$summary_artifact" "$workspace"; then
            agent_runner_error "worker role '$role' cannot write summary outside configured reproduction workspace: $summary_artifact"
            return 1
        fi
    fi
    if [[ -n "$summary_artifact" && "$summary_artifact" != "null" ]]; then
        if [[ "$workspace_scope" == "read_only" || "$write_policy" == "none" ]]; then
            if agent_runner_is_within "$summary_artifact" "$workspace"; then
                agent_runner_error "read-only role '$role' cannot write summary to reproduction workspace: $summary_artifact"
                return 1
            fi
        fi
    fi

    local started_at ended_at run_id exit_status redaction_status
    started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run_id="$(agent_runner_new_run_id "$role")"
    exit_status="success"
    redaction_status="not_needed"

    local input_json output_json summary_json parent_json group_json record
    input_json="$(printf '%s\n' "${input_artifacts[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
    output_json="$(printf '%s\n' "${output_artifacts[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
    if [[ -n "$summary_artifact" && "$summary_artifact" != "null" ]]; then
        summary_json="$(jq -n --arg v "$summary_artifact" '$v')"
    else
        summary_json="null"
    fi
    if [[ "$parent_run_id" == "null" || -z "$parent_run_id" ]]; then parent_json="null"; else parent_json="$(jq -n --arg v "$parent_run_id" '$v')"; fi
    if [[ "$independence_group" == "null" || -z "$independence_group" ]]; then group_json="null"; else group_json="$(jq -n --arg v "$independence_group" '$v')"; fi

    mkdir -p "$(dirname "$manifest")"
    record="$(agent_runner_build_record "running" "null" "$redaction_status")"
    printf '%s\n' "$record" >> "$manifest"

    if [[ "$provider" == "mock" ]]; then
        for output in "${output_artifacts[@]}"; do
            mkdir -p "$(dirname "$output")"
            jq -n --arg run_id "$run_id" --arg role "$role" '{generated_by:$run_id, role:$role, mock:true}' > "$output"
        done
        if [[ -n "$summary_artifact" && "$summary_artifact" != "null" ]]; then
            mkdir -p "$(dirname "$summary_artifact")"
            printf 'Mock agent run %s for role %s\n' "$run_id" "$role" > "$summary_artifact"
        fi
    else
        if ! agent_runner_execute_provider; then
            case "$?" in
                10|11)
                    exit_status="blocked"
                    redaction_status="blocked"
                    ;;
                *)
                    exit_status="failed"
                    ;;
            esac
            ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            record="$(agent_runner_build_record "$exit_status" "$ended_at" "$redaction_status")"
            printf '%s\n' "$record" >> "$manifest"
            printf '%s\n' "$record"
            return 1
        fi
    fi

    for output in "${output_artifacts[@]}"; do
        if [[ ! -f "$output" ]]; then
            agent_runner_error "declared output artifact was not created: $output"
            exit_status="failed"
            ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            record="$(agent_runner_build_record "$exit_status" "$ended_at" "$redaction_status")"
            printf '%s\n' "$record" >> "$manifest"
            printf '%s\n' "$record"
            return 1
        fi
    done
    if [[ -n "$summary_artifact" && "$summary_artifact" != "null" && ! -f "$summary_artifact" ]]; then
        agent_runner_error "declared summary artifact was not created: $summary_artifact"
        exit_status="failed"
        ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        record="$(agent_runner_build_record "$exit_status" "$ended_at" "$redaction_status")"
        printf '%s\n' "$record" >> "$manifest"
        printf '%s\n' "$record"
        return 1
    fi

    ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    record="$(agent_runner_build_record "$exit_status" "$ended_at" "$redaction_status")"
    printf '%s\n' "$record" >> "$manifest"
    printf '%s\n' "$record"
}

agent_runner_validate_independence() {
    local runs_file="${1:-}"
    local independence_group="${2:-}"
    local required_count="${3:-2}"

    [[ -f "$runs_file" ]] || { agent_runner_error "Agent run file not found: $runs_file"; return 1; }
    [[ -n "$independence_group" ]] || { agent_runner_error "independence_group is required."; return 1; }
    [[ "$required_count" =~ ^[0-9]+$ && "$required_count" -ge 1 ]] || { agent_runner_error "required_count must be >= 1."; return 1; }

    local filtered count unique_runs unique_outputs duplicate_run duplicate_output
    filtered="$(jq -s --arg group "$independence_group" '[.[] | select(.independence_group == $group and ((.exit_status // "success") != "running") and ((has("ended_at") | not) or .ended_at != null))]' "$runs_file")" || return 1
    count="$(jq 'length' <<<"$filtered")"
    if [[ "$count" -lt "$required_count" ]]; then
        agent_runner_error "independence group '$independence_group' has $count run(s), requires $required_count."
        return 1
    fi

    unique_runs="$(jq '[.[].run_id] | unique | length' <<<"$filtered")"
    if [[ "$unique_runs" -ne "$count" ]]; then
        duplicate_run="$(jq -r '[.[].run_id] | group_by(.)[] | select(length > 1) | .[0]' <<<"$filtered" | head -1)"
        agent_runner_error "duplicate run_id cannot count as independent: $duplicate_run"
        return 1
    fi

    unique_outputs="$(jq '[.[] | ((.output_artifacts // [])[]?, (.summary_artifact // empty))] | unique | length' <<<"$filtered")"
    local output_count
    output_count="$(jq '[.[] | ((.output_artifacts // [])[]?, (.summary_artifact // empty))] | length' <<<"$filtered")"
    if [[ "$unique_outputs" -ne "$output_count" ]]; then
        duplicate_output="$(jq -r '[.[] | ((.output_artifacts // [])[]?, (.summary_artifact // empty))] | group_by(.)[] | select(length > 1) | .[0]' <<<"$filtered" | head -1)"
        agent_runner_error "duplicate output artifact cannot count as independent: $duplicate_output"
        return 1
    fi

    jq -n --arg group "$independence_group" --argjson count "$count" --argjson required_count "$required_count" '{independence_group:$group, independent_run_count:$count, required_count:$required_count, status:"pass"}'
}
