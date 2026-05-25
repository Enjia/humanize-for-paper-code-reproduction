#!/usr/bin/env bash
# Checkpoint-aware stop hook for paper reproduction loops.

set -euo pipefail

usage() {
    echo "Usage: $0 --state <state.json>" >&2
    exit 2
}

STATE_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --state)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            STATE_FILE="$2"
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

[[ -f "$STATE_FILE" ]] || { echo "VALIDATION_ERROR: STATE_NOT_FOUND" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKPOINT_VALIDATE="$PROJECT_ROOT/scripts/checkpoint-validate.sh"
CHECKPOINT_MIGRATE="$PROJECT_ROOT/scripts/checkpoint-state-migrate.sh"

plan_path="$(jq -r '.plan_path // empty' "$STATE_FILE")"
active_checkpoint_id="$(jq -r '.active_checkpoint_id // empty' "$STATE_FILE")"
[[ -n "$plan_path" && -f "$plan_path" ]] || { echo "VALIDATION_ERROR: PLAN_NOT_FOUND" >&2; exit 1; }
[[ -n "$active_checkpoint_id" && "$active_checkpoint_id" != "null" ]] || { echo "VALIDATION_ERROR: ACTIVE_CHECKPOINT_NOT_FOUND" >&2; exit 1; }

"$CHECKPOINT_VALIDATE" --plan "$plan_path" --checkpoint "$active_checkpoint_id" >/dev/null

tmp_state="$(mktemp)"
trap 'rm -f "$tmp_state"' EXIT
"$CHECKPOINT_MIGRATE" --input "$STATE_FILE" --output "$tmp_state" --advance "$active_checkpoint_id" >/dev/null
cp "$tmp_state" "$STATE_FILE"

next_checkpoint="$(jq -r '.active_checkpoint_id // empty' "$STATE_FILE")"
status="$(jq -r '.status // "in_progress"' "$STATE_FILE")"

echo "PAPER_REPRO_STOP_HOOK"
echo "loop_kind=paper_repro"
echo "checkpoint_advanced=$active_checkpoint_id"
if [[ -n "$next_checkpoint" && "$next_checkpoint" != "null" ]]; then
    echo "next_checkpoint=$next_checkpoint"
else
    echo "next_checkpoint=complete"
fi
echo "state_status=$status"
