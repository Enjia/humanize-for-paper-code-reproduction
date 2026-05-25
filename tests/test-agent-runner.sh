#!/usr/bin/env bash
# Tests for audited paper-run-scoped agent execution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

AGENT_RUNNER="$PROJECT_ROOT/scripts/lib/agent-runner.sh"

echo "=========================================="
echo "Agent Runner Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -s "$AGENT_RUNNER" ]]; then
  pass "agent-runner.sh exists"
else
  fail "agent-runner.sh exists" "non-empty file" "missing"
  print_test_summary "Agent Runner Tests"
  exit 1
fi

# shellcheck source=../scripts/lib/agent-runner.sh
source "$AGENT_RUNNER"

mkdir -p "$TEST_DIR/inputs" "$TEST_DIR/outputs" "$TEST_DIR/paper-repro"
printf 'paper evidence' > "$TEST_DIR/inputs/evidence-map.json"

run_json=$(agent_runner_run \
  --role paper_decomposer \
  --provider mock \
  --model deterministic \
  --effort none \
  --timeout 60 \
  --workspace "$TEST_DIR/paper-repro" \
  --workspace-scope read_only \
  --write-policy none \
  --network-policy disabled \
  --input-artifact "$TEST_DIR/inputs/evidence-map.json" \
  --output-artifact "$TEST_DIR/outputs/decomposition.json" \
  --summary-artifact "$TEST_DIR/outputs/summary.md" \
  --manifest "$TEST_DIR/agent-runs.jsonl")

if jq -e '.run_id and .role == "paper_decomposer" and .provider == "mock" and .redaction_status == "not_needed" and .exit_status == "success"' <<<"$run_json" >/dev/null; then
  pass "agent_runner_run returns a valid agent-run record"
else
  fail "agent_runner_run returns a valid agent-run record" "valid JSON record" "$run_json"
fi

if [[ -s "$TEST_DIR/agent-runs.jsonl" ]] && jq -e '.role == "paper_decomposer" and (.input_artifacts | length == 1) and (.output_artifacts | length == 1)' "$TEST_DIR/agent-runs.jsonl" >/dev/null; then
  pass "agent_runner_run appends audit record to manifest"
else
  fail "agent_runner_run appends audit record to manifest" "jsonl audit record" "$(cat "$TEST_DIR/agent-runs.jsonl" 2>/dev/null || true)"
fi

run_id=$(jq -r '.run_id' <<<"$run_json")
if [[ -s "$TEST_DIR/agent-runs.jsonl" ]] && jq -e -s --arg run_id "$run_id" '
  ([.[] | select(.run_id == $run_id)] | length) == 2 and
  (.[0].run_id == $run_id) and
  (.[0].exit_status == "running") and
  (.[0].ended_at == null) and
  (.[1].run_id == $run_id) and
  (.[1].exit_status == "success") and
  (.[1].ended_at != null)
' "$TEST_DIR/agent-runs.jsonl" >/dev/null; then
  pass "agent_runner_run records lifecycle start before final success"
else
  fail "agent_runner_run records lifecycle start before final success" "running and success records for one run" "$(cat "$TEST_DIR/agent-runs.jsonl" 2>/dev/null || true)"
fi

if [[ -s "$TEST_DIR/outputs/decomposition.json" && -s "$TEST_DIR/outputs/summary.md" ]]; then
  pass "mock provider writes declared output and summary artifacts"
else
  fail "mock provider writes declared output and summary artifacts" "output files" "missing"
fi

BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/codex" <<'MOCK'
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
mkdir -p "$(dirname "$summary_artifact")"
printf 'codex summary for %s\n' "$role" > "$summary_artifact"
MOCK
chmod +x "$BIN_DIR/codex"

provider_run_json=$(PATH="$BIN_DIR:$PATH" agent_runner_run \
  --role planner_a \
  --provider codex \
  --model gpt-5.5 \
  --effort medium \
  --timeout 60 \
  --workspace "$TEST_DIR/provider-workspace" \
  --workspace-scope read_only \
  --write-policy none \
  --network-policy disabled \
  --input-artifact "$TEST_DIR/inputs/evidence-map.json" \
  --output-artifact "$TEST_DIR/provider-outputs/planner-a.json" \
  --summary-artifact "$TEST_DIR/provider-outputs/planner-a-summary.md" \
  --manifest "$TEST_DIR/provider-agent-runs.jsonl")

if jq -e '.provider == "codex" and .role == "planner_a" and .exit_status == "success"' <<<"$provider_run_json" >/dev/null; then
  pass "agent_runner_run executes codex provider through adapter"
else
  fail "agent_runner_run executes codex provider through adapter" "successful codex-backed agent-run record" "$provider_run_json"
fi

if [[ -s "$TEST_DIR/provider-outputs/planner-a.json" ]] && jq -e '.provider == "codex" and .role == "planner_a"' "$TEST_DIR/provider-outputs/planner-a.json" >/dev/null && [[ -s "$TEST_DIR/provider-outputs/planner-a-summary.md" ]]; then
  pass "provider adapter creates declared artifacts"
else
  fail "provider adapter creates declared artifacts" "codex output and summary artifacts" "$(cat "$TEST_DIR/provider-outputs/planner-a.json" 2>/dev/null || true)"
fi

provider_run_id=$(jq -r '.run_id' <<<"$provider_run_json")
if [[ -s "$TEST_DIR/provider-agent-runs.jsonl" ]] && jq -e -s --arg run_id "$provider_run_id" '
  ([.[] | select(.run_id == $run_id)] | length) == 2 and
  (.[0].exit_status == "running") and
  (.[1].exit_status == "success") and
  (.[1].provider == "codex")
' "$TEST_DIR/provider-agent-runs.jsonl" >/dev/null; then
  pass "provider-backed agent runs record lifecycle entries"
else
  fail "provider-backed agent runs record lifecycle entries" "running and success records for codex run" "$(cat "$TEST_DIR/provider-agent-runs.jsonl" 2>/dev/null || true)"
fi

stderr_out=""
exit_code=0
stderr_out=$(agent_runner_run \
  --role paper_decomposer \
  --provider mock \
  --model deterministic \
  --workspace "$TEST_DIR/paper-repro" \
  --workspace-scope read_only \
  --write-policy none \
  --network-policy disabled \
  --input-artifact "$TEST_DIR/inputs/evidence-map.json" \
  --output-artifact "$TEST_DIR/paper-repro/illegal.json" \
  --manifest "$TEST_DIR/bad.jsonl" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "read-only" <<<"$stderr_out"; then
  pass "read-only roles cannot write to reproduction workspace"
else
  fail "read-only roles cannot write to reproduction workspace" "non-zero read-only policy error" "exit=$exit_code stderr=$stderr_out"
fi

stderr_out=""
exit_code=0
stderr_out=$(agent_runner_run \
  --role implementation_worker \
  --provider mock \
  --model deterministic \
  --workspace "$TEST_DIR/paper-repro" \
  --workspace-scope workspace_write \
  --write-policy workspace-only \
  --network-policy disabled \
  --input-artifact "$TEST_DIR/inputs/evidence-map.json" \
  --output-artifact "$TEST_DIR/outside.json" \
  --manifest "$TEST_DIR/bad-worker.jsonl" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "outside" <<<"$stderr_out"; then
  pass "worker roles cannot write outside configured reproduction workspace"
else
  fail "worker roles cannot write outside configured reproduction workspace" "non-zero outside-workspace error" "exit=$exit_code stderr=$stderr_out"
fi

print_test_summary "Agent Runner Tests"
