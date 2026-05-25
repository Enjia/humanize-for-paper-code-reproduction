#!/usr/bin/env bash
#
# Tests for the test-runner signal reset wrapper.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$PROJECT_ROOT/scripts/run-with-default-signals.py"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    echo "  Expected: $2"
    echo "  Got: $3"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/sigint-trap.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -u
cleanup_triggered=false

_cleanup() {
    cleanup_triggered=true
    echo "CLEANUP_BY_SIGINT"
}

trap '_cleanup' INT

(
    sleep 0.1
    kill -INT $$
) &
child_pid=$!

for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.1
    [[ "$cleanup_triggered" == "true" ]] && break
done

wait "$child_pid" 2>/dev/null || true

[[ "$cleanup_triggered" == "true" ]]
SCRIPT
chmod +x "$TEST_DIR/sigint-trap.sh"

echo "========================================"
echo "Run With Default Signals Tests"
echo "========================================"
echo ""

echo "Test 1: baseline inherited ignored SIGINT prevents bash trap"
set +e
baseline_output=$(bash -c 'trap "" INT; "$1"' bash "$TEST_DIR/sigint-trap.sh" 2>&1)
baseline_exit=$?
set -e
if [[ $baseline_exit -ne 0 ]] && ! echo "$baseline_output" | grep -q "CLEANUP_BY_SIGINT"; then
    pass "baseline reproduces inherited ignored SIGINT"
else
    fail "baseline inherited ignored SIGINT" "non-zero without cleanup" "exit $baseline_exit, output: $baseline_output"
fi

echo ""
echo "Test 2: wrapper restores default SIGINT before exec"
set +e
wrapped_output=$(bash -c 'trap "" INT; "$1" "$2"' bash "$WRAPPER" "$TEST_DIR/sigint-trap.sh" 2>&1)
wrapped_exit=$?
set -e
if [[ $wrapped_exit -eq 0 ]] && echo "$wrapped_output" | grep -q "CLEANUP_BY_SIGINT"; then
    pass "wrapper restores default SIGINT before exec"
else
    fail "wrapper restores default SIGINT before exec" "exit 0 with cleanup" "exit $wrapped_exit, output: $wrapped_output"
fi

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"
