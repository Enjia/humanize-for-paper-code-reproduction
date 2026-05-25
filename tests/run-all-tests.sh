#!/usr/bin/env bash
#
# Run all test suites for the Humanize plugin (parallel execution)
#
# Usage: ./tests/run-all-tests.sh
#
# Each test suite runs in its own isolated temp directory, so parallel
# execution is safe with no shared state or resource contention.
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNAL_WRAPPER="$PROJECT_ROOT/scripts/run-with-default-signals.py"

# Max parallel test jobs (throttle to avoid resource exhaustion in small CI runners).
# Override with HUMANIZE_TEST_JOBS=<N>.
default_jobs() {
    local n=4
    if command -v getconf >/dev/null 2>&1; then
        n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
    fi
    [[ "$n" =~ ^[0-9]+$ ]] || n=4
    # Cap by default to keep memory/process usage bounded.
    [[ "$n" -gt 8 ]] && n=8
    [[ "$n" -lt 1 ]] && n=1
    echo "$n"
}

MAX_JOBS="${HUMANIZE_TEST_JOBS:-$(default_jobs)}"
if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || [[ "$MAX_JOBS" -lt 1 ]]; then
    echo "Error: HUMANIZE_TEST_JOBS must be an integer >= 1, got: ${HUMANIZE_TEST_JOBS:-}" >&2
    exit 1
fi

# wait -n is available starting from bash 4.3
supports_wait_n() {
    local major="${BASH_VERSINFO[0]:-0}"
    local minor="${BASH_VERSINFO[1]:-0}"
    [[ "$major" -gt 4 ]] || ( [[ "$major" -eq 4 ]] && [[ "$minor" -ge 3 ]] )
}

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'
esc=$'\033'

echo "========================================"
echo "Running All Humanize Plugin Tests"
echo "========================================"
echo "Parallel jobs: $MAX_JOBS"
echo ""

# Test suites to run
DEFAULT_TEST_SUITES=(
    "test-template-loader.sh"
    "test-bash-validator-patterns.sh"
    "test-todo-checker.sh"
    "test-plan-file-validation.sh"
    "test-template-references.sh"
    "test-state-exit-naming.sh"
    "test-stop-gate.sh"
    "test-templates-comprehensive.sh"
    "test-plan-file-hooks.sh"
    "test-stop-hook-legacy-compat.sh"
    "test-stop-hook-bg-allow.sh"
    "test-error-scenarios.sh"
    "test-ansi-parsing.sh"
    "test-run-all-tests-progress.sh"
    "test-allowlist-validators.sh"
    "test-finalize-phase.sh"
    "test-codex-review-merge.sh"
    "test-cancel-signal-file.sh"
    "test-humanize-escape.sh"
    "test-zsh-monitor-safety.sh"
    "test-monitor-runtime.sh"
    "test-run-with-default-signals.sh"
    "test-monitor-e2e-deletion.sh"
    "test-monitor-e2e-sigint.sh"
    "test-gen-plan.sh"
    "test-provider-role-routing.sh"
    "test-agent-runner.sh"
    "test-runtime-adapter-layer.sh"
    "test-agent-run-independence.sh"
    "test-snapshot-manager.sh"
    "test-paper-repro-plan.sh"
    "test-gen-paper-repro-plan.sh"
    "test-paper-extract-and-decompose.sh"
    "test-paper-repro-planner-agents.sh"
    "test-paper-type-classification.sh"
    "test-paper-evidence-map.sh"
    "test-checkpoint-graph.sh"
    "test-paper-repro-loop.sh"
    "test-parent-child-review.sh"
    "test-reproduce-entrypoint-contract.sh"
    "test-result-compare-tolerances.sh"
    "test-memory-lifecycle.sh"
    "test-memory-workflow.sh"
    "test-skill-lifecycle.sh"
    "test-skill-safety.sh"
    "test-skill-workflow.sh"
    "test-paper-repro-docs.sh"
    "test-paper-repro-command-artifacts.sh"
    "test-paper-input-safety-audit.sh"
    "test-checkpoint-state-migration.sh"
    "test-checkpoint-prompt-templates.sh"
    "test-paper-decomposition.sh"
    "test-paper-prompt-injection.sh"
    "test-paper-input-privacy.sh"
    "test-artifact-profile.sh"
    "test-paper-repro-dry-run-pipeline.sh"
    "test-refine-plan.sh"
    "test-task-tag-routing.sh"
    "test-config-merge.sh"
    "test-config-error-handling.sh"
    "test-codex-hook-install.sh"
    "test-unified-codex-config.sh"
    "test-disable-nested-codex-hooks.sh"
    # Session ID and Agent Teams tests
    "test-session-id.sh"
    "test-agent-teams.sh"
    # Ask Codex tests
    "test-ask-codex.sh"
    # Bitlesson routing tests
    "test-bitlesson-select-routing.sh"
    # Provider routing tests
    "test-model-router.sh"
    # Skill monitor tests
    "test-skill-monitor.sh"
    # Robustness tests
    "robustness/test-state-file-robustness.sh"
    "robustness/test-session-robustness.sh"
    "robustness/test-goal-tracker-robustness.sh"
    "robustness/test-path-validation-robustness.sh"
    "robustness/test-git-operations-robustness.sh"
    "robustness/test-hook-input-robustness.sh"
    "robustness/test-template-stress-robustness.sh"
    "robustness/test-plan-file-robustness.sh"
    "robustness/test-cancel-security-robustness.sh"
    "robustness/test-timeout-robustness.sh"
    "robustness/test-base-branch-detection.sh"
    "robustness/test-setup-scripts-robustness.sh"
    "robustness/test-concurrent-state-robustness.sh"
    "robustness/test-hook-system-robustness.sh"
    "robustness/test-template-error-robustness.sh"
    "robustness/test-state-transition-robustness.sh"
)

