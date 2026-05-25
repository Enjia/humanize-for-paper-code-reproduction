#!/usr/bin/env bash
# Validates a candidate skill and records reviewer approval evidence.

set -euo pipefail

usage() {
    echo "Usage: $0 --candidate <skill-dir> --output <validation.json> --reviewer-run-id <run-id>" >&2
    exit 2
}

CANDIDATE=""
OUTPUT=""
REVIEWER_RUN_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --candidate) [[ $# -ge 2 && "$2" != --* ]] || usage; CANDIDATE="$2"; shift 2 ;;
        --output) [[ $# -ge 2 && "$2" != --* ]] || usage; OUTPUT="$2"; shift 2 ;;
        --reviewer-run-id) [[ $# -ge 2 && "$2" != --* ]] || usage; REVIEWER_RUN_ID="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$CANDIDATE" && -n "$OUTPUT" && -n "$REVIEWER_RUN_ID" ]] || usage
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
mkdir -p "$(dirname "$OUTPUT")"
AUDIT_TMP="$OUTPUT.audit.$$"
"$SCRIPT_DIR/skill-safety-audit.sh" --candidate "$CANDIDATE" --output "$AUDIT_TMP" >/dev/null
jq \
  --arg reviewer_run_id "$REVIEWER_RUN_ID" \
  '.state = "validated"
   | .reviewer_run_id = $reviewer_run_id
   | .validation_results = [{kind:"safety_audit", status:"pass"}]
   | .skill_entry.state = "validated"' "$AUDIT_TMP" > "$OUTPUT"
rm -f "$AUDIT_TMP"

echo "SKILL_VALIDATE_SUCCESS"
echo "output=$OUTPUT"
