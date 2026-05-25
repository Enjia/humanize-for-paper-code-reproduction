#!/usr/bin/env bash
# memory-safety-audit.sh
# Redacts paper reproduction event records before memory persistence.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <events.jsonl> --output <redacted-memory.jsonl>" >&2
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
[[ -f "$INPUT" ]] || { echo "MEMORY_AUDIT_ERROR: input not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "MEMORY_AUDIT_ERROR: jq is required" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/lib/memory-safety-scanner.sh"

mkdir -p "$(dirname "$OUTPUT")"
: > "$OUTPUT"

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if ! jq empty <<<"$line" >/dev/null 2>&1; then
        echo "MEMORY_AUDIT_ERROR: invalid JSONL event" >&2
        exit 1
    fi
    event_id="$(jq -r '.event_id // empty' <<<"$line")"
    module_id="$(jq -r '.module_id // empty' <<<"$line")"
    criterion_id="$(jq -r '.criterion_id // empty' <<<"$line")"
    checkpoint_id="$(jq -r '.checkpoint_id // empty' <<<"$line")"
    paper_hash="$(jq -r '.paper_hash // empty' <<<"$line")"
    if [[ -z "$event_id" || -z "$module_id" || -z "$criterion_id" || -z "$checkpoint_id" || -z "$paper_hash" ]]; then
        echo "MEMORY_AUDIT_ERROR: event missing required lineage fields: event_id, module_id, criterion_id, checkpoint_id, paper_hash" >&2
        exit 1
    fi
    summary="$(jq -r '.summary // ""' <<<"$line")"
    redacted_summary="$(memory_redact_text "$summary")"
    status="not_needed"
    if [[ "$summary" != "$redacted_summary" ]]; then
        status="redacted"
    fi
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -c \
      --arg summary "$redacted_summary" \
      --arg redaction_status "$status" \
      --arg memory_id "MEM-$event_id" \
      --arg event_id "$event_id" \
      --arg module_id "$module_id" \
      --arg criterion_id "$criterion_id" \
      --arg checkpoint_id "$checkpoint_id" \
      --arg created_at "$created_at" \
      '
      del(.raw_log, .transcript, .prompt, .paper_text)
      | .memory_id = $memory_id
      | .memory_type = "episodic"
      | .source_events = [$event_id]
      | .module_ids = [$module_id]
      | .criterion_ids = [$criterion_id]
      | .checkpoint_ids = [$checkpoint_id]
      | .tags = ["paper-repro-event"]
      | .created_at = $created_at
      | .summary = $summary
      | .redaction_status = $redaction_status
    ' <<<"$line" >> "$OUTPUT"
done < "$INPUT"

echo "MEMORY_AUDIT_SUCCESS"
echo "Output: $OUTPUT"
