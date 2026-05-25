#!/usr/bin/env bash
# paper-input-safety-audit.sh
# Audits paper input threats without executing paper content.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <paper> --output <audit.json>" >&2
    exit 2
}

INPUT=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            INPUT="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            OUTPUT="$2"
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

[[ -n "$INPUT" && -n "$OUTPUT" ]] || usage
[[ -f "$INPUT" ]] || { echo "PAPER_INPUT_AUDIT_ERROR: input not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "PAPER_INPUT_AUDIT_ERROR: jq is required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SANITIZED="$TMP_DIR/sanitized.json"

"$SCRIPT_DIR/paper-input-sanitize.sh" --input "$INPUT" --output "$SANITIZED" >/dev/null
threat_count="$(jq '.threats | length' "$SANITIZED")"

jq -n \
    --slurpfile sanitized "$SANITIZED" \
    --argjson blocked_instruction_count "$threat_count" \
    '{paper_text_untrusted:true, supplementary_code_executed:false, blocked_instruction_count:$blocked_instruction_count, threats:$sanitized[0].threats}' > "$OUTPUT"

echo "PAPER_INPUT_SAFETY_AUDIT_SUCCESS"
echo "Output: $OUTPUT"
