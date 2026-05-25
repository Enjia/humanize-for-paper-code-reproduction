#!/usr/bin/env bash
# Shared provider adapter helpers for role-scoped paper reproduction execution.

[[ -n "${_PROVIDER_COMMON_LOADED:-}" ]] && return 0 2>/dev/null || true
_PROVIDER_COMMON_LOADED=1

provider_error() {
    echo "Error: $*" >&2
}

provider_json_string_or_default() {
    local json="${1:-}"
    local key="${2:-}"
    local default_value="${3:-}"

    printf '%s' "$json" | jq -r --arg key "$key" --arg default_value "$default_value" '
        if has($key) and .[$key] != null and (.[$key] | tostring | length) > 0 then
            .[$key] | tostring
        else
            $default_value
        end
    '
}
