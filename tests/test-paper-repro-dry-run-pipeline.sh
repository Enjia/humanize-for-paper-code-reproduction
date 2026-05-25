#!/usr/bin/env bash
#
# Tests for deterministic Phase 1 paper reproduction dry-run pipeline.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PIPELINE="$PROJECT_ROOT/scripts/gen-paper-repro-plan-dry-run.sh"
VALIDATOR="$PROJECT_ROOT/scripts/validate-paper-repro-plan.sh"

echo "=========================================="
echo "Paper Repro Dry Run Pipeline Tests"
echo "=========================================="
echo ""

setup_test_dir
cd "$TEST_DIR"

cat > paper.md <<'TEXT'
# Routing Kernel Paper

Abstract: We claim the routing kernel improves inference throughput by 20 percent.

Section 3 Method: Algorithm 1 computes a route score using Equation 2.

Section 4 Experiments: We evaluate latency, throughput, memory, and warmup on one A100 GPU in Table 1.

Limitation: The exact driver version is not specified.
TEXT

if [[ -x "$PIPELINE" ]]; then
  pass "gen-paper-repro-plan-dry-run.sh exists and is executable"
else
  fail "gen-paper-repro-plan-dry-run.sh exists and is executable" "executable pipeline" "missing or not executable"
fi

if grep -q "paper-extract.sh" "$PIPELINE" && grep -q "paper-decompose.sh" "$PIPELINE"; then
  pass "dry-run pipeline uses standalone extract and decompose stages"
else
  fail "dry-run pipeline uses standalone extract and decompose stages" "paper-extract.sh and paper-decompose.sh calls" "missing"
fi

if "$PIPELINE" --input paper.md --output paper-repro-plan.md --manifest paper-repro-plan.json --workspace paper-repro/routing-kernel --budget smoke >/tmp/paper-dry-run.out 2>&1; then
  pass "dry-run pipeline completes"
else
  fail "dry-run pipeline completes" "exit 0" "$(cat /tmp/paper-dry-run.out)"
fi

if [[ -s paper-repro-plan.md ]]; then
  pass "dry-run pipeline writes markdown plan"
else
  fail "dry-run pipeline writes markdown plan" "paper-repro-plan.md" "missing"
fi

if [[ -s paper-repro-plan.json ]] && jq empty paper-repro-plan.json >/dev/null 2>&1; then
  pass "dry-run pipeline writes valid JSON manifest"
else
  fail "dry-run pipeline writes valid JSON manifest" "valid paper-repro-plan.json" "missing or invalid"
fi

if "$VALIDATOR" paper-repro-plan.json >/tmp/paper-dry-run-validate.out 2>&1; then
  pass "dry-run manifest passes validator"
else
  fail "dry-run manifest passes validator" "validator exit 0" "$(cat /tmp/paper-dry-run-validate.out)"
fi

if jq -e '.decomposition.modules | length >= 3' paper-repro-plan.json >/dev/null; then
  pass "dry-run manifest includes decomposition modules"
else
  fail "dry-run manifest includes decomposition modules" "at least 3 modules" "$(jq '.decomposition.modules' paper-repro-plan.json 2>/dev/null || true)"
fi

if jq -e '(.criteria | length >= 3) and all(.criteria[]; (.module_ids | length) >= 1)' paper-repro-plan.json >/dev/null; then
  pass "dry-run manifest includes module-bound criteria"
else
  fail "dry-run manifest includes module-bound criteria" "criteria with module_ids" "$(jq '.criteria' paper-repro-plan.json 2>/dev/null || true)"
fi

if jq -e '(.checkpoint_graph.checkpoints | length >= 1) and all(.checkpoint_graph.checkpoints[]; has("verification_commands") and (has("commands") | not))' paper-repro-plan.json >/dev/null; then
  pass "dry-run manifest includes checkpoint verification commands only"
else
  fail "dry-run manifest includes checkpoint verification commands only" "verification_commands and no checkpoint commands" "$(jq '.checkpoint_graph.checkpoints' paper-repro-plan.json 2>/dev/null || true)"
fi

if jq -e '(.tasks | length >= 1) and all(.tasks[]; has("lineage_mode") and (.module_ids | length >= 1) and (.criterion_ids | length >= 1) and has("checkpoint_id"))' paper-repro-plan.json >/dev/null; then
  pass "dry-run manifest includes lineage-bound tasks"
else
  fail "dry-run manifest includes lineage-bound tasks" "tasks with lineage" "$(jq '.tasks' paper-repro-plan.json 2>/dev/null || true)"
fi

if jq -e '(.agent_runs | length >= 4) and all(.agent_runs[]; has("redaction_status"))' paper-repro-plan.json >/dev/null; then
  pass "dry-run manifest records agent run audit entries"
else
  fail "dry-run manifest records agent run audit entries" "agent_runs with redaction_status" "$(jq '.agent_runs' paper-repro-plan.json 2>/dev/null || true)"
fi

if jq -e '
  ([.agent_runs[] | select(.exit_status != "running") | .role] | index("planner_a") and index("planner_b") and index("synthesizer") and index("checkpoint_planner")) and
  ([.agent_runs[] | select(.role == "planner_a" or .role == "planner_b") | .independence_group] | unique | length == 1) and
  ([.agent_runs[] | select(.role == "planner_a" or .role == "planner_b") | .run_id] | unique | length >= 2)
