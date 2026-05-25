#!/usr/bin/env bash
# validate-paper-repro-plan-io.sh
# Side-effect-free IO validation for gen-paper-repro-plan.

set -euo pipefail

usage() {
    echo "Usage: $0 --input <paper> --output <paper-repro-plan.md> --manifest <paper-repro-plan.json> [--workspace paper-repro/<slug>]" >&2
    exit 6
}

INPUT_FILE=""
OUTPUT_FILE=""
MANIFEST_FILE=""
WORKSPACE_PATH="paper-repro/default"

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
        --manifest)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            MANIFEST_FILE="$2"
            shift 2
            ;;
        --workspace)
            [[ $# -ge 2 && "$2" != --* ]] || usage
            WORKSPACE_PATH="$2"
            shift 2
            ;;
        --paper-type|--budget|--from-scratch-policy)
            [[ $# -ge 2 && "$2" != --* ]] || usage
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

[[ -n "$INPUT_FILE" && -n "$OUTPUT_FILE" && -n "$MANIFEST_FILE" ]] || usage

reject_absolute() {
    local label="$1"
    local path="$2"
    if [[ "$path" = /* ]]; then
        echo "VALIDATION_ERROR: ${label}_ABSOLUTE_PATH" >&2
        echo "$label path must be relative to the project root: $path" >&2
        exit 1
    fi
}

reject_bad_chars() {
    local label="$1"
    local path="$2"
    if [[ "$path" =~ [[:space:]] ]]; then
        echo "VALIDATION_ERROR: ${label}_PATH_SPACES" >&2
        echo "$label path cannot contain spaces: $path" >&2
        exit 1
    fi
    case "$path" in
        *';'*|*'&'*|*'|'*|*'$'*|*'`'*|*'<'*|*'>'*|*'('*|*')'*|*'{'*|*'}'*|*'['*|*']'*|*'!'*|*'#'*|*'~'*|*'*'*|*'?'*)
            echo "VALIDATION_ERROR: ${label}_SHELL_METACHARACTERS" >&2
            echo "$label path cannot contain shell metacharacters: $path" >&2
            exit 1
            ;;
    esac
    if printf '%s' "$path" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        echo "VALIDATION_ERROR: ${label}_CONTROL_CHAR" >&2
        echo "$label path cannot contain control characters: $path" >&2
        exit 1
    fi
}

reject_traversal() {
    local label="$1"
    local path="$2"
    if [[ "$path" == *..* ]]; then
        echo "VALIDATION_ERROR: ${label}_PARENT_TRAVERSAL" >&2
        echo "$label path cannot contain parent traversal: $path" >&2
        exit 1
    fi
}

# Paper input may be an absolute local file path supplied by the user. It is
# still treated as untrusted data and never executed. Generated outputs and the
# reproduction workspace must remain project-relative for MVP safety.
reject_bad_chars "INPUT" "$INPUT_FILE"

for pair in "OUTPUT:$OUTPUT_FILE" "MANIFEST:$MANIFEST_FILE" "WORKSPACE:$WORKSPACE_PATH"; do
    label="${pair%%:*}"
    path="${pair#*:}"
    reject_absolute "$label" "$path"
    reject_bad_chars "$label" "$path"
    reject_traversal "$label" "$path"
done

case "$WORKSPACE_PATH" in
    .humanize|.humanize/*|.git|.git/*|.claude-flow|.claude-flow/*|.swarm|.swarm/*)
        echo "VALIDATION_ERROR: WORKSPACE_PROTECTED_PATH" >&2
        echo "workspace path cannot be inside protected runtime directories such as .humanize or .git: $WORKSPACE_PATH" >&2
        exit 1
        ;;
esac

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "VALIDATION_ERROR: INPUT_NOT_FOUND" >&2
    echo "Input paper file not found: $INPUT_FILE" >&2
    exit 1
fi

if [[ ! -s "$INPUT_FILE" ]]; then
    echo "VALIDATION_ERROR: INPUT_EMPTY" >&2
    echo "Input paper file is empty: $INPUT_FILE" >&2
    exit 2
fi

for target in "$OUTPUT_FILE" "$MANIFEST_FILE"; do
    parent="$(dirname "$target")"
    if [[ ! -d "$parent" ]]; then
        echo "VALIDATION_ERROR: OUTPUT_DIR_NOT_FOUND" >&2
        echo "Output directory not found: $parent" >&2
        exit 3
    fi
    if [[ -e "$target" ]]; then
        echo "VALIDATION_ERROR: OUTPUT_EXISTS" >&2
        echo "Output path already exists: $target" >&2
        exit 4
    fi
    if [[ ! -w "$parent" ]]; then
        echo "VALIDATION_ERROR: NO_WRITE_PERMISSION" >&2
        echo "No write permission for output directory: $parent" >&2
        exit 5
    fi
done

echo "VALIDATION_SUCCESS"
echo "Input: $INPUT_FILE"
echo "Output: $OUTPUT_FILE"
echo "Manifest: $MANIFEST_FILE"
echo "Workspace: $WORKSPACE_PATH"
