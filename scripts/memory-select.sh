#!/usr/bin/env bash
# Selects relevant structured paper reproduction memories.

set -euo pipefail

usage() {
    echo "Usage: $0 --memory-dir <dir> [--module ID] [--criterion ID] [--checkpoint ID] [--limit N]" >&2
    exit 2
}

MEMORY_DIR=""
MODULE_ID=""
CRITERION_ID=""
CHECKPOINT_ID=""
LIMIT=10
while [[ $# -gt 0 ]]; do
    case "$1" in
        --memory-dir) [[ $# -ge 2 && "$2" != --* ]] || usage; MEMORY_DIR="$2"; shift 2 ;;
        --module) [[ $# -ge 2 && "$2" != --* ]] || usage; MODULE_ID="$2"; shift 2 ;;
        --criterion) [[ $# -ge 2 && "$2" != --* ]] || usage; CRITERION_ID="$2"; shift 2 ;;
        --checkpoint) [[ $# -ge 2 && "$2" != --* ]] || usage; CHECKPOINT_ID="$2"; shift 2 ;;
        --limit) [[ $# -ge 2 && "$2" != --* ]] || usage; LIMIT="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$MEMORY_DIR" ]] || usage
[[ "$LIMIT" =~ ^[0-9]+$ && "$LIMIT" -ge 1 ]] || { echo "MEMORY_SELECT_ERROR: --limit must be >= 1" >&2; exit 1; }
MEMORIES="$MEMORY_DIR/memories.jsonl"
[[ -s "$MEMORIES" ]] || { echo "MEMORY_SELECT_ERROR: memories.jsonl not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "MEMORY_SELECT_ERROR: jq is required" >&2; exit 1; }

jq -s \
  --arg module_id "$MODULE_ID" \
  --arg criterion_id "$CRITERION_ID" \
  --arg checkpoint_id "$CHECKPOINT_ID" \
  --argjson limit "$LIMIT" \
  '[
    .[]
    | select($module_id == "" or ((.module_ids // []) | index($module_id)))
    | select($criterion_id == "" or ((.criterion_ids // []) | index($criterion_id)))
    | select($checkpoint_id == "" or ((.checkpoint_ids // []) | index($checkpoint_id)))
  ][: $limit]' "$MEMORIES"
