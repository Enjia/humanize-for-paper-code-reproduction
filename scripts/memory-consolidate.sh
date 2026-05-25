#!/usr/bin/env bash
# Builds structured memory stores from redacted paper reproduction events.

set -euo pipefail

usage() {
    echo "Usage: $0 --memory-dir <dir>" >&2
    exit 2
}

MEMORY_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --memory-dir) [[ $# -ge 2 && "$2" != --* ]] || usage; MEMORY_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$MEMORY_DIR" ]] || usage
EVENTS="$MEMORY_DIR/events.jsonl"
[[ -s "$EVENTS" ]] || { echo "MEMORY_CONSOLIDATE_ERROR: events.jsonl not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "MEMORY_CONSOLIDATE_ERROR: jq is required" >&2; exit 1; }

mkdir -p "$MEMORY_DIR"
jq -c '.' "$EVENTS" > "$MEMORY_DIR/memories.jsonl"
jq -c '{memory_id, source_events, module_ids, criterion_ids, checkpoint_ids}' "$EVENTS" > "$MEMORY_DIR/links.jsonl"
jq -s '
  {
    schema_version: "paper-repro-memory-index/v1",
    memory_count: length,
    module_ids: ([.[].module_ids[]?] | unique),
    criterion_ids: ([.[].criterion_ids[]?] | unique),
    checkpoint_ids: ([.[].checkpoint_ids[]?] | unique),
    tags: ([.[].tags[]?] | unique)
  }
' "$MEMORY_DIR/memories.jsonl" > "$MEMORY_DIR/index.json"

echo "MEMORY_CONSOLIDATE_SUCCESS"
echo "memories=$MEMORY_DIR/memories.jsonl"
echo "index=$MEMORY_DIR/index.json"
