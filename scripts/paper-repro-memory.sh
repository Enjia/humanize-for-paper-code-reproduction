#!/usr/bin/env bash
# paper-repro-memory.sh
# Captures redacted memory events and optionally selects matching memories.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <events.jsonl> --memory-dir <dir> [--select-module <module_id>] [--limit <n>]" >&2
    exit 2
}

INPUT=""
MEMORY_DIR=""
SELECT_MODULE=""
LIMIT="10"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input) [[ $# -ge 2 && "$2" != --* ]] || usage; INPUT="$2"; shift 2 ;;
        --memory-dir) [[ $# -ge 2 && "$2" != --* ]] || usage; MEMORY_DIR="$2"; shift 2 ;;
        --select-module) [[ $# -ge 2 && "$2" != --* ]] || usage; SELECT_MODULE="$2"; shift 2 ;;
        --limit) [[ $# -ge 2 && "$2" != --* ]] || usage; LIMIT="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$INPUT" && -n "$MEMORY_DIR" ]] || usage
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

"$SCRIPT_DIR/memory-capture.sh" --input "$INPUT" --memory-dir "$MEMORY_DIR" >/dev/null
"$SCRIPT_DIR/memory-consolidate.sh" --memory-dir "$MEMORY_DIR" >/dev/null

if [[ -n "$SELECT_MODULE" ]]; then
    "$SCRIPT_DIR/memory-select.sh" --memory-dir "$MEMORY_DIR" --module "$SELECT_MODULE" --limit "$LIMIT"
else
    cat "$MEMORY_DIR/memories.jsonl"
fi
