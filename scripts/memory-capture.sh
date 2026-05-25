#!/usr/bin/env bash
# Captures paper reproduction events as redacted memory event records.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <events.jsonl> --memory-dir <dir>" >&2
    exit 2
}

INPUT=""
MEMORY_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input) [[ $# -ge 2 && "$2" != --* ]] || usage; INPUT="$2"; shift 2 ;;
        --memory-dir) [[ $# -ge 2 && "$2" != --* ]] || usage; MEMORY_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$INPUT" && -n "$MEMORY_DIR" ]] || usage
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
mkdir -p "$MEMORY_DIR"
TMP_OUTPUT="$MEMORY_DIR/events.jsonl.tmp.$$"
"$SCRIPT_DIR/memory-safety-audit.sh" --input "$INPUT" --output "$TMP_OUTPUT" >/dev/null
cat "$TMP_OUTPUT" >> "$MEMORY_DIR/events.jsonl"
rm -f "$TMP_OUTPUT"

echo "MEMORY_CAPTURE_SUCCESS"
echo "events=$MEMORY_DIR/events.jsonl"
