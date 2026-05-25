#!/usr/bin/env bash
# Tests for proposed paper reproduction user command artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=========================================="
echo "Paper Repro Command Artifact Tests"
echo "=========================================="
echo ""

MEMORY_SCRIPT="$PROJECT_ROOT/scripts/paper-repro-memory.sh"
SKILL_CURATE_SCRIPT="$PROJECT_ROOT/scripts/paper-repro-skill-curate.sh"
START_LOOP_SCRIPT="$PROJECT_ROOT/scripts/start-paper-repro-loop.sh"

COMMANDS=(
  start-paper-repro-loop.md
  paper-repro-status.md
  paper-repro-memory.md
  paper-repro-skill-curate.md
)

for command in "${COMMANDS[@]}"; do
  file="$PROJECT_ROOT/commands/$command"
  if [[ -s "$file" ]]; then
    pass "command exists: $command"
  else
    fail "command exists: $command" "non-empty command file" "missing"
  fi
done

if [[ -x "$MEMORY_SCRIPT" ]]; then
  pass "paper-repro-memory.sh exists and is executable"
else
  fail "paper-repro-memory.sh exists and is executable" "executable script" "missing"
fi

if [[ -x "$START_LOOP_SCRIPT" ]]; then
  pass "start-paper-repro-loop.sh exists and is executable"
else
  fail "start-paper-repro-loop.sh exists and is executable" "executable script" "missing"
fi

if [[ -x "$SKILL_CURATE_SCRIPT" ]]; then
  pass "paper-repro-skill-curate.sh exists and is executable"
else
  fail "paper-repro-skill-curate.sh exists and is executable" "executable script" "missing"
fi

if [[ -s "$PROJECT_ROOT/commands/start-paper-repro-loop.md" ]] && grep -q "setup-paper-repro-loop.sh" "$PROJECT_ROOT/commands/start-paper-repro-loop.md" && grep -q "loop_kind=paper_repro" "$PROJECT_ROOT/commands/start-paper-repro-loop.md"; then
  pass "start-paper-repro-loop command uses dedicated paper loop setup"
else
  fail "start-paper-repro-loop command uses dedicated paper loop setup" "setup-paper-repro-loop.sh and loop_kind=paper_repro" "missing"
fi

if [[ -s "$PROJECT_ROOT/commands/paper-repro-status.md" ]] && grep -q "paper-repro-status.sh" "$PROJECT_ROOT/commands/paper-repro-status.md"; then
  pass "paper-repro-status command delegates to status script"
else
  fail "paper-repro-status command delegates to status script" "paper-repro-status.sh" "missing"
fi

if [[ -s "$PROJECT_ROOT/commands/paper-repro-memory.md" ]] && grep -q "memory-safety-audit.sh" "$PROJECT_ROOT/commands/paper-repro-memory.md" && grep -q "redacted" "$PROJECT_ROOT/commands/paper-repro-memory.md"; then
  pass "paper-repro-memory command documents redacted memory contract"
else
  fail "paper-repro-memory command documents redacted memory contract" "memory-safety-audit.sh and redacted" "missing"
fi

if [[ -s "$PROJECT_ROOT/commands/paper-repro-skill-curate.md" ]] && grep -q "skill-safety-audit.sh" "$PROJECT_ROOT/commands/paper-repro-skill-curate.md" && grep -q "manual" "$PROJECT_ROOT/commands/paper-repro-skill-curate.md"; then
  pass "paper-repro-skill-curate command documents manual promotion"
else
  fail "paper-repro-skill-curate command documents manual promotion" "skill-safety-audit.sh and manual" "missing"
fi

if rg -n "codex exec|claude .*--|Task\(" "$PROJECT_ROOT/commands/gen-paper-repro-plan.md" "$PROJECT_ROOT/prompt-template/paper" >/tmp/paper-command-provider-direct.out 2>&1; then
  fail "paper planning templates avoid direct provider CLI invocation" "no direct provider CLI" "$(cat /tmp/paper-command-provider-direct.out)"
