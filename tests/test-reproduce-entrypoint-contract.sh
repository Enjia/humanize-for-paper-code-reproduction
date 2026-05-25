#!/usr/bin/env bash
# Tests for final reproduction package entrypoint contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

TEMPLATE="$PROJECT_ROOT/templates/reproduce.sh"
REPORT_TEMPLATE="$PROJECT_ROOT/templates/reproduction-report.md"
AUDIT="$PROJECT_ROOT/scripts/repro-package-audit.sh"

echo "=========================================="
echo "Reproduce Entrypoint Contract Tests"
echo "=========================================="
echo ""

setup_test_dir

for file in "$TEMPLATE" "$REPORT_TEMPLATE"; do
  if [[ -s "$file" ]]; then
    pass "template exists: $(basename "$file")"
  else
    fail "template exists: $(basename "$file")" "non-empty file" "missing"
  fi
done

if [[ -x "$AUDIT" ]]; then
  pass "repro-package-audit.sh exists and is executable"
else
  fail "repro-package-audit.sh exists and is executable" "executable script" "missing"
fi

WORKSPACE="$TEST_DIR/workspace"
mkdir -p "$WORKSPACE"
cp "$TEMPLATE" "$WORKSPACE/reproduce.sh" 2>/dev/null || true
chmod +x "$WORKSPACE/reproduce.sh" 2>/dev/null || true
cat > "$WORKSPACE/results.json" <<'JSON'
{
  "schema_version": "paper-repro-results/v1",
  "runs": [
    {"run_id": "RUN-001", "checkpoint_id": "CHK-001", "module_ids": ["ALG-001"], "criterion_ids": ["CRIT-001"], "status": "reproduced", "metrics": {"throughput": 120.0}}
  ],
  "summary": {"reproduced": 1, "partially_reproduced": 0, "failed": 0, "blocked": 0, "not_applicable": 0}
}
JSON
cat > "$WORKSPACE/reproduction-report.md" <<'MD'
# Reproduction Report

module_id: ALG-001
criterion_id: CRIT-001
checkpoint_id: CHK-001
evidence: CLAIM-001
MD

if "$AUDIT" --workspace "$WORKSPACE" >/tmp/repro-audit.out 2>&1; then
  pass "package audit accepts valid reproduction package"
else
  fail "package audit accepts valid reproduction package" "exit 0" "$(cat /tmp/repro-audit.out)"
fi

TEMPLATE_WORKSPACE="$TEST_DIR/template-workspace"
mkdir -p "$TEMPLATE_WORKSPACE"
cp "$TEMPLATE" "$TEMPLATE_WORKSPACE/reproduce.sh"
chmod +x "$TEMPLATE_WORKSPACE/reproduce.sh"
if "$TEMPLATE_WORKSPACE/reproduce.sh" --run-id RUN-TEMPLATE-001 >/tmp/reproduce-template.out 2>&1; then
  pass "reproduce.sh template runs with explicit run id"
else
  fail "reproduce.sh template runs with explicit run id" "exit 0" "$(cat /tmp/reproduce-template.out)"
fi

CLI_WORKSPACE="$TEST_DIR/cli-workspace"
mkdir -p "$CLI_WORKSPACE"
cp "$TEMPLATE" "$CLI_WORKSPACE/reproduce.sh"
chmod +x "$CLI_WORKSPACE/reproduce.sh"
if "$CLI_WORKSPACE/reproduce.sh" --run-id RUN-CLI-001 --smoke --offline --skip-download --seed 123 --output-dir custom-outputs/RUN-CLI-001 >/tmp/reproduce-cli.out 2>&1; then
  pass "reproduce.sh template accepts planned top-level CLI options"
else
  fail "reproduce.sh template accepts planned top-level CLI options" "exit 0" "$(cat /tmp/reproduce-cli.out)"
fi

if [[ -s "$CLI_WORKSPACE/results.json" && -s "$CLI_WORKSPACE/custom-outputs/RUN-CLI-001/results.json" ]] && \
  jq -e '.latest_run_id == "RUN-CLI-001" and .latest_run.path == "custom-outputs/RUN-CLI-001/results.json"' "$CLI_WORKSPACE/results.json" >/dev/null && \
  jq -e '.run_id == "RUN-CLI-001" and .run_mode == "smoke" and .execution.offline == true and .execution.skip_download == true and .execution.seed == 123 and .execution.output_dir == "custom-outputs/RUN-CLI-001"' "$CLI_WORKSPACE/custom-outputs/RUN-CLI-001/results.json" >/dev/null; then
  pass "reproduce.sh records execution mode flags and custom output path"
else
  fail "reproduce.sh records execution mode flags and custom output path" "results index and per-run execution metadata" "root=$(cat "$CLI_WORKSPACE/results.json" 2>/dev/null || true) run=$(cat "$CLI_WORKSPACE/custom-outputs/RUN-CLI-001/results.json" 2>/dev/null || true)"
