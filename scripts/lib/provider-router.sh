#!/usr/bin/env bash
# Role-specific provider routing for Humanize paper reproduction agents.

[[ -n "${_PROVIDER_ROUTER_LOADED:-}" ]] && return 0 2>/dev/null || true
_PROVIDER_ROUTER_LOADED=1

_PROVIDER_ROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib/model-router.sh
source "$_PROVIDER_ROUTER_DIR/model-router.sh"
# shellcheck source=scripts/lib/provider-common.sh
source "$_PROVIDER_ROUTER_DIR/provider-common.sh"

_resolve_role_value() {
    local merged_config_json="${1:-}"
    local role="${2:-}"
    local suffix="${3:-}"
    local default_value="${4:-}"
    local key="${role}_${suffix}"

    provider_json_string_or_default "$merged_config_json" "$key" "$default_value"
}

resolve_provider_role() {
    local merged_config_json="${1:-}"
    local role="${2:-}"
    local workspace_root="${3:-}"

    if [[ -z "$merged_config_json" || -z "$role" ]]; then
        provider_error "Usage: resolve_provider_role <merged_config_json> <role> [workspace_root]"
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        provider_error "jq is required for provider role routing."
        return 1
    fi

    local model provider effort timeout sandbox write_policy network_policy
    model="$(_resolve_role_value "$merged_config_json" "$role" "model" "default")"
    provider="$(_resolve_role_value "$merged_config_json" "$role" "provider" "")"
    if [[ -z "$provider" ]]; then
        provider="$(detect_provider "$model")" || return 1
    fi

    effort="$(_resolve_role_value "$merged_config_json" "$role" "effort" "medium")"
    effort="$(map_effort "$effort" "$provider")" || return 1
    timeout="$(_resolve_role_value "$merged_config_json" "$role" "timeout_seconds" "1800")"
    sandbox="$(_resolve_role_value "$merged_config_json" "$role" "sandbox_mode" "read-only")"
    write_policy="$(_resolve_role_value "$merged_config_json" "$role" "write_policy" "none")"
    network_policy="$(_resolve_role_value "$merged_config_json" "$role" "network_policy" "disabled")"
    workspace_root="${workspace_root:-$(_resolve_role_value "$merged_config_json" "$role" "workspace_root" "paper-repro")}" 

    jq -n \
        --arg role "$role" \
        --arg provider "$provider" \
        --arg model "$model" \
        --arg effort "$effort" \
        --arg sandbox_mode "$sandbox" \
        --arg write_policy "$write_policy" \
        --arg network_policy "$network_policy" \
        --arg workspace_root "$workspace_root" \
        --argjson timeout_seconds "$timeout" \
        '{role:$role, provider:$provider, model:$model, effort:$effort, timeout_seconds:$timeout_seconds, sandbox_mode:$sandbox_mode, write_policy:$write_policy, network_policy:$network_policy, workspace_root:$workspace_root}'
}

check_provider_role_dependency() {
    local role_json="${1:-}"
    if [[ -z "$role_json" ]]; then
        provider_error "Usage: check_provider_role_dependency <role_json>"
        return 1
    fi

    local role provider binary
    role="$(jq -r '.role // "unknown_role"' <<<"$role_json")"
    provider="$(jq -r '.provider // empty' <<<"$role_json")"
    case "$provider" in
        codex) binary="codex" ;;
        claude) binary="claude" ;;
        mock) return 0 ;;
        *) provider_error "Unknown provider '$provider' for role '$role'."; return 1 ;;
    esac

    if command -v "$binary" >/dev/null 2>&1; then
        return 0
    fi

    provider_error "Required binary '$binary' was not found for role '$role' configured with provider '$provider'."
    return 1
}
