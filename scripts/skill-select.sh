#!/usr/bin/env bash
# Selects active paper reproduction skills from the project registry.

set -euo pipefail

usage() {
    echo "Usage: $0 --registry <registry.json> [--skill-id <id>]" >&2
    exit 2
}

REGISTRY=""
SKILL_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry) [[ $# -ge 2 && "$2" != --* ]] || usage; REGISTRY="$2"; shift 2 ;;
        --skill-id) [[ $# -ge 2 && "$2" != --* ]] || usage; SKILL_ID="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$REGISTRY" ]] || usage
[[ -s "$REGISTRY" ]] || { echo "SKILL_SELECT_ERROR: registry not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKILL_SELECT_ERROR: jq is required" >&2; exit 1; }

jq --arg skill_id "$SKILL_ID" '[.skills[]? | select(.state == "active") | select($skill_id == "" or .skill_id == $skill_id)]' "$REGISTRY"