else
  pass "paper planning templates avoid direct provider CLI invocation"
fi

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

cat > "$TEST_DIR/events.jsonl" <<'JSONL'
{"event_id":"EV-001","module_id":"ALG-001","criterion_id":"CRIT-001","checkpoint_id":"CHK-001","paper_hash":"sha256:abc","summary":"token=abcd1234 should be redacted"}
JSONL
cat > "$TEST_DIR/paper-repro-plan.json" <<'JSON'
{
  "schema_version": "paper-repro-plan/v1",
  "created_at": "2026-05-24T00:00:00Z",
  "paper_hash": "sha256:abc",
  "input_sources": [],
  "budget_profile": "smoke",
  "unsupported_items": [],
  "risk_level": "medium",
  "privacy_mode": "local_only",
  "paper": {"title": "Fixture", "paper_types": ["algorithm-experiment"]},
  "workspace": {"path": "paper-repro/fixture"},
  "safety": {},
  "budget": {},
  "feasibility": {},
  "evidence_map": {"claims": [], "methods": [], "experiments": [], "ambiguities": []},
  "decomposition": {"modules": [{"module_id": "ALG-001", "module_type": "algorithm_module", "origin": "paper", "origin_source": "CLAIM-001", "title": "Algorithm", "paper_evidence": ["CLAIM-001"], "depends_on": [], "claims_supported": ["CLAIM-001"], "reproduction_needs": [], "expected_artifact_kinds": [], "verification_targets": [], "ambiguities": [], "risk_level": "medium"}]},
  "criteria": [{"criterion_id": "CRIT-001", "module_ids": ["ALG-001"], "type": "method", "paper_evidence": ["CLAIM-001"], "expected_artifacts": ["src/algorithm.py"], "expected_artifact_kinds": ["source_module"], "expected_outputs": [], "verification_method": "unit_test", "status": "pending", "blocking": true, "open_questions": []}],
  "artifact_profile": {},
  "assumption_ledger": [],
  "checkpoint_graph": {"checkpoints": [
    {"checkpoint_id": "CHK-001", "kind": "child", "title": "Child", "depends_on": [], "covered_modules": ["ALG-001"], "covered_criteria": ["CRIT-001"], "expected_artifacts": ["src/algorithm.py"], "verification_commands": ["test -f src/algorithm.py"], "reviewer_count": 1, "reviewer_run_ids": ["RUN-REV-1"], "reviewer_provider_policy": {}, "base_snapshot": null, "target_snapshot": null, "changed_paths": [], "artifact_hashes": {}, "checkpoint_base_commit": null, "acceptance_rule": "all_blocking_criteria_pass", "open_question_policy": "block_if_material", "fallback_policy": "record_assumption", "failure_escalation": "revise_checkpoint"}
  ]},
  "tasks": [],
  "provider_roles": {},
  "agent_runs": [],
  "review_policy": {"child_reviewers": 1, "parent_reviewers": 2},
  "final_package_contract": {"entrypoint": "reproduce.sh", "results": "results.json"}
}
JSON
mkdir -p "$TEST_DIR/paper-repro/fixture/src"
printf 'def route():\n    return "ok"\n' > "$TEST_DIR/paper-repro/fixture/src/algorithm.py"

if "$START_LOOP_SCRIPT" "$TEST_DIR/paper-repro-plan.json" --state-dir "$TEST_DIR/.humanize/paper-repro" >/tmp/paper-repro-start-loop.out 2>&1; then
  pass "start-paper-repro-loop wrapper initializes paper loop state"
else
  fail "start-paper-repro-loop wrapper initializes paper loop state" "exit 0" "$(cat /tmp/paper-repro-start-loop.out)"
fi