TEST_SUITES=("${DEFAULT_TEST_SUITES[@]}")
if [[ -n "${HUMANIZE_TEST_SUITES:-}" ]]; then
    TEST_SUITES=()
    IFS=',' read -r -a TEST_SUITES <<< "$HUMANIZE_TEST_SUITES"
fi

# Tests that must be run with zsh (not bash)
ZSH_TESTS=(
    "test-zsh-monitor-safety.sh"
)

# Temp directory for per-suite output files
OUTPUT_DIR=$(mktemp -d)
trap "rm -rf $OUTPUT_DIR" EXIT

# Provide a mock codex binary when the real one is not installed.
# Tests only need codex to pass the `command -v codex` check in setup scripts;
# tests that require specific codex behavior already create their own mocks.
if ! command -v codex &>/dev/null; then
    mkdir -p "$OUTPUT_DIR/mock-bin"
    cat > "$OUTPUT_DIR/mock-bin/codex" << 'MOCK_CODEX'
#!/usr/bin/env bash
exit 0
MOCK_CODEX
    chmod +x "$OUTPUT_DIR/mock-bin/codex"
    export PATH="$OUTPUT_DIR/mock-bin:$PATH"
fi

# Check if a suite needs zsh
needs_zsh() {
    local suite="$1"
    for zsh_test in "${ZSH_TESTS[@]}"; do
        if [[ "$suite" == "$zsh_test" ]]; then
            return 0
        fi
    done
    return 1
}

# Format milliseconds as human-readable duration
format_ms() {
    local ms="$1"
    local s=$((ms / 1000))
    local frac=$(( (ms % 1000) / 100 ))  # tenths of a second
    echo "${s}.${frac}s"
}

current_ms() {
    # BSD date on macOS does not support %N. Seconds precision is enough for
    # suite ordering and keeps this runner compatible with Bash 3.
    echo "$(($(date +%s) * 1000))"
}

SKIPPED_SUITES=()
SKIPPED_REASONS=()
RUNNABLE_SUITES=()

for suite in "${TEST_SUITES[@]}"; do
    suite_path="$SCRIPT_DIR/$suite"

    if [[ ! -f "$suite_path" ]]; then
        SKIPPED_SUITES+=("$suite")
        SKIPPED_REASONS+=("not found")
        continue
    fi

    if needs_zsh "$suite" && ! command -v zsh &>/dev/null; then
        SKIPPED_SUITES+=("$suite")
        SKIPPED_REASONS+=("zsh not available")
        continue
    fi

    RUNNABLE_SUITES+=("$suite")
done

RUN_SUITES=()
RUN_PIDS=()
ACTIVE_PIDS=()
COLLECTED_FLAGS=()
COMPLETED_SUITES=0
TOTAL_RUN_SUITES="${#RUNNABLE_SUITES[@]}"
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_SUITES=()
# Sortable file: elapsed_ms<TAB>display_line
SORT_FILE="$OUTPUT_DIR/sortable.txt"
: > "$SORT_FILE"

