#!/usr/bin/env bash
# setup-paper-repro-loop.sh
# Initializes checkpoint-aware paper reproduction loop state.

set -euo pipefail

usage() {
    echo "Usage: $0 <paper-repro-plan.json> [--state-dir <dir>]" >&2
    exit 2
}

PLAN_FILE="${1:-}"
[[ $# -ge 1 ]] || usage
shift
STATE_DIR=".humanize/paper-repro"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --state-dir)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            STATE_DIR="$2"
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

[[ -f "$PLAN_FILE" ]] || { echo "VALIDATION_ERROR: PLAN_NOT_FOUND" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
"$SCRIPT_DIR/validate-paper-repro-plan.sh" "$PLAN_FILE" >/dev/null

active_checkpoint="$(jq -r '.checkpoint_graph.checkpoints[0].checkpoint_id // empty' "$PLAN_FILE")"
[[ -n "$active_checkpoint" ]] || { echo "VALIDATION_ERROR: NO_CHECKPOINTS" >&2; exit 1; }

mkdir -p "$STATE_DIR"
state_file="$STATE_DIR/state.json"
created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
    --arg loop_kind "paper_repro" \
    --arg plan_path "$PLAN_FILE" \
    --arg active_checkpoint_id "$active_checkpoint" \
    --arg created_at "$created_at" \
    '{loop_kind:$loop_kind, plan_path:$plan_path, active_checkpoint_id:$active_checkpoint_id, completed_checkpoints:[], created_at:$created_at, updated_at:$created_at}' > "$state_file"

echo "PAPER_REPRO_LOOP_SETUP_SUCCESS"
echo "state=$state_file"
echo "active_checkpoint=$active_checkpoint"