if [[ -s "$TEST_DIR/.humanize/paper-repro/state.json" ]] && jq -e '.loop_kind == "paper_repro" and .active_checkpoint_id == "CHK-001"' "$TEST_DIR/.humanize/paper-repro/state.json" >/dev/null 2>&1; then
  pass "start-paper-repro-loop wrapper writes paper loop state"
else
  fail "start-paper-repro-loop wrapper writes paper loop state" "paper loop state json" "$(cat "$TEST_DIR/.humanize/paper-repro/state.json" 2>/dev/null || true)"
fi

if "$MEMORY_SCRIPT" --input "$TEST_DIR/events.jsonl" --memory-dir "$TEST_DIR/.humanize/memory" --select-module ALG-001 > "$TEST_DIR/memory-selected.json" 2>/tmp/paper-repro-memory.out; then
  pass "paper-repro-memory wrapper captures and selects memory"
else
  fail "paper-repro-memory wrapper captures and selects memory" "exit 0" "$(cat /tmp/paper-repro-memory.out)"
fi

if jq -e 'length == 1 and .[0].memory_id == "MEM-EV-001"' "$TEST_DIR/memory-selected.json" >/dev/null 2>&1; then
  pass "paper-repro-memory wrapper returns structured selected memories"
else
  fail "paper-repro-memory wrapper returns structured selected memories" "selected MEM-EV-001" "$(cat "$TEST_DIR/memory-selected.json" 2>/dev/null || true)"
fi

mkdir -p "$TEST_DIR/.humanize/skills/candidates/benchmark-checklist"
cat > "$TEST_DIR/.humanize/skills/candidates/benchmark-checklist/SKILL.md" <<'MD'
# Benchmark Checklist

Record warmup, repeats, and hardware metadata before comparing numbers.
MD
cat > "$TEST_DIR/.humanize/skills/candidates/benchmark-checklist/skill-entry.json" <<'JSON'
{
  "skill_id": "benchmark-checklist",
  "state": "candidate",
  "provenance": {
    "source_memories": ["MEM-EV-001"],
    "source_checkpoint": "CHK-001",
    "authoring_agent": "skill_generator",
    "reviewer": "skill_reviewer",
    "timestamp": "2026-05-24T00:00:00Z"
  },
  "validation_commands": ["echo validate"],
  "created_at": "2026-05-24T00:00:00Z"
}
JSON
cat > "$TEST_DIR/.humanize/skills/registry.json" <<'JSON'
{
  "skills": [
    {"skill_id": "benchmark-checklist", "state": "active"}
  ]
}
JSON
if "$SKILL_CURATE_SCRIPT" --candidate "$TEST_DIR/.humanize/skills/candidates/benchmark-checklist" --output "$TEST_DIR/skill-audit.json" --registry "$TEST_DIR/.humanize/skills/registry.json" --skill-id benchmark-checklist > "$TEST_DIR/selected-skills.json" 2>/tmp/paper-repro-skill.out; then
  pass "paper-repro-skill-curate wrapper audits and selects skills"
else
  fail "paper-repro-skill-curate wrapper audits and selects skills" "exit 0" "$(cat /tmp/paper-repro-skill.out)"
fi

if jq -e '.status == "candidate_pass"' "$TEST_DIR/skill-audit.json" >/dev/null 2>&1 && jq -e 'length == 1 and .[0].skill_id == "benchmark-checklist"' "$TEST_DIR/selected-skills.json" >/dev/null 2>&1; then
  pass "paper-repro-skill-curate wrapper emits audit and selected active skills"
else
  fail "paper-repro-skill-curate wrapper emits audit and selected active skills" "candidate_pass audit and selected skill" "audit=$(cat "$TEST_DIR/skill-audit.json" 2>/dev/null || true) selected=$(cat "$TEST_DIR/selected-skills.json" 2>/dev/null || true)"
fi

print_test_summary "Paper Repro Command Artifact Tests"
