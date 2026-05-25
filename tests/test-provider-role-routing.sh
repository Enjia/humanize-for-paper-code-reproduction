#!/usr/bin/env bash
# Tests for role-specific provider routing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PROVIDER_ROUTER="$PROJECT_ROOT/scripts/lib/provider-router.sh"
CONFIG_LOADER="$PROJECT_ROOT/scripts/lib/config-loader.sh"
SAFE_BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

echo "=========================================="
echo "Provider Role Routing Tests"
echo "=========================================="
echo ""

setup_test_dir

if [[ -s "$PROVIDER_ROUTER" ]]; then
  pass "provider-router.sh exists"
else
  fail "provider-router.sh exists" "non-empty file" "missing"
  print_test_summary "Provider Role Routing Tests"
  exit 1
fi

# shellcheck source=../scripts/lib/config-loader.sh
source "$CONFIG_LOADER"
# shellcheck source=../scripts/lib/provider-router.sh
source "$PROVIDER_ROUTER"

PROJECT_DIR="$TEST_DIR/project"
mkdir -p "$PROJECT_DIR/.humanize"
cat > "$PROJECT_DIR/.humanize/config.json" <<'JSON'
{
  "summary_reviewer_provider": "claude",
  "summary_reviewer_model": "sonnet",
  "summary_reviewer_effort": "high",
  "summary_reviewer_timeout_seconds": 333,
  "summary_reviewer_sandbox_mode": "read-only",
  "summary_reviewer_write_policy": "none",
  "summary_reviewer_network_policy": "disabled",
  "code_reviewer_model": "gpt-5.3-codex",
  "worker_provider": "codex",
  "worker_model": "gpt-5.5",
  "worker_effort": "medium",
  "worker_timeout_seconds": 444,
  "worker_write_policy": "workspace-only"
}
JSON

merged=$(XDG_CONFIG_HOME="$TEST_DIR/no-user-config" load_merged_config "$PROJECT_ROOT" "$PROJECT_DIR" 2>/dev/null)

summary_role=$(resolve_provider_role "$merged" "summary_reviewer" "paper-repro/work")
if jq -e '.role == "summary_reviewer" and .provider == "claude" and .model == "sonnet" and .effort == "high" and .timeout_seconds == 333 and .write_policy == "none"' <<<"$summary_role" >/dev/null; then
  pass "explicit role provider config is honored"
else
  fail "explicit role provider config is honored" "claude summary reviewer role" "$summary_role"
fi

code_role=$(resolve_provider_role "$merged" "code_reviewer" "paper-repro/work")
if jq -e '.provider == "codex" and .model == "gpt-5.3-codex"' <<<"$code_role" >/dev/null; then
  pass "provider falls back to model-name detection only when provider is absent"
else
  fail "provider falls back to model-name detection only when provider is absent" "codex from gpt model" "$code_role"
fi

stderr_out=""
exit_code=0
stderr_out=$(PATH="$SAFE_BASE_PATH" check_provider_role_dependency "$summary_role" 2>&1 >/dev/null) || exit_code=$?
if [[ $exit_code -ne 0 ]] && grep -q "summary_reviewer" <<<"$stderr_out" && grep -q "claude" <<<"$stderr_out" && ! grep -q "codex" <<<"$stderr_out"; then
  pass "missing dependency error is role-aware and provider-specific"
else
  fail "missing dependency error is role-aware and provider-specific" "summary_reviewer/claude without codex" "exit=$exit_code stderr=$stderr_out"
fi

BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$BIN_DIR/claude"

if PATH="$BIN_DIR:$SAFE_BASE_PATH" check_provider_role_dependency "$summary_role" >/tmp/provider-role.out 2>&1; then
  pass "claude reviewer dependency check does not require codex"
else
  fail "claude reviewer dependency check does not require codex" "exit 0 with mock claude only" "$(cat /tmp/provider-role.out)"
fi

worker_role=$(resolve_provider_role "$merged" "worker" "paper-repro/work")
if jq -e '.provider == "codex" and .workspace_root == "paper-repro/work" and .write_policy == "workspace-only"' <<<"$worker_role" >/dev/null; then
  pass "worker role carries workspace and write policy"
else
  fail "worker role carries workspace and write policy" "workspace-only codex worker" "$worker_role"
fi

print_test_summary "Provider Role Routing Tests"
