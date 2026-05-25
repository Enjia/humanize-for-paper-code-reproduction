#!/usr/bin/env bash
# Tests for checkpoint snapshot manager primitives.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SNAPSHOT_MANAGER="$PROJECT_ROOT/scripts/lib/snapshot-manager.sh"

echo "=========================================="
echo "Snapshot Manager Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -s "$SNAPSHOT_MANAGER" ]]; then
  pass "snapshot-manager.sh exists"
else
  fail "snapshot-manager.sh exists" "non-empty file" "missing"
  print_test_summary "Snapshot Manager Tests"
  exit 1
fi

# shellcheck source=../scripts/lib/snapshot-manager.sh
source "$SNAPSHOT_MANAGER"

WORKSPACE="$TEST_DIR/workspace"
STORE="$TEST_DIR/snapshots"
mkdir -p "$WORKSPACE/src" "$WORKSPACE/logs" "$WORKSPACE/outputs"
printf 'alpha' > "$WORKSPACE/src/a.txt"
printf 'log' > "$WORKSPACE/logs/run.log"
printf 'large' > "$WORKSPACE/outputs/result.bin"

snap1=$(snapshot_create "$WORKSPACE" "$STORE" "CHK-001" 2>/tmp/snapshot.err)
if jq -e '.snapshot_id and .checkpoint_id == "CHK-001" and .workspace and .manifest_path and (.file_count >= 1)' <<<"$snap1" >/dev/null; then
  pass "snapshot_create returns linkable snapshot metadata"
else
  fail "snapshot_create returns linkable snapshot metadata" "snapshot JSON" "stdout=$snap1 stderr=$(cat /tmp/snapshot.err)"
fi

manifest_path=$(jq -r '.manifest_path' <<<"$snap1")
if [[ -s "$manifest_path" ]] && jq -e '.files[] | select(.path == "src/a.txt" and .sha256)' "$manifest_path" >/dev/null; then
  pass "snapshot manifest records tracked file hashes"
else
  fail "snapshot manifest records tracked file hashes" "src/a.txt hash" "$(cat "$manifest_path" 2>/dev/null || true)"
fi

if jq -e 'all(.files[]; (.path | startswith("logs/") | not) and (.path | startswith("outputs/") | not))' "$manifest_path" >/dev/null; then
  pass "snapshot excludes runtime logs and generated outputs by default"
else
  fail "snapshot excludes runtime logs and generated outputs by default" "no logs/outputs entries" "$(jq '.files' "$manifest_path" 2>/dev/null || true)"
fi

printf 'beta' > "$WORKSPACE/src/b.txt"
snap2=$(snapshot_create "$WORKSPACE" "$STORE" "CHK-001" 2>/tmp/snapshot.err)
diff_json=$(snapshot_diff "$snap1" "$snap2")
if jq -e '.changed_paths | index("src/b.txt")' <<<"$diff_json" >/dev/null; then
  pass "snapshot_diff reports changed paths for checkpoint records"
else
  fail "snapshot_diff reports changed paths for checkpoint records" "src/b.txt changed" "$diff_json"
fi

print_test_summary "Snapshot Manager Tests"
