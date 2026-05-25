#!/usr/bin/env bash
# Runtime adapter registry for paper reproduction execution.

[[ -n "${_RUNTIME_ADAPTER_COMMON_LOADED:-}" ]] && return 0 2>/dev/null || true
_RUNTIME_ADAPTER_COMMON_LOADED=1

runtime_adapter_describe() {
    local adapter_id="${1:-}"
    case "$adapter_id" in
        humanize)
            jq -n '{adapter_id:"humanize", adapter_kind:"local_shell", capabilities:["agent_runner", "snapshot_manager", "command_guard", "mock_provider"], provider_roles:{}}'
            ;;
        *)
            echo "Error: Unknown runtime adapter '$adapter_id'." >&2
            return 1
            ;;
    esac
}