fi

if [[ -s "$TEMPLATE_WORKSPACE/results.json" && -s "$TEMPLATE_WORKSPACE/outputs/RUN-TEMPLATE-001/results.json" ]] && \
  jq -e '.schema_version == "paper-repro-results-index/v1" and .latest_run_id == "RUN-TEMPLATE-001" and (.run_ids | index("RUN-TEMPLATE-001")) and .latest_run.path == "outputs/RUN-TEMPLATE-001/results.json"' "$TEMPLATE_WORKSPACE/results.json" >/dev/null && \
  jq -e '.schema_version == "paper-repro-run-results/v1" and .run_id == "RUN-TEMPLATE-001" and has("checkpoint_results") and has("summary")' "$TEMPLATE_WORKSPACE/outputs/RUN-TEMPLATE-001/results.json" >/dev/null; then
  pass "reproduce.sh writes root results index and immutable per-run results"
else
  fail "reproduce.sh writes root results index and immutable per-run results" "root index and outputs/RUN-TEMPLATE-001/results.json" "root=$(cat "$TEMPLATE_WORKSPACE/results.json" 2>/dev/null || true) run=$(cat "$TEMPLATE_WORKSPACE/outputs/RUN-TEMPLATE-001/results.json" 2>/dev/null || true)"
fi

LARGE_BAD="$TEST_DIR/large-bad-workspace"
mkdir -p "$LARGE_BAD"
cp "$TEMPLATE" "$LARGE_BAD/reproduce.sh"
chmod +x "$LARGE_BAD/reproduce.sh"
"$LARGE_BAD/reproduce.sh" --run-id RUN-LARGE-001 >/dev/null
cat > "$LARGE_BAD/reproduction-report.md" <<'MD'
# Reproduction Report

module_id: ALG-001
criterion_id: CRIT-001
checkpoint_id: CHK-001
evidence: CLAIM-001
MD
python3 - "$LARGE_BAD/large-generated.bin" <<'PY'
import sys
with open(sys.argv[1], "wb") as f:
    f.write(b"x" * (2 * 1024 * 1024))
PY
if "$AUDIT" --workspace "$LARGE_BAD" >/tmp/repro-audit.out 2>&1; then
  fail "package audit rejects large generated artifacts outside outputs" "non-zero exit" "audit passed"
else
  if grep -q "outputs" /tmp/repro-audit.out && grep -q "large" /tmp/repro-audit.out; then
    pass "package audit rejects large generated artifacts outside outputs"
  else
    fail "large artifact policy error mentions outputs" "outputs and large" "$(cat /tmp/repro-audit.out)"
  fi
fi

BAD="$TEST_DIR/bad-workspace"
mkdir -p "$BAD"
cp "$WORKSPACE/results.json" "$BAD/results.json"
if "$AUDIT" --workspace "$BAD" >/tmp/repro-audit.out 2>&1; then
  fail "package audit rejects missing reproduce.sh" "non-zero exit" "audit passed"
else
  if grep -q "reproduce.sh" /tmp/repro-audit.out; then
    pass "package audit rejects missing reproduce.sh"
  else
    fail "missing reproduce.sh error mentions file" "reproduce.sh" "$(cat /tmp/repro-audit.out)"
  fi
fi

NO_REPORT="$TEST_DIR/no-report-workspace"
mkdir -p "$NO_REPORT"
printf '#!/usr/bin/env bash\nexit 0\n' > "$NO_REPORT/reproduce.sh"
chmod +x "$NO_REPORT/reproduce.sh"
cp "$WORKSPACE/results.json" "$NO_REPORT/results.json"
if "$AUDIT" --workspace "$NO_REPORT" >/tmp/repro-audit.out 2>&1; then
  fail "package audit rejects missing reproduction report" "non-zero exit" "audit passed"
else
  if grep -q "reproduction-report.md" /tmp/repro-audit.out; then
    pass "package audit rejects missing reproduction report"
  else
    fail "missing reproduction report error mentions file" "reproduction-report.md" "$(cat /tmp/repro-audit.out)"
  fi
fi

BAD_RESULTS="$TEST_DIR/bad-results"
mkdir -p "$BAD_RESULTS"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BAD_RESULTS/reproduce.sh"
chmod +x "$BAD_RESULTS/reproduce.sh"
printf '{}' > "$BAD_RESULTS/results.json"
if "$AUDIT" --workspace "$BAD_RESULTS" >/tmp/repro-audit.out 2>&1; then
  fail "package audit rejects invalid results.json" "non-zero exit" "audit passed"
else
  if grep -q "results.json" /tmp/repro-audit.out; then
    pass "package audit rejects invalid results.json"
  else
    fail "invalid results.json error mentions file" "results.json" "$(cat /tmp/repro-audit.out)"
  fi
fi

print_test_summary "Reproduce Entrypoint Contract Tests"
