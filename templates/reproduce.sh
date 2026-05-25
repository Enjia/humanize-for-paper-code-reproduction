#!/usr/bin/env bash
# Reproduction package entrypoint template.
# Workspaces should replace the placeholder body while preserving outputs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RESULTS_FILE="$ROOT_DIR/results.json"
RUN_ID=""
RUN_MODE="standard"
OFFLINE=false
SKIP_DOWNLOAD=false
OUTPUT_DIR=""
SEED=""
CLEAN=false

usage() {
  echo "Usage: $0 [--run-id RUN_ID] [--smoke|--full] [--offline] [--skip-download] [--output-dir DIR] [--seed N] [--clean]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      [[ $# -ge 2 && "$2" != --* ]] || { usage; exit 2; }
      RUN_ID="$2"
      shift 2
      ;;
    --smoke)
      RUN_MODE="smoke"
      shift
      ;;
    --full)
      RUN_MODE="full"
      shift
      ;;
    --offline)
      OFFLINE=true
      shift
      ;;
    --skip-download)
      SKIP_DOWNLOAD=true
      shift
      ;;
    --output-dir)
      [[ $# -ge 2 && "$2" != --* ]] || { usage; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --seed)
      [[ $# -ge 2 && "$2" != --* ]] || { usage; exit 2; }
      SEED="$2"
      shift 2
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)"
fi

case "$RUN_ID" in
  ""|/*|*/*|*..*|*[$'\001'-$'\037']*)
    echo "ERROR: invalid run id: $RUN_ID" >&2
    exit 2
    ;;
esac

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="outputs/$RUN_ID"
fi

case "$OUTPUT_DIR" in
  ""|/*|../*|*/../*|..|*[$'\001'-$'\037']*)
    echo "ERROR: invalid output dir: $OUTPUT_DIR" >&2
    exit 2
    ;;
esac

if [[ -n "$SEED" ]] && ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
  echo "ERROR: seed must be a non-negative integer" >&2
  exit 2
fi

RUN_DIR="$ROOT_DIR/$OUTPUT_DIR"
RUN_RESULTS_FILE="$RUN_DIR/results.json"

if [[ "$CLEAN" == "true" ]]; then
  rm -rf "$RUN_DIR"
fi

mkdir -p "$RUN_DIR"

if [[ -e "$RUN_RESULTS_FILE" ]]; then
  echo "ERROR: per-run results already exist and are immutable: $RUN_RESULTS_FILE" >&2
  exit 1
fi

seed_json="null"
if [[ -n "$SEED" ]]; then
  seed_json="$SEED"
fi

cat > "$RUN_RESULTS_FILE" <<JSON
{
  "schema_version": "paper-repro-run-results/v1",
  "run_id": "$RUN_ID",
  "run_mode": "$RUN_MODE",
  "execution": {
    "offline": $OFFLINE,
    "skip_download": $SKIP_DOWNLOAD,
    "seed": $seed_json,
    "clean": $CLEAN,
    "output_dir": "$OUTPUT_DIR"
  },
  "checkpoint_results": [],
  "summary": {
    "reproduced": 0,
    "partially_reproduced": 0,
    "failed": 0,
    "blocked": 1,
    "not_applicable": 0
  }
}
JSON

previous_run_ids='[]'
if [[ -s "$RESULTS_FILE" ]] && jq -e '.run_ids | type == "array"' "$RESULTS_FILE" >/dev/null 2>&1; then
  previous_run_ids="$(jq '.run_ids' "$RESULTS_FILE")"
fi

tmp_results="$RESULTS_FILE.tmp.$$"
jq -n \
  --arg run_id "$RUN_ID" \
  --arg run_path "$OUTPUT_DIR/results.json" \
  --argjson previous_run_ids "$previous_run_ids" \
  --slurpfile run "$RUN_RESULTS_FILE" \
  '{
    schema_version: "paper-repro-results-index/v1",
    latest_run_id: $run_id,
    run_ids: (($previous_run_ids + [$run_id]) | unique),
    latest_run: {
      run_id: $run_id,
      path: $run_path,
      run_mode: $run[0].run_mode,
      execution: $run[0].execution,
      summary: $run[0].summary
    },
    summary: $run[0].summary
  }' > "$tmp_results"
mv "$tmp_results" "$RESULTS_FILE"

echo "results=$RESULTS_FILE"
echo "run_results=$RUN_RESULTS_FILE"