' paper-repro-plan.json >/dev/null; then
  pass "dry-run planning agents are recorded through independent agent-runner runs"
else
  fail "dry-run planning agents are recorded through independent agent-runner runs" "planner_a/planner_b/synthesizer/checkpoint_planner finalized runs" "$(jq '.agent_runs' paper-repro-plan.json 2>/dev/null || true)"
fi

if jq -e '
  .planning_trace.independent_plans.planner_a_artifact and
  .planning_trace.independent_plans.planner_b_artifact and
  .planning_trace.synthesis_artifact and
  (.planning_trace.synthesis_decisions | length >= 1) and
  has("planning_trace") and
  (.planning_trace | has("unresolved_disagreements")) and
  (.planning_trace.final_review_notes | length >= 1)
' paper-repro-plan.json >/dev/null; then
  pass "dry-run manifest records independent plans, synthesis decisions, disagreements, and final review notes"
else
  fail "dry-run manifest records independent plans, synthesis decisions, disagreements, and final review notes" "planning_trace with plan/synthesis/review fields" "$(jq '.planning_trace' paper-repro-plan.json 2>/dev/null || true)"
fi

if jq -e '.artifact_profile.not_applicable_artifacts | index("training_script")' paper-repro-plan.json >/dev/null; then
  pass "dry-run inference manifest marks training not applicable"
else
  fail "dry-run inference manifest marks training not applicable" "training_script not applicable" "$(jq '.artifact_profile' paper-repro-plan.json 2>/dev/null || true)"
fi

mkdir -p .humanize mock-bin
cat > .humanize/config.json <<'JSON'
{
  "planner_strategy": "mixed",
  "planner_a_provider": "codex",
  "planner_a_model": "gpt-5.5",
  "planner_a_effort": "high",
  "planner_b_provider": "claude",
  "planner_b_model": "sonnet",
  "planner_b_effort": "high",
  "planner_synthesizer_provider": "codex",
  "planner_synthesizer_model": "gpt-5.5",
  "planner_synthesizer_effort": "medium",
  "checkpoint_planner_provider": "claude",
  "checkpoint_planner_model": "sonnet",
  "checkpoint_planner_effort": "medium"
}
JSON

cat > mock-bin/codex <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output_artifact=""
summary_artifact=""
role=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-artifact) output_artifact="$2"; shift 2 ;;
    --summary-artifact) summary_artifact="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$(dirname "$output_artifact")"
printf '{"provider":"codex","role":"%s"}\n' "$role" > "$output_artifact"
if [[ -n "$summary_artifact" ]]; then
  mkdir -p "$(dirname "$summary_artifact")"
  printf 'codex summary for %s\n' "$role" > "$summary_artifact"
fi
MOCK
cat > mock-bin/claude <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output_artifact=""
summary_artifact=""
role=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-artifact) output_artifact="$2"; shift 2 ;;
    --summary-artifact) summary_artifact="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$(dirname "$output_artifact")"
printf '{"provider":"claude","role":"%s"}\n' "$role" > "$output_artifact"
if [[ -n "$summary_artifact" ]]; then
  mkdir -p "$(dirname "$summary_artifact")"
  printf 'claude summary for %s\n' "$role" > "$summary_artifact"
fi
MOCK
chmod +x mock-bin/codex mock-bin/claude

if PATH="$TEST_DIR/mock-bin:$PATH" "$PIPELINE" --input paper.md --output provider-plan.md --manifest provider-plan.json --workspace paper-repro/provider-routing --budget smoke >/tmp/paper-dry-run-provider.out 2>&1; then
  pass "dry-run pipeline completes with configured provider roles"
else
  fail "dry-run pipeline completes with configured provider roles" "exit 0" "$(cat /tmp/paper-dry-run-provider.out)"
fi

if jq -e '
  .provider_roles.planner_strategy == "mixed" and
  .provider_roles.planner_a.provider == "codex" and
  .provider_roles.planner_b.provider == "claude" and
  .provider_roles.synthesizer.provider == "codex" and
  .provider_roles.checkpoint_planner.provider == "claude"
' provider-plan.json >/dev/null; then
  pass "dry-run manifest records resolved provider roles"
else
  fail "dry-run manifest records resolved provider roles" "resolved provider role map" "$(jq '.provider_roles' provider-plan.json 2>/dev/null || true)"
fi

if jq -e '
  ([.agent_runs[] | select(.role == "planner_a") | .provider] == ["codex"]) and
  ([.agent_runs[] | select(.role == "planner_b") | .provider] == ["claude"]) and
  ([.agent_runs[] | select(.role == "synthesizer") | .provider] == ["codex"]) and
  ([.agent_runs[] | select(.role == "checkpoint_planner") | .provider] == ["claude"])
' provider-plan.json >/dev/null; then
  pass "dry-run planning agent runs use configured providers"
else
  fail "dry-run planning agent runs use configured providers" "provider-specific agent runs" "$(jq '.agent_runs' provider-plan.json 2>/dev/null || true)"
fi

print_test_summary "Paper Repro Dry Run Pipeline Tests"
