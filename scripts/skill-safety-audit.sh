#!/usr/bin/env bash
# skill-safety-audit.sh
# Audits paper reproduction candidate skills before promotion.

set -euo pipefail

usage() {
    echo "Usage: $0 --candidate <skill-dir> --output <audit.json>" >&2
    exit 2
}

CANDIDATE=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --candidate)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            CANDIDATE="$2"
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

[[ -n "$CANDIDATE" && -n "$OUTPUT" ]] || usage
[[ -d "$CANDIDATE" && -f "$CANDIDATE/SKILL.md" ]] || { echo "SKILL_AUDIT_ERROR: candidate skill missing SKILL.md" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKILL_AUDIT_ERROR: jq is required" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/lib/skill-safety-scanner.sh"

content="$(cat "$CANDIDATE/SKILL.md")"
findings="$(skill_safety_scan_text "$content")"
count="$(jq 'length' <<<"$findings")"
mkdir -p "$(dirname "$OUTPUT")"

ENTRY_FILE="$CANDIDATE/skill-entry.json"
if [[ ! -s "$ENTRY_FILE" ]]; then
    jq -n --arg candidate "$CANDIDATE" '{candidate:$candidate, status:"blocked", promotion:"blocked", findings:[{kind:"missing_provenance", message:"candidate skill missing skill-entry.json provenance metadata"}]}' > "$OUTPUT"
    echo "SKILL_AUDIT_ERROR: candidate skill missing provenance metadata" >&2
    exit 1
fi
if ! jq empty "$ENTRY_FILE" >/dev/null 2>&1; then
    jq -n --arg candidate "$CANDIDATE" '{candidate:$candidate, status:"blocked", promotion:"blocked", findings:[{kind:"invalid_provenance", message:"candidate skill-entry.json is invalid JSON"}]}' > "$OUTPUT"
    echo "SKILL_AUDIT_ERROR: candidate skill provenance metadata is invalid" >&2
    exit 1
fi
if ! jq -e '
  .state == "candidate" and
  (.provenance.source_memories | type == "array" and length >= 1) and
  (.provenance.source_checkpoint | type == "string" and length >= 1) and
  (.provenance.authoring_agent | type == "string" and length >= 1) and
  (.provenance.reviewer | type == "string" and length >= 1) and
  (.provenance.timestamp | type == "string" and length >= 1) and
  (.validation_commands | type == "array" and length >= 1) and
  (.created_at | type == "string" and length >= 1)
' "$ENTRY_FILE" >/dev/null; then
    jq -n --arg candidate "$CANDIDATE" --slurpfile skill_entry "$ENTRY_FILE" '{candidate:$candidate, status:"blocked", promotion:"blocked", skill_entry:$skill_entry[0], findings:[{kind:"invalid_provenance", message:"candidate provenance must include source memories, source checkpoint, authoring agent, reviewer, validation commands, and timestamps"}]}' > "$OUTPUT"
    echo "SKILL_AUDIT_ERROR: candidate skill provenance metadata is incomplete" >&2
    exit 1
fi

if [[ "$count" -gt 0 ]]; then
    jq -n --arg candidate "$CANDIDATE" --argjson findings "$findings" --slurpfile skill_entry "$ENTRY_FILE" '{candidate:$candidate, status:"blocked", promotion:"blocked", skill_entry:$skill_entry[0], findings:$findings}' > "$OUTPUT"
    echo "SKILL_AUDIT_BLOCKED"
    echo "Output: $OUTPUT"
    exit 1
fi

jq -n --arg candidate "$CANDIDATE" --slurpfile skill_entry "$ENTRY_FILE" '{candidate:$candidate, status:"candidate_pass", promotion:"manual_review_required", skill_entry:$skill_entry[0], findings:[]}' > "$OUTPUT"
echo "SKILL_AUDIT_SUCCESS"
echo "Output: $OUTPUT"
