#!/usr/bin/env bash
# result-compare.sh
# Compares reproduced outputs to paper claims using declared comparison modes.

set -euo pipefail

usage() {
    echo "Usage: $0 --expected <expected.json> --actual <actual.json> --output <comparison.json>" >&2
    exit 2
}

EXPECTED=""
ACTUAL=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --expected)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            EXPECTED="$2"
            shift 2
            ;;
        --actual)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            ACTUAL="$2"
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

[[ -n "$EXPECTED" && -n "$ACTUAL" && -n "$OUTPUT" ]] || usage
[[ -f "$EXPECTED" && -f "$ACTUAL" ]] || { echo "COMPARE_ERROR: expected and actual files are required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "COMPARE_ERROR: jq is required" >&2; exit 1; }

jq -n --slurpfile expected "$EXPECTED" --slurpfile actual "$ACTUAL" '
  def getpathstr($obj; $path):
    ($path | split(".")) as $parts |
    try ($obj | getpath($parts)) catch null;

  def compare_one($cmp; $actual):
    (getpathstr($actual; ($cmp.actual_path // ""))) as $actual_value |
    if $actual_value == null then
      $cmp + {status:"missing_output", actual:null}
    elif (($cmp.expected_unit // null) != null) and (($cmp.actual_unit_path // null) != null) and (getpathstr($actual; $cmp.actual_unit_path) != $cmp.expected_unit) then
      $cmp + {status:"unit_mismatch", actual:$actual_value, actual_unit:getpathstr($actual; $cmp.actual_unit_path)}
    elif $cmp.mode == "exact" then
      if $actual_value == $cmp.expected then $cmp + {status:"exact_match", actual:$actual_value} else $cmp + {status:"mismatch", actual:$actual_value} end
    elif $cmp.mode == "numeric_tolerance" then
      ($cmp.tolerance.absolute // 0) as $tol |
      if (($actual_value - $cmp.expected) | fabs) <= $tol then $cmp + {status:"tolerance_match", actual:$actual_value} else $cmp + {status:"tolerance_mismatch", actual:$actual_value} end
    elif $cmp.mode == "trend" then
      (getpathstr($actual; ($cmp.baseline_path // ""))) as $baseline |
      if ($cmp.expected == "increase" and $actual_value > $baseline) or ($cmp.expected == "decrease" and $actual_value < $baseline) then $cmp + {status:"trend_match", actual:$actual_value, baseline:$baseline} else $cmp + {status:"trend_mismatch", actual:$actual_value, baseline:$baseline} end
    elif $cmp.mode == "qualitative_structural" then
      ($cmp.expected_keys // []) as $keys |
      if all($keys[]; . as $key | $actual_value | has($key)) then $cmp + {status:"qualitative_structural_match", actual:$actual_value} else $cmp + {status:"qualitative_structural_mismatch", actual:$actual_value} end
    else
      $cmp + {status:"unsupported_mode", actual:$actual_value}
    end;

  ($actual[0]) as $a |
  [($expected[0].comparisons // [])[] | compare_one(.; $a)] as $results |
  {
    schema_version: "paper-repro-comparison/v1",
    results: $results,
    summary: ($results | group_by(.status) | map({(.[0].status): length}) | add // {})
  }
' > "$OUTPUT"

echo "RESULT_COMPARE_SUCCESS"
echo "Output: $OUTPUT"
