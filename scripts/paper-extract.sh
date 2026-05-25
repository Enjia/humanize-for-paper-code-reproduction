#!/usr/bin/env bash
# paper-extract.sh
# Runs paper input sanitization and evidence extraction as separate audited artifacts.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <paper> --sanitized-output <sanitized.json> --evidence-output <evidence-map.json>" >&2
    exit 2
}

INPUT_FILE=""
SANITIZED_OUTPUT=""
EVIDENCE_OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            INPUT_FILE="$2"
            shift 2
            ;;
        --sanitized-output)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            SANITIZED_OUTPUT="$2"
            shift 2
            ;;
        --evidence-output)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            EVIDENCE_OUTPUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage
            ;;
    esac
done

[[ -n "$INPUT_FILE" && -n "$SANITIZED_OUTPUT" && -n "$EVIDENCE_OUTPUT" ]] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

"$SCRIPT_DIR/paper-input-sanitize.sh" --input "$INPUT_FILE" --output "$SANITIZED_OUTPUT" >/dev/null
"$SCRIPT_DIR/paper-evidence-map.sh" --input "$INPUT_FILE" --output "$EVIDENCE_OUTPUT" >/dev/null

if jq -e 'has("criteria") | not' "$EVIDENCE_OUTPUT" >/dev/null; then
    :
else
    echo "VALIDATION_ERROR: evidence extraction must not generate criteria" >&2
    exit 1
fi

echo "PAPER_EXTRACT_SUCCESS"
echo "Sanitized: $SANITIZED_OUTPUT"
echo "Evidence: $EVIDENCE_OUTPUT"
