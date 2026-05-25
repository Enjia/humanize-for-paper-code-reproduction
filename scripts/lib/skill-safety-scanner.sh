#!/usr/bin/env bash
# Skill safety scanner for candidate paper reproduction skills.

[[ -n "${_SKILL_SAFETY_SCANNER_LOADED:-}" ]] && return 0 2>/dev/null || true
_SKILL_SAFETY_SCANNER_LOADED=1

skill_safety_scan_text() {
    local text="${1:-}"
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    : > "$tmp"

    add() {
        local kind="$1"
        local detail="$2"
        jq -cn --arg kind "$kind" --arg detail "$detail" '{kind:$kind, detail:$detail}' >> "$tmp"
    }

    if grep -Eiq '(~|/home/[^ ]+|/Users/[^ ]+)?/\.ssh/(id_rsa|id_ed25519)|\.aws/credentials|GITHUB_TOKEN|OPENAI_API_KEY' <<<"$text"; then
        add "credential_access" "candidate references credential paths or secret environment variables"
    fi
    if grep -Eiq 'git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f' <<<"$text"; then
        add "destructive_git" "candidate contains destructive git command"
    fi
    if grep -Eiq '(npm|pip|uv|brew)[[:space:]].*(-g|--global)|pip[[:space:]]+install[[:space:]].*--user' <<<"$text"; then
        add "global_install" "candidate installs packages globally or into user environment"
    fi
    if grep -Eiq '(curl|wget).*(\|[[:space:]]*(sh|bash))|\|[[:space:]]*(sh|bash)' <<<"$text"; then
        add "network_shell" "candidate pipes downloaded or generated content to shell"
    fi
    if grep -Eiq 'base64[[:space:]]+-d|python[[:space:]]+-c|eval[[:space:]]+|bash[[:space:]]+-c' <<<"$text"; then
        add "encoded_payload" "candidate contains encoded or dynamic shell execution pattern"
    fi
    if grep -Eiq '>>[[:space:]]*(~|\$HOME)/\.(zshrc|bashrc|profile)|/etc/' <<<"$text"; then
        add "global_config_write" "candidate writes global shell or system configuration"
    fi

    jq -s . "$tmp"
}
