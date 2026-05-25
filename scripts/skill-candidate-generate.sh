#!/usr/bin/env bash
# Generates a deterministic candidate skill package from validated procedural memory.

set -euo pipefail

usage() {
    echo "Usage: $0 --memory <memory.json> --candidate-root <dir> --skill-id <id>" >&2
    exit 2
}

MEMORY=""
CANDIDATE_ROOT=""
SKILL_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --memory) [[ $# -ge 2 && "$2" != --* ]] || usage; MEMORY="$2"; shift 2 ;;
        --candidate-root) [[ $# -ge 2 && "$2" != --* ]] || usage; CANDIDATE_ROOT="$2"; shift 2 ;;
        --skill-id) [[ $# -ge 2 && "$2" != --* ]] || usage; SKILL_ID="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage ;;
    esac
done

[[ -n "$MEMORY" && -n "$CANDIDATE_ROOT" && -n "$SKILL_ID" ]] || usage
[[ -f "$MEMORY" ]] || { echo "SKILL_GENERATE_ERROR: memory not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKILL_GENERATE_ERROR: jq is required" >&2; exit 1; }
[[ "$SKILL_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "SKILL_GENERATE_ERROR: invalid skill id" >&2; exit 1; }

memory_id="$(jq -r '.memory_id // empty' "$MEMORY")"
summary="$(jq -r '.summary // empty' "$MEMORY")"
checkpoint="$(jq -r '(.checkpoint_ids // ["unknown"])[0]' "$MEMORY")"
[[ -n "$memory_id" && -n "$summary" ]] || { echo "SKILL_GENERATE_ERROR: memory must include memory_id and summary" >&2; exit 1; }

CANDIDATE_DIR="$CANDIDATE_ROOT/$SKILL_ID"
mkdir -p "$CANDIDATE_DIR"
cat > "$CANDIDATE_DIR/SKILL.md" <<MD
---
name: $SKILL_ID
description: Candidate skill generated from validated paper reproduction memory.
---

# $SKILL_ID

Use this only for paper reproduction tasks matching the source memory.

Source memory summary:
$summary
MD

created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg skill_id "$SKILL_ID" \
  --arg path "$CANDIDATE_DIR" \
  --arg memory_id "$memory_id" \
  --arg checkpoint "$checkpoint" \
  --arg created_at "$created_at" \
  '{
    skill_id: $skill_id,
    state: "candidate",
    path: $path,
    provenance: {
      source_memories: [$memory_id],
      source_checkpoint: $checkpoint,
      authoring_agent: "skill_generator",
      reviewer: "skill_reviewer",
      timestamp: $created_at
    },
    validation_commands: ["test -s SKILL.md"],
    created_at: $created_at
  }' > "$CANDIDATE_DIR/skill-entry.json"

echo "SKILL_CANDIDATE_GENERATE_SUCCESS"
echo "candidate=$CANDIDATE_DIR"
