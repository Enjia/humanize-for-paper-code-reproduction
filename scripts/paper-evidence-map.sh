#!/usr/bin/env bash
# paper-evidence-map.sh
# Deterministic evidence-map extractor for Phase 1 dry-run fixtures.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <paper-text> --output <evidence-map.json>" >&2
    exit 2
}

INPUT_FILE=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            INPUT_FILE="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            OUTPUT_FILE="$2"
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

[[ -n "$INPUT_FILE" && -n "$OUTPUT_FILE" ]] || usage

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "VALIDATION_ERROR: INPUT_NOT_FOUND" >&2
    exit 1
fi

if [[ ! -s "$INPUT_FILE" ]]; then
    echo "VALIDATION_ERROR: INPUT_EMPTY" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "VALIDATION_ERROR: JQ_NOT_FOUND" >&2
    exit 1
fi

out_dir="$(dirname "$OUTPUT_FILE")"
if [[ ! -d "$out_dir" ]]; then
    echo "VALIDATION_ERROR: OUTPUT_DIR_NOT_FOUND" >&2
    exit 1
fi

sha256_of_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        echo "VALIDATION_ERROR: SHA256_TOOL_NOT_FOUND" >&2
        exit 1
    fi
}

SOURCE_HASH="sha256:$(sha256_of_file "$INPUT_FILE")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

claims="$TMP_DIR/claims.jsonl"
methods="$TMP_DIR/methods.jsonl"
experiments="$TMP_DIR/experiments.jsonl"
ambiguities="$TMP_DIR/ambiguities.jsonl"
: > "$claims"
: > "$methods"
: > "$experiments"
: > "$ambiguities"

record() {
    local file="$1"
    local evidence_id="$2"
    local summary="$3"
    local section="$4"
    jq -n \
        --arg evidence_id "$evidence_id" \
        --arg summary "$summary" \
        --arg section "$section" \
        --arg source_hash "$SOURCE_HASH" \
        '{
          evidence_id: $evidence_id,
          summary: $summary,
          source_refs: [{section: $section, source_hash: $source_hash}],
          confidence: "medium"
        }' >> "$file"
}

claim_i=1
method_i=1
experiment_i=1
ambiguity_i=1
current_section="unknown"

while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$stripped" ]] && continue
    if [[ "$stripped" == \#* ]] || grep -Eiq '^(abstract|section|limitation|appendix|method|experiments?)' <<< "$stripped"; then
        current_section="$stripped"
    fi
    lower="$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]')"
    if grep -Eiq '\bclaim\b|improve|outperform|better|increase|decrease|reduce' <<< "$lower"; then
        record "$claims" "CLAIM-$(printf '%03d' "$claim_i")" "$stripped" "$current_section"
        claim_i=$((claim_i + 1))
    fi
    if grep -Eiq 'method|algorithm|equation|architecture|compute|transform|kernel|solver' <<< "$lower"; then
        record "$methods" "METHOD-$(printf '%03d' "$method_i")" "$stripped" "$current_section"
        method_i=$((method_i + 1))
    fi
    if grep -Eiq 'experiment|evaluate|benchmark|baseline|metric|table|figure|dataset|gpu|latency|accuracy|throughput' <<< "$lower"; then
        record "$experiments" "EXPERIMENT-$(printf '%03d' "$experiment_i")" "$stripped" "$current_section"
        experiment_i=$((experiment_i + 1))
    fi
    if grep -Eiq 'not specified|unclear|missing|limitation|ambiguous|unknown|not available' <<< "$lower"; then
        record "$ambiguities" "AMBIG-$(printf '%03d' "$ambiguity_i")" "$stripped" "$current_section"
        ambiguity_i=$((ambiguity_i + 1))
    fi
done < "$INPUT_FILE"

json_array() {
    local file="$1"
    if [[ -s "$file" ]]; then
        jq -s . "$file"
    else
        jq -n '[]'
    fi
}

jq -n \
    --arg schema_version "paper-evidence-map/v1" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg paper_hash "$SOURCE_HASH" \
    --argjson claims "$(json_array "$claims")" \
    --argjson methods "$(json_array "$methods")" \
    --argjson experiments "$(json_array "$experiments")" \
    --argjson ambiguities "$(json_array "$ambiguities")" \
    '{
      schema_version: $schema_version,
      created_at: $created_at,
      paper_hash: $paper_hash,
      input_sources: [{source_id: "SRC-001", kind: "text", path: input_filename, sha256: $paper_hash}],
      budget_profile: "smoke",
      unsupported_items: [],
      risk_level: "medium",
      privacy_mode: "local_only",
      claims: $claims,
      methods: $methods,
      experiments: $experiments,
      ambiguities: $ambiguities
    }' --arg input_filename "$INPUT_FILE" > "$OUTPUT_FILE"

echo "EVIDENCE_MAP_SUCCESS"
echo "Output: $OUTPUT_FILE"
echo "Claims: $(jq '.claims | length' "$OUTPUT_FILE")"
echo "Methods: $(jq '.methods | length' "$OUTPUT_FILE")"
echo "Experiments: $(jq '.experiments | length' "$OUTPUT_FILE")"
echo "Ambiguities: $(jq '.ambiguities | length' "$OUTPUT_FILE")"
