#!/usr/bin/env bash
# Memory safety scanner for redacted paper reproduction event records.

[[ -n "${_MEMORY_SAFETY_SCANNER_LOADED:-}" ]] && return 0 2>/dev/null || true
_MEMORY_SAFETY_SCANNER_LOADED=1

memory_redact_text() {
    local text="${1:-}"
    printf '%s' "$text" \
        | sed -E 's/sk-[A-Za-z0-9_-]{10,}/[REDACTED_SECRET]/g' \
        | sed -E 's/(api[_-]?key|token|password)[=:][A-Za-z0-9_\-]+/\1=[REDACTED_SECRET]/Ig'
}
