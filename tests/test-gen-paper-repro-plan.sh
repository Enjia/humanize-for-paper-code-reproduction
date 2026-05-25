#!/usr/bin/env bash
#
# Tests for gen-paper-repro-plan command and IO validation skeleton.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

COMMAND_FILE="$PROJECT_ROOT/commands/gen-paper-repro-plan.md"
SKILL_FILE="$PROJECT_ROOT/skills/humanize-gen-paper-repro-plan/SKILL.md"
VALIDATOR="$PROJECT_ROOT/scripts/validate-paper-repro-plan-io.sh"
PIPELINE="$PROJECT_ROOT/scripts/gen-paper-repro-plan.sh"

echo "=========================================="
echo "gen-paper-repro-plan Tests"
echo "=========================================="
echo ""

setup_test_dir
INPUT="$TEST_DIR/paper.md"
OUT_MD="paper-repro-plan.md"
OUT_JSON="paper-repro-plan.json"
WORKSPACE="paper-repro/fixture-paper"
printf '# Paper\n\nAlgorithm text.\n' > "$INPUT"

if [[ -s "$COMMAND_FILE" ]]; then
  pass "gen-paper-repro-plan command exists"
else
  fail "gen-paper-repro-plan command exists" "non-empty command file" "missing"
fi

if [[ -s "$SKILL_FILE" ]]; then
  pass "gen paper repro skill exists"
else
  fail "gen paper repro skill exists" "non-empty SKILL.md" "missing"
fi

if [[ -x "$VALIDATOR" ]]; then
  pass "validate-paper-repro-plan-io.sh exists and is executable"
else
  fail "validate-paper-repro-plan-io.sh exists and is executable" "executable validator" "missing or not executable"
fi

if [[ -x "$PIPELINE" ]]; then
  pass "gen-paper-repro-plan.sh exists and is executable"
else
  fail "gen-paper-repro-plan.sh exists and is executable" "executable pipeline" "missing or not executable"
fi

if [[ -s "$COMMAND_FILE" ]] && grep -q "paper-input-sanitize.sh" "$COMMAND_FILE" && grep -q "paper-decomposer" "$COMMAND_FILE" && grep -q "paper-repro-plan.json" "$COMMAND_FILE"; then
  pass "command documents sanitizer to decomposer to manifest pipeline"
else
  fail "command documents sanitizer to decomposer to manifest pipeline" "sanitizer/decomposer/manifest references" "missing"
fi

cd "$TEST_DIR"

if "$VALIDATOR" --input "$INPUT" --output "$OUT_MD" --manifest "$OUT_JSON" --workspace "$WORKSPACE" >/tmp/gen-paper-io.out 2>&1; then
  pass "paper repro plan IO validation accepts valid paths"
else
  fail "paper repro plan IO validation accepts valid paths" "exit 0" "$(cat /tmp/gen-paper-io.out)"
fi

if [[ -x "$PIPELINE" ]] && "$PIPELINE" --input "$INPUT" --output "$OUT_MD" --manifest "$OUT_JSON" --workspace "$WORKSPACE" --budget smoke >/tmp/gen-paper-pipeline.out 2>&1; then
  pass "gen-paper-repro-plan pipeline runs end to end"
else
  fail "gen-paper-repro-plan pipeline runs end to end" "exit 0" "$(cat /tmp/gen-paper-pipeline.out 2>/dev/null || true)"
fi

if [[ -s "$OUT_MD" && -s "$OUT_JSON" ]] && jq -e '.checkpoint_graph.checkpoints | length >= 1' "$OUT_JSON" >/dev/null 2>&1; then
  pass "gen-paper-repro-plan pipeline writes plan markdown and manifest"
else
  fail "gen-paper-repro-plan pipeline writes plan markdown and manifest" "paper-repro-plan.md and valid manifest" "md=$(cat "$OUT_MD" 2>/dev/null || true) json=$(cat "$OUT_JSON" 2>/dev/null || true)"
fi

if "$VALIDATOR" --input "$INPUT" --output /tmp/plan.md --manifest "$OUT_JSON" --workspace "$WORKSPACE" >/tmp/gen-paper-io.out 2>&1; then
  fail "paper repro plan IO validation rejects absolute output path" "non-zero exit" "validation passed"
else
  if grep -q "relative" /tmp/gen-paper-io.out; then
    pass "paper repro plan IO validation rejects absolute output path"
  else
    fail "absolute output path error mentions relative" "relative" "$(cat /tmp/gen-paper-io.out)"
  fi
fi

if "$VALIDATOR" --input "$INPUT" --output "$OUT_MD" --manifest "$OUT_JSON" --workspace ".humanize/paper" >/tmp/gen-paper-io.out 2>&1; then
  fail "paper repro plan IO validation rejects .humanize workspace" "non-zero exit" "validation passed"
else
  if grep -q ".humanize" /tmp/gen-paper-io.out; then
    pass "paper repro plan IO validation rejects .humanize workspace"
  else
    fail ".humanize workspace error mentions .humanize" ".humanize" "$(cat /tmp/gen-paper-io.out)"
  fi
fi

if "$VALIDATOR" --input "$INPUT" --output "$OUT_MD" --manifest "$OUT_JSON" --workspace "paper-repro/bad;name" >/tmp/gen-paper-io.out 2>&1; then
  fail "paper repro plan IO validation rejects shell metacharacters" "non-zero exit" "validation passed"
else
  if grep -q "shell metacharacters" /tmp/gen-paper-io.out; then
    pass "paper repro plan IO validation rejects shell metacharacters"
  else
    fail "shell metacharacter error mentions shell metacharacters" "shell metacharacters" "$(cat /tmp/gen-paper-io.out)"
  fi
fi

print_test_summary "gen-paper-repro-plan Tests"
