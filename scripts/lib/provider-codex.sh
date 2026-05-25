#!/usr/bin/env bash
# Codex provider adapter metadata.

[[ -n "${_PROVIDER_CODEX_LOADED:-}" ]] && return 0 2>/dev/null || true
_PROVIDER_CODEX_LOADED=1

provider_codex_binary() {
    echo "codex"
}

provider_codex_capabilities() {
    jq -n '{provider:"codex", capabilities:["prompt_execution", "review", "effort_mapping"]}'
}
