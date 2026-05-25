#!/usr/bin/env bash
# checkpoint-state-migrate.sh
# Normalizes legacy paper checkpoint state files to paper-repro-state/v1.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <state.json> --output <state-v1.json> [--advance <checkpoint_id>]" >&2
    exit 2
}

INPUT=""
OUTPUT=""
ADVANCE_CHECKPOINT=""
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
        --advance)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            ADVANCE_CHECKPOINT="$2"
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
[[ -f "$INPUT" ]] || { echo "MIGRATION_ERROR: input not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "MIGRATION_ERROR: jq is required" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

normalized="$(mktemp)"
trap 'rm -f "$normalized"' EXIT

jq --arg now "$now" '
  {
    schema_version: "paper-repro-state/v1",
    loop_kind: (.loop_kind // "paper_repro"),
    plan_path: (.plan_path // .manifest_path // "paper-repro-plan.json"),
    active_checkpoint_id: (.active_checkpoint_id // .current_checkpoint // .checkpoint_id // null),
    completed_checkpoints: (.completed_checkpoints // .done // []),
    created_at: (.created_at // $now),
    updated_at: $now
  }
' "$INPUT" > "$normalized"

if [[ -n "$ADVANCE_CHECKPOINT" ]]; then
    active_checkpoint="$(jq -r '.active_checkpoint_id // empty' "$normalized")"
    if [[ "$ADVANCE_CHECKPOINT" != "$active_checkpoint" ]]; then
        echo "MIGRATION_ERROR: cannot advance non-active checkpoint '$ADVANCE_CHECKPOINT'; active checkpoint is '$active_checkpoint'" >&2
        exit 1
    fi
    plan_path="$(jq -r '.plan_path // empty' "$normalized")"
    if [[ ! -f "$plan_path" ]]; then
        echo "MIGRATION_ERROR: plan_path not found for checkpoint advance: $plan_path" >&2
        exit 1
    fi
    next_checkpoint="$(jq -r --arg id "$ADVANCE_CHECKPOINT" '
      (.checkpoint_graph.checkpoints // []) as $checkpoints |
      ($checkpoints | map(.checkpoint_id) | index($id)) as $idx |
      if $idx == null then "__MISSING__"
      elif ($idx + 1) < ($checkpoints | length) then $checkpoints[$idx + 1].checkpoint_id
      else ""
      end
    ' "$plan_path")"
    if [[ "$next_checkpoint" == "__MISSING__" ]]; then
        echo "MIGRATION_ERROR: active checkpoint not found in plan: $ADVANCE_CHECKPOINT" >&2
        exit 1
    fi
    jq \
      --arg now "$now" \
      --arg completed "$ADVANCE_CHECKPOINT" \
      --arg next "$next_checkpoint" \
      '.completed_checkpoints = ((.completed_checkpoints + [$completed]) | unique)
       | .active_checkpoint_id = (if $next == "" then null else $next end)
       | .status = (if $next == "" then "complete" else "in_progress" end)
       | .updated_at = $now' "$normalized" > "$OUTPUT"
else
    cp "$normalized" "$OUTPUT"
fi

echo "CHECKPOINT_STATE_MIGRATION_SUCCESS"
echo "Output: $OUTPUT"
