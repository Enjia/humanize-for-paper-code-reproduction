#!/usr/bin/env bash
# Guard paper-derived commands before execution. Paper text is untrusted data.

[[ -n "${_COMMAND_GUARD_LOADED:-}" ]] && return 0 2>/dev/null || true
_COMMAND_GUARD_LOADED=1

command_guard_check() {
    local command_text="${1:-}"
    if [[ -z "$command_text" ]]; then
        echo "Error: command guard requires command text." >&2
        return 1
    fi

    if printf '%s' "$command_text" | grep -qiE '(curl|wget)[^|;&]*(\||;|&&|\$\(|`)[[:space:]]*(sh|bash)|\|[[:space:]]*(sh|bash)'; then
        echo "Error: remote shell execution is blocked by command guard." >&2
        return 1
    fi

    if printf '%s' "$command_text" | grep -qiE '(^|[;&|[:space:]])git[[:space:]]+reset[[:space:]]+--hard|(^|[;&|[:space:]])git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f|(^|[;&|[:space:]])rm[[:space:]]+-rf[[:space:]]+(/|\$HOME|~)'; then
        echo "Error: destructive command is blocked by command guard." >&2
        return 1
    fi

    return 0
}
