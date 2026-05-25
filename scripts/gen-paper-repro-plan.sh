#!/usr/bin/env bash
# gen-paper-repro-plan.sh
# Public entrypoint for checkpoint-driven paper reproduction planning.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec "$SCRIPT_DIR/gen-paper-repro-plan-dry-run.sh" "$@"
