#!/usr/bin/env bash
# Humanize runtime adapter entrypoints.

[[ -n "${_RUNTIME_ADAPTER_HUMANIZE_LOADED:-}" ]] && return 0 2>/dev/null || true
_RUNTIME_ADAPTER_HUMANIZE_LOADED=1

_RUNTIME_HUMANIZE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib/runtime-adapter-common.sh
source "$_RUNTIME_HUMANIZE_DIR/runtime-adapter-common.sh"

runtime_humanize_describe() {
    runtime_adapter_describe "humanize"
}
