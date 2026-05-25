#!/usr/bin/env bash
# Tests for candidate skill generation, validation, explicit promotion, and selection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

GENERATE="$PROJECT_ROOT/scripts/skill-candidate-generate.sh"
VALIDATE="$PROJECT_ROOT/scripts/skill-validate.sh"
PROMOTE="$PROJECT_ROOT/scripts/skill-promote.sh"
SELECT="$PROJECT_ROOT/scripts/skill-select.sh"

echo "=========================================="
echo "Skill Workflow Tests"
echo "=========================================="
echo ""

setup_test_dir

missing=0
for file in "$GENERATE" "$VALIDATE" "$PROMOTE" "$SELECT" "$PROJECT_ROOT/agents/skill-generator.md" "$PROJECT_ROOT/agents/skill-reviewer.md" "$PROJECT_ROOT/agents/skill-curator.md"; do
  if [[ -s "$file" ]]; then
    pass "skill workflow artifact exists: $(basename "$file")"
  else
    fail "skill workflow artifact exists: $(basename "$file")" "non-empty file" "missing"
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  print_test_summary "Skill Workflow Tests"
  exit 1
fi

MEMORY="$TEST_DIR/memory.json"
CANDIDATE_ROOT="$TEST_DIR/.humanize/skills/candidates"
CANDIDATE="$CANDIDATE_ROOT/benchmark-checklist"
AUDIT="$TEST_DIR/validation.json"
REGISTRY="$TEST_DIR/.humanize/skills/registry.json"
ACTIVE_ROOT="$TEST_DIR/.humanize/skills/active"
cat > "$MEMORY" <<'JSON'
{"memory_id":"MEM-EV-001","checkpoint_ids":["CHK-001"],"summary":"Record benchmark warmup and hardware metadata before comparison.","tags":["benchmark"],"memory_type":"procedural"}
JSON

if "$GENERATE" --memory "$MEMORY" --candidate-root "$CANDIDATE_ROOT" --skill-id benchmark-checklist >/tmp/skill-generate.out 2>&1; then
  pass "skill candidate generation runs from validated memory"
else
  fail "skill candidate generation runs from validated memory" "exit 0" "$(cat /tmp/skill-generate.out)"
fi

if [[ -s "$CANDIDATE/SKILL.md" && -s "$CANDIDATE/skill-entry.json" ]] && jq -e '.state == "candidate" and (.provenance.source_memories | index("MEM-EV-001"))' "$CANDIDATE/skill-entry.json" >/dev/null; then
  pass "skill generator emits candidate package with provenance"
else
  fail "skill generator emits candidate package with provenance" "SKILL.md and candidate skill-entry.json" "$(cat "$CANDIDATE/skill-entry.json" 2>/dev/null || true)"
fi

if "$VALIDATE" --candidate "$CANDIDATE" --output "$AUDIT" --reviewer-run-id RUN-SKILL-REV-001 >/tmp/skill-validate.out 2>&1; then
  pass "skill validation records independent reviewer approval"
else
  fail "skill validation records independent reviewer approval" "exit 0" "$(cat /tmp/skill-validate.out)"
fi

if jq -e '.state == "validated" and .reviewer_run_id == "RUN-SKILL-REV-001" and (.validation_results | length >= 1)' "$AUDIT" >/dev/null; then
  pass "validated skill includes validation evidence"
else
  fail "validated skill includes validation evidence" "validated result" "$(cat "$AUDIT" 2>/dev/null || true)"
fi

exit_code=0
"$PROMOTE" --candidate "$CANDIDATE" --validation "$AUDIT" --registry "$REGISTRY" --active-root "$ACTIVE_ROOT" >/tmp/skill-promote.out 2>&1 || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "approval" /tmp/skill-promote.out; then
  pass "skill promotion requires explicit approval"
else
  fail "skill promotion requires explicit approval" "non-zero approval error" "exit=$exit_code output=$(cat /tmp/skill-promote.out)"
fi

if "$PROMOTE" --candidate "$CANDIDATE" --validation "$AUDIT" --registry "$REGISTRY" --active-root "$ACTIVE_ROOT" --approve >/tmp/skill-promote.out 2>&1; then
  pass "approved skill promotion runs"
else
  fail "approved skill promotion runs" "exit 0" "$(cat /tmp/skill-promote.out)"
fi

if [[ -s "$ACTIVE_ROOT/benchmark-checklist/SKILL.md" ]] && jq -e '.skills[] | select(.skill_id == "benchmark-checklist" and .state == "active")' "$REGISTRY" >/dev/null; then
  pass "promotion writes active skill and registry entry"
else
  fail "promotion writes active skill and registry entry" "active skill registry" "$(cat "$REGISTRY" 2>/dev/null || true)"
fi

if "$SELECT" --registry "$REGISTRY" --skill-id benchmark-checklist > "$TEST_DIR/selected-skills.json" && jq -e 'length == 1 and .[0].state == "active"' "$TEST_DIR/selected-skills.json" >/dev/null; then
  pass "skill selection returns active matching skill"
else
  fail "skill selection returns active matching skill" "active skill selection" "$(cat "$TEST_DIR/selected-skills.json" 2>/dev/null || true)"
fi

print_test_summary "Skill Workflow Tests"