collect_suite_result() {
    local idx="$1"
    local suite pid safe_name out_file exit_file time_file exit_code output elapsed_ms elapsed_display
    local output_stripped passed failed zsh_label line progress_status progress_detail

    if [[ "${COLLECTED_FLAGS[$idx]:-0}" -eq 1 ]]; then
        return
    fi

    suite="${RUN_SUITES[$idx]}"
    pid="${RUN_PIDS[$idx]}"
    wait "$pid" 2>/dev/null || true

    safe_name="$(echo "$suite" | tr '/' '_')"
    out_file="$OUTPUT_DIR/${safe_name}.out"
    exit_file="$OUTPUT_DIR/${safe_name}.exit"
    time_file="$OUTPUT_DIR/${safe_name}.time"

    exit_code=$(cat "$exit_file" 2>/dev/null || echo "1")
    output=$(cat "$out_file" 2>/dev/null || echo "")
    elapsed_ms=$(cat "$time_file" 2>/dev/null || echo "0")
    elapsed_display=$(format_ms "$elapsed_ms")

    output_stripped=$(echo "$output" | sed "s/${esc}\\[[0-9;]*m//g")
    passed=$(echo "$output_stripped" | grep -oE 'Passed:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' | tail -1 || echo "0")
    failed=$(echo "$output_stripped" | grep -oE 'Failed:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' | tail -1 || echo "0")

    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))

    if [[ $exit_code -ne 0 ]] || [[ "$failed" -gt 0 ]]; then
        FAILED_SUITES+=("$suite")
        line=$(echo -e "${RED}FAILED${NC}: $suite (exit code: $exit_code, failed: $failed, ${elapsed_display})")
        printf '%d\t%s\n' "$elapsed_ms" "$line" >> "$SORT_FILE"
        printf '%s\n' "$output" > "$OUTPUT_DIR/${safe_name}.detail"
        progress_status="FAILED"
        progress_detail="exit code: $exit_code, failed: $failed"
    else
        zsh_label=""
        needs_zsh "$suite" && zsh_label=" (zsh)"
        line=$(echo -e "${GREEN}PASSED${NC}: $suite${zsh_label} ($passed tests, ${elapsed_display})")
        printf '%d\t%s\n' "$elapsed_ms" "$line" >> "$SORT_FILE"
        progress_status="PASSED"
        progress_detail="$passed tests"
    fi

    COMPLETED_SUITES=$((COMPLETED_SUITES + 1))
    echo "[$COMPLETED_SUITES/$TOTAL_RUN_SUITES] $progress_status: $suite ($progress_detail, ${elapsed_display})"
    COLLECTED_FLAGS[$idx]=1
}

collect_finished_suites() {
    local idx pid
    for idx in "${!RUN_SUITES[@]}"; do
        if [[ "${COLLECTED_FLAGS[$idx]:-0}" -eq 1 ]]; then
            continue
        fi
        pid="${RUN_PIDS[$idx]}"
        if ! kill -0 "$pid" 2>/dev/null; then
            collect_suite_result "$idx"
        fi
    done
}

wait_for_any_active_pid() {
    local still_running found_finished pid
    while true; do
        still_running=()
        found_finished=0
        for pid in "${ACTIVE_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                still_running+=("$pid")
            else
                found_finished=1
            fi
        done
        ACTIVE_PIDS=("${still_running[@]}")
        if [[ "$found_finished" -eq 1 ]]; then
            return
        fi
        sleep 1
    done
}

for suite in "${RUNNABLE_SUITES[@]}"; do
    suite_path="$SCRIPT_DIR/$suite"
    safe_name="$(echo "$suite" | tr '/' '_')"
    out_file="$OUTPUT_DIR/${safe_name}.out"
    exit_file="$OUTPUT_DIR/${safe_name}.exit"
    time_file="$OUTPUT_DIR/${safe_name}.time"

    if needs_zsh "$suite"; then
        (
            t_start=$(current_ms)
            "$SIGNAL_WRAPPER" zsh "$suite_path" >"$out_file" 2>&1
            echo $? >"$exit_file"
            echo $(( $(current_ms) - t_start )) >"$time_file"
        ) &
    else
        (
            t_start=$(current_ms)
            "$SIGNAL_WRAPPER" "$suite_path" >"$out_file" 2>&1
            echo $? >"$exit_file"
            echo $(( $(current_ms) - t_start )) >"$time_file"
        ) &
    fi
    RUN_SUITES+=("$suite")
    RUN_PIDS+=("$!")
    ACTIVE_PIDS+=("$!")
    COLLECTED_FLAGS+=("0")

    # Throttle background jobs
    while [[ "${#ACTIVE_PIDS[@]}" -ge "$MAX_JOBS" ]]; do
        if supports_wait_n; then
            wait -n 2>/dev/null || true
            # Prune finished PIDs from ACTIVE_PIDS
            still_running=()
            for pid in "${ACTIVE_PIDS[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    still_running+=("$pid")
                fi
            done
            ACTIVE_PIDS=("${still_running[@]}")
            collect_finished_suites
        else
            # Bash 3 fallback: poll until any active PID exits, then collect it.
            wait_for_any_active_pid
            collect_finished_suites
        fi
    done
done

collect_finished_suites

for i in "${!RUN_SUITES[@]}"; do
    collect_suite_result "$i"
done

# Print skipped suites first
for i in "${!SKIPPED_SUITES[@]}"; do
    echo -e "${YELLOW}SKIP${NC}: ${SKIPPED_SUITES[$i]} (${SKIPPED_REASONS[$i]})"
done

# Print results sorted by elapsed time (fastest first)
sort -t$'\t' -k1,1n "$SORT_FILE" | cut -f2-

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Total Passed: ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Total Failed: ${RED}$TOTAL_FAILED${NC}"
echo ""

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo -e "${RED}Failed Test Suites:${NC}"
    for suite in "${FAILED_SUITES[@]}"; do
        echo "  - $suite"
        safe_name="$(echo "$suite" | tr '/' '_')"
        detail_file="$OUTPUT_DIR/${safe_name}.detail"
        if [[ -f "$detail_file" ]]; then
            echo "    ----------------------------------------"
            sed 's/^/    /' "$detail_file"
            echo ""
        fi
    done
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
