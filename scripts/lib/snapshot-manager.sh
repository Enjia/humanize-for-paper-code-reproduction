#!/usr/bin/env bash
# Snapshot primitives for paper reproduction checkpoints.

[[ -n "${_SNAPSHOT_MANAGER_LOADED:-}" ]] && return 0 2>/dev/null || true
_SNAPSHOT_MANAGER_LOADED=1

snapshot_error() {
    echo "Error: $*" >&2
}

snapshot_sha256() {
    local file="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    else
        snapshot_error "No sha256 tool found."
        return 1
    fi
}

snapshot_create() {
    local workspace="${1:-}"
    local store="${2:-}"
    local checkpoint_id="${3:-}"

    [[ -d "$workspace" ]] || { snapshot_error "Workspace not found: $workspace"; return 1; }
    [[ -n "$store" ]] || { snapshot_error "Snapshot store is required."; return 1; }
    [[ -n "$checkpoint_id" ]] || { snapshot_error "checkpoint_id is required."; return 1; }
    command -v jq >/dev/null 2>&1 || { snapshot_error "jq is required."; return 1; }

    local created_at snapshot_id snapshot_dir files_json manifest_path file_count
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    snapshot_id="SNAP-${checkpoint_id}-$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}${RANDOM}"
    snapshot_dir="$store/$snapshot_id"
    mkdir -p "$snapshot_dir"
    manifest_path="$snapshot_dir/manifest.json"

    files_json="$({
        cd "$workspace"
        find . -type f \
            ! -path './.git/*' \
            ! -path './logs/*' \
            ! -path './outputs/*' \
            ! -path './.humanize/cache/*' \
            -print | sort | while IFS= read -r rel; do
                clean="${rel#./}"
                hash="$(snapshot_sha256 "$clean")"
                jq -cn --arg path "$clean" --arg sha256 "$hash" '{path:$path, sha256:$sha256}'
            done
    } | jq -s '.')"
    file_count="$(jq 'length' <<<"$files_json")"

    jq -n \
        --arg snapshot_id "$snapshot_id" \
        --arg checkpoint_id "$checkpoint_id" \
        --arg created_at "$created_at" \
        --arg workspace "$workspace" \
        --arg manifest_path "$manifest_path" \
        --argjson file_count "$file_count" \
        --argjson files "$files_json" \
        '{snapshot_id:$snapshot_id, checkpoint_id:$checkpoint_id, created_at:$created_at, workspace:$workspace, manifest_path:$manifest_path, file_count:$file_count, files:$files}' > "$manifest_path"

    jq -n \
        --arg snapshot_id "$snapshot_id" \
        --arg checkpoint_id "$checkpoint_id" \
        --arg created_at "$created_at" \
        --arg workspace "$workspace" \
        --arg manifest_path "$manifest_path" \
        --argjson file_count "$file_count" \
        '{snapshot_id:$snapshot_id, checkpoint_id:$checkpoint_id, created_at:$created_at, workspace:$workspace, manifest_path:$manifest_path, file_count:$file_count}'
}

snapshot_diff() {
    local base_json="${1:-}"
    local target_json="${2:-}"
    local base_manifest target_manifest

    base_manifest="$(jq -r '.manifest_path // empty' <<<"$base_json")"
    target_manifest="$(jq -r '.manifest_path // empty' <<<"$target_json")"
    [[ -f "$base_manifest" ]] || { snapshot_error "Base snapshot manifest not found: $base_manifest"; return 1; }
    [[ -f "$target_manifest" ]] || { snapshot_error "Target snapshot manifest not found: $target_manifest"; return 1; }

    jq -n --slurpfile base "$base_manifest" --slurpfile target "$target_manifest" '
      ($base[0].files // []) as $base_files |
      ($target[0].files // []) as $target_files |
      ($base_files | map({key:.path, value:.sha256}) | from_entries) as $base_map |
      ($target_files | map({key:.path, value:.sha256}) | from_entries) as $target_map |
      (($base_map | keys) + ($target_map | keys) | unique) as $all_paths |
      {
        base_snapshot: $base[0].snapshot_id,
        target_snapshot: $target[0].snapshot_id,
        changed_paths: ($all_paths | map(select(($base_map[.] // null) != ($target_map[.] // null))))
      }
    '
}
