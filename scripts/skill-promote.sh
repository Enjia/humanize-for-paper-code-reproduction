#!/usr/bin/env bash
# Promotes a validated candidate skill only with explicit approval.

set -euo pipefail

usage() {
    echo "Usage: $0 --candidate <skill-dir> --validation <validation.json> --registry <registry.json> --active-root <dir> [--approve]" >&2
    exit 2
}

CANDIDATE=""
VALIDATION=""
REGISTRY=""
ACTIVE_ROOT=""
APPROVE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --candidate) [[ $# -ge 2 && "$2" != --* ]] || usage; CANDIDATE="$2"; shift 2 ;;
        --validation) [[ $# -ge 2 && "$2" != --* ]] || usage; VALIDATION="$2"; shift 2 ;;
        --registry) [[ $# -ge 2 && "$2" != --* ]] || usage; REGISTRY="$2"; shift 2 ;;
        --active-root) [[ $# -ge 2 && "$2" != --* ]] || usage; ACTIVE_ROOT="$2"; shift 2 ;;
        --approve) APPROVE=true; shift ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$CANDIDATE" && -n "$VALIDATION" && -n "$REGISTRY" && -n "$ACTIVE_ROOT" ]] || usage
[[ "$APPROVE" == "true" ]] || { echo "SKILL_PROMOTE_ERROR: explicit approval is required" >&2; exit 1; }
[[ -d "$CANDIDATE" && -s "$VALIDATION" ]] || { echo "SKILL_PROMOTE_ERROR: candidate and validation are required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKILL_PROMOTE_ERROR: jq is required" >&2; exit 1; }
if ! jq -e '.state == "validated" and .promotion == "manual_review_required"' "$VALIDATION" >/dev/null; then
    echo "SKILL_PROMOTE_ERROR: validation must be passed and manual-review gated" >&2
    exit 1
fi

skill_id="$(jq -r '.skill_entry.skill_id' "$VALIDATION")"
[[ "$skill_id" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "SKILL_PROMOTE_ERROR: invalid skill id" >&2; exit 1; }
ACTIVE_DIR="$ACTIVE_ROOT/$skill_id"
mkdir -p "$ACTIVE_DIR" "$(dirname "$REGISTRY")"
cp "$CANDIDATE/SKILL.md" "$ACTIVE_DIR/SKILL.md"
cp "$CANDIDATE/skill-entry.json" "$ACTIVE_DIR/skill-entry.json"

if [[ ! -s "$REGISTRY" ]]; then
    echo '{"schema_version":"paper-repro-skill-registry/v1","skills":[]}' > "$REGISTRY"
fi
tmp_registry="$REGISTRY.tmp.$$"
jq \
  --arg skill_id "$skill_id" \
  --arg path "$ACTIVE_DIR" \
  --slurpfile validation "$VALIDATION" \
  '.skills = ((.skills // []) | map(select(.skill_id != $skill_id)) + [{
    skill_id: $skill_id,
    state: "active",
    path: $path,
    provenance: $validation[0].skill_entry.provenance,
    validation_commands: $validation[0].skill_entry.validation_commands,
    reviewer_run_id: $validation[0].reviewer_run_id,
    promoted_at: (now | todate)
  }])' "$REGISTRY" > "$tmp_registry"
mv "$tmp_registry" "$REGISTRY"

echo "SKILL_PROMOTE_SUCCESS"
echo "active=$ACTIVE_DIR"
