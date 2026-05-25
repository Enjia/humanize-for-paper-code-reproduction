#!/usr/bin/env bash
# Claude provider adapter metadata.

[[ -n "${_PROVIDER_CLAUDE_LOADED:-}" ]] && return 0 2>/dev/null || true
_PROVIDER_CLAUDE_LOADED=1

provider_claude_binary() {
    echo "claude"
}

provider_claude_capabilities() {
    jq -n '{provider:"claude", capabilities:["prompt_execution", "effort_mapping"]}'
}
