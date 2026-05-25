#!/usr/bin/env bash
#
# Tests for paper-type artifact profile rule packs.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PROFILE_DIR="$PROJECT_ROOT/profiles"

echo "=========================================="
echo "Artifact Profile Tests"
echo "=========================================="
echo ""

profiles=(
  ml-training
  inference-optimization
  systems
  compiler
  numerical-simulation
  data-analysis
  algorithm-experiment
)

for profile in "${profiles[@]}"; do
  file="$PROFILE_DIR/$profile.json"
  if [[ -s "$file" ]]; then
    pass "profile exists: $profile"
  else
    fail "profile exists: $profile" "non-empty JSON file" "missing or empty"
    continue
  fi

  if jq empty "$file" >/dev/null 2>&1; then
    pass "profile is valid JSON: $profile"
  else
    fail "profile is valid JSON: $profile" "valid JSON" "invalid"
    continue
  fi

  for field in profile_id required_artifact_kinds optional_artifact_kinds not_applicable_artifact_kinds rules; do
    if jq -e --arg field "$field" 'has($field)' "$file" >/dev/null; then
      pass "profile $profile includes $field"
    else
      fail "profile $profile includes $field" "$field" "missing"
    fi
  done

done

for profile in inference-optimization algorithm-experiment; do
  file="$PROFILE_DIR/$profile.json"
  if jq -e '.required_artifact_kinds | index("training_script") | not' "$file" >/dev/null; then
    pass "$profile does not require training_script"
  else
    fail "$profile does not require training_script" "training_script absent from required_artifact_kinds" "present"
  fi
  if jq -e '.not_applicable_artifact_kinds | index("training_script")' "$file" >/dev/null; then
    pass "$profile marks training_script not applicable by default"
  else
    fail "$profile marks training_script not applicable by default" "training_script in not_applicable_artifact_kinds" "missing"
  fi
done

for profile in inference-optimization systems numerical-simulation data-analysis algorithm-experiment; do
  file="$PROFILE_DIR/$profile.json"
  if jq -e '.required_artifact_kinds | index("reproduce_entrypoint") and index("results_json") and index("environment_spec")' "$file" >/dev/null; then
    pass "$profile includes common reproduction artifacts"
  else
    fail "$profile includes common reproduction artifacts" "reproduce_entrypoint, results_json, environment_spec" "missing"
  fi
done

print_test_summary "Artifact Profile Tests"
