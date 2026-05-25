#!/usr/bin/env bash
# paper-repro-skill-curate.sh
# Audits a candidate skill and optionally selects active skills from the registry.

set -euo pipefail

usage() {
    echo "Usage: $0 --candidate <skill-dir> --output <audit.json> [--registry <registry.json> --skill-id <id>]" >&2
    exit 2
}

CANDIDATE=""
OUTPUT=""
REGISTRY=""
SKILL_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --candidate) [[ $# -ge 2 && "$2" != --* ]] || usage; CANDIDATE="$2"; shift 2 ;;
        --output) [[ $# -ge 2 && "$2" != --* ]] || usage; OUTPUT="$2"; shift 2 ;;
        --registry) [[ $# -ge 2 && "$2" != --* ]] || usage; REGISTRY="$2"; shift 2 ;;
        --skill-id) [[ $# -ge 2 && "$2" != --* ]] || usage; SKILL_ID="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$CANDIDATE" && -n "$OUTPUT" ]] || usage
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

"$SCRIPT_DIR/skill-safety-audit.sh" --candidate "$CANDIDATE" --output "$OUTPUT" >/dev/null

if [[ -n "$REGISTRY" ]]; then
    if [[ -n "$SKILL_ID" ]]; then
        "$SCRIPT_DIR/skill-select.sh" --registry "$REGISTRY" --skill-id "$SKILL_ID"
    else
        "$SCRIPT_DIR/skill-select.sh" --registry "$REGISTRY"
    fi
else
    cat "$OUTPUT"
fi
